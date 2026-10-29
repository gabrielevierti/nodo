import Foundation
import SwiftUI
import Combine

@MainActor final class DeviceStore: ObservableObject {
    @Published var devices: [NODODevice] = [] { didSet { persist() } }
    @Published var preferences = DashboardPreferences() { didSet { persist() } }
    @Published var message: String? = nil
    @Published var dashboards: [NODODashboard] = [] { didSet { persist() } }
    @Published var activeDashboardID: String = "home" { didSet { persist() } }
    @Published var ble = BLEManager()
    private var observations = Set<AnyCancellable>()
    private let storageKey = "nodo.app.local.v1"
    private var isLoading = true

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            devices = snapshot.devices
            preferences = snapshot.preferences
            dashboards = snapshot.dashboards ?? []
            activeDashboardID = snapshot.activeDashboardID ?? "home"
        } else {
            devices = [
                .init(id:"demo-cover",name:"Tende soggiorno",room:"Soggiorno",kind:.cover,transport:.demo,value:65,online:true),
                .init(id:"demo-light",name:"Luce studio",room:"Studio",kind:.light,transport:.demo,value:80,online:true),
                .init(id:"demo-sensor",name:"Temperatura",room:"Soggiorno",kind:.sensor,transport:.demo,value:22.4,online:true),
                .init(id:"demo-switch",name:"Ventilatore",room:"Studio",kind:.switchDevice,transport:.demo,value:0,online:true)
            ]
        }
        if dashboards.isEmpty {
            dashboards = [NODODashboard(id:"home",name:"My home",symbol:"house",widgetIDs:preferences.order.isEmpty ? devices.map(\.id) : preferences.order,hiddenIDs: preferences.visibilityConfigured ? devices.map(\.id).filter{ !preferences.visibleIDs.contains($0) } : [], spans:Dictionary(uniqueKeysWithValues:preferences.wideIDs.map{($0,2)}),columns:preferences.columns,accent:preferences.accent)]
        }
        if !dashboards.contains(where:{$0.id == activeDashboardID}) { activeDashboardID = dashboards[0].id }
        isLoading = false
        ble.$connected.combineLatest(ble.$ready, ble.$values, ble.$manifests)
            .receive(on: RunLoop.main)
            .sink { [weak self] connected, ready, values, manifests in
                self?.syncBLE(connected: connected, ready: ready, values: values, manifests: manifests)
            }.store(in: &observations)
        ble.$lastError.receive(on: RunLoop.main).sink { [weak self] errors in
            if let error = errors.values.first { self?.message = error }
        }.store(in: &observations)
    }
    private func syncBLE(connected: Set<UUID>, ready: Set<UUID>, values: [UUID: Double], manifests: [UUID: String]) {
        for index in devices.indices where devices[index].transport == .ble {
            guard let raw = devices[index].peripheralUUID, let uuid = UUID(uuidString: raw) else { continue }
            devices[index].online = connected.contains(uuid) && ready.contains(uuid) && manifests[uuid] != nil
            if let manifest = manifests[uuid],
               let data = manifest.data(using: .utf8),
               let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               payload["kind"] as? String == "switch" {
                devices[index].kind = .switchDevice
                if let name = payload["name"] as? String { devices[index].name = name }
            }
            if let value = values[uuid] { devices[index].value = value }
        }
    }
    private struct Snapshot: Codable { var devices: [NODODevice]; var preferences: DashboardPreferences; var dashboards: [NODODashboard]?; var activeDashboardID: String? }
    private func persist() {
        guard !isLoading, let data = try? JSONEncoder().encode(Snapshot(devices:devices, preferences:preferences, dashboards:dashboards, activeDashboardID:activeDashboardID)) else { return }
        UserDefaults.standard.set(data, forKey:storageKey)
    }
    func setValue(id: String, value: Double) {
        guard let index = devices.firstIndex(where: {$0.id == id}) else { return }
        if devices[index].transport == .demo { devices[index].value = value; return }
        if devices[index].transport == .ble, let string = devices[index].peripheralUUID, let uuid = UUID(uuidString:string) {
            let command = devices[index].kind == .switchDevice ? "set_power" : "set_value"
            if !ble.send(command, value:value, to:uuid) { message = "Device unavailable or command unsupported" }
            // Actual value must arrive from device state notification.
        } else { message = "This transport isn't implemented yet" }
    }
    func addBLE(_ uuid: UUID, name: String) {
        if devices.contains(where: {$0.peripheralUUID == uuid.uuidString}) {
            ble.connect(uuid)
            return
        }
        devices.append(.init(id:"ble-\(uuid.uuidString)",name:name,room:"Unassigned",kind:.custom,transport:.ble,value:0,online:false,peripheralUUID:uuid.uuidString))
        ble.connect(uuid)
    }
    var arrangedDevices: [NODODevice] {
        devices.sorted {
            let lhs = preferences.order.firstIndex(of: $0.id) ?? Int.max
            let rhs = preferences.order.firstIndex(of: $1.id) ?? Int.max
            return lhs == rhs ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lhs < rhs
        }
    }
    var visibleDevices: [NODODevice] {
        arrangedDevices.filter { !preferences.visibilityConfigured || preferences.visibleIDs.contains($0.id) }
    }
    func setVisible(_ visible: Bool, id: String) {
        if !preferences.visibilityConfigured {
            preferences.visibleIDs = devices.map(\.id)
            preferences.visibilityConfigured = true
        }
        if visible && !preferences.visibleIDs.contains(id) { preferences.visibleIDs.append(id) }
        if !visible { preferences.visibleIDs.removeAll { $0 == id } }
    }
    func setWide(_ wide: Bool, id: String) {
        if wide && !preferences.wideIDs.contains(id) { preferences.wideIDs.append(id) }
        if !wide { preferences.wideIDs.removeAll { $0 == id } }
    }
    func move(_ id: String, by amount: Int) {
        var ids = arrangedDevices.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + amount) else { return }
        ids.swapAt(index, index + amount)
        preferences.order = ids
    }
    func restoreLayout() { preferences = DashboardPreferences() }

}

