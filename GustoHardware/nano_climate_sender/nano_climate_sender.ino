#include <Arduino_HS300x.h>
#include <Arduino_APDS9960.h>
#include <ArduinoBLE.h>
#include <math.h>
#include <stdint.h>

struct LineBuffer {
    char bytes[128];
    size_t length = 0;
    bool discarding = false;
};

constexpr uint8_t kBleRecordSize = 17;
BLEService climateService("ef05ba28-5c0a-4c52-9d3a-a643c142ba10");
BLECharacteristic climateData("ef05ba28-5c0a-4c52-9d3a-a643c142ba11",
                              BLERead | BLENotify, kBleRecordSize, true);
bool bleReady = false;
enum ClimateBleMode { BLE_MODE_OFF, BLE_MODE_ADVERTISING, BLE_MODE_CONNECTED, BLE_MODE_ERROR };
ClimateBleMode bleMode = BLE_MODE_OFF;
uint32_t advertisingStarted = 0;
uint32_t lastBleReport = 0;
bool bleStateChanged = true;

const char* bleModeName() {
    switch (bleMode) {
        case BLE_MODE_ADVERTISING: return "ADVERTISING";
        case BLE_MODE_CONNECTED: return "CONNECTED";
        case BLE_MODE_ERROR: return "ERROR";
        default: return "OFF";
    }
}

void setBleMode(ClimateBleMode mode) {
    if (bleMode != mode) {
        bleMode = mode;
        bleStateChanged = true;
    }
}

void reportBleState() {
    Serial1.print("BLE,1,STATE,");
    Serial1.println(bleModeName());
    lastBleReport = millis();
    bleStateChanged = false;
}

void startBleDiscovery() {
    if (!bleReady) {
        setBleMode(BLE_MODE_ERROR);
    } else if (BLE.connected()) {
        setBleMode(BLE_MODE_CONNECTED);
    } else {
        advertisingStarted = millis();
        setBleMode(BLE.advertise() ? BLE_MODE_ADVERTISING : BLE_MODE_ERROR);
    }
    reportBleState();
}

void stopBleDiscovery() {
    if (bleReady && !BLE.connected()) BLE.stopAdvertise();
    setBleMode(bleReady && BLE.connected() ? BLE_MODE_CONNECTED : BLE_MODE_OFF);
    reportBleState();
}

void pollBle() {
    if (bleReady) BLE.poll();
    if (bleReady && BLE.connected()) setBleMode(BLE_MODE_CONNECTED);
    else if (bleMode == BLE_MODE_CONNECTED) {
        BLE.stopAdvertise();
        setBleMode(BLE_MODE_OFF);
    } else if (bleMode == BLE_MODE_ADVERTISING &&
               uint32_t(millis() - advertisingStarted) >= 60000) {
        BLE.stopAdvertise();
        setBleMode(BLE_MODE_OFF);
    }
    if (bleStateChanged || uint32_t(millis() - lastBleReport) >= 1000) reportBleState();
}

void put16(uint8_t* target, uint16_t value) {
    target[0] = uint8_t(value);
    target[1] = uint8_t(value >> 8);
}

void put32(uint8_t* target, uint32_t value) {
    for (unsigned i = 0; i < 4; ++i) target[i] = uint8_t(value >> (8 * i));
}

void publishBle(uint32_t sequence, uint32_t uptime, float temperatureF,
                float humidity, int light, uint8_t validMask) {
    if (!bleReady) return;
    uint8_t record[kBleRecordSize] = {0x30, 1};
    put32(record + 2, sequence);
    put32(record + 6, uptime);
    if (validMask & 1) put16(record + 10, uint16_t(int16_t(roundf(temperatureF * 10))));
    if (validMask & 2) put16(record + 12, uint16_t(roundf(humidity * 10)));
    if (validMask & 4) put16(record + 14, uint16_t(light));
    record[16] = validMask;
    climateData.writeValue(record, sizeof record);
}

LineBuffer usbInput;
LineBuffer uartInput;
bool climateReady = false;
bool lightReady = false;
uint32_t sequenceNumber = 0;
uint32_t lastSample = 0;

bool validNonce(const char* nonce) {
    size_t length = strlen(nonce);
    if (length == 0 || length > 32) return false;
    for (size_t i = 0; i < length; ++i) {
        char c = nonce[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '-' || c == '_')) return false;
    }
    return true;
}

