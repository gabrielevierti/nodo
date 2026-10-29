import SwiftUI
import Charts

// Preview widgets never send commands. Bound controls use the same normalized
// value channel as existing NODO device cards. Real device state is authoritative.
struct NODOWidgetCard: View {
    @EnvironmentObject private var store: DeviceStore
    let widget: NODOWidget
    let accent: Color
    let card: Color
    @State private var demoValue = 50.0
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var history: [Double] = [35,42,39,48,58,53,66,61,72,68,75,70]

    private var device: NODODevice? { store.devices.first(where: { $0.id == widget.deviceID }) }
    private var isWritable: Bool { device.map { $0.transport == .demo || $0.online } ?? false }
    private var value: Double { device?.value ?? demoValue }
    private var range: ClosedRange<Double> { min(widget.minimum, widget.maximum - 0.01)...max(widget.minimum + 0.01, widget.maximum) }
    private func send(_ value: Double) {
        guard let device else { demoValue = value; return }
        guard isWritable, device.kind != .sensor else { return }
        store.setValue(id: device.id, value: value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(widget.title, systemImage: widget.kind.symbol).font(.headline)
                Spacer()
                if device == nil { Text("PREVIEW").font(.caption2.bold()).foregroundStyle(.secondary) }
                else { Image(systemName: device?.online == true ? "checkmark.circle.fill" : "wifi.slash")
                    .foregroundStyle(device?.online == true ? accent : .orange) }
            }
            switch widget.kind {
            case .slider:
                HStack { Text("Value"); Spacer(); Text(value.formatted(.number.precision(.fractionLength(0)))) }
                Slider(value: Binding(get: { min(max(value,range.lowerBound),range.upperBound) },set:send), in:range, step:max(0.01, widget.step))
                    .tint(accent).disabled(device != nil && (!isWritable || device?.kind == .sensor))
            case .button:
                Button { send(widget.actionValue) } label: {
                    Label("Send command",systemImage:"bolt.fill").frame(maxWidth:.infinity)
                }.buttonStyle(.borderedProminent).tint(accent)
                    .disabled(device != nil && (!isWritable || device?.kind == .sensor))
            case .gauge:
                Gauge(value: min(max(value,range.lowerBound),range.upperBound),in:range) {
                    Text(widget.title)
                } currentValueLabel: {
                    Text(value.formatted(.number.precision(.fractionLength(1))))
                }.gaugeStyle(.accessoryCircularCapacity).tint(accent).scaleEffect(1.35).frame(height:110)
            case .chart:
                Chart(Array(history.enumerated()),id: \.offset) { index, sample in
                    LineMark(x:.value("Sample",index),y:.value("Value",sample)).foregroundStyle(accent)
                }.frame(height:125)
                Text(device == nil ? "Sample data · not live" : "Sample data · live history not implemented")
                    .font(.caption).foregroundStyle(.secondary)
            case .joystick:
                GeometryReader { geometry in
                    let diameter = min(geometry.size.width, 170.0)
                    ZStack {
                        Circle().fill(accent.opacity(0.13)).overlay(Circle().strokeBorder(accent.opacity(0.5)))
                        Circle().fill(accent).frame(width:38,height:38).offset(x:x * (diameter-38)/2,y:y * (diameter-38)/2)
                    }
                    .frame(width:diameter,height:diameter)
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance:0)
                        .onChanged { event in
                            let radius = max(1,(diameter-38)/2)
                            x = min(1,max(-1,(event.location.x-diameter/2)/radius))
                            y = min(1,max(-1,(event.location.y-diameter/2)/radius))
                            // M4 sends a single normalized horizontal axis. A later
                            // protocol revision will expose multi-axis control.
                            if device != nil { send((x + 1) * 50) }
                        }
                        .onEnded { _ in x=0;y=0; if device != nil { send(50) } })
                }.frame(height:180)
                Text("X: \(x,specifier:"%.2f") · Y: \(y,specifier:"%.2f")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text("Single-axis preview; do not use for safety-critical motors")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if let device { Text("\(device.name) · \(device.transport.rawValue.uppercased())").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(20).frame(maxWidth:.infinity,alignment:.leading)
        .background(card,in:RoundedRectangle(cornerRadius:18))
    }
}

struct NODOWidgetStudio: View {
    @EnvironmentObject private var store: DeviceStore
    let accent: Color
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Widget Engine").font(.title3.bold())
            Text("Add controls and bind them to a device. Unbound widgets run in preview mode. Changes save automatically on this dashboard.")
                .font(.caption).foregroundStyle(.secondary)
            Menu {
                ForEach(NODOWidgetKind.allCases) { kind in
                    Button { store.addCustomWidget(kind:kind) } label: {
                        Label(kind.label,systemImage:kind.symbol)
                    }
                }
            } label: { Label("Add custom widget",systemImage:"plus.square.on.square") }
                .buttonStyle(.borderedProminent).tint(accent)
            ForEach(store.activeCustomWidgets) { widget in
                WidgetSettingsRow(widget:widget,accent:accent)
            }
        }
    }
}

private struct WidgetSettingsRow: View {
    @EnvironmentObject private var store: DeviceStore
    let widget: NODOWidget
    let accent: Color
    private var deviceBinding: Binding<String> {
        Binding(get:{ widget.deviceID ?? "" },set: { id in
            var copy=widget; copy.deviceID=id.isEmpty ? nil : id;store.updateCustomWidget(copy)
        })
    }
    private func edit(_ mutation: (inout NODOWidget)->Void) {
        var copy=widget;mutation(&copy);store.updateCustomWidget(copy)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Image(systemName:widget.kind.symbol).foregroundStyle(accent)
                TextField("Widget name",text:Binding(get:{widget.title},set:{ title in edit{$0.title=title} }))
                    .textFieldStyle(.roundedBorder)
                Button(role:.destructive) { store.deleteCustomWidget(widget.id) } label: { Image(systemName:"trash") }
            }
            HStack {
                Picker("Device",selection:deviceBinding) {
                    Text("Preview / unbound").tag("")
                    ForEach(store.devices) { device in Text(device.name).tag(device.id) }
                }
                Picker("Width",selection:Binding(get:{widget.width},set:{v in edit{$0.width=v}})) {
                    ForEach(1...store.activeDashboard.columns,id:\.self) { n in Text("\(n) col").tag(n) }
                }.frame(width:135)
            }
            if widget.kind == .slider || widget.kind == .gauge {
                HStack {
                    Text("Min"); TextField("Min",value:Binding(get:{widget.minimum},set:{v in edit{$0.minimum=v}}),format:.number).frame(width:65).textFieldStyle(.roundedBorder)
                    Text("Max"); TextField("Max",value:Binding(get:{widget.maximum},set:{v in edit{$0.maximum=v}}),format:.number).frame(width:65).textFieldStyle(.roundedBorder)
                    if widget.kind == .slider {
                        Text("Step"); TextField("Step",value:Binding(get:{widget.step},set:{v in edit{$0.step=max(0.01,v)}}),format:.number).frame(width:65).textFieldStyle(.roundedBorder)
                    }
                }.font(.caption)
            }
            if widget.kind == .button {
                HStack {
                    Text("Command value")
                    TextField("Value",value:Binding(get:{widget.actionValue},set:{v in edit{$0.actionValue=v}}),format:.number)
                        .textFieldStyle(.roundedBorder).frame(width:100)
                }.font(.caption)
            }
        }
        .padding(12).background(.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
    }
}
