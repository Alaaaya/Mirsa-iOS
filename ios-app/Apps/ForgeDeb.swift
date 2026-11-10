import Foundation

/// Builds a .deb (ar + uncompressed tar members, which dpkg accepts) for a generated tweak.
enum ForgeDeb {
    private static func tarEntry(path: String, data: Data?, mode: Int, dir: Bool = false) -> Data {
        var h = [UInt8](repeating: 0, count: 512)
        func put(_ s: String, _ at: Int, _ len: Int) { for (i, b) in s.utf8.prefix(len).enumerated() { h[at + i] = b } }
        put(path, 0, 100)
        put(String(format: "%07o", mode), 100, 8); put("0000000", 108, 8); put("0000000", 116, 8)
        put(String(format: "%011o", data?.count ?? 0), 124, 12); put(String(format: "%011o", Int(Date().timeIntervalSince1970)), 136, 12)
        put("        ", 148, 8); h[156] = dir ? 53 : 48
        put("ustar", 257, 6); put("00", 263, 2)
        let sum = h.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o", sum), 148, 7); h[154] = 0; h[155] = 32
        var out = Data(h)
        if let data { out.append(data); out.append(Data(repeating: 0, count: (512 - data.count % 512) % 512)) }
        return out
    }
    private static func tar(_ entries: [Data]) -> Data { entries.reduce(Data(), +) + Data(repeating: 0, count: 1024) }
    private static func arMember(_ name: String, _ data: Data) -> Data {
        var h = name.padding(toLength: 16, withPad: " ", startingAt: 0) + "0".padding(toLength: 12, withPad: " ", startingAt: 0)
        h += "0     0     100644  " + String(data.count).padding(toLength: 10, withPad: " ", startingAt: 0) + "`\n"
        var out = Data(h.utf8); out.append(data); if data.count % 2 == 1 { out.append(10) }
        return out
    }
    static func build(name: String, bundleID: String, dylib: Data) -> Data {
        let id = "com.mirsa.forge." + name.lowercased().filter { $0.isLetter || $0.isNumber }
        let control = "Package: \(id)\nName: \(name)\nVersion: 1.0\nArchitecture: iphoneos-arm\nDescription: Mirsa generated tweak for \(bundleID)\nMaintainer: Mirsa\nSection: Tweaks\nDepends: mobilesubstrate\n\n"
        let filter = "{ Filter = { Bundles = ( \"\(bundleID)\" ); }; }\n"
        let dir = "Library/MobileSubstrate/DynamicLibraries"
        let ctar = tar([tarEntry(path: "./control", data: Data(control.utf8), mode: 0o644)])
        let dtar = tar([
            tarEntry(path: "./Library/", data: nil, mode: 0o755, dir: true),
            tarEntry(path: "./Library/MobileSubstrate/", data: nil, mode: 0o755, dir: true),
            tarEntry(path: "./\(dir)/", data: nil, mode: 0o755, dir: true),
            tarEntry(path: "./\(dir)/\(name).dylib", data: dylib, mode: 0o755),
            tarEntry(path: "./\(dir)/\(name).plist", data: Data(filter.utf8), mode: 0o644),
        ])
        return Data("!<arch>\n".utf8) + arMember("debian-binary", Data("2.0\n".utf8)) + arMember("control.tar", ctar) + arMember("data.tar", dtar)
    }
}
