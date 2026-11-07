import Foundation

/// Read-only Mach-O report built from header bytes only (the file is never loaded or executed).
struct MachOSliceReport: Identifiable, Equatable {
    var id = UUID()
    var arch: String
    var fileType: String
    var encrypted: Bool
    var cryptID: UInt32
    var uuid: String?
    var minOS: String?
    var platform: String?
    var signed: Bool
    var libraries: [MachOLibrary]
    var rpaths: [String]
}
struct MachOLibrary: Identifiable, Equatable {
    let name: String
    let kind: String   // load, weak, reexport, lazy, upward
    var id: String { kind + name }
}
enum MachOViewerError: Error { case notMachO, malformed, tooLarge }

enum MachOViewer {
    static func report(for url: URL) throws -> [MachOSliceReport] {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        let head = try h.read(upToCount: 8 + 20 * 16) ?? Data()
        guard head.count >= 8 else { throw MachOViewerError.notMachO }
        let magicBE = MachOInspector.u32(head, 0, big: true)
        var slices: [(UInt64, UInt64)] = []
        if magicBE == 0xCAFEBABE {
            let n = Int(MachOInspector.u32(head, 4, big: true))
            guard n > 0, n <= 16, head.count >= 8 + n * 20 else { throw MachOViewerError.malformed }
            let size = try h.seekToEnd()
            for i in 0..<n {
                let o = 8 + i * 20
                let off = UInt64(MachOInspector.u32(head, o + 8, big: true)), sz = UInt64(MachOInspector.u32(head, o + 12, big: true))
                guard off + sz <= size else { throw MachOViewerError.malformed }
                slices.append((off, sz))
            }
        } else { slices = [(0, UInt64.max)] }
        return try slices.map { try parseSlice(h, offset: $0.0, size: $0.1) }
    }

    static func cpuName(_ cpu: UInt32, _ sub: UInt32) -> String {
        let s = sub & 0x00FFFFFF
        switch cpu {
        case 0x0100000C: return s == 2 ? "arm64e" : (s == 1 ? "arm64 (v8)" : "arm64")
        case 0x0000000C: return s == 11 ? "armv7s" : (s == 9 ? "armv7" : "arm")
        case 0x01000007: return "x86_64"
        case 0x00000007: return "i386"
        case 0x0200000C: return "arm64_32"
        default: return String(format: "cpu 0x%X", cpu)
        }
    }
    static let fileTypes: [UInt32: String] = [1: "Object", 2: "Executable", 3: "Fixed VM library", 4: "Core", 5: "Preload", 6: "Dynamic library", 7: "Dynamic linker", 8: "Bundle", 9: "Dylib stub", 10: "dSYM", 11: "Kext"]
    static let platforms: [UInt32: String] = [1: "macOS", 2: "iOS", 3: "tvOS", 4: "watchOS", 5: "bridgeOS", 6: "Mac Catalyst", 7: "iOS Simulator", 8: "tvOS Simulator", 9: "watchOS Simulator", 11: "visionOS", 12: "visionOS Simulator"]
    static func ver(_ v: UInt32) -> String {
        let p = v & 0xFF
        return "\(v >> 16).\((v >> 8) & 0xFF)" + (p > 0 ? ".\(p)" : "")
    }

    private static func parseSlice(_ h: FileHandle, offset: UInt64, size: UInt64) throws -> MachOSliceReport {
        try h.seek(toOffset: offset)
        guard let hd = try h.read(upToCount: 32), hd.count == 32 else { throw MachOViewerError.malformed }
        let magic = MachOInspector.u32(hd, 0, big: false)
        guard magic == 0xFEEDFACF || magic == 0xFEEDFACE else { throw MachOViewerError.notMachO }
        let is64 = magic == 0xFEEDFACF
        let hdrSize = is64 ? 32 : 28
        let cpu = MachOInspector.u32(hd, 4, big: false), sub = MachOInspector.u32(hd, 8, big: false)
        let ftype = MachOInspector.u32(hd, 12, big: false)
        let ncmds = Int(MachOInspector.u32(hd, 16, big: false)), sizeofcmds = Int(MachOInspector.u32(hd, 20, big: false))
        guard ncmds <= 4096, sizeofcmds <= 4 * 1024 * 1024, UInt64(hdrSize + sizeofcmds) <= size else { throw MachOViewerError.malformed }
        try h.seek(toOffset: offset + UInt64(hdrSize))
        guard let cmds = try h.read(upToCount: sizeofcmds), cmds.count == sizeofcmds else { throw MachOViewerError.malformed }
        var r = MachOSliceReport(arch: cpuName(cpu, sub), fileType: fileTypes[ftype] ?? "Type \(ftype)", encrypted: false, cryptID: 0,
                                 uuid: nil, minOS: nil, platform: nil, signed: false, libraries: [], rpaths: [])
        var off = 0
        func str(_ at: Int, _ cmdSize: Int, _ strOff: Int) -> String {
            guard strOff < cmdSize else { return "" }
            let s = cmds.subdata(in: (cmds.startIndex + at + strOff)..<(cmds.startIndex + at + cmdSize))
            return String(decoding: s.prefix { $0 != 0 }, as: UTF8.self)
        }
        for _ in 0..<ncmds {
            guard off + 8 <= sizeofcmds else { throw MachOViewerError.malformed }
            let cmd = MachOInspector.u32(cmds, off, big: false), sz = Int(MachOInspector.u32(cmds, off + 4, big: false))
            guard sz >= 8, off + sz <= sizeofcmds else { throw MachOViewerError.malformed }
            switch cmd {
            case 0x0C, 0x18 | 0x80000000, 0x1F | 0x80000000, 0x20, 0x23 | 0x80000000:
                let kind = cmd == 0x0C ? "load" : cmd == 0x20 ? "lazy" : cmd == (0x18 | 0x80000000) ? "weak" : cmd == (0x1F | 0x80000000) ? "reexport" : "upward"
                if sz >= 24 { r.libraries.append(MachOLibrary(name: str(off, sz, Int(MachOInspector.u32(cmds, off + 8, big: false))), kind: kind)) }
            case 0x1C | 0x80000000:
                if sz >= 12 { r.rpaths.append(str(off, sz, Int(MachOInspector.u32(cmds, off + 8, big: false)))) }
            case 0x21, 0x2C:
                if sz >= 20 { let c = MachOInspector.u32(cmds, off + 16, big: false); r.cryptID = c; r.encrypted = c != 0 }
            case 0x1B:
                if sz >= 24 { r.uuid = (0..<16).map { String(format: "%02X", cmds[cmds.startIndex + off + 8 + $0]) }.joined() }
            case 0x1D: r.signed = true
            case 0x32:
                if sz >= 24 { r.platform = platforms[MachOInspector.u32(cmds, off + 8, big: false)]; r.minOS = ver(MachOInspector.u32(cmds, off + 12, big: false)) }
            case 0x25, 0x24, 0x2F, 0x30:
                if sz >= 16, r.minOS == nil {
                    r.minOS = ver(MachOInspector.u32(cmds, off + 8, big: false))
                    r.platform = cmd == 0x25 ? "iOS" : cmd == 0x24 ? "macOS" : cmd == 0x2F ? "tvOS" : "watchOS"
                }
            default: break
            }
            off += sz
        }
        return r
    }
}
