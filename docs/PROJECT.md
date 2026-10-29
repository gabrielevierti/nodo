# NODO — Product specification (living document)

## Product
NODO (no trailing dot in name, wordmark, bundle metadata or public copy) is a local-first, open-source customizable control surface for maker hardware and supported smart-home devices. An iPad should work without a server for foreground control. Raspberry Pi NODO Core is an optional always-on automation hub.

## Users / jobs
1. A tinkerer builds an ESP32 motor, exposes a NODO profile, connects from iPad, controls it and creates a widget.
2. A household member opens a saved dashboard and operates approved accessories without editing electronics settings.
3. A smart-home owner integrates compatible commercial products using isolated provider adapters, without false promises of universal compatibility.

## Architecture boundaries
- `native/`: SwiftUI iPad app, CoreBluetooth and future LAN/Matter adapters; own local device registry and dashboards.
- `core/` + `web/`: existing optional Python hub and browser dashboard, maintained separately; no mandatory server for the native prototype.
- `firmware/`: example peripherals; motor interlocks belong on-device.
- `protocol/`: transport-neutral capabilities, message envelopes, protocol version, bounded payloads, acknowledgments.

## Release rules
- No direct command should be optimistically marked physically executed. Distinguish requested / accepted / confirmed state.
- Device pairing must acquire explicit approval and bind stable identity before production deployment.
- Do not rely on iPad background execution for safety-critical or 24/7 automation. On-device schedules or optional Core handle unattended execution.
- Commercial protocol support is additive (Matter, HomeKit when authorized, LAN APIs, existing bridges); availability depends on manufacturer and platform permissions.
- UI configurations persist locally; future export/import must be versioned and validated.
- NODO must work in demo mode with no hardware or cloud account.

## Capabilities
`switch`, `level`, `position`, `temperature`, `humidity`, `color`, `momentary`, `servo`, `camera` (planned). Capabilities describe range, units, read/write actions, and control widget. Adapters translate real transport messages to these semantic types.

## Delivery milestones
- M0: native shell, sample dashboard, local persistence, BLE scan/connect/JSON GATT, native project generator (this starter).
- M1: production BLE fragmentation/reassembly, firmware reference, manifest validation, identity challenge/approval, notifications and state sync, tests on physical iPad.
- M2: Wi-Fi Bonjour discovery + signed local pairing; HTTP/WebSocket adapters; genuine Raspberry Pi device profile.
- M3: dashboard drag/drop, resizing, themes, per-room pages, import/export, live preview, accessibility.
- M4: Matter and selected commercial smart integrations verified on supported accessories.
- M5: device-owned local automation, optional Core orchestration, secure upgrades, beta testing, installation/distribution.

## Explicit non-goals for the first release
No universal control of arbitrary Bluetooth devices, no arbitrary firmware flashing from iPad, no proprietary cloud account harvesting, no background iPad server, no mains hardware certification.
