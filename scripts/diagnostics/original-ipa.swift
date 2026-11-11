let fm = FileManager.default
let download = try MirsaManagedTmp.begin("url-diagnostic")
let pending = try MirsaManagedTmp.begin("import-diagnostic")
let ipa = pending.appendingPathComponent("original.ipa")
try Data("archive".utf8).write(to: ipa)
print("ROOT", MirsaManagedTmp.root.path, "WORK", pending.path, "ACTIVE", MirsaManagedTmp.isActive(pending.path))
for item in try fm.contentsOfDirectory(at: MirsaManagedTmp.root, includingPropertiesForKeys: nil) {
    print("ENTRY", item.path, "ACTIVE", MirsaManagedTmp.isActive(item.path))
}
MirsaManagedTmp.end(download)
print("AFTER_DOWNLOAD_END", fm.fileExists(atPath: ipa.path))
MirsaManagedTmp.cleanNow()
print("AFTER_CLEAN", fm.fileExists(atPath: ipa.path))
precondition(fm.fileExists(atPath: ipa.path), "Cleanup deleted pending original IPA")
MirsaManagedTmp.end(pending)
