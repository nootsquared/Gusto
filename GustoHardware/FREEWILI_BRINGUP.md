FREE-WILi + Nano climate bring-up â€” current status

Firmware 012 was uploaded to FREE-WILi through COM5 using the combined climate_main.uf2. The existing display bootloader installed the embedded display application. No commits or pushes were made.

Verified on hardware: uart_ready=1, direction_result=0, directions_complete=1. Disconnected ping timed out as expected. Display reports panel/LED/audio ready, ioexp=1 and link=1. Connected verification now passed: ten of ten physical UART pings returned, 31 consecutive sensor records were collected over approximately 30 seconds, all validity masks were 7, and 30 display acknowledgments were captured (the final record arrived as capture closed). The malformed count remained at 1 throughout this capture; no new malformed records were counted. The earlier missing data was resolved by seating the Nano fully into the breadboard, as reported by the user.

Checks: climate C protocol tests passed; 186 BSP Python tests passed; 40 BSP C tests passed with -fwrapv -fno-sanitize=undefined. The initial sanitizer run flagged existing signed arithmetic in the unused microphone/CIC routines. Those BSP routines were not changed.

Software changes are in MHacks/GustoHardware/free-wili-screen. The original screen prototype is preserved in GustoHardware/Prototypes/free-wili-screen. New receiver uses 115200 baud external UART, framed internal display messages, Fahrenheit first with Celsius in parentheses, humidity percent and raw light counts. Stale or invalid readings show -- after 5 seconds. Ambient light counts are not calibrated lux. Manual warnings and power controls remain in the display program.

User confirmed post-flash power-off/wake and -- display behavior. Nano USB ping and ten sensor records passed independently. User then connected the UART and confirmed live display values after seating the Nano fully.

Planned final wiring after checks, with both boards powered off while moving wires:
- FREE-WILi header 6 to header 4 (3.3 V I/O reference).
- Nano breadboard A14 (same A-E row as E14 GND) to FREE-WILi header 19 GND.
- Nano J15 (same F-J row as I15 TX1) to FREE-WILi header 5 RX.
- Nano J14 (same F-J row as I14 RX0) to FREE-WILi header 9 TX.
Power each board by its own USB; do not connect the Nano power pins to FREE-WILi. Actual pin orientation and voltages have not been independently measured or visually verified.

Remaining optional physical check: stale-data disappearance/recovery after safely disconnecting and restoring the data connection. Stale handling passed host protocol tests. LCD display is working according to the user; its exact Fahrenheit/Celsius formatting has not been independently photographed. Sensor plausibility is different from calibrated accuracy; no calibrated reference instruments have been used.

BLE discovery update, October 4, 2026: Firmware 013 and the button-controlled Nano sketch uploaded. Blue held two seconds requests a 60-second advertisement window; display pairing cues stop on connection or timeout. Nano USB and 30-second FREE-WILi telemetry checks passed. Diagnostic `ble start`/`ble stop` round trips confirmed Nano advertising and display pairing states. Physical blue button and iPhone connection still need user testing.

Physical Bluetooth check: User held FREE-WILi blue, discovered `MHacks Climate` in LightBlue on iPhone, connected, saw `BLE: CONNECTED`, and heard the pairing beep stop. FREE-WILi display diagnostics independently reported ble=2, pairing=0. The user confirmed changing values on the BLE characteristic in LightBlue; the physical end-to-end path passed.
