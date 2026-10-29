# NODO

<img width="896" height="625" alt="Screenshot 2026-10-29 at 16 36 36" src="https://github.com/user-attachments/assets/45b0d3fa-8c02-4566-8e1d-90d99f8a8dab" />

**Your devices. Your interface.**

NODO is an experimental, local-first maker dashboard for iPad. Build customizable control surfaces for DIY electronics, and grow towards a unified home control experience. 

## Run on a Mac

Install [Xcode](https://developer.apple.com/xcode/) and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then:

```bash
cd native
xcodegen generate
open NODO.xcodeproj
```

Choose an iPad simulator and press **⌘R**. The demo mode needs no server and no connected ESP32. For BLE, use a physical iPad and compatible Arduino firmware; consult [M1 hardware guide](docs/M1-HARDWARE.md).

## Contributions and distribution

MIT licensed (see [LICENSE](LICENSE)). Open issues with device models, firmware version, iPadOS version and exact reproduction steps. Do not commit pairing credentials, Wi-Fi secrets, or local `.env` files.

For a new GitHub repository, create `gabrielevierti/nodo`, then push the contents of this directory to its `main` branch.
