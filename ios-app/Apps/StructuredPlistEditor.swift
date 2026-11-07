import SwiftUI
import UIKit

/// Uses the native typed plist model. Original bundle bytes are never modified:
/// saving validates and atomically writes an overlay blob for the next unsigned signing workspace.
struct StructuredPlistEditor: View {
    let manager: BundleFileManager
    let entry: BundleEntry
    var onChange: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var document: PlistDocument?
    @State private var raw = ""
    @State private var rawMode = false
    @State private var editing = false
    @State private var search = ""
    @State private var expanded: Set<String> = []
    @State private var selection: PlistEditSelection?
    @State private var error: String?
    @State private var warnings: [String] = []
    @State private var showWarnings = false

    private func label(_ value: String) -> String { MirsaTr.lit(value) }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(document?.format == .binary ? "Binary plist" : "XML plist", systemImage: "list.bullet.rectangle")
                    .font(.caption.monospaced()).foregroundStyle(.cyan)
                Spacer()
                if !rawMode && editing {
                    Button {
                        selection = PlistEditSelection(path: [], key: "", type: "string", text: "", adding: true,
                                                       container: document?.root is [String: Any])
                    } label: { Image(systemName: "plus").font(.headline).frame(width: 34, height: 34).background(.purple, in: Circle()) }
                        .buttonStyle(.plain).accessibilityLabel(label("Add value"))
                }
                Button(label(rawMode ? "Tree" : "Raw XML")) { toggleMode() }
                    .buttonStyle(.bordered).tint(.cyan)
            }.padding(.horizontal)
            Text(label("Changes are staged. Sign the app again before installing."))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal) }
            if rawMode {
                PlistSyntaxText(text: $raw, editable: editing).padding(.horizontal, 8)
            } else {
                TextField(label("Search keys and values"), text: $search)
                    .padding(12).background(Color.purple.opacity(0.13), in: Capsule()).overlay(Capsule().stroke(Color.purple.opacity(0.25))).padding(.horizontal)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { group in
                            let members = rows.filter { category($0) == group }
                            if !members.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(members) { row in
                                        treeRow(row)
                                        if row.id != members.last?.id { Divider().overlay(Color.white.opacity(0.06)).padding(.horizontal, 12) }
                                    }
                                }
                                .background(Color(red: 0.12, green: 0.10, blue: 0.29).opacity(0.7), in: RoundedRectangle(cornerRadius: 22))
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.purple.opacity(0.23), lineWidth: 1))
                            }
                        }
                    }.padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 12)
        .background(LinearGradient(colors: [Color(red: 0.09, green: 0.055, blue: 0.22), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(label(editing ? "Save" : "Edit")) {
                    if editing { save() } else { editing = true }
                }.buttonStyle(.borderedProminent).tint(.blue).accessibilityIdentifier("mirsa.plist.edit")
            }
        }
        .sheet(item: $selection) { item in
            PlistValueSheet(item: item) { key, type, text in
                guard var doc = document else { return }
                if item.adding { try doc.add(at: item.path, key: key, type: type, text: text) }
                else {
                    if case .key(let old)? = item.path.last, old != key {
                        try doc.rename(at: item.path, to: key)
                        let path = Array(item.path.dropLast()) + [PlistDocument.Key.key(key)]
                        if !item.container { try doc.setScalar(at: path, text: text) }
                    } else if !item.container { try doc.setScalar(at: item.path, text: text) }
                }
                // Validate complete serialization before adopting any mutation.
                _ = try doc.serialized()
                document = doc
            }
        }
        .alert(label("Staged with warnings"), isPresented: $showWarnings) {
            Button(label("OK")) { dismiss() }
        } message: { Text(warnings.joined(separator: "\n")) }
        .preferredColorScheme(.dark).environment(\.layoutDirection, .leftToRight)
        .task {
            do {
                if case .plist(let doc) = try manager.read(entry.path) { document = doc; raw = try doc.xmlText() }
            } catch { self.error = error.localizedDescription }
        }
    }

    private struct Row: Identifiable {
        let id: String
        let path: [PlistDocument.Key]
        let key: String
        let value: Any
        let depth: Int
        var type: String { PlistDocument.typeName(value) }
        var container: Bool { type == "array" || type == "dictionary" }
    }
    private var rows: [Row] {
        guard let doc = document else { return [] }
        var result: [Row] = []
        func visit(_ value: Any, _ path: [PlistDocument.Key], _ key: String, _ id: String, _ depth: Int) {
            let row = Row(id: id, path: path, key: key, value: value, depth: depth)
            let match = search.isEmpty || key.localizedCaseInsensitiveContains(search) || Self.display(value).localizedCaseInsensitiveContains(search)
            if search.isEmpty || match { result.append(row) }
            guard depth <= BundleLimits.maxPlistDepth, !search.isEmpty || expanded.contains(id) else { return }
            if let dict = value as? [String: Any] {
                for key in dict.keys.sorted() {
                    visit(dict[key]!, path + [.key(key)], key, id + "/k:" + key, depth + 1)
                }
            } else if let array = value as? [Any] {
                for (i, child) in array.enumerated() { visit(child, path + [.index(i)], "[\(i)]", id + "/i:\(i)", depth + 1) }
            }
        }
        if let dict = doc.root as? [String: Any] {
            for key in dict.keys.sorted() { visit(dict[key]!, [.key(key)], key, "root/k:" + key, 0) }
        } else if let array = doc.root as? [Any] {
            for (i, value) in array.enumerated() { visit(value, [.index(i)], "[\(i)]", "root/i:\(i)", 0) }
        } else { visit(doc.root, [], label("Root"), "root", 0) }
        return result
    }
    private func category(_ row: Row) -> Int {
        let key: String
        if case .key(let root)? = row.path.first { key = root } else { key = row.key }
        if ["CFBundleIdentifier", "CFBundleDisplayName", "CFBundleVersion"].contains(key) { return 0 }
        if key.hasPrefix("NS") && key.contains("UsageDescription") { return 2 }
        if ["UIRequiredDeviceCapabilities", "CFBundleShortVersionString", "MinimumOSVersion"].contains(key) { return 3 }
        return 1
    }
    @ViewBuilder private func treeRow(_ row: Row) -> some View {
        HStack(spacing: 8) {
            Button {
                if row.container {
                    if expanded.contains(row.id) { expanded.remove(row.id) } else { expanded.insert(row.id) }
                    return
                }
                guard editing else { return }
                selection = PlistEditSelection(path: row.path, key: row.key, type: row.type,
                                               text: Self.display(row.value), adding: false, container: row.container)
            } label: {
                HStack(spacing: 8) {
                    Text(row.key).font(.system(size: 13, weight: .semibold)).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(label(row.type == "dictionary" ? "Dict" : row.type.capitalized))
                        .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 4)
                        .background(typeColor(row.type), in: Capsule())
                    if row.type != "bool" {
                        Text(Self.display(row.value)).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(3).multilineTextAlignment(.trailing).frame(maxWidth: 105, alignment: .trailing)
                    }
                    if row.type != "bool" && !row.key.contains("UsageDescription") {
                        Image(systemName: row.container && expanded.contains(row.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
            }.buttonStyle(.plain)
            if row.type == "bool" {
                Toggle("", isOn: Binding(get: { (row.value as? NSNumber)?.boolValue == true }, set: { value in
                    do { var doc = document; try doc?.setScalar(at: row.path, text: value ? "true" : "false"); document = doc }
                    catch { self.error = error.localizedDescription }
                })).labelsHidden().disabled(!editing).scaleEffect(0.8).frame(width: 42)
            }
            if row.container && editing {
                Button {
                    selection = PlistEditSelection(path: row.path, key: "", type: "string", text: "", adding: true, container: row.type == "dictionary")
                } label: { Image(systemName: "plus").frame(width: 30, height: 36) }.buttonStyle(.plain).tint(.cyan)
            }
        }
        .padding(.leading, CGFloat(min(row.depth, 8)) * 13)
        .padding(.horizontal, 13).padding(.vertical, 14)
        .contextMenu {
            if editing {
                Button(label("Edit")) {
                    selection = PlistEditSelection(path: row.path, key: row.key, type: row.type,
                                                   text: Self.display(row.value), adding: false, container: row.container)
                }
            }
            if editing && !row.path.isEmpty {
                Button(role: .destructive) {
                    do { var doc = document; try doc?.remove(at: row.path); document = doc }
                    catch { self.error = error.localizedDescription }
                } label: { Label(label("Delete"), systemImage: "trash") }
            }
        }
    }
    private func typeColor(_ type: String) -> Color {
        switch type {
        case "bool": return Color.green.opacity(0.7)
        case "array": return Color.purple.opacity(0.8)
        case "dictionary": return Color.orange.opacity(0.8)
        case "integer", "real": return Color.teal.opacity(0.7)
        default: return Color.blue.opacity(0.8)
        }
    }
    static func display(_ value: Any) -> String {
        switch PlistDocument.typeName(value) {
        case "dictionary": return "\((value as? [String: Any])?.count ?? 0)"
        case "array": return "\((value as? [Any])?.count ?? 0)"
        case "data": return (value as? Data)?.base64EncodedString() ?? ""
        case "date": return (value as? Date).map { ISO8601DateFormatter().string(from: $0) } ?? ""
        case "bool": return (value as? NSNumber)?.boolValue == true ? "true" : "false"
        default: return String(describing: value)
        }
    }
    private func toggleMode() {
        guard let doc = document else { return }
        do {
            if rawMode { document = try PlistDocument(xmlText: raw, preserving: doc.format) }
            else { raw = try doc.xmlText() }
            rawMode.toggle(); error = nil
        } catch { self.error = error.localizedDescription } // Invalid raw text stays on screen, never discarded.
    }
    private func save() {
        guard var doc = document else { return }
        do {
            if rawMode { doc = try PlistDocument(xmlText: raw, preserving: doc.format) }
            let bytes = try doc.serialized()
            warnings = try manager.stageWrite(entry.path, data: bytes)
            document = doc; onChange()
            if warnings.isEmpty { dismiss() } else { showWarnings = true }
        } catch { self.error = error.localizedDescription }
    }
}

private struct PlistEditSelection: Identifiable {
    let id = UUID()
    let path: [PlistDocument.Key]
    let key: String
    let type: String
    let text: String
    let adding: Bool
    let container: Bool
}
private struct PlistValueSheet: View {
    let item: PlistEditSelection
    let apply: (String, String, String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var type = "string"
    @State private var text = ""
    @State private var error: String?
    private var showsKey: Bool {
        if item.adding { return item.container }
        if case .key? = item.path.last { return true }
        return false
    }
    var body: some View {
        NavigationStack {
            Form {
                if showsKey {
                    TextField(MirsaTr.lit("Key"), text: $key).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                if item.adding {
                    Picker(MirsaTr.lit("Type"), selection: $type) {
                        ForEach(["string", "integer", "real", "bool", "array", "dictionary", "data", "date"], id: \.self) {
                            Text(MirsaTr.lit($0.capitalized)).tag($0)
                        }
                    }
                }
                if type == "bool" {
                    Toggle(MirsaTr.lit("Value"), isOn: Binding(get: { text == "true" }, set: { text = $0 ? "true" : "false" }))
                } else if !["array", "dictionary"].contains(type) {
                    TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 160)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    if type == "data" { Text("Base64").font(.caption).foregroundStyle(.secondary) }
                    if type == "date" { Text("ISO 8601 · 2026-11-07T12:00:00Z").font(.caption).foregroundStyle(.secondary) }
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle(MirsaTr.lit(item.adding ? "Add value" : "Edit"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(MirsaTr.lit("Cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(MirsaTr.lit("Save")) {
                        do { try apply(key, type, text); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }.preferredColorScheme(.dark).environment(\.layoutDirection, .leftToRight)
        .onAppear { key = item.key; type = item.type; text = item.text }
    }
}

/// Native attributed text preserves selection and scroll position while highlighting XML.
private struct PlistSyntaxText: UIViewRepresentable {
    @Binding var text: String
    var editable: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.autocorrectionType = .no; view.autocapitalizationType = .none
        view.smartQuotesType = .no; view.smartDashesType = .no
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = editable
        if view.text != text { view.text = text; context.coordinator.highlight(view) }
        else if view.attributedText.length == 0 { context.coordinator.highlight(view) }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlistSyntaxText
        init(_ parent: PlistSyntaxText) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) { parent.text = view.text; highlight(view) }
        func highlight(_ view: UITextView) {
            let range = view.selectedRange
            let value = view.text ?? ""
            let attributed = NSMutableAttributedString(string: value, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white])
            for (pattern, color) in [(#"<[^>]+>"#, UIColor.systemTeal), (#"<key>[^<]*</key>"#, UIColor.systemOrange)] {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    regex.enumerateMatches(in: value, range: NSRange(value.startIndex..., in: value)) { match, _, _ in
                        if let match { attributed.addAttribute(.foregroundColor, value: color, range: match.range) }
                    }
                }
            }
            view.attributedText = attributed
            view.selectedRange = NSRange(location: min(range.location, attributed.length), length: 0)
        }
    }
}
