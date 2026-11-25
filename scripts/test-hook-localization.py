#!/usr/bin/env python3
"""Compile the real editor hook-error/notice functions without UIKit or FFI."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "ios-app/Apps/IPAEditorService.swift").read_text()
start = source.index("    static func editingError(")
end = source.index("    /// Do not expose backend English", start)
checks = r"""
let failures = [
    "Missing dependency: /private/user/secrets.dylib. Mirsa never bundles CydiaSubstrate or ElleKit.",
    "Hook engine validation: Unsupported hook engine API: _EKPrivateSecret",
    "Existing CydiaSubstrate.framework conflicts with Mirsa hook engine",
    "CydiaSubstrate.framework is reserved for Mirsa hook engine",
    "Case-colliding hook engine destination",
    "Hook engine preparation: Permission denied /private/user",
    "Hook engine validation: Invalid symbol strings",
    "Hook engine resolution: No such file or directory"
]
for failure in failures {
    let messages = AppLanguage.allCases.map { IPAEditorService.editingError(failure, language: $0) }
    precondition(Set(messages).count == AppLanguage.allCases.count)
    for message in messages {
        precondition(message != failure && !message.contains("/private"))
        precondition(!message.contains("_EKPrivateSecret") && !message.contains("never bundles"))
    }
    let arabic = IPAEditorService.editingError(failure, language: .arabic)
    precondition(arabic.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) })
}
let notices = AppLanguage.allCases.map { IPAEditorService.injectionNotice(language: $0) }
precondition(Set(notices).count == AppLanguage.allCases.count)
for notice in notices {
    precondition(notice.contains("Objective-C") && !notice.contains("no CydiaSubstrate"))
}
precondition(IPAEditorService.injectionNotice(language: .english).contains("not inline"))
precondition(IPAEditorService.editingError("unrelated detail", language: .english) == "unrelated detail")
precondition(IPAEditorService.editingError("Mach-O editing storage limit", language: .arabic).contains("1.5 GB"))
print("Hook error and notice localization passed: 8 error cases, 5 languages, no path or symbol leaks")
"""
prelude = """import Foundation
enum AppLanguage: CaseIterable { case english, arabic, german, kurmanji, sorani }
enum AppLanguageStore { static var snapshot: AppLanguage { .arabic } }
enum IPAEditorService {
"""
with tempfile.TemporaryDirectory(prefix="mirsa-hook-localization-") as tmp:
    path = Path(tmp)
    swift = path / "main.swift"
    swift.write_text(prelude + source[start:end] + "}\n" + checks)
    binary = path / "localization"
    subprocess.run(["swiftc", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
