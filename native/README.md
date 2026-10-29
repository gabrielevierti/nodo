# NODO M3 · Dashboard Studio

This native SwiftUI iPad app runs locally without a server. Open `native/` in Terminal, run `xcodegen generate`, then open `NODO.xcodeproj` in Xcode and run an iPad simulator. The bundled M1 BLE code is preserved for future hardware tests.

M3 includes named dashboards, per-dashboard light/dark theme, accent colors, dashboard columns, per-widget widths in columns, visibility, drag-to-reorder in Studio and the Dashboard, and local state persistence with migration from M2 snapshots.

Drag a widget onto another widget to reorder. Widgets sized 2/3 columns occupy the corresponding relative width. UserDefaults stores small dashboard layouts and device snapshots. This is a source prototype, not yet compiled or tested on Apple hardware in this environment. Bluetooth connectivity still requires physical testing.

The M3 editor currently supports a column-based canvas rather than unrestricted pixel positioning; freeform resizing/custom widget authoring remain future milestones.

M4: Studio → Widget Engine provides per-dashboard widgets (slider, button, joystick, gauge, chart) with local persisted settings and optional device binding. Chart data is demonstrative; joystick is single-axis only.