void handleLine(Stream& connection, const char* line) {
    if (strcmp(line, "BLE_STATUS") == 0) {
        connection.print("BLE_READY=");
        connection.print(bleReady ? 1 : 0);
        connection.print(",CONNECTED=");
        connection.print(bleReady && BLE.connected() ? 1 : 0);
        connection.print(",MODE=");
        connection.println(bleModeName());
        return;
    }
    if (strcmp(line, "BLE,1,START") == 0) {
        startBleDiscovery();
        return;
    }
    if (strcmp(line, "BLE,1,STOP") == 0) {
        stopBleDiscovery();
        return;
    }
    if (strncmp(line, "PING,1,", 7) != 0 || !validNonce(line + 7)) return;
    connection.print("PONG,1,");
    connection.println(line + 7);
}

void pollConnection(Stream& connection, LineBuffer& buffer) {
    unsigned int processed = 0;
    while (connection.available() && processed++ < 128) {
        char incoming = connection.read();
        if (incoming == '\n') {
            if (!buffer.discarding) {
                if (buffer.length && buffer.bytes[buffer.length - 1] == '\r') --buffer.length;
                buffer.bytes[buffer.length] = 0;
                handleLine(connection, buffer.bytes);
            }
            buffer.length = 0;
            buffer.discarding = false;
        } else if (!buffer.discarding) {
            if (buffer.length >= sizeof(buffer.bytes) - 1 || incoming == 0) {
                buffer.discarding = true;
                buffer.length = 0;
            } else {
                buffer.bytes[buffer.length++] = incoming;
            }
        }
    }
}

void setup() {
    Serial.begin(115200);
    Serial1.begin(115200);
    climateReady = HS300x.begin();
    lightReady = APDS.begin();
    if (lightReady) APDS.colorAvailable();
    lastSample = millis();
    lastBleReport = lastSample;
    if (BLE.begin()) {
        BLE.setDeviceName("MHacks Climate");
        BLE.setLocalName("MHacks Climate");
        BLE.setAdvertisedService(climateService);
        climateService.addCharacteristic(climateData);
        BLE.addService(climateService);
        uint8_t empty[kBleRecordSize] = {0x30, 1};
        climateData.writeValue(empty, sizeof empty);
        bleReady = true;
    }
}

void loop() {
    pollBle();
    if (Serial) pollConnection(Serial, usbInput);
    pollConnection(Serial1, uartInput);
    if (lightReady) APDS.colorAvailable();
    uint32_t now = millis();
    if (uint32_t(now - lastSample) < 1000) return;
    lastSample = now;

    float temperatureC = climateReady ? HS300x.readTemperature() : NAN;
    float humidity = climateReady ? HS300x.readHumidity() : NAN;
    float temperatureF = temperatureC * 9.0f / 5.0f + 32.0f;
    int red = -1, green = -1, blue = -1, clear = -1;
    if (lightReady && APDS.colorAvailable()) APDS.readColor(red, green, blue, clear);

    uint8_t validMask = 0;
    char temperatureText[16] = "NA";
    char humidityText[16] = "NA";
    char lightText[8] = "NA";
    if (isfinite(temperatureF) && temperatureF >= -40 && temperatureF <= 185) {
        validMask |= 1;
        snprintf(temperatureText, sizeof(temperatureText), "%.1f", temperatureF);
    }
    if (isfinite(humidity) && humidity >= 0 && humidity <= 100) {
        validMask |= 2;
        snprintf(humidityText, sizeof(humidityText), "%.1f", humidity);
    }
    if (clear >= 0 && clear <= 65535) {
        validMask |= 4;
        snprintf(lightText, sizeof(lightText), "%d", clear);
    }
    char record[128];
    uint32_t sampleSequence = sequenceNumber++;
    int length = snprintf(record, sizeof(record), "DATA,1,%lu,%lu,%s,%s,%s,%u\n",
                          (unsigned long)sampleSequence, (unsigned long)now,
                          temperatureText, humidityText, lightText, validMask);
    if (length > 0 && size_t(length) < sizeof(record)) {
        Serial1.write((const uint8_t*)record, length);
        if (Serial) Serial.write((const uint8_t*)record, length);
        publishBle(sampleSequence, now, temperatureF, humidity, clear, validMask);
    }
}
