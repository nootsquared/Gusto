#include "climate_protocol.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

int climate_line_feed(climate_line_t *line, char byte) {
    if (byte == '\n') {
        bool bad = line->discarding;
        if (line->length && line->text[line->length - 1] == '\r') --line->length;
        line->text[line->length] = 0;
        line->length = 0;
        line->discarding = false;
        return bad ? -1 : 1;
    }
    if (!line->discarding) {
        if (byte == 0 || line->length >= sizeof(line->text) - 1) {
            line->length = 0;
            line->discarding = true;
        } else line->text[line->length++] = byte;
    }
    return 0;
}

static bool unsigned_value(const char *text, uint32_t maximum, uint32_t *out) {
    if (!*text) return false;
    uint32_t value = 0;
    for (; *text; ++text) {
        if (*text < '0' || *text > '9') return false;
        uint32_t digit = (uint32_t)(*text - '0');
        if (value > maximum / 10 || (value == maximum / 10 && digit > maximum % 10)) return false;
        value = value * 10 + digit;
    }
    *out = value;
    return true;
}

static bool decimal_value(const char *text, float low, float high, int *out) {
    const char *p = text;
    if (*p == '-') ++p;
    const char *digits = p;
    while (*p >= '0' && *p <= '9') ++p;
    if (p == digits || *p++ != '.') return false;
    if (*p < '0' || *p > '9' || p[1]) return false;
    char *end;
    float value = strtof(text, &end);
    if (*end || !isfinite(value) || value < low || value > high) return false;
    *out = (int)lroundf(value * 10);
    return true;
}

bool climate_parse_data(const char *line, climate_sample_t *sample) {
    size_t length = strlen(line);
    if (length >= 128) return false;
    char copy[128];
    memcpy(copy, line, length + 1);
    char *fields[8];
    unsigned count = 1;
    fields[0] = copy;
    for (char *p = copy; *p; ++p) {
        if (*p != ',') continue;
        if (count == 8) return false;
        *p = 0;
        fields[count++] = p + 1;
    }
    if (count != 8 || strcmp(fields[0], "DATA") || strcmp(fields[1], "1")) return false;
    climate_sample_t result = {0};
    uint32_t mask, light;
    int temperature, humidity;
    if (!unsigned_value(fields[2], UINT32_MAX, &result.sequence) ||
        !unsigned_value(fields[3], UINT32_MAX, &result.uptime_ms) ||
        !unsigned_value(fields[7], 7, &mask)) return false;
    result.valid_mask = (uint8_t)mask;
    if (mask & 1) {
        if (!decimal_value(fields[4], -40, 185, &temperature)) return false;
        result.temperature_tenths_f = (int16_t)temperature;
    } else if (strcmp(fields[4], "NA")) return false;
    if (mask & 2) {
        if (!decimal_value(fields[5], 0, 100, &humidity)) return false;
        result.humidity_tenths = (uint16_t)humidity;
    } else if (strcmp(fields[5], "NA")) return false;
    if (mask & 4) {
        if (!unsigned_value(fields[6], 65535, &light)) return false;
        result.light_counts = (uint16_t)light;
    } else if (strcmp(fields[6], "NA")) return false;
    *sample = result;
    return true;
}

bool climate_nonce_valid(const char *nonce) {
    size_t length = strlen(nonce);
    if (!length || length > 32) return false;
    for (size_t i = 0; i < length; ++i) {
        char c = nonce[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '-' || c == '_')) return false;
    }
    return true;
}

bool climate_parse_pong(const char *line, char nonce[33]) {
    if (strncmp(line, "PONG,1,", 7) || !climate_nonce_valid(line + 7)) return false;
    strcpy(nonce, line + 7);
    return true;
}

