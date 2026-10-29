# NODO M1 — ESP32 switch via Bluetooth LE

## What works
- iPad discovers ESP32 by NODO service UUID and connects with CoreBluetooth.
- ESP32 exposes `nodo/1` switch manifest, state characteristic and writable command.
- NODO turns a connected device into a switch widget and consumes state notifications.
- Previously added BLE devices remain in the local list, but must be manually reconnected via Add device after restarting the app.

## Hardware test
1. Install **Espressif Arduino-ESP32 boards package (3.x)** in Arduino IDE. Choose your ESP32-S3 target.
2. Open `firmware/esp32-nodo-ble-switch/esp32-nodo-ble-switch.ino`. Connect an LED **with suitable series resistor** to a safe GPIO and GND; change `OUTPUT_PIN` to match. Some Freenove boards have GPIO2 already occupied by peripherals: consult board schematic before wiring.
3. Upload sketch; observe `NODO M1 BLE switch advertising` in Serial Monitor (115200).
4. In Xcode from `native/`, run `xcodegen generate`, open project and run on a **physical iPad**. Simulator Bluetooth scanning is insufficient.
5. Enable Bluetooth and grant NODO permission. Tap Add device → Scan for NODO devices → NODO ESP32 Demo.
6. Return to Home. Once connected, an `ESP32 Demo LED` switch appears; toggle it. GPIO output must follow and state return through BLE notify/read.
7. Disconnect power: card should turn Offline; reconnect through Add device after reboot.

## Security and limitations
Prototype only. There is **no authenticated pairing or encrypted application-level command channel**. A nearby BLE client can issue commands. Do not use with locks, alarms, high-voltage relays, heaters, safety systems or unattended motors. Commands only update UI after BLE state, not when merely submitted. Manifest is restricted to a single switch device; complete capability schema and secure bonding are future work.

App BLE characteristics and firmware UUIDs are defined in `native/NODO/Services/BLEManager.swift`.
