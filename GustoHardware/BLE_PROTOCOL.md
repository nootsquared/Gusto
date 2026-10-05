# Climate data over Bluetooth Low Energy

The Nano 33 BLE Sense Rev2 samples its sensors every second, even when no phone is connected. It sends the same sample to FREE-WILi over UART and publishes it as one BLE characteristic when a phone connects. The iPhone app performs its own algorithm; the Nano sends measurements only. The laptop's USB connection and FREE-WILi UART connection can remain active during a phone connection.

- FREE-WILi blue button: hold for two seconds to request Bluetooth discovery. The screen shows `BLE: PAIRING`; blue LEDs blink and a short beep repeats until a phone connects. The Nano advertises for up to 60 seconds. On connection, the cue stops and the screen shows `BLE: CONNECTED`. After disconnection, hold blue again to reopen discovery.
- This is an app discovery/connection flow, not a passcode or bonded Bluetooth pairing. Any nearby BLE central can connect during the discovery window.
- Advertised name: `MHacks Climate`
- Service UUID: `ef05ba28-5c0a-4c52-9d3a-a643c142ba10`
- Read and notify characteristic UUID: `ef05ba28-5c0a-4c52-9d3a-a643c142ba11`
- Characteristic length: exactly 17 bytes. Read once after connecting to get the latest sample, then enable notifications for subsequent once-per-second updates. It is a binary value, not UTF-8 text.

| Byte offset | Size | Type / meaning |
| --- | --- | --- |
| 0 | 1 | `0x30`, climate record type |
| 1 | 1 | `1`, protocol version |
| 2–5 | 4 | Unsigned sequence number, little endian; wraps at 2^32 |
| 6–9 | 4 | Unsigned Nano uptime in milliseconds, little endian; wraps at 2^32 |
| 10–11 | 2 | Signed temperature in tenths of °F, little endian |
| 12–13 | 2 | Unsigned relative humidity in tenths of a percent, little endian |
| 14–15 | 2 | Unsigned raw APDS9960 clear-channel count, little endian; **not lux** |
| 16 | 1 | Validity mask: bit 0 temperature, bit 1 humidity, bit 2 light |

Ignore numeric fields whose validity bit is clear. Convert temperature for secondary display with `°C = (°F - 32) × 5 / 9`. An initial record may have mask zero before the first measurement. Accept only a 17-byte record with header `0x30`, version `1`, and mask in `0...7`. When no notification arrives for five seconds, show readings as stale instead of continuing to display old values. Detect reconnect by connection state; do not assume the sequence continues through a Nano reboot.

In an iPhone app using Core Bluetooth, create a `CBCentralManager`, prompt the user to hold FREE-WILi blue for two seconds, scan for the service UUID when Bluetooth is on, connect to `MHacks Climate`, discover the characteristic, read its current value, and call `setNotifyValue(true, for:)`. Decode each `didUpdateValueFor` value into the fields above and feed the app's algorithm. Stop notifications or disconnect when the user turns live monitoring off. Show Bluetooth-off, scanning, connected, and disconnected states in the interface. The iPhone Bluetooth Settings screen is not the data viewer; connection and subscription happen inside the app.

For a first phone check, use Nordic Semiconductor's nRF Connect for Mobile on the iPhone. Scan for `MHacks Climate`, connect, locate the service/characteristic, read it, and enable notifications. Expect a 17-byte value changing about once per second. This validates the radio path; the app still needs to decode the value.

Hardware checks completed on October 4, 2026: Nano BLE control sketch and FREE-WILi paired firmware 013 compiled and uploaded; Nano USB ping and ten sensor records passed; FREE-WILi passed ten wired UART pings and 30 seconds of display-acknowledged readings. A main-console `ble start` test changed Nano mode to `ADVERTISING` and display pairing indicator to active; `ble stop` returned both to `OFF`. The user physically held blue for two seconds, saw the iPhone discover and connect to `MHacks Climate`, observed `BLE: CONNECTED` on FREE-WILi, and heard the pairing beep stop. FREE-WILi diagnostics reported `ble=2, pairing=0` throughout the connection. The user confirmed LightBlue received changing characteristic values. The full blue-button to iPhone notification path is now verified. The laptop used for development had no available Bluetooth adapter for a radio scan. `BLE_STATUS` on Nano USB reports initialization, connection, and mode; FREE-WILi main USB `status` reports its last Nano state. The main USB `ble start` and `ble stop` commands are diagnostic equivalents of entering and leaving discovery.