static void put16(uint8_t *out, uint16_t value) {
    out[0] = (uint8_t)value;
    out[1] = (uint8_t)(value >> 8);
}
static void put32(uint8_t *out, uint32_t value) {
    for (unsigned i = 0; i < 4; ++i) out[i] = (uint8_t)(value >> (8 * i));
}
static uint16_t get16(const uint8_t *data) {
    return (uint16_t)(data[0] | ((uint16_t)data[1] << 8));
}
static uint32_t get32(const uint8_t *data) {
    uint32_t value = 0;
    for (unsigned i = 0; i < 4; ++i) value |= (uint32_t)data[i] << (8 * i);
    return value;
}

void climate_encode(const climate_sample_t *sample, uint8_t out[CLIMATE_PAYLOAD_SIZE]) {
    out[0] = CLIMATE_MESSAGE_SAMPLE;
    out[1] = 1;
    put32(out + 2, sample->sequence);
    put32(out + 6, sample->uptime_ms);
    put16(out + 10, (uint16_t)sample->temperature_tenths_f);
    put16(out + 12, sample->humidity_tenths);
    put16(out + 14, sample->light_counts);
    out[16] = sample->valid_mask;
}

bool climate_decode(const uint8_t *data, size_t length, climate_sample_t *sample) {
    if (length != CLIMATE_PAYLOAD_SIZE || data[0] != CLIMATE_MESSAGE_SAMPLE || data[1] != 1 || data[16] > 7) return false;
    uint16_t raw_temperature = get16(data + 10);
    int32_t temperature = raw_temperature >= 32768 ? (int32_t)raw_temperature - 65536 : raw_temperature;
    climate_sample_t result = {
        .sequence = get32(data + 2), .uptime_ms = get32(data + 6),
        .temperature_tenths_f = (int16_t)temperature,
        .humidity_tenths = get16(data + 12), .light_counts = get16(data + 14),
        .valid_mask = data[16]
    };
    if ((result.valid_mask & 1) && (temperature < -400 || temperature > 1850)) return false;
    if ((result.valid_mask & 2) && result.humidity_tenths > 1000) return false;
    *sample = result;
    return true;
}

void climate_ack_encode(uint32_t sequence, uint8_t out[6]) {
    out[0] = CLIMATE_MESSAGE_ACK;
    out[1] = 1;
    put32(out + 2, sequence);
}
bool climate_ack_decode(const uint8_t *data, size_t length, uint32_t *sequence) {
    if (length != 6 || data[0] != CLIMATE_MESSAGE_ACK || data[1] != 1) return false;
    *sequence = get32(data + 2);
    return true;
}
bool climate_state_fresh(const climate_state_t *state, uint32_t now) {
    return state->received && (uint32_t)(now - state->received_ms) < 5000;
}

bool climate_parse_ble_state(const char *line, climate_ble_state_t *state) {
    if (!strcmp(line, "BLE,1,STATE,OFF")) *state = CLIMATE_BLE_OFF;
    else if (!strcmp(line, "BLE,1,STATE,ADVERTISING")) *state = CLIMATE_BLE_ADVERTISING;
    else if (!strcmp(line, "BLE,1,STATE,CONNECTED")) *state = CLIMATE_BLE_CONNECTED;
    else if (!strcmp(line, "BLE,1,STATE,ERROR")) *state = CLIMATE_BLE_ERROR;
    else return false;
    return true;
}
void climate_ble_start_encode(uint8_t out[2]) {
    out[0] = CLIMATE_MESSAGE_BLE_START;
    out[1] = 1;
}
bool climate_ble_start_decode(const uint8_t *data, size_t length) {
    return length == 2 && data[0] == CLIMATE_MESSAGE_BLE_START && data[1] == 1;
}
void climate_ble_state_encode(climate_ble_state_t state, uint8_t out[3]) {
    out[0] = CLIMATE_MESSAGE_BLE_STATE;
    out[1] = 1;
    out[2] = (uint8_t)state;
}
bool climate_ble_state_decode(const uint8_t *data, size_t length, climate_ble_state_t *state) {
    if (length != 3 || data[0] != CLIMATE_MESSAGE_BLE_STATE || data[1] != 1 ||
        data[2] > CLIMATE_BLE_ERROR) return false;
    *state = (climate_ble_state_t)data[2];
    return true;
}
