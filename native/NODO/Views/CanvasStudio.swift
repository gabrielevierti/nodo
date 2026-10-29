import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let nodoLayout = UTType(exportedAs: "dev.nodo.layout", conformingTo: .json)
}

struct NODOLayoutFile: FileDocument {
    static var readableContentTypes: [UTType] { [.nodoLayout, .json] }
    static var writableContentTypes: [UTType] { [.nodoLayout] }
    var template: NODOTemplate
    init(_ template: NODOTemplate) { self.template=template }
    init(configuration: ReadConfiguration) throws {
        guard let bytes=configuration.file.regularFileContents, bytes.count < 512_000 else {
            throw NODOTemplateError.invalid
        }
        template=try JSONDecoder().decode(NODOTemplate.self,from:bytes)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        return FileWrapper(regularFileWithContents:try encoder.encode(template))
    }
}

// An explicitly bounded six-column canvas avoids pixel-based, device-dependent layouts.
struct NODOCanvasStudio: View {
    @EnvironmentObject private var store: DeviceStore
    let accent: Color
    let card: Color
    @State private var selectedID: String?
    @State private var showExport=false
    @State private var showImport=false
    @State private var error: String?
    private let columns=6
    private let unit: CGFloat=108
    private let gap: CGFloat=10
    private var widgets: [NODOWidget] { store.activeCustomWidgets }
    private var positions: [String:NODOPlacement] { store.canvasPlacements }
    private var selected: NODOWidget? { widgets.first(where:{$0.id == selectedID}) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text("Canvas Studio").font(.title2.bold())
                    Text("Drag to position · Select to edit · 6-column responsive canvas")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(NODOWidgetKind.allCases) { kind in
                        Button { store.addCustomWidget(kind:kind); selectedID=store.activeCustomWidgets.last?.id } label: {
                            Label(kind.label,systemImage:kind.symbol)
                        }
                    }
                } label: { Label("Add widget",systemImage:"plus") }
                    .buttonStyle(.borderedProminent).tint(accent)
            }
            HStack(spacing:10) {
                Button { showExport=true } label: { Label("Export layout",systemImage:"square.and.arrow.up") }
                Button { showImport=true } label: { Label("Import layout",systemImage:"square.and.arrow.down") }
                Text("Templates never include device pairing or credentials.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.buttonStyle(.bordered)
            ScrollView(.horizontal) {
                GeometryReader { _ in
                    ZStack(alignment:.topLeading) {
                        RoundedRectangle(cornerRadius:14).fill(.primary.opacity(0.025))
                        Path { p in
                            for c in 0...6 { let x=CGFloat(c)*(unit+gap)
                                p.move(to:CGPoint(x:x,y:0));p.addLine(to:CGPoint(x:x,y:2100)) }
                            for r in 0...19 { let y=CGFloat(r)*(unit+gap)
                                p.move(to:CGPoint(x:0,y:y));p.addLine(to:CGPoint(x:696,y:y)) }
                        }.stroke(.primary.opacity(0.075),lineWidth:1)
                        ForEach(widgets) { widget in
                            let pos=positions[widget.id] ?? NODOPlacement()
                            canvasTile(widget,pos:pos)
                                .frame(width:CGFloat(pos.columns)*unit+CGFloat(pos.columns-1)*gap,
                                       height:CGFloat(pos.rows)*unit+CGFloat(pos.rows-1)*gap)
                                .offset(x:CGFloat(pos.column)*(unit+gap),y:CGFloat(pos.row)*(unit+gap))
                                .zIndex(selectedID == widget.id ? 2 : 1)
                        }
                    }
                }
                .frame(width:696,height: max(480,CGFloat((positions.values.map { $0.row+$0.rows }.max() ?? 3)+1)*(unit+gap)))
            }.frame(maxHeight:630)
            if let widget=selected { inspector(widget) }
            else { Text("Select a widget to edit its properties.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .fileExporter(isPresented:$showExport,document:NODOLayoutFile(store.makeTemplate()),contentType:.nodoLayout,
                      defaultFilename:"NODO-layout") { result in
            if case .failure(let err)=result { error=err.localizedDescription }
        }
        .fileImporter(isPresented:$showImport,allowedContentTypes:[.nodoLayout,.json]) { result in
            do {
                let url=try result.get()
                let access=url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data=try Data(contentsOf:url)
                guard data.count < 512_000 else { throw NODOTemplateError.invalid }
                try store.importTemplate(JSONDecoder().decode(NODOTemplate.self,from:data))
                selectedID=nil;error=nil
            } catch { self.error=error.localizedDescription }
        }
    }
    private func canvasTile(_ widget:NODOWidget,pos:NODOPlacement)->some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Image(systemName:widget.kind.symbol).foregroundStyle(accent)
                Text(widget.title).font(.headline).lineLimit(1)
                Spacer(minLength:2)
                Image(systemName:"arrow.up.left.and.arrow.down.right").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
            // Editor deliberately does not send live commands while dragging.
            Text(widget.kind.label).font(.caption).foregroundStyle(.secondary)
            Text(widget.deviceID == nil ? "Preview" : "Bound device")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(card,in:RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(selectedID == widget.id ? accent : .secondary.opacity(0.16),lineWidth:selectedID == widget.id ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { selectedID=widget.id }
        .gesture(DragGesture(minimumDistance:7).onEnded { gesture in
            let dx=Int((gesture.translation.width/(unit+gap)).rounded())
            let dy=Int((gesture.translation.height/(unit+gap)).rounded())
            var changed=pos
            changed.column+=dx;changed.row+=dy
            store.placeCustomWidget(widget.id,changed)
            selectedID=widget.id
        })
    }
    private func inspector(_ widget:NODOWidget)->some View {
        let pos=positions[widget.id] ?? NODOPlacement()
        return VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Properties").font(.headline)
                Spacer()
                Button(role:.destructive) { store.deleteCustomWidget(widget.id);selectedID=nil } label: {
                    Label("Delete",systemImage:"trash")
                }.buttonStyle(.bordered)
            }
            TextField("Widget title",text:Binding(get:{widget.title},set:{value in
                var changed=widget;changed.title=value;store.updateCustomWidget(changed)
            })).textFieldStyle(.roundedBorder)
            HStack {
                Picker("Device",selection:Binding(get:{widget.deviceID ?? ""},set:{id in
                    var changed=widget;changed.deviceID=id.isEmpty ? nil : id;store.updateCustomWidget(changed)
                })) {
                    Text("Preview (unbound)").tag("")
                    ForEach(store.devices) { device in Text(device.name).tag(device.id) }
                }
                Spacer()
            }
            HStack(spacing:14) {
                Stepper("Column: \(pos.column+1)",value:Binding(get:{pos.column},set:{n in
                    var changed=pos;changed.column=n;store.placeCustomWidget(widget.id,changed)
                }),in:0...5)
                Stepper("Row: \(pos.row+1)",value:Binding(get:{pos.row},set:{n in
                    var changed=pos;changed.row=n;store.placeCustomWidget(widget.id,changed)
                }),in:0...18)
            }
            HStack(spacing:14) {
                Stepper("Width: \(pos.columns)",value:Binding(get:{pos.columns},set:{n in
                    var changed=pos;changed.columns=n;store.placeCustomWidget(widget.id,changed)
                }),in:1...6)
                Stepper("Height: \(pos.rows)",value:Binding(get:{pos.rows},set:{n in
                    var changed=pos;changed.rows=n;store.placeCustomWidget(widget.id,changed)
                }),in:1...6)
            }
            Text("Canvas uses a snapping grid. Overlapping widgets can be repositioned using the inspector.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(16).background(card,in:RoundedRectangle(cornerRadius:14))
    }
}
