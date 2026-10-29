# NODO BLE GATT prototype protocol (draft v0)

Service `B99E0001-3C1B-48F0-9F14-7B0401600001` (advertised)
- Manifest (read): `B99E0002-3C1B-48F0-9F14-7B0401600001`, UTF-8 JSON `{"protocol":"nodo/1","name":"Tende","capabilities":[{"id":"position","type":"position","min":0,"max":100}]}`
- State (read/notify): `B99E0003-3C1B-48F0-9F14-7B0401600001`, UTF-8 JSON `{"value":65}`
- Command (write-with-response): `B99E0004-3C1B-48F0-9F14-7B0401600001`, UTF-8 JSON `{"command":"set_value","value":75}`

**Prototype only:** no transport framing/fragmentation; command size presently limited to 180 bytes and manifest/state to 4096 bytes. Most BLE ATT MTUs cannot fit a large manifest in one read, so multi-capability manifests require a negotiated/chunked protocol. Readback state is authoritative; write acknowledgment only confirms transport, not actuation. BLE security must add device identity, pairing approval, authorization and replay prevention before controlling real actuators. Do not use on safety-sensitive equipment. Firmware GATT implementation is an M1 deliverable, not included in this version.
