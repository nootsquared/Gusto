#include <Arduino_HTS221.h>
// These two official libraries share global temperature-unit names.
#define FAHRENHEIT HS300X_FAHRENHEIT
#define CELSIUS HS300X_CELSIUS
#include <Arduino_HS300x.h>
#undef FAHRENHEIT
#undef CELSIUS
#include <Arduino_APDS9960.h>
#include <math.h>

bool htsOk = false, hsOk = false, lightOk = false;
bool recording = false;
unsigned long started = 0;
unsigned int sample = 0;
char command[16];
unsigned int commandLength = 0;
void status() {
  Serial.print("SENSORS,temp_humidity=");
  Serial.print(htsOk ? "HTS221" : (hsOk ? "HS300x" : "MISSING"));
  Serial.print(",ambient_light=");
  Serial.println(lightOk ? "APDS9960" : "MISSING");
}
void setup() {
  Serial.begin(115200);
  htsOk = HTS.begin();
  if (!htsOk) hsOk = HS300x.begin();
  lightOk = APDS.begin();
  if (lightOk) APDS.colorAvailable(); // Starts ambient-light acquisition, without proximity or gesture sensing.
}
void loop() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      command[commandLength] = 0;
      if (!strcmp(command, "STATUS")) status();
      if (!strcmp(command, "START") && !recording) {
        status();
        Serial.println("elapsed_ms,temperature_f,temperature_c,humidity_pct,light_clear_raw,red_raw,green_raw,blue_raw");
        sample = 0;
        started = millis();
        recording = true;
      }
      commandLength = 0;
    } else if (commandLength < sizeof(command) - 1) command[commandLength++] = c;
  }
  if (recording && millis() - started >= sample * 500UL) {
    unsigned long elapsed = millis() - started;
    float t = NAN, h = NAN;
    if (htsOk) { t = HTS.readTemperature(); h = HTS.readHumidity(); }
    else if (hsOk) { t = HS300x.readTemperature(); h = HS300x.readHumidity(); }
    int r = -1, g = -1, b = -1, clear = -1;
    // readColor ends each acquisition; allow the next one to finish.
    bool lightReady = false;
    if (lightOk) {
      unsigned long waitStarted = millis();
      while (!(lightReady = APDS.colorAvailable()) && millis() - waitStarted < 150) delay(2);
    }
    if (lightReady) {
      if (!APDS.readColor(r, g, b, clear)) r = g = b = clear = -1;
    }
    Serial.print(elapsed); Serial.print(',');
    Serial.print(t * 9.0f / 5.0f + 32.0f, 3); Serial.print(','); Serial.print(t, 3); Serial.print(','); Serial.print(h, 3); Serial.print(',');
    Serial.print(clear); Serial.print(','); Serial.print(r); Serial.print(',');
    Serial.print(g); Serial.print(','); Serial.println(b);
    if (++sample == 21) { recording = false; Serial.println("DONE"); }
  }
}