// MARK: - M3 dashboard studio
extension DeviceStore {
    var activeDashboard: NODODashboard {
        dashboards.first(where: { $0.id == activeDashboardID }) ?? dashboards[0]
    }
    var orderedDevicesForActiveDashboard: [NODODevice] {
        let ids = activeDashboard.widgetIDs + devices.map(\.id).filter { !activeDashboard.widgetIDs.contains($0) }
        return ids.compactMap { id in devices.first(where:{$0.id == id}) }
    }
    var activeDevices: [NODODevice] {
        let page = activeDashboard
        let order = page.widgetIDs + devices.map(\.id).filter { !page.widgetIDs.contains($0) }
        return order.compactMap { id in devices.first(where: { $0.id == id && !page.hiddenIDs.contains(id) }) }
    }
    func editDashboard(_ transform: (inout NODODashboard) -> Void) {
        guard let index = dashboards.firstIndex(where:{$0.id == activeDashboardID}) else { return }
        transform(&dashboards[index])
        dashboards[index].columns = min(3,max(1,dashboards[index].columns))
    }
    func createDashboard() {
        let page = NODODashboard(name:"New dashboard", symbol:"square.grid.2x2", widgetIDs:devices.map(\.id))
        dashboards.append(page)
        activeDashboardID = page.id
    }
    func deleteActiveDashboard() {
        guard dashboards.count > 1 else { return }
        dashboards.removeAll(where:{$0.id == activeDashboardID})
        activeDashboardID = dashboards[0].id
    }
    func moveWidget(_ source: String, before destination: String) {
        guard source != destination else { return }
        editDashboard { page in
            var ids = page.widgetIDs + devices.map(\.id).filter { !page.widgetIDs.contains($0) }
            guard ids.contains(source), ids.contains(destination) else { return }
            ids.removeAll(where:{$0 == source})
            guard let target = ids.firstIndex(of:destination) else { return }
            ids.insert(source,at:target)
            page.widgetIDs=ids
        }
    }
    func setWidgetHidden(_ id:String, hidden:Bool) {
        editDashboard { page in
            page.hiddenIDs.removeAll(where:{$0 == id})
            if hidden { page.hiddenIDs.append(id) }
        }
    }
    func setWidgetSpan(_ id:String, span:Int) {
        editDashboard { page in page.spans[id] = min(3,max(1,span)) }
    }
    func addWidget(_ id:String) {
        editDashboard { page in
            if !page.widgetIDs.contains(id) { page.widgetIDs.append(id) }
            page.hiddenIDs.removeAll(where:{$0 == id})
        }
    }
}


