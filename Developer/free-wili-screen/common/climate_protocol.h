#ifndef CLIMATE_PROTOCOL_H
#define CLIMATE_PROTOCOL_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define CLIMATE_MESSAGE_SAMPLE 0x30u
#define CLIMATE_MESSAGE_ACK 0x31u
#define CLIMATE_PAYLOAD_SIZE 17u

typedef struct {
    uint32_t sequence;
    uint32_t uptime_ms;
    int16_t temperature_tenths_f;
    uint16_t humidity_tenths;
    uint16_t light_counts;
    uint8_t valid_mask;
} climate_sample_t;

typedef struct {
    char text[128];
    size_t length;
    bool discarding;
} climate_line_t;

typedef struct {
    climate_sample_t sample;
    uint32_t received_ms;
    bool received;
} climate_state_t;

int climate_line_feed(climate_line_t *line, char byte);
bool climate_parse_data(const char *line, climate_sample_t *sample);
bool climate_parse_pong(const char *line, char nonce[33]);
bool climate_nonce_valid(const char *nonce);
void climate_encode(const climate_sample_t *sample, uint8_t out[CLIMATE_PAYLOAD_SIZE]);
bool climate_decode(const uint8_t *data, size_t length, climate_sample_t *sample);
void climate_ack_encode(uint32_t sequence, uint8_t out[6]);
bool climate_ack_decode(const uint8_t *data, size_t length, uint32_t *sequence);
bool climate_state_fresh(const climate_state_t *state, uint32_t now);
#endif
