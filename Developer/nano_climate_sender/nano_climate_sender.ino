#include <Arduino_HS300x.h>
#include <Arduino_APDS9960.h>
#include <math.h>
#include <stdint.h>

struct LineBuffer {
    char bytes[128];
    size_t length = 0;
    bool discarding = false;
};

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
}

void loop() {
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
    int length = snprintf(record, sizeof(record), "DATA,1,%lu,%lu,%s,%s,%s,%u\n",
                          (unsigned long)sequenceNumber++, (unsigned long)now,
                          temperatureText, humidityText, lightText, validMask);
    if (length > 0 && size_t(length) < sizeof(record)) {
        Serial1.write((const uint8_t*)record, length);
        if (Serial) Serial.write((const uint8_t*)record, length);
    }
}
