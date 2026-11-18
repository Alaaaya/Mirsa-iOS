//! Only the source-owned Mirsa loader ABI is recognized, never filenames alone.
//! All imported code remains data. Unknown/modified/third-party loaders stay read-only.
use super::*;
const LOADER: &[u8] = include_bytes!("../../loader/MirsaLoader.dylib");
pub(super) const OWNER: &str = "Frameworks/MirsaLoadOrder.txt";
const LOADER_PATH: &str = "Frameworks/MirsaLoader.dylib";

/// Recognize the exact source-owned executable, allowing ONLY an appended code
/// signature and its required header/linkedit size changes. This is deliberately
/// stricter than a UUID, filename, string or text-section fingerprint.
fn known_loader(d: &[u8]) -> Result<bool> {
    let original = commands(LOADER)?;
    let actual = commands(d)?;
    if d.get(..16) != LOADER.get(..16) || d.get(24..32) != LOADER.get(24..32) {
        return Ok(false);
    }
    let signatures: Vec<_> = actual.iter().filter(|c| c.kind == 0x1d).collect();
    if signatures.len() > 1 {
        return Ok(false);
    }
    let is_linkedit = |bytes: &[u8]| bytes.get(8..24) == Some(b"__LINKEDIT\0\0\0\0\0\0".as_slice());
    let old_linkedit = original
        .iter()
        .find(|c| c.kind == 0x19 && is_linkedit(&LOADER[c.at..c.at + c.size]))
        .ok_or("Missing known linkedit")?;
    let mut normalized = Vec::new();
    for c in &actual {
        if c.kind == 0x1d {
            continue;
        }
        let mut bytes = d[c.at..c.at + c.size].to_vec();
        if c.kind == 0x19 && is_linkedit(&bytes) {
            if c.size != 72 {
                return Ok(false);
            }
            let off = word(&bytes, 40, 8, true)?;
            let size = word(&bytes, 48, 8, true)?;
            let vm = word(&bytes, 32, 8, true)?;
            if off.checked_add(size) != Some(d.len() as u64)
                || vm < size
                || vm > size.checked_add(16383).ok_or("Linkedit overflow")?
            {
                return Ok(false);
            }
            // Only sizes may grow to accommodate an appended signature.
            bytes[32..40].copy_from_slice(&LOADER[old_linkedit.at + 32..old_linkedit.at + 40]);
            bytes[48..56].copy_from_slice(&LOADER[old_linkedit.at + 48..old_linkedit.at + 56]);
        }
        normalized.push(bytes);
    }
    let expected: Vec<_> = original
        .iter()
        .map(|c| LOADER[c.at..c.at + c.size].to_vec())
        .collect();
    if normalized != expected {
        return Ok(false);
    }
    let old_end = 32 + u32at(LOADER, 20)? as usize;
    let new_end = 32 + u32at(d, 20)? as usize;
    if new_end < old_end
        || new_end > LOADER.len()
        || LOADER[old_end..new_end].iter().any(|b| *b != 0)
        || d.get(new_end..LOADER.len()) != Some(&LOADER[new_end..])
    {
        return Ok(false);
    }
    if let Some(c) = signatures.first() {
        if c.size != 16 {
            return Ok(false);
        }
        let off = u32at(d, c.at + 8)? as usize;
        let size = u32at(d, c.at + 12)? as usize;
        if off < LOADER.len()
            || off.checked_add(size) != Some(d.len())
            || size == 0
            || d[LOADER.len()..off].iter().any(|b| *b != 0)
        {
            return Ok(false);
        }
    } else if d.len() != LOADER.len() {
        return Ok(false);
    }
    Ok(true)
}
fn safe(s: &str) -> bool {
    !s.is_empty()
        && s.len() < 1024
        && s.split('/').all(|p| {
            !p.is_empty()
                && p != "."
                && p != ".."
                && p.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
        })
}
pub(super) fn entries(app: &Path, graph: &[Library]) -> Result<Vec<Library>> {
    let loader = app.join(LOADER_PATH);
    let manifest = app.join(OWNER);
    if !loader.is_file() || !manifest.is_file() {
        return Ok(vec![]);
    }
    // The ABI must actually be reachable by a main executable load command.
    if !graph
        .iter()
        .any(|l| !l.owner.contains('/') && l.bundled_path.as_deref() == Some(LOADER_PATH))
    {
        return Ok(vec![]);
    }
    if !known_loader(&read_macho(&loader)?)? {
        return Ok(vec![]);
    }
    if fs::metadata(&manifest).map_err(err)?.len() > 65536 {
        return Err("Runtime manifest exceeds safe limit".into());
    }
    let data = fs::read(&manifest).map_err(err)?;
    if data.is_empty() {
        return Ok(vec![]);
    }
    if data.last() != Some(&b'\n') {
        return Err("Truncated runtime manifest".into());
    }
    let code = binaries(app)?;
    let text = std::str::from_utf8(&data).map_err(err)?;
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for line in text[..text.len() - 1].split('\n') {
        if out.len() == 64 || !safe(line) || !seen.insert(line) {
            return Err("Invalid runtime manifest entry".into());
        }
        let relative = format!("Frameworks/{line}");
        let resolved =
            safe_join(app, &app.join("Frameworks"), line)?.ok_or("Missing runtime library")?;
        // No same-file aliases, manifests, loader recursion or non-code resources.
        if relative == LOADER_PATH || relative == OWNER || !code.contains(&resolved) {
            return Err("Runtime entry is not a managed binary".into());
        }
        out.push(Library {
            id: format!("runtime|{line}"),
            owner: OWNER.into(),
            load_path: line.into(),
            kind: "runtime".into(),
            bundled_path: Some(relative),
            provenance: "verifiedMirsaRuntime".into(),
            slices: vec![],
        });
    }
    Ok(out)
}
pub(super) fn plan(
    app: &Path,
    graph: &[Library],
    edits: &[Edit],
) -> Result<(Vec<Library>, Option<Vec<u8>>)> {
    let entries = entries(app, graph)?;
    let mine: Vec<_> = edits.iter().filter(|e| e.owner == OWNER).collect();
    if mine.is_empty() {
        return Ok((entries, None));
    }
    if mine.len() != 1 || entries.is_empty() {
        return Err("No verified runtime configuration for this edit".into());
    }
    let e = mine[0];
    let removed: HashSet<_> = e.removed.iter().chain(&e.disabled).collect();
    let ordered: HashSet<_> = e.order.iter().collect();
    if removed.len() != e.removed.len() + e.disabled.len()
        || ordered.len() != e.order.len()
        || removed.intersection(&ordered).next().is_some()
    {
        return Err("Conflicting runtime edits".into());
    }
    for name in e.removed.iter().chain(&e.disabled).chain(&e.order) {
        if !entries.iter().any(|l| &l.load_path == name) {
            return Err("Unknown runtime entry".into());
        }
    }
    let mut kept: Vec<_> = entries
        .iter()
        .filter(|l| !removed.contains(&l.load_path))
        .collect();
    kept.sort_by_key(|l| {
        e.order
            .iter()
            .position(|n| n == &l.load_path)
            .unwrap_or(usize::MAX)
    });
    // Removing a manifest entry cannot prevent another binary from loading it.
    for l in entries.iter().filter(|l| removed.contains(&l.load_path)) {
        if graph
            .iter()
            .any(|edge| edge.bundled_path.is_none() || edge.bundled_path == l.bundled_path)
        {
            return Err(
                "Another dependency may load this runtime library; it cannot safely be disabled"
                    .into(),
            );
        }
    }
    // Reordering must not imply an initialization order that dependencies defeat.
    for (index, l) in kept.iter().enumerate() {
        let mut queue = vec![l.bundled_path.clone().unwrap()];
        let mut visited = HashSet::new();
        while let Some(owner) = queue.pop() {
            if !visited.insert(owner.clone()) {
                continue;
            }
            for edge in graph.iter().filter(|e| e.owner == owner) {
                let target = edge
                    .bundled_path
                    .as_ref()
                    .ok_or("Unresolved runtime dependency")?;
                if kept
                    .iter()
                    .enumerate()
                    .any(|(j, k)| j >= index && k.bundled_path.as_ref() == Some(target))
                {
                    return Err("Runtime dependency must precede its consumer".into());
                }
                queue.push(target.clone());
            }
        }
    }
    let data = if kept.is_empty() {
        Vec::new()
    } else {
        format!(
            "{}\n",
            kept.iter()
                .map(|l| l.load_path.as_str())
                .collect::<Vec<_>>()
                .join("\n")
        )
        .into_bytes()
    };
    Ok((entries, Some(data)))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn setup(tag: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!("mirsa-runtime-{}-{tag}", std::process::id()));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(p.join("Frameworks")).unwrap();
        fs::write(p.join(LOADER_PATH), LOADER).unwrap();
        fs::write(p.join(OWNER), b"A.dylib\nB.dylib\n").unwrap();
        fs::write(
            p.join("Main"),
            super::super::tests::fixture(
                &[(0xc, "@executable_path/Frameworks/MirsaLoader.dylib")],
                &[],
            ),
        )
        .unwrap();
        for n in ["A.dylib", "B.dylib"] {
            fs::write(
                p.join("Frameworks").join(n),
                super::super::tests::fixture(&[], &[]),
            )
            .unwrap()
        }
        p
    }
    #[test]
    fn exact_loader_and_signature_only_fingerprint() {
        assert!(known_loader(LOADER).unwrap());
        let mut d = LOADER.to_vec();
        let at = 32 + u32at(&d, 20).unwrap() as usize;
        put32(&mut d, at, 0x1d);
        put32(&mut d, at + 4, 16);
        put32(&mut d, at + 8, LOADER.len() as u32);
        put32(&mut d, at + 12, 16);
        let n = u32at(&d, 16).unwrap();
        let s = u32at(&d, 20).unwrap();
        put32(&mut d, 16, n + 1);
        put32(&mut d, 20, s + 16);
        d.extend([0xfa; 16]);
        let link = commands(&d)
            .unwrap()
            .into_iter()
            .find(|c| {
                c.kind == 0x19
                    && d.get(c.at + 8..c.at + 24) == Some(b"__LINKEDIT\0\0\0\0\0\0".as_slice())
            })
            .unwrap();
        let off = word(&d, link.at + 40, 8, true).unwrap();
        let size = d.len() as u64 - off;
        d[link.at + 48..link.at + 56].copy_from_slice(&size.to_le_bytes());
        d[link.at + 32..link.at + 40].copy_from_slice(&((size + 16383) & !16383).to_le_bytes());
        assert!(known_loader(&d).unwrap());
        d[16384] ^= 1;
        assert!(!known_loader(&d).unwrap());
    }
    #[test]
    fn actual_production_signed_loader_is_recognized_and_re_signable() {
        let entitlements = plist::Dictionary::new();
        let config = apple_codesign_quick::MachOSigningConfig::new(
            "MirsaLoader.dylib",
            "TEAM",
            &entitlements,
            None,
        );
        let signed =
            apple_codesign_quick::sign_macho_data(Path::new("MirsaLoader.dylib"), LOADER, &config)
                .unwrap();
        assert!(known_loader(&signed).unwrap());
        let again =
            apple_codesign_quick::sign_macho_data(Path::new("MirsaLoader.dylib"), &signed, &config)
                .unwrap();
        assert!(known_loader(&again).unwrap());
        let p = setup("signed");
        fs::write(p.join(LOADER_PATH), &again).unwrap();
        assert_eq!(
            inventory(&p)
                .unwrap()
                .iter()
                .filter(|l| l.kind == "runtime")
                .count(),
            2
        );
        fs::remove_dir_all(p).unwrap();
    }
    #[test]
    fn only_verified_manifest_is_editable_and_source_files_stay() {
        let p = setup("edit");
        let original = fs::read(p.join("Main")).unwrap();
        let rows = inventory(&p).unwrap();
        assert_eq!(rows.iter().filter(|l| l.kind == "runtime").count(), 2);
        let e = Edit {
            owner: OWNER.into(),
            disabled: vec!["A.dylib".into()],
            ..Edit::default()
        };
        apply(&p, &[e]).unwrap();
        assert_eq!(fs::read(p.join(OWNER)).unwrap(), b"B.dylib\n");
        assert!(p.join("Frameworks/A.dylib").is_file());
        assert_eq!(fs::read(p.join("Main")).unwrap(), original);
        fs::remove_dir_all(p).unwrap();
    }
    #[test]
    fn arbitrary_loader_names_are_not_runtime_provenance() {
        let p = setup("fake");
        fs::write(p.join(LOADER_PATH), super::super::tests::fixture(&[], &[])).unwrap();
        assert!(!inventory(&p).unwrap().iter().any(|l| l.kind == "runtime"));
        assert!(apply(
            &p,
            &[Edit {
                owner: OWNER.into(),
                disabled: vec!["A.dylib".into()],
                ..Edit::default()
            }]
        )
        .is_err());
        fs::remove_dir_all(p).unwrap();
    }
    #[test]
    fn traversal_malformed_and_duplicate_manifests_fail_before_writes() {
        for (i, bad) in [
            "../A.dylib\n",
            "A.dylib\nA.dylib\n",
            "A.dylib",
            "A.dylib\r\n",
            "Missing.dylib\n",
        ]
        .iter()
        .enumerate()
        {
            let p = setup(&format!("bad{i}"));
            fs::write(p.join(OWNER), bad).unwrap();
            assert!(apply(&p, &[]).is_err());
            assert_eq!(fs::read_to_string(p.join(OWNER)).unwrap(), *bad);
            fs::remove_dir_all(p).unwrap();
        }
    }
    #[test]
    fn reorder_and_disable_reject_shared_dependencies() {
        let p = setup("shared");
        fs::write(
            p.join("Frameworks/B.dylib"),
            super::super::tests::fixture(&[(0xc, "@loader_path/A.dylib")], &[]),
        )
        .unwrap();
        assert!(apply(
            &p,
            &[Edit {
                owner: OWNER.into(),
                disabled: vec!["A.dylib".into()],
                ..Edit::default()
            }]
        )
        .is_err());
        assert!(apply(
            &p,
            &[Edit {
                owner: OWNER.into(),
                order: vec!["B.dylib".into(), "A.dylib".into()],
                ..Edit::default()
            }]
        )
        .is_err());
        assert_eq!(fs::read(p.join(OWNER)).unwrap(), b"A.dylib\nB.dylib\n");
        fs::remove_dir_all(p).unwrap();
    }
}
