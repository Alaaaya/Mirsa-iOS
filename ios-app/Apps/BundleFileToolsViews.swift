import SwiftUI

// MARK: - Hex editor (patches bytes of a staged copy; bounded to FileToolsLimits.maxHexBytes)
struct HexEditorView: View {
    let manager: BundleFileManager
    let entry: BundleEntry
    var onChange: () -> Void = {}
    @State private var bytes = Data()
    @State private var original = Data()
    @State private var selected: Int?
    @State private var input = ""
    @State private var query = ""
    @State private var results: [Int] = []
    @State private var resultIndex = 0
    @State private var message: String?
    @State private var tooBig = false
    private let perRow = 16
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if tooBig {
                Text(MirsaTr.ft("File is too large for the hex editor (max 8 MB).")).padding()
            } else {
                searchBar
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(0..<rowCount, id: \.self) { row in rowView(row).id(row) }
                        }.padding(.horizontal, 8)
                    }
                    .onChange(of: resultIndex) { _ in if results.indices.contains(resultIndex) { withAnimation { proxy.scrollTo(results[resultIndex] / perRow, anchor: .center) } } }
                }
                editBar
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
        }
        .environment(\.layoutDirection, .leftToRight)
        .navigationTitle(entry.name)
        .toolbar { Button(MirsaTr.ft("Save")) { save() }.disabled(bytes == original || tooBig) }
        .onAppear(perform: load)
    }
    private var rowCount: Int { (bytes.count + perRow - 1) / perRow }
    private var searchBar: some View {
        HStack {
            TextField(MirsaTr.ft("Find hex (e.g. DE AD BE EF) or text"), text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced)).onSubmit(runSearch)
            Button(MirsaTr.ft("Find"), action: runSearch)
            if !results.isEmpty {
                Text("\(resultIndex + 1)/\(results.count)").font(.caption)
                Button { resultIndex = (resultIndex + 1) % results.count; selected = results[resultIndex] } label: { Image(systemName: "chevron.down") }
            }
        }.padding(8)
    }
    private var editBar: some View {
        HStack {
            Text(selected.map { String(format: "0x%X", $0) } ?? MirsaTr.ft("Tap a byte")).font(.system(.footnote, design: .monospaced))
            TextField("hex", text: $input).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(.body, design: .monospaced)).frame(maxWidth: 140).textFieldStyle(.roundedBorder)
            Button(MirsaTr.ft("Set")) { apply() }.disabled(selected == nil)
        }.padding(8)
    }
    private func rowView(_ row: Int) -> some View {
        let start = row * perRow
        return HStack(alignment: .top, spacing: 8) {
            Text(String(format: "%08X", start)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<perRow, id: \.self) { i in
                    let idx = start + i
                    if idx < bytes.count {
                        Text(String(format: "%02X", bytes[idx]))
                            .padding(.horizontal, 1)
                            .background(cellColor(idx))
                            .onTapGesture { selected = idx; input = String(format: "%02X", bytes[idx]) }
                    } else { Text("  ") }
                }
            }
            Text(String(bytes[start..<min(start + perRow, bytes.count)].map { $0 >= 32 && $0 < 127 ? Character(UnicodeScalar($0)) : "." }))
        }.font(.system(size: 11, design: .monospaced))
    }
    private func cellColor(_ idx: Int) -> Color {
        if idx == selected { return Color.accentColor.opacity(0.4) }
        let changed: Bool = idx < original.count && bytes[idx] != original[idx]
        return changed ? Color.orange.opacity(0.3) : Color.clear
    }
    private func load() {
        do {
            guard entry.size <= FileToolsLimits.maxHexBytes else { tooBig = true; return }
            bytes = try manager.readData(entry.path); original = bytes
        } catch { message = String(describing: error) }
    }
    private func apply() {
        guard let i = selected, i < bytes.count else { return }
        let clean = input.filter { $0.isHexDigit }
        guard !clean.isEmpty, clean.count % 2 == 0, clean.count <= 2 * 64 else { message = MirsaTr.ft("Enter 1-64 bytes as hex."); return }
        var out: [UInt8] = []
        var it = clean.makeIterator()
        while let a = it.next(), let b = it.next() { out.append(UInt8(String([a, b]), radix: 16)!) }
        guard i + out.count <= bytes.count else { message = MirsaTr.ft("Past the end of the file."); return }
        for (k, v) in out.enumerated() { bytes[i + k] = v }
        message = nil
    }
    private func runSearch() {
        let hex = query.filter { $0.isHexDigit }
        var needle: [UInt8]
        let spaced = query.replacingOccurrences(of: " ", with: "")
        if !spaced.isEmpty, spaced.allSatisfy({ $0.isHexDigit }), spaced.count % 2 == 0 {
            needle = []; var it = hex.makeIterator()
            while let a = it.next(), let b = it.next() { needle.append(UInt8(String([a, b]), radix: 16)!) }
        } else { needle = Array(query.utf8) }
        guard !needle.isEmpty else { return }
        var found: [Int] = []
        let arr = [UInt8](bytes)
        if arr.count >= needle.count {
            for i in 0...(arr.count - needle.count) where arr[i] == needle[0] {
                if Array(arr[i..<(i + needle.count)]) == needle { found.append(i); if found.count >= 500 { break } }
            }
        }
        results = found; resultIndex = 0
        selected = found.first
        message = found.isEmpty ? MirsaTr.ft("Not found.") : nil
        if let f = found.first { input = String(format: "%02X", arr[f]) }
    }
    private func save() {
        do { try manager.stageWriteRaw(entry.path, data: bytes); onChange(); dismiss() }
        catch { message = String(describing: error) }
    }
}

