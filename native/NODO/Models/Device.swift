import Foundation

enum DeviceKind: String, Codable, CaseIterable {
    case cover, light, sensor, switchDevice = "switch", servo, custom
    var symbol: String {
        switch self {
        case .cover: "window.shade.open"
        case .light: "lightbulb.fill"
        case .sensor: "thermometer.medium"
        case .switchDevice: "power"
        case .servo: "gearshape.2.fill"
        case .custom: "cpu"
        }
    }
}

enum Transport: String, Codable { case demo, ble, lan, matter, integration }

struct NODODevice: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var room: String
    var kind: DeviceKind
    var transport: Transport
    var value: Double
    var online: Bool
    var peripheralUUID: String? = nil
    var lastError: String? = nil
}

struct DashboardPreferences: Codable {
    var accent: String = "teal"
    var columns: Int = 2
    var visibleIDs: [String] = []
    var order: [String] = []
    var wideIDs: [String] = []
    var visibilityConfigured: Bool = false

    init() {}
    private enum CodingKeys: String, CodingKey { case accent, columns, visibleIDs, order, wideIDs, visibilityConfigured }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "teal"
        columns = min(3, max(1, try c.decodeIfPresent(Int.self, forKey: .columns) ?? 2))
        visibleIDs = try c.decodeIfPresent([String].self, forKey: .visibleIDs) ?? []
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        wideIDs = try c.decodeIfPresent([String].self, forKey: .wideIDs) ?? []
        // M1 stored an empty array to mean all widgets visible.
        visibilityConfigured = try c.decodeIfPresent(Bool.self, forKey: .visibilityConfigured) ?? !visibleIDs.isEmpty
    }
}

// A dashboard is an independent, locally stored canvas.
struct NODODashboard: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var symbol: String
    var widgetIDs: [String]
    var hiddenIDs: [String] = []
    var spans: [String: Int] = [:]
    var columns: Int = 2
    var accent: String = "teal"
    var theme: String = "dark"
    // Optional for backwards-compatible loading of dashboards created in M3.
    var customWidgets: [NODOWidget]? = nil
    var canvasPlacements: [String: NODOPlacement]? = nil

    init(id: String = UUID().uuidString, name: String, symbol: String = "square.grid.2x2", widgetIDs: [String] = [], hiddenIDs: [String] = [], spans: [String:Int] = [:], columns: Int = 2, accent: String = "teal", theme: String = "dark") {
        self.id=id; self.name=name; self.symbol=symbol; self.widgetIDs=widgetIDs; self.hiddenIDs=hiddenIDs; self.spans=spans; self.columns=columns; self.accent=accent; self.theme=theme
    }
}
