//! Read only LC_CODE_SIGNATURE discovery. Never interprets encrypted sections.
//! Call encryption_status first to validate all container/load-command bounds.
type Result<T> = std::result::Result<T, String>;
fn word(d: &[u8], at: usize, big: bool) -> Result<u32> {
    let b = d.get(at..at.checked_add(4).ok_or("Mach-O offset overflow")?)
        .ok_or("Truncated Mach-O word")?.try_into().map_err(|_| "Invalid word")?;
    Ok(if big { u32::from_be_bytes(b) } else { u32::from_le_bytes(b) })
}
pub(super) fn signatures(d: &[u8]) -> Result<Vec<&[u8]>> { slices(d, false) }
fn slices(d: &[u8], nested: bool) -> Result<Vec<&[u8]>> {
    let magic = word(d, 0, true)?;
    if matches!(magic, 0xcafebabe | 0xcafebabf | 0xbebafeca | 0xbfbafeca) {
        if nested { return Err("Nested FAT container".into()); }
        let big = matches!(magic, 0xcafebabe | 0xcafebabf);
        let wide = matches!(magic, 0xcafebabf | 0xbfbafeca);
        let stride = if wide { 32 } else { 20 };
        let count = word(d, 4, big)? as usize;
        let end = count.checked_mul(stride).and_then(|v| v.checked_add(8)).ok_or("FAT overflow")?;
        if count == 0 || count > 128 || end > d.len() { return Err("Invalid FAT table".into()); }
        let mut result = Vec::new();
        let mut ranges = Vec::new();
        for i in 0..count {
            let at = 8 + i * stride + 8;
            let read = |at| -> Result<usize> {
                let n = if wide {
                    let b = d.get(at..at+8).ok_or("Truncated FAT table")?.try_into().map_err(|_| "Invalid FAT word")?;
                    if big { u64::from_be_bytes(b) } else { u64::from_le_bytes(b) }
                } else { word(d, at, big)? as u64 };
                usize::try_from(n).map_err(|_| "FAT offset overflow".into())
            };
            let off = read(at)?;
            let len = read(at + if wide { 8 } else { 4 })?;
            let stop = off.checked_add(len).ok_or("FAT range overflow")?;
            if off < end || stop > d.len() || ranges.iter().any(|&(a,b)| off < b && stop > a) {
                return Err("Invalid FAT slice bounds".into());
            }
            ranges.push((off, stop));
            result.extend(slices(&d[off..stop], true)?);
        }
        return Ok(result);
    }
    let (big, wide) = match magic {
        0xfeedface => (true, false), 0xcefaedfe => (false, false),
        0xfeedfacf => (true, true), 0xcffaedfe => (false, true),
        _ => return Err("Unsupported Mach-O magic".into()),
    };
    let mut at: usize = if wide { 32 } else { 28 };
    let end = at.checked_add(word(d, 20, big)? as usize).ok_or("Load table overflow")?;
    let count = word(d, 16, big)? as usize;
    if end > d.len() || count > 65536 { return Err("Invalid load table".into()); }
    let mut found = None;
    for _ in 0..count {
        if at.checked_add(8).ok_or("Command overflow")? > end { return Err("Truncated load command".into()); }
        let kind = word(d, at, big)?;
        let size = word(d, at+4, big)? as usize;
        if size < 8 || size % (if wide {8} else {4}) != 0 || size > end-at {
            return Err("Invalid load command size".into());
        }
        if kind == 0x1d {
            if size < 16 || found.is_some() { return Err("Invalid duplicate/short LC_CODE_SIGNATURE".into()); }
            let off = word(d, at+8, big)? as usize;
            let len = word(d, at+12, big)? as usize;
            let stop = off.checked_add(len).ok_or("Signature range overflow")?;
            if off < end || len < 12 { return Err("Invalid LC_CODE_SIGNATURE range".into()); }
            found = Some(d.get(off..stop).ok_or("Signature outside file")?);
        }
        at += size;
    }
    if at != end { return Err("Invalid command count".into()); }
    // One element per architecture, including unsigned slices, so callers can
    // reject inconsistent entitlements rather than silently granting one slice's.
    Ok(vec![found.unwrap_or(&[])])
}
#[cfg(test)]
mod tests {
    use super::*;
    fn put(d: &mut [u8], at: usize, n: u32, big: bool) {
        d[at..at+4].copy_from_slice(&if big {n.to_be_bytes()} else {n.to_le_bytes()});
    }
    fn fixture(wide: bool, big: bool) -> Vec<u8> {
        let mut d = vec![0; 512];
        let header = if wide {32} else {28};
        put(&mut d, 0, if wide {0xfeedfacf} else {0xfeedface}, big);
        put(&mut d, 16, 2, big); put(&mut d, 20, 40, big);
        // LC_ENCRYPTION_INFO_64 / LC_ENCRYPTION_INFO, ciphertext is opaque.
        put(&mut d, header, if wide {0x2c} else {0x21}, big);
        put(&mut d, header+4, 24, big); put(&mut d, header+8, 128, big);
        put(&mut d, header+12, 128, big); put(&mut d, header+16, 1, big);
        d[128..256].fill(0xa7);
        put(&mut d, header+24, 0x1d, big); put(&mut d, header+28, 16, big);
        put(&mut d, header+32, 256, big); put(&mut d, header+36, 12, big);
        d[256..268].copy_from_slice(&[0xfa,0xde,0x0c,0xc0,0,0,0,12,0,0,0,0]);
        d
    }
    #[test] fn encrypted_framework_and_appex_32_64_both_endian() {
        for wide in [false,true] { for big in [false,true] {
            let d = fixture(wide,big); let original = d.clone();
            assert_eq!(signatures(&d).unwrap(), vec![&d[256..268]]);
            assert_eq!(d,original); // including cryptid and ciphertext
        }}
    }
    #[test] fn fat32_fat64_and_swapped_encrypted_slices() {
        for wide in [false,true] { for big in [false,true] {
            let a=fixture(false,false); let b=fixture(true,false);
            let stride=if wide {32} else {20};
            let mut d=vec![0;1536];
            put(&mut d,0,if wide {0xcafebabf} else {0xcafebabe},big);
            put(&mut d,4,2,big);
            for (i,off) in [512usize,1024].into_iter().enumerate() {
                let at=8+i*stride+8;
                if wide {
                    d[at..at+8].copy_from_slice(&if big {(off as u64).to_be_bytes()} else {(off as u64).to_le_bytes()});
                    d[at+8..at+16].copy_from_slice(&if big {512u64.to_be_bytes()} else {512u64.to_le_bytes()});
                } else { put(&mut d,at,off as u32,big);put(&mut d,at+4,512,big); }
            }
            d[512..1024].copy_from_slice(&a);d[1024..1536].copy_from_slice(&b);
            assert_eq!(signatures(&d).unwrap().len(),2);
        }}
    }
    #[test] fn malformed_reports_reason_not_panic() {
        for len in 0..300 { let d=fixture(true,false); let _=signatures(&d[..len]); }
        let mut d=fixture(true,false); put(&mut d,68,u32::MAX,false);
        assert!(signatures(&d).unwrap_err().contains("outside"));
    }
}