// MARK: - M4 Widget Engine
extension DeviceStore {
    var activeCustomWidgets: [NODOWidget] { activeDashboard.customWidgets ?? [] }
    func addCustomWidget(kind: NODOWidgetKind) {
        editDashboard { board in
            var items = board.customWidgets ?? []
            items.append(NODOWidget(title: kind.label, kind: kind))
            board.customWidgets = items
        }
    }
    func updateCustomWidget(_ widget: NODOWidget) {
        editDashboard { board in
            guard let index = (board.customWidgets ?? []).firstIndex(where: { $0.id == widget.id }) else { return }
            board.customWidgets?[index] = widget
        }
    }
    func deleteCustomWidget(_ id: String) {
        editDashboard { board in board.customWidgets?.removeAll(where: { $0.id == id }) }
    }
    func moveCustomWidgets(from offsets: IndexSet, to destination: Int) {
        editDashboard { board in
            var widgets = board.customWidgets ?? []
            // Equivalent to SwiftUI move with explicit array operations.
            let selected = offsets.sorted().map { widgets[$0] }
            for i in offsets.sorted(by: >) { widgets.remove(at: i) }
            let shift = offsets.filter { $0 < destination }.count
            widgets.insert(contentsOf: selected, at: min(widgets.count, max(0, destination - shift)))
            board.customWidgets = widgets
        }
    }
}


// MARK: - M5 portable canvas and templates
extension DeviceStore {
    var canvasPlacements: [String: NODOPlacement] {
        let widgets = activeCustomWidgets
        let saved = activeDashboard.canvasPlacements ?? [:]
        var result = saved
        // First upgrade from M4: preserve order and IDs, create non-overlapping grid positions.
        for (index, widget) in widgets.enumerated() where result[widget.id] == nil {
            result[widget.id] = NODOPlacement(column:(index % 3) * 2,row:(index / 3) * 2,columns:2,rows:2)
        }
        return result
    }
    func placeCustomWidget(_ id: String, _ placement: NODOPlacement) {
        editDashboard { board in
            var placements = board.canvasPlacements ?? [:]
            let safe = NODOPlacement(column:min(5,max(0,placement.column)),
                row:min(18,max(0,placement.row)),columns:min(6,max(1,placement.columns)),
                rows:min(6,max(1,placement.rows)))
            placements[id] = NODOPlacement(column:min(safe.column,6-safe.columns),row:safe.row,
                                           columns:safe.columns,rows:safe.rows)
            board.canvasPlacements = placements
        }
    }
    func makeTemplate() -> NODOTemplate {
        var widgets = activeCustomWidgets
        // Bindings are device-specific and MUST NOT be exported.
        for i in widgets.indices { widgets[i].deviceID = nil }
        return NODOTemplate(title:activeDashboard.name,symbol:activeDashboard.symbol,
                            accent:activeDashboard.accent,theme:activeDashboard.theme,
                            widgets:widgets,placements:canvasPlacements)
    }
    func importTemplate(_ template: NODOTemplate) throws {
        guard template.format == "nodo.layout/1", template.widgets.count <= 80,
              template.title.count <= 100, template.widgets.allSatisfy({$0.title.count <= 100}) else {
            throw NODOTemplateError.invalid
        }
        var board=NODODashboard(name:template.title,symbol:template.symbol,widgetIDs:[],
                                accent:["teal","blue","amber","violet"].contains(template.accent) ? template.accent : "teal",
                                theme:["light","dark"].contains(template.theme) ? template.theme : "dark")
        var remapped: [String:NODOPlacement] = [:]
        var widgets: [NODOWidget] = []
        for incoming in template.widgets {
            var widget=incoming
            widget.id=UUID().uuidString
            widget.deviceID=nil // imported templates never take control of hardware
            widgets.append(widget)
            if let pos=template.placements[incoming.id] {
                let width=min(6,max(1,pos.columns))
                remapped[widget.id]=NODOPlacement(column:min(6-width,max(0,pos.column)),
                    row:min(18,max(0,pos.row)),columns:width,rows:min(6,max(1,pos.rows)))
            }
        }
        board.customWidgets=widgets
        board.canvasPlacements=remapped
        dashboards.append(board)
        activeDashboardID=board.id
    }
}
enum NODOTemplateError: LocalizedError {
    case invalid
    var errorDescription: String? { "Unsupported or invalid NODO layout file" }
}
