# FreeWili screen

Firmware for the FreeWili OG. The screen displays temperature in Fahrenheit,
relative humidity, and ambient light in lux with large labels and readings.
Current values are placeholders: 72.5 F, 45.0%, and 320 lux.
The Arduino Nano sketch and live UART sensor receiver are not implemented yet.

White toggles the temperature warning, yellow toggles humidity, and green
toggles ambient light. Each active reading stays red while a warning triangle
beside it blinks in sync with the seven top LEDs: 250 ms on every 1.5 seconds,
with a 175 ms G4 beep (392 Hz).
Press the same button again to restore that reading to steady blue.
Multiple warnings can be active together; the shared LEDs and beep stop
when all warnings are off. All warnings start off after a reboot.
Hold red for six seconds to power off;
hold white or attach USB to wake.

## Dependencies

Install the Raspberry Pi Pico SDK 2.3.0 and ARM toolchain using the Pico VS Code
extension. The included CMake presets use its standard installation paths.
CMake must be version 3.21 or newer.

From this folder, obtain the FreeWili OG board-support package:

```sh
git clone https://github.com/freewili/wiliOGbsp.git third_party/wiliOGbsp
git -C third_party/wiliOGbsp checkout 071d00c3ec6ba8fc9e272e19843eea219e6f82cd
python3 -m venv .venv
.venv/bin/python -m pip install -r third_party/wiliOGbsp/requirements.txt
```

On Windows, use `.venv\Scripts\python.exe` for the Python commands.
Dependencies, virtual environments, and build files are ignored by Git.
An existing BSP checkout can be used by configuring with `-DFWOG_BSP_PATH=/path/to/wiliOGbsp`.

## Build and flash

On macOS or Linux:

```sh
cmake --preset target-posix
cmake --build --preset target-posix --target climate_main
.venv/bin/python third_party/wiliOGbsp/tools/fw.py flash climate_main --uf2 build/climate_main.uf2
```

On Windows, use the `target` preset and `.venv\Scripts\python.exe`.
If CMake is not on PATH, use the executable installed under `.pico-sdk/cmake`.

`build/climate_main.uf2` includes both processors' firmware. Flash the main
image; it updates the display through the installed display bootloader.
Do not flash `climate_display.uf2` directly. A new board first needs the
FreeWili display bootloader installed using the BSP's setup instructions.

## Source

- `display/main.c`: readings, screen layout, independent white/yellow/green warnings, LEDs, and audio.
- `main/main.c`: display update and main-processor watchdog.
- `CMakeLists.txt`: board configuration and combined firmware build.

Change `temperature_f`, `humidity_percent`, and `ambient_lux` in `display/main.c`
to update the readings. The warning uses `WARNING_BEEP_HZ`, `WARNING_PERIOD_MS`,
and `WARNING_FLASH_MS` for pitch and timing.

The external FreeWili BSP has its own licenses and third-party notices.
