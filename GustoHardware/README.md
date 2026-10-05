# GustoHardware

The connected storage system for Gusto: climate sensing, Bluetooth telemetry,
and a companion FREE-WILi display. Active firmware and verification tools live here;
`Prototypes/` preserves the earlier screen implementation.

The Nano 33 BLE Sense Rev2 reads its onboard HS300x temperature/humidity sensor and APDS9960 light sensor. `nano_climate_sender/nano_climate_sender.ino` sends a `DATA,1,...` record once per second over USB and its TX1 pin at 115200 baud. It exposes the latest reading over Bluetooth Low Energy for the iPhone app when discovery is started by holding FREE-WILi blue for two seconds. FREE-WILi receives the data over UART and shows Fahrenheit first (Celsius in parentheses), relative humidity, and raw ambient-light counts. Light counts are not lux.

## Nano

From PowerShell in this directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\arduino.ps1 Setup
powershell -NoProfile -ExecutionPolicy Bypass -File .\arduino.ps1 List
powershell -NoProfile -ExecutionPolicy Bypass -File .\arduino.ps1 Upload -Port COM8 -SketchName nano_climate_sender
python .\verify_nano.py --port COM8 --output nano-verification.json
```

Close Arduino Serial Monitor before using the commands. COM8 was the Nano port during testing; use `List` again if Windows assigns another number. The Arduino IDE can also compile the sender after installing `Arduino_HS300x`, `Arduino_APDS9960`, and `ArduinoBLE`. The `Upload` command defaults to the earlier `SerialSmokeTest`, so specify `-SketchName nano_climate_sender` to restore the live sender.

`SensorTenSecondTest` and `record-sensors.ps1` are earlier standalone checks. `SerialSmokeTest` and `arduino.ps1 Test` are earlier USB command checks. Arduino CLI, libraries, toolchains, build outputs, and local port configuration are ignored by Git.

BLE integration is specified in `BLE_PROTOCOL.md`. Hold FREE-WILi blue for two seconds to begin a 60-second discovery window; its blue lights and beep stop when an app connects. The phone should scan for `MHacks Climate` and subscribe to the 17-byte data characteristic. To check whether the Nano started advertising, send `BLE_STATUS` followed by a newline to its USB serial port at 115200 baud; the reply should include `BLE_READY=1`.

## Wiring

Place the Nano so its pins occupy E1–E15 and I1–I15 on the breadboard. With power off, connect:

| Nano / FREE-WILi | FREE-WILi |
| --- | --- |
| J15, same row as Nano I15 TX1 | Pin 5 RX |
| J14, same row as Nano I14 RX0 | Pin 9 TX |
| A14, same row as Nano E14 GND | Pin 19 GND |
| Pin 6, 3.3 V | Pin 4, I/O voltage input |

Power each device by its own USB. Do not connect either board's 5 V pin, Nano VIN, VUSB, or 3.3 V to the other board. Verify the printed header labels and seat the Nano fully; a partially seated Nano produced no UART data despite normal USB readings.

## FREE-WILi

`free-wili-screen` contains the two-processor receiver/display firmware. Follow its README to obtain the pinned board-support package and Pico SDK, build the combined `climate_main.uf2`, and flash only that main image. Its README includes the protocol and diagnostic commands.

On October 4, 2026, the combined firmware 012 was uploaded. Ten physical UART pings replied; 31 consecutive valid readings were recorded over approximately 30 seconds, with 30 corresponding display acknowledgments captured. Observed values were 75.4–75.6 °F (24.1–24.2 °C), 43.8–46.3% humidity, and 1–273 raw light counts. These are plausible values, not calibrated accuracy measurements. The user confirmed the screen changed from dashes to live values after fully seating the Nano. See `FREEWILI_BRINGUP.md` for the bring-up record.