// MARK: - Code editor (find / replace / go to line, validation on save)
struct CodeEditorView: View {
    let manager: BundleFileManager
    let entry: BundleEntry
    var onChange: () -> Void = {}
    @State private var text = ""
    @State private var original = ""
    @State private var find = ""
    @State private var replace = ""
    @State private var showFind = false
    @State private var lineText = ""
    @State private var message: String?
    @State private var warnings: [String] = []
    @State private var showWarnings = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if showFind {
                VStack(spacing: 6) {
                    HStack {
                        TextField(MirsaTr.ft("Find"), text: $find).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text(MirsaTr.ft("%d matches", matchCount)).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField(MirsaTr.ft("Replace with"), text: $replace).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(MirsaTr.ft("Replace all")) { replaceAll() }.disabled(find.isEmpty)
                    }
                }.textFieldStyle(.roundedBorder).padding(8)
            }
            HStack(alignment: .top, spacing: 0) {
                ScrollView { Text(gutter).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary).padding(.vertical, 8).padding(.horizontal, 6) }
                    .scrollDisabled(true).frame(width: 44)
                TextEditor(text: $text).font(.system(.footnote, design: .monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            HStack {
                Text(MirsaTr.ft("%d lines", lineCount)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let message { Text(message).font(.footnote).foregroundStyle(.red) }
            }.padding(.horizontal, 10).padding(.vertical, 4)
        }
        .environment(\.layoutDirection, .leftToRight)
        .navigationTitle(entry.name)
        .toolbar {
            ToolbarItemGroup {
                Button { showFind.toggle() } label: { Image(systemName: "magnifyingglass") }
                Button(MirsaTr.ft("Save")) { save() }.disabled(text == original)
            }
        }
        .alert(MirsaTr.lit("Staged with warnings"), isPresented: $showWarnings) { Button(MirsaTr.lit("OK")) { dismiss() } } message: { Text(warnings.joined(separator: "\n")) }
        .onAppear(perform: load)
    }
    private var lineCount: Int { max(1, text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }) }
    private var gutter: String { (1...min(lineCount, 5000)).map(String.init).joined(separator: "\n") }
    private var matchCount: Int { find.isEmpty ? 0 : text.components(separatedBy: find).count - 1 }
    private func replaceAll() { text = text.replacingOccurrences(of: find, with: replace) }
    private func load() {
        do { if case let .text(t) = try manager.read(entry.path) { text = t; original = t } else { message = MirsaTr.lit("Not editable.") } }
        catch { message = String(describing: error) }
    }
    private func validate() -> [String] {
        let n = entry.name.lowercased()
        if n.hasSuffix(".json"), (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) == nil {
            return [MirsaTr.ft("This is not valid JSON; the app may fail to read it.")]
        }
        if n.hasSuffix(".xml"), !XMLChecker.wellFormed(text) { return [MirsaTr.ft("This XML is not well-formed.")] }
        return []
    }
    private func save() {
        do {
            var w = try manager.stageWrite(entry.path, text: text)
            w += validate()
            onChange()
            if w.isEmpty { dismiss() } else { warnings = w; showWarnings = true }
        } catch { message = String(describing: error) }
    }
}

enum XMLChecker {
    private final class D: NSObject, XMLParserDelegate {}
    static func wellFormed(_ s: String) -> Bool {
        let p = XMLParser(data: Data(s.utf8)); let d = D(); p.delegate = d
        p.shouldResolveExternalEntities = false
        return p.parse()
    }
}

