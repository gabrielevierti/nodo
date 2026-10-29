import SwiftUI
import UniformTypeIdentifiers

private enum Style {
    static func accent(_ key: String) -> Color {
        switch key {
        case "blue": return Color(red:0.48,green:0.69,blue:0.96)
        case "amber": return Color(red:0.94,green:0.75,blue:0.48)
        case "violet": return Color(red:0.76,green:0.62,blue:0.96)
        default: return Color(red:0.42,green:0.84,blue:0.79)
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var section = 0
    @State private var showScanner = false
    @State private var editing = false
    @State private var showDeleteConfirmation = false

    private var board: NODODashboard { store.activeDashboard }
    private var accent: Color { Style.accent(board.accent) }
    private var isLight: Bool { board.theme == "light" }
    private var background: Color { isLight ? Color(red:0.94,green:0.96,blue:0.97) : Color(red:0.065,green:0.09,blue:0.105) }
    private var card: Color { isLight ? .white : Color(red:0.115,green:0.17,blue:0.185) }

    private var rows: [[NODODevice]] {
        var output:[[NODODevice]] = []
        var current:[NODODevice] = []
        var used = 0
        let columns=board.columns
        for device in store.activeDevices {
            let span=min(columns,max(1,board.spans[device.id] ?? 1))
            if used+span > columns && !current.isEmpty {
                output.append(current); current=[]; used=0
            }
            current.append(device); used += span
            if used == columns { output.append(current); current=[]; used=0 }
        }
        if !current.isEmpty { output.append(current) }
        return output
    }
    var body: some View {
        NavigationStack {
            HStack(spacing:0) {
                VStack(alignment:.leading,spacing:16) {
                    Text("NODO").font(.system(size:34,weight:.bold,design:.rounded)).foregroundStyle(accent).padding(.bottom,20)
                    nav("Dashboard",symbol:"house",index:0)
                    nav("Devices",symbol:"cpu",index:1)
                    nav("Studio",symbol:"slider.horizontal.3",index:2)
                    Divider()
                    Text("DASHBOARDS").font(.caption2.bold()).foregroundStyle(.secondary)
                    ForEach(store.dashboards) { page in
                        Button { store.activeDashboardID=page.id; section=0 } label: {
                            Label(page.name,systemImage:page.symbol).lineLimit(1)
                                .foregroundStyle(store.activeDashboardID == page.id ? accent : .secondary)
                                .frame(maxWidth:.infinity,alignment:.leading)
                        }.buttonStyle(.plain).padding(.vertical,5)
                    }
                    Button { store.createDashboard();section=2 } label: { Label("New dashboard",systemImage:"plus") }
                        .font(.caption).tint(accent).padding(.top,5)
                    Spacer()
                    Text("LOCAL FIRST").font(.caption2).foregroundStyle(.secondary)
                }.padding(22).frame(width:210,alignment:.leading)
                Rectangle().fill(.gray.opacity(0.18)).frame(width:1)
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        HStack {
                            VStack(alignment:.leading,spacing:5) {
                                Text(section == 1 ? "Devices" : section == 2 ? "NODO Studio" : board.name)
                                    .font(.system(size:30,weight:.semibold))
                                Text("Your devices. Your interface.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if section == 0 {
                                Button { editing.toggle() } label: { Label(editing ? "Done" : "Edit layout",systemImage:editing ? "checkmark" : "square.dashed") }
                                    .buttonStyle(.bordered).tint(accent)
                            }
                            Button { showScanner=true } label: { Label("Add device",systemImage:"plus") }
                                .buttonStyle(.borderedProminent).tint(accent)
                        }
                        if section == 0 { dashboard }
                        else if section == 1 { deviceList }
                        else { studio }
                        if let message=store.message { Text(message).font(.caption).foregroundStyle(.orange) }
                    }.padding(28).frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            .background(background)
            .preferredColorScheme(isLight ? .light : .dark)
            .sheet(isPresented:$showScanner) { ScannerView() }
            .confirmationDialog("Delete this dashboard?",isPresented:$showDeleteConfirmation) {
                Button("Delete dashboard",role:.destructive) { store.deleteActiveDashboard() }
            } message: { Text("Devices and other dashboards will not be deleted.") }
        }
    }
    private func nav(_ title:String,symbol:String,index:Int)->some View {
        Button { section=index; editing=false } label: {
            Label(title,systemImage:symbol).font(.headline)
                .foregroundStyle(section == index ? accent : .secondary)
                .frame(maxWidth:.infinity,alignment:.leading).padding(11)
                .background(section == index ? card : .clear,in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain)
    }
    private var dashboard: some View {
        VStack(spacing:14) {
            if store.activeDevices.isEmpty {
                VStack(spacing:12) { Image(systemName:"square.grid.2x2").font(.largeTitle); Text("Empty dashboard").font(.headline); Text("Open Studio to show your devices.").foregroundStyle(.secondary) }.frame(maxWidth:.infinity).padding(40)
            }
            Grid(alignment:.leading,horizontalSpacing:14,verticalSpacing:14) {
            ForEach(rows.indices,id:\.self) { i in
                GridRow(alignment:.top) {
                    ForEach(rows[i]) { device in
                        let span=min(board.columns,max(1,board.spans[device.id] ?? 1))
                        VStack(spacing:4) {
                            if editing {
                                HStack {
                                    Image(systemName:"line.3.horizontal").foregroundStyle(accent)
                                    Text("Drag to reorder").font(.caption2).foregroundStyle(.secondary)
                                    Spacer()
                                    Button { store.setWidgetHidden(device.id,hidden:true) } label: { Image(systemName:"eye.slash") }
                                }.padding(.horizontal,8)
                            }
                            DeviceCard(device:device,accent:accent,card:card)
                        }
                        .frame(maxWidth:.infinity,alignment:.topLeading)
                        .gridCellColumns(span)
                        .onDrag { NSItemProvider(object:device.id as NSString) }
                        .onDrop(of:[UTType.plainText],isTargeted:nil) { providers in
                            guard editing,let provider=providers.first else { return false }
                            _ = provider.loadObject(ofClass: NSString.self) { object,_ in
                                if let source=object as? String {
                                    DispatchQueue.main.async { store.moveWidget(source,before:device.id) }
                                }
                            }
                            return true
                        }
                    }
                    let remaining=board.columns-rows[i].reduce(0) { $0+min(board.columns,max(1,board.spans[$1.id] ?? 1)) }
                    if remaining > 0 {
                        Color.clear.gridCellColumns(remaining).accessibilityHidden(true)
                    }
                }
            }
            }
            if !store.activeCustomWidgets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom controls").font(.title3.bold()).padding(.top, 8)
                    // Render using the same logical placements edited in Canvas Studio.
                    ScrollView(.horizontal) {
                        ZStack(alignment:.topLeading) {
                            ForEach(store.activeCustomWidgets) { widget in
                                let p=store.canvasPlacements[widget.id] ?? NODOPlacement()
                                NODOWidgetCard(widget:widget,accent:accent,card:card)
                                    .frame(width:CGFloat(p.columns)*112+CGFloat(p.columns-1)*12,
                                           height:CGFloat(p.rows)*112+CGFloat(p.rows-1)*12,alignment:.top)
                                    .clipped()
                                    .offset(x:CGFloat(p.column)*124,y:CGFloat(p.row)*124)
                            }
                        }
                        .frame(width:732,height:CGFloat((store.canvasPlacements.values.map{$0.row+$0.rows}.max() ?? 2))*124,alignment:.topLeading)
                    }
                }
            }
            if editing { Text("Drag a widget onto another to reorder. Change size, themes and visibility in Studio.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
        }
    }
    private var deviceList: some View {
        VStack(spacing:10) {
            ForEach(store.devices) { device in
                HStack(spacing:14) {
                    Image(systemName:device.kind.symbol).frame(width:32).foregroundStyle(accent)
                    VStack(alignment:.leading) {
                        Text(device.name).font(.headline)
                        Text("\(device.room) · \(device.transport.rawValue.uppercased())").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(device.online ? "Available" : "Offline").foregroundStyle(device.online ? accent : .orange)
                }.padding(18).background(card,in:RoundedRectangle(cornerRadius:14))
            }
        }
    }
    private var studio: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack {
                Text("Dashboard settings").font(.title3.bold())
                Spacer()
                Button("View dashboard") { section=0 }.buttonStyle(.borderedProminent).tint(accent)
            }
            TextField("Dashboard name",text:Binding(get:{board.name},set:{value in store.editDashboard{$0.name=value}}))
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Icon").frame(width:70,alignment:.leading)
                Picker("Icon",selection:Binding(get:{board.symbol},set:{v in store.editDashboard{$0.symbol=v}})) {
                    ForEach(["house","square.grid.2x2","hammer","lightbulb","cpu","slider.horizontal.3"],id:\.self) { name in
                        Label(name,systemImage:name).tag(name)
                    }
                }
                Spacer()
            }
            HStack {
                Text("Theme").font(.headline)
                Spacer()
                Picker("Theme",selection:Binding(get:{board.theme},set:{v in store.editDashboard{$0.theme=v}})) {
                    Text("Dark").tag("dark");Text("Light").tag("light")
                }.pickerStyle(.segmented).frame(maxWidth:260)
            }
            VStack(alignment:.leading,spacing:10) {
                Text("Accent color").font(.headline)
                HStack(spacing:16) {
                    ForEach(["teal","blue","amber","violet"],id:\.self) { key in
                        Button { store.editDashboard{$0.accent=key} } label: {
                            Circle().fill(Style.accent(key)).frame(width:38,height:38)
                                .overlay { if board.accent == key { Image(systemName:"checkmark").font(.caption.bold()).foregroundStyle(.black) } }
                        }.buttonStyle(.plain).accessibilityLabel(key)
                    }
                }
            }
            HStack {
                Text("Columns").font(.headline)
                Spacer()
                Picker("Columns",selection:Binding(get:{board.columns},set:{v in store.editDashboard{$0.columns=v}})) {
                    Text("1").tag(1);Text("2").tag(2);Text("3").tag(3)
                }.pickerStyle(.segmented).frame(maxWidth:250)
            }
            Divider()
            Text("Widgets").font(.title3.bold())
            Text("Drag a row onto another to reorder it. Select width and visibility for each dashboard independently.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(store.orderedDevicesForActiveDashboard) { device in
                HStack(spacing:10) {
                    Image(systemName:"line.3.horizontal").foregroundStyle(.secondary)
                    Image(systemName:device.kind.symbol).frame(width:26).foregroundStyle(accent)
                    VStack(alignment:.leading) {
                        Text(device.name).font(.subheadline.bold())
                        Text(device.room).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Width",selection:Binding(
                        get:{min(board.columns,max(1,board.spans[device.id] ?? 1))},
                        set:{store.setWidgetSpan(device.id,span:$0)})) {
                            ForEach(1...board.columns,id:\.self) { width in Text("\(width) col").tag(width) }
                        }.frame(width:110)
                    Toggle("Visible",isOn:Binding(
                        get:{!board.hiddenIDs.contains(device.id)},
                        set:{store.setWidgetHidden(device.id,hidden: !$0)}
                    )).labelsHidden().tint(accent)
                }
                .padding(12).background(background.opacity(0.8),in:RoundedRectangle(cornerRadius:12))
                .onDrag { NSItemProvider(object:device.id as NSString) }
                .onDrop(of:[UTType.plainText],isTargeted:nil) { providers in
                    guard let provider=providers.first else { return false }
                    _ = provider.loadObject(ofClass:NSString.self) { item,_ in
                        if let source=item as? String { DispatchQueue.main.async { store.moveWidget(source,before:device.id) } }
                    }
                    return true
                }
            }
            Divider()
            NODOCanvasStudio(accent: accent, card: card)
            Divider()
            NODOWidgetStudio(accent: accent)
            HStack {
                Button("New dashboard") { store.createDashboard() }
                Spacer()
                Button("Delete dashboard",role:.destructive) { showDeleteConfirmation=true }
                    .disabled(store.dashboards.count <= 1)
            }
        }.padding(22).background(card,in:RoundedRectangle(cornerRadius:18))
    }
}

private struct DeviceCard: View {
    @EnvironmentObject private var store: DeviceStore
    let device: NODODevice
    let accent: Color
    let card: Color
    var body: some View {
        VStack(alignment:.leading,spacing:13) {
            HStack {
                Image(systemName:device.kind.symbol).font(.title2).foregroundStyle(accent)
                Spacer()
                Image(systemName:device.transport == .ble ? "bluetooth" : "wifi").foregroundStyle(.secondary)
            }
            Text(device.name).font(.title3.bold())
            Text("\(device.room) · \(device.transport.rawValue.uppercased())").font(.caption).foregroundStyle(.secondary)
            if device.transport == .ble && !device.online {
                Label("Offline — reconnect from Add device",systemImage:"antenna.radiowaves.left.and.right.slash")
                    .font(.caption).foregroundStyle(.orange)
            }
            if device.kind == .sensor {
                Text(String(format:"%.1f °C",device.value)).font(.system(size:30,weight:.semibold,design:.rounded))
            } else if device.kind == .switchDevice {
                Toggle("Power",isOn:Binding(get:{device.value>0},set:{store.setValue(id:device.id,value:$0 ? 1 : 0)}))
                    .tint(accent).disabled(device.transport != .demo && !device.online)
            } else if device.kind == .custom {
                Text("Connect a compatible NODO device to discover controls.").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack { Text("Level");Spacer();Text("\(Int(device.value))%") }.font(.subheadline)
                Slider(value:Binding(get:{device.value},set:{store.setValue(id:device.id,value:$0)}),in:0...100,step:5)
                    .tint(accent).disabled(device.transport != .demo && !device.online)
            }
        }
        .padding(20).frame(maxWidth:.infinity,alignment:.leading)
        .background(card,in:RoundedRectangle(cornerRadius:18))
    }
}
