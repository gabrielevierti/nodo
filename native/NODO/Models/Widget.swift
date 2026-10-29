import Foundation

// NODO widgets are independent from the transport protocol. A binding references
// one device and its normalized primary value; no arbitrary scripts are executed.
enum NODOWidgetKind: String, Codable, CaseIterable, Identifiable {
    case slider, button, joystick, gauge, chart
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .slider: "slider.horizontal.3"
        case .button: "hand.tap"
        case .joystick: "circle.grid.cross"
        case .gauge: "gauge.with.dots.needle.67percent"
        case .chart: "chart.xyaxis.line"
        }
    }
}

struct NODOWidget: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var kind: NODOWidgetKind
    var deviceID: String? = nil
    var width: Int = 1
    var minimum: Double = 0
    var maximum: Double = 100
    var step: Double = 5
    var actionValue: Double = 1
    // An unbound widget stays as an explicitly marked interactive preview.
    init(title: String, kind: NODOWidgetKind, deviceID: String? = nil) {
        self.title = title; self.kind = kind; self.deviceID = deviceID
    }
}


// Grid coordinates are logical, not pixels. Layouts remain portable between iPads.
struct NODOPlacement: Codable, Equatable {
    var column: Int = 0
    var row: Int = 0
    var columns: Int = 2
    var rows: Int = 2
}

// Export contains UI metadata only. Device identifiers and credentials are excluded.
struct NODOTemplate: Codable {
    var format: String = "nodo.layout/1"
    var title: String
    var symbol: String
    var accent: String
    var theme: String
    var widgets: [NODOWidget]
    var placements: [String: NODOPlacement]
}
