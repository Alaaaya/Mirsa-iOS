import Foundation
enum MirsaStoreCode {
    private static let strip: Set<UInt32> = [0x200E, 0x200F, 0x061C, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
                                             0x2066, 0x2067, 0x2068, 0x2069]
    /// Lenient: maps digits to ASCII, removes whitespace and bidi controls, keeps everything else as is.
    static func normalize(_ input: String) -> String {
        var out = String.UnicodeScalarView()
        for u in input.unicodeScalars {
            let v = u.value
            if strip.contains(v) || u.properties.isWhitespace { continue }
            if (0x0660...0x0669).contains(v) { out.append(Unicode.Scalar(v - 0x0660 + 48)!) }
            else if (0x06F0...0x06F9).contains(v) { out.append(Unicode.Scalar(v - 0x06F0 + 48)!) }
            else { out.append(u) }
        }
        return String(out)
    }
    /// Strict: exactly six ASCII digits after normalization, else nil.
    static func valid(_ input: String) -> String? {
        let n = normalize(input)
        return n.utf8.count == 6 && n.utf8.allSatisfy({ (48...57).contains($0) }) ? n : nil
    }
}