// MARK: - Mach-O viewer
struct MachOView: View {
    let manager: BundleFileManager
    let entry: BundleEntry
    @State private var slices: [MachOSliceReport] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Section(MirsaTr.ft("Architectures")) {
                ForEach(slices) { s in Label(s.arch, systemImage: "cpu") }
            }
            ForEach(slices) { s in
                Section(s.arch) {
                    row(MirsaTr.ft("Type"), s.fileType)
                    row(MirsaTr.ft("Encryption"), s.encrypted ? MirsaTr.ft("Encrypted (cryptid %d)", Int(s.cryptID)) : MirsaTr.ft("Not encrypted"))
                    row(MirsaTr.ft("Code signature"), s.signed ? MirsaTr.ft("Present") : MirsaTr.ft("None"))
                    if let p = s.platform { row(MirsaTr.ft("Platform"), p) }
                    if let m = s.minOS { row(MirsaTr.ft("Minimum OS"), m) }
                    if let u = s.uuid { row("UUID", u) }
                }
                if !s.rpaths.isEmpty { Section("RPATH " + s.arch) { ForEach(s.rpaths, id: \.self) { Text($0).font(.system(.footnote, design: .monospaced)) } } }
                Section(MirsaTr.ft("Libraries") + " (\(s.libraries.count)) " + s.arch) {
                    ForEach(s.libraries) { l in
                        VStack(alignment: .leading) {
                            Text(l.name).font(.system(.footnote, design: .monospaced))
                            if l.kind != "load" { Text(l.kind).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .navigationTitle(entry.name)
        .onAppear {
            do { slices = try MachOViewer.report(for: try manager.fileURL(of: entry.path)) }
            catch { self.error = MirsaTr.ft("Not a valid Mach-O file.") }
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.footnote)
    }
}

// MARK: - Search
struct BundleSearchView: View {
    let manager: BundleFileManager
    var directory: String = ""
    var onChange: () -> Void = {}
    @State private var query = ""
    @State private var content = false
    @State private var hits: [BundleSearchHit] = []
    @State private var busy = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        List {
            Toggle(MirsaTr.ft("Search inside text files"), isOn: $content).onChange(of: content) { _ in run() }
            if busy { ProgressView() }
            ForEach(hits) { h in
                NavigationLink { BundleFileOpenView(manager: manager, path: h.path, onChange: onChange) } label: {
                    VStack(alignment: .leading) {
                        Text(h.path).font(.footnote).lineLimit(1)
                        if let l = h.line { Text("\(l): \(h.snippet)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }
            if hits.count >= FileToolsLimits.maxSearchResults { Text(MirsaTr.ft("Showing the first %d results.", FileToolsLimits.maxSearchResults)).font(.caption) }
        }
        .environment(\.layoutDirection, .leftToRight)
        .searchable(text: $query, prompt: MirsaTr.ft("Search files"))
        .onChange(of: query) { _ in run() }
        .navigationTitle(MirsaTr.ft("Search"))
    }
    private func run() {
        task?.cancel()
        let q = query, c = content, m = manager, d = directory
        guard !q.isEmpty else { hits = []; return }
        busy = true
        task = Task.detached {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let r = m.search(q, in: d, content: c, isCancelled: { Task.isCancelled })
            await MainActor.run { if !Task.isCancelled { hits = r; busy = false } }
        }
    }
}

/// Opens any file in the right tool: plist editor, code editor, or hex + Mach-O.
struct BundleFileOpenView: View {
    let manager: BundleFileManager
    let path: String
    var onChange: () -> Void = {}
    var body: some View {
        if let e = try? manager.entry(path) {
            switch e.kind {
            case .plist: StructuredPlistEditor(manager: manager, entry: e, onChange: onChange)
            case .text: CodeEditorView(manager: manager, entry: e, onChange: onChange)
            case .binary: BinaryFileToolsView(manager: manager, entry: e, onChange: onChange)
            case .directory: BundleFileBrowserView(manager: manager, directory: path, onChange: onChange)
            }
        } else { Text(MirsaTr.lit("Not editable.")) }
    }
}

struct BinaryFileToolsView: View {
    let manager: BundleFileManager
    let entry: BundleEntry
    var onChange: () -> Void = {}
    var body: some View {
        List {
            Section { Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)).foregroundStyle(.secondary) }
            NavigationLink { HexEditorView(manager: manager, entry: entry, onChange: onChange) } label: { Label(MirsaTr.ft("Hex editor"), systemImage: "number") }
            NavigationLink { MachOView(manager: manager, entry: entry) } label: { Label(MirsaTr.ft("Mach-O info"), systemImage: "cpu") }
        }.navigationTitle(entry.name)
    }
}
