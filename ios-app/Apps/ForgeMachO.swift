import Foundation

/// Reads the Objective-C class names of an app's main binary so the AI only hooks classes that exist.
/// App Store binaries are FairPlay-encrypted (cryptid != 0): their class names are not readable.
enum ForgeMachO {
    struct Info { let encrypted: Bool; let classes: [String] }
    enum Failure: Error { case unreadable }

    static func inspect(_ url: URL) throws -> Info {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        var base = 0
        guard data.count > 32 else { throw Failure.unreadable }
        func u32(_ o: Int, big: Bool = false) -> UInt32 {
            let v = data.subdata(in: o..<o + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return big ? v.byteSwapped : v
        }
        if u32(0) == 0xBEBAFECA { // fat: pick arm64 slice
            let n = Int(u32(4, big: true))
            for i in 0..<n {
                let e = 8 + i * 20
                if u32(e, big: true) == 0x0100000C { base = Int(u32(e + 8, big: true)); break }
            }
        }
        guard u32(base) == 0xFEEDFACF else { throw Failure.unreadable }
        let ncmds = Int(u32(base + 16))
        var off = base + 32
        var encrypted = false
        var names: [String] = []
        for _ in 0..<ncmds {
            guard off + 8 <= data.count else { break }
            let cmd = u32(off), size = Int(u32(off + 4))
            if cmd == 0x2C { encrypted = u32(off + 16) != 0 }
            if cmd == 0x19 { // LC_SEGMENT_64
                let nsects = Int(u32(off + 64))
                var s = off + 72
                for _ in 0..<nsects {
                    let sect = String(decoding: data.subdata(in: s..<s + 16).prefix { $0 != 0 }, as: UTF8.self)
                    if sect == "__objc_classname" {
                        let size64 = data.subdata(in: s + 40..<s + 48).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
                        let fileOff = Int(u32(s + 48))
                        let start = base + fileOff, end = min(data.count, start + Int(size64))
                        if start < end {
                            names = data.subdata(in: start..<end).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
                        }
                    }
                    s += 80
                }
            }
            off += max(size, 8)
        }
        let clean = Array(Set(names.filter { !$0.isEmpty && !$0.hasPrefix("_") })).sorted()
        return Info(encrypted: encrypted, classes: clean)
    }
}
