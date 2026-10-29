import SwiftUI

struct ScannerView: View {
    @EnvironmentObject private var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    Text(store.ble.status).foregroundStyle(.secondary)
                    Button("Scan for NODO devices") { store.ble.scan() }
                    ForEach(store.ble.discovered.keys.sorted(by:{$0.uuidString < $1.uuidString}),id:\.self) { id in
                        Button {
                            store.addBLE(id,name:store.ble.discovered[id] ?? "NODO device")
                            store.ble.stopScan(); dismiss()
                        } label: {
                            HStack { Image(systemName:"cpu");Text(store.ble.discovered[id] ?? id.uuidString);Spacer();Image(systemName:"plus.circle") }
                        }
                    }
                }
                Section("Supported today") {
                    Text("NODO M1: ESP32 switch over BLE. Select a discovered device to connect or reconnect it. Device status is confirmed by BLE notifications. Commercial devices are not yet supported.")
                }
            }
            .navigationTitle("Add a device")
            .toolbar { Button("Close") { store.ble.stopScan();dismiss() } }
        }
    }
}
