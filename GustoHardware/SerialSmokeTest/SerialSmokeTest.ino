char input[64];
unsigned int length = 0;
unsigned long lastBlink = 0;
bool led = false;
void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(115200);
}
void loop() {
  if (millis() - lastBlink >= 500) {
    lastBlink = millis();
    led = !led;
    digitalWrite(LED_BUILTIN, led);
  }
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      input[length] = '\0';
      if (strcmp(input, "PING") == 0) Serial.println("PONG");
      else if (strcmp(input, "INFO") == 0) Serial.println("BOARD=Nano 33 BLE; TEST=SerialSmokeTest; BAUD=115200");
      else if (strcmp(input, "UPTIME") == 0) { Serial.print("UPTIME_MS="); Serial.println(millis()); }
      else if (strncmp(input, "ECHO ", 5) == 0) { Serial.print("ECHO: "); Serial.println(input + 5); }
      else Serial.println("ERROR: use PING, INFO, UPTIME, or ECHO text");
      length = 0;
    } else if (length < sizeof(input) - 1) input[length++] = c;
    else { length = 0; Serial.println("ERROR: command too long"); }
  }
}
