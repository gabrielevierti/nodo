import Foundation
import CoreBluetooth

// NODO GATT v1 prototype. The ESP32 firmware must implement these UUIDs.
// No implicit trust: discovered peripherals are not paired until selected by the user.
final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let serviceUUID = CBUUID(string: "B99E0001-3C1B-48F0-9F14-7B0401600001")
    static let manifestUUID = CBUUID(string: "B99E0002-3C1B-48F0-9F14-7B0401600001")
    static let stateUUID = CBUUID(string: "B99E0003-3C1B-48F0-9F14-7B0401600001")
    static let commandUUID = CBUUID(string: "B99E0004-3C1B-48F0-9F14-7B0401600001")

    @Published var discovered: [UUID: String] = [:]
    @Published var status: String = "Bluetooth starting"
    @Published var connected: Set<UUID> = []
    @Published var values: [UUID: Double] = [:]
    @Published var manifests: [UUID: String] = [:]
    @Published var lastError: [UUID: String] = [:]
    @Published var ready: Set<UUID> = []

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var commandCharacteristics: [UUID: CBCharacteristic] = [:]


    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "Ready"
        case .poweredOff: status = "Bluetooth disabled"
        case .unauthorized: status = "Bluetooth permission denied"
        case .unsupported: status = "Bluetooth unsupported"
        default: status = "Bluetooth unavailable"
        }
    }

    func scan() {
        guard central.state == .poweredOn else { return }
        discovered.removeAll()
        central.scanForPeripherals(withServices: [Self.serviceUUID])
        status = "Scanning for NODO devices"
    }
    func stopScan() { central.stopScan(); status = "Ready" }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        discovered[peripheral.identifier] = peripheral.name ?? "NODO peripheral"
    }
    func connect(_ id: UUID) {
        guard let peripheral = peripherals[id] else { return }
        peripheral.delegate = self
        central.connect(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected.insert(peripheral.identifier)
        status = "Connected to \(peripheral.name ?? "NODO device")"
        peripheral.discoverServices([Self.serviceUUID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = error?.localizedDescription ?? "Connection failed"
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected.remove(peripheral.identifier)
        ready.remove(peripheral.identifier)
        commandCharacteristics.removeValue(forKey: peripheral.identifier)
        status = "Disconnected: \(peripheral.name ?? "device")"
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { status = "Service discovery failed"; return }
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.manifestUUID, Self.stateUUID, Self.commandUUID], for: service)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { status = "Characteristic discovery failed"; return }
        for char in service.characteristics ?? [] {
            if char.uuid == Self.commandUUID {
                commandCharacteristics[peripheral.identifier] = char
                if char.properties.contains(.write) { ready.insert(peripheral.identifier) }
            }
            if char.uuid == Self.manifestUUID || char.uuid == Self.stateUUID {
                if char.properties.contains(.read) { peripheral.readValue(for: char) }
                if char.uuid == Self.stateUUID && char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, data.count <= 4096 else { return }
        if characteristic.uuid == Self.manifestUUID {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["protocol"] as? String == "nodo/1",
                  json["kind"] as? String == "switch" else {
                lastError[peripheral.identifier] = "Unsupported device manifest"; return
            }
            manifests[peripheral.identifier] = String(data: data, encoding: .utf8)
        } else if characteristic.uuid == Self.stateUUID,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let number = obj["value"] as? NSNumber {
            values[peripheral.identifier] = number.doubleValue
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { lastError[peripheral.identifier] = error.localizedDescription }
    }
    func send(_ command: String, value: Double?, to id: UUID) -> Bool {
        guard let peripheral = peripherals[id], connected.contains(id),
              ready.contains(id), let characteristic = commandCharacteristics[id],
              characteristic.properties.contains(.write) else { return false }
        var object: [String: Any] = ["command": command]
        if let value { object["value"] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: object), data.count <= 180 else { return false }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        return true // Queued only: state updates arrive from ESP32 notifications.
    }
}
