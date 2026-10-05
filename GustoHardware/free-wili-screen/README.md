# FREE-WILi climate display

Firmware for FREE-WILi OG. The main processor receives sensor data from the Arduino Nano 33 BLE Sense Rev2 over its external UART at 115200 baud, validates it, and forwards it to the display processor over the board's framed internal link. The screen shows temperature in Fahrenheit with Celsius in parentheses, humidity in percent, and ambient light as raw APDS9960 clear-channel counts. Invalid or stale readings show `--` after five seconds.

Holding blue for two seconds asks the Nano to advertise `MHacks Climate` over BLE. The screen shows pairing status, blue LEDs blink, and a short beep repeats until a phone connects or discovery times out. The Nano reports connection state over UART; FREE-WILi displays `CONNECTED` and stops the cue when a phone connects. A disconnected phone needs another blue-button hold. This is BLE discovery/connection without a passcode or bond.

The gray, yellow, and green buttons toggle temperature, humidity, and light warnings independently. Each active reading turns red; its triangle and the seven LEDs flash for 250 ms every 1.5 seconds, accompanied by a 175 ms G4 beep. Hold red for six seconds to power off; use white or USB to wake.

## Dependencies

Use the Raspberry Pi Pico SDK 2.3.0, an ARM GNU toolchain, CMake 3.21 or newer, Ninja, Python 3, and the pinned FREE-WILi OG BSP:

```sh
git clone https://github.com/freewili/wiliOGbsp.git third_party/wiliOGbsp
git -C third_party/wiliOGbsp checkout 071d00c3ec6ba8fc9e272e19843eea219e6f82cd
python -m venv .venv
.venv/bin/python -m pip install -r third_party/wiliOGbsp/requirements.txt
```

On Windows, use `.venv\Scripts\python.exe`. `CMakePresets.json` assumes the default Pico VS Code extension installation paths. If your tools are elsewhere, configure with explicit `PICO_SDK_PATH`, `PICO_TOOLCHAIN_PATH`, `FWOG_BSP_PATH`, and Python interpreter paths.

## Build and flash

```sh
cmake --preset target-posix
cmake --build --preset target-posix --target climate_main
.venv/bin/python third_party/wiliOGbsp/tools/fw.py flash climate_main --uf2 /absolute/path/to/build/climate_main.uf2
```

Use the `target` preset on Windows. `climate_main.uf2` embeds the display application; flash the main image only. The display requires the BSP's serial display bootloader. Do not flash `climate_display.uf2` directly.

## Diagnose

Main USB console: `status` reports `uart_ready`, `direction_result`, sample count, age, and display acknowledgment. `ping nonce` sends a physical UART `PING,1,nonce` and expects `UART_PONG nonce`. The Nano sends one `DATA,1,sequence,uptime_ms,temperature_f,humidity,light,valid_mask` line per second and replies with `PONG,1,nonce`. Validity bits 1, 2, and 4 identify temperature, humidity, and light; a missing value is `NA`. The receiver ignores malformed lines. `verify_freewili.py --port COM5 --seconds 30 --output verification.json` checks ten UART pings, at least 25 sensor records, and display acknowledgments. COM5 was the main console during testing and may change.

Firmware version 012 passed a combined build, receiver protocol tests, 40 BSP C host tests, 186 BSP Python tests, and live connected verification on October 4, 2026. The live test received 31 consecutive fully valid sensor records and 30 display acknowledgments during capture. The final acknowledgment followed as the capture closed. Counts are raw sensor output, not calibrated lux. The hardware wiring and diagnostics are described in `../README.md` and `../FREEWILI_BRINGUP.md`.

Firmware version 013 adds blue-button BLE discovery control and connection indicators. The paired Nano sketch and combined FREE-WILi image compiled and uploaded; USB ping and ten samples passed, 30-second UART/display verification passed, and diagnostic start/stop commands confirmed Nano advertising and display pairing states. The physical blue-button and phone connection checks passed: user saw `BLE: CONNECTED` and the beep stopped, while device diagnostics reported ble=2, pairing=0. The user confirmed changing characteristic notifications in LightBlue.
