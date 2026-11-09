//! Checked universal-container selection. Never modifies the supplied archive.
type Result<T> = std::result::Result<T, String>;
pub(super) fn word(d: &[u8], o: usize, wide: bool, little: bool) -> Result<u64> {
    let n = if wide { 8 } else { 4 };
    let bytes = d.get(o..o.checked_add(n).ok_or("FAT offset overflow")?)
        .ok_or("Truncated FAT header")?;
    let mut out = 0u64;
    if little {
        for (i, &b) in bytes.iter().enumerate() { out |= u64::from(b) << (8 * i); }
    } else {
        for &b in bytes { out = (out << 8) | u64::from(b); }
    }
    Ok(out)
}
pub(super) fn arm64(d: &[u8]) -> Result<&[u8]> {
    if d.len()<4 {return Err("Truncated Mach-O".into())}
    if !matches!(d.get(..4), Some([0xca,0xfe,0xba,0xbe]|[0xbe,0xba,0xfe,0xca]|[0xca,0xfe,0xba,0xbf]|[0xbf,0xba,0xfe,0xca])) {return Ok(d)}
    let ranges = arm64_ranges(d)?;
    ranges.into_iter().map(|(a,b)| &d[a..b]).find(|s| word(s,8,false,true).map(|n| n & 0xffffff == 0).unwrap_or(false)).ok_or("FAT binary has no generic arm64 slice (arm64e is not a fallback)".into())
}
pub(super) fn arm64_ranges(d: &[u8]) -> Result<Vec<(usize,usize)>> {
    let magic = d.get(..4).ok_or("Truncated Mach-O")?;
    let (wide, little) = match magic {
        [0xca, 0xfe, 0xba, 0xbe] => (false, false),
        [0xbe, 0xba, 0xfe, 0xca] => (false, true),
        [0xca, 0xfe, 0xba, 0xbf] => (true, false),
        [0xbf, 0xba, 0xfe, 0xca] => (true, true),
        _ => {
            if word(d,0,false,true)? != 0xfeedfacf || word(d,4,false,true)? != 0x100000c {return Err("Unsupported thin architecture".into())}
            return Ok(vec![(0,d.len())]);
        },
    };
    let count = word(d, 4, false, little)? as usize;
    let stride = if wide { 32 } else { 20 };
    if count == 0 || count > 128 { return Err("Invalid FAT architecture count".into()); }
    let table_end = 8 + count * stride;
    if table_end > d.len() { return Err("Truncated FAT architecture table".into()); }
    let mut ranges = Vec::new();
    let mut cpus = std::collections::HashSet::new();
    let mut selected = Vec::new();
    for i in 0..count {
        let a = 8 + i * stride;
        let cpu = word(d, a, false, little)? as u32;
        let sub = word(d, a + 4, false, little)? as u32;
        if !cpus.insert((cpu, sub & 0x00ff_ffff)) {
            return Err("Ambiguous duplicate FAT architecture".into());
        }
        let off = word(d, a + 8, wide, little)?;
        let size = word(d, a + if wide { 16 } else { 12 }, wide, little)?;
        let align = word(d, a + if wide { 24 } else { 16 }, false, little)?;
        if align > 31 || off % (1u64 << align) != 0 {
            return Err("Invalid FAT slice alignment".into());
        }
        if wide && word(d, a + 28, false, little)? != 0 {
            return Err("Nonzero FAT64 reserved field".into());
        }
        let end = off.checked_add(size).ok_or("FAT slice overflow")?;
        if off < table_end as u64 || size < 28 || end > d.len() as u64
            || ranges.iter().any(|&(a,b)| off < b && end > a) {
            return Err("Invalid or overlapping FAT slice bounds".into());
        }
        ranges.push((off, end));
        let slice = &d[off as usize..end as usize];
        // Validate every slice's actual CPU header, not just the selected slice.
        let thin_magic = &slice[..4];
        let (is64, le) = match thin_magic {
            [0xcf,0xfa,0xed,0xfe] => (true,true),
            [0xfe,0xed,0xfa,0xcf] => (true,false),
            [0xce,0xfa,0xed,0xfe] => (false,true),
            [0xfe,0xed,0xfa,0xce] => (false,false),
            _ => return Err("Invalid or nested FAT slice Mach-O header".into()),
        };
        if (is64 && size < 32) || word(slice,4,false,le)? != u64::from(cpu)
            || word(slice,8,false,le)? != u64::from(sub) {
            return Err("FAT table and Mach-O CPU header disagree".into());
        }
        if cpu == 0x0100_000c {
            if !is64 || !le { return Err("Unsupported arm64 slice format".into()); }
            selected.push((off as usize,end as usize));
        }
    }
    if selected.is_empty() {Err("FAT binary has no arm64 slices".into())} else {Ok(selected)}
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;
    pub(crate) fn fat(slices: &[Vec<u8>], wide: bool, little: bool) -> Vec<u8> {
        let stride = if wide {32} else {20};
        let mut d = vec![0;4096];
        d[..4].copy_from_slice(match (wide,little) {
            (false,false)=>&[0xca,0xfe,0xba,0xbe],(false,true)=>&[0xbe,0xba,0xfe,0xca],
            (true,false)=>&[0xca,0xfe,0xba,0xbf],(true,true)=>&[0xbf,0xba,0xfe,0xca]});
        set(&mut d,4,slices.len() as u64,false,little);
        for (i,s) in slices.iter().enumerate() {
            let off = d.len(); let a=8+i*stride;
            set(&mut d,a,u32::from_le_bytes(s[4..8].try_into().unwrap()) as u64,false,little);
            set(&mut d,a+4,u32::from_le_bytes(s[8..12].try_into().unwrap()) as u64,false,little);
            set(&mut d,a+8,off as u64,wide,little);
            set(&mut d,a+if wide{16}else{12},s.len() as u64,wide,little);
            set(&mut d,a+if wide{24}else{16},12,false,little);
            d.extend_from_slice(s);
            d.resize((d.len()+4095)&!4095,0);
        } d
    }
    fn set(d:&mut[u8],o:usize,v:u64,wide:bool,le:bool) {
        let n=if wide{8}else{4};let bytes=if le{v.to_le_bytes()}else{v.to_be_bytes()};
        d[o..o+n].copy_from_slice(if le{&bytes[..n]}else{&bytes[8-n..]});
    }
    fn thin(cpu:u32,sub:u32)->Vec<u8>{
        let mut d=vec![0;32];d[..4].copy_from_slice(&0xfeedfacfu32.to_le_bytes());
        d[4..8].copy_from_slice(&cpu.to_le_bytes());d[8..12].copy_from_slice(&sub.to_le_bytes());d
    }
    #[test] fn thin_selection_keeps_existing_parser_authority() {
        let e=thin(0x100000c,2);assert_eq!(arm64(&e).unwrap(),e);
        let x=thin(0x1000007,3);assert_eq!(arm64(&x).unwrap(),x);
        assert!(arm64_ranges(&x).is_err());
    }
    #[test] fn all_formats_select_generic_not_first() {
        for wide in [false,true] {for le in [false,true] {
            let generic=thin(0x100000c,0);let e=thin(0x100000c,2);
            let d=fat(&[e,generic.clone()],wide,le);assert_eq!(arm64(&d).unwrap(),generic);
        }}
    }
    #[test] fn malformed_tables_fail_closed() {
        for wide in [false,true] {for le in [false,true] {
            let stride=if wide{32}else{20};
            let base=fat(&[thin(0x100000c,0),thin(0x100000c,2)],wide,le);
            for len in [0,3,7,8,8+stride*2-1] {assert!(arm64(&base[..len]).is_err());}
            for (o,v,w) in [(4,0,false),(4,129,false),(16,0,wide),
                (16,u64::MAX,wide),(8+if wide{16}else{12},u64::MAX,wide),
                (8+if wide{24}else{16},64,false),
                (8+if wide{24}else{16},31,false),
                (8+stride+8,4096,wide),
                (8+stride+4,0,false),(8,7,false)] {
                let mut d=base.clone();set(&mut d,o,v,w,le);assert!(arm64(&d).is_err(),"{wide} {le} {o} {v}");
            }
            let mut d=base.clone();d[4096..4100].copy_from_slice(&[0xca,0xfe,0xba,0xbe]);assert!(arm64(&d).is_err());
            let mut d=base.clone();d[4104]=2;assert!(arm64(&d).is_err());
            if wide {let mut d=base.clone();set(&mut d,36,1,false,le);assert!(arm64(&d).is_err());}
        }}
    }
    #[test] fn no_arm64e_or_32bit_fallback() {
        assert!(arm64(&fat(&[thin(0x100000c,2)],false,false)).is_err());
        let mut d=thin(12,0);d[..4].copy_from_slice(&0xfeedfaceu32.to_le_bytes());
        assert!(arm64(&fat(&[d],false,false)).is_err());
        assert!(arm64(&fat(&[thin(0x100000c,0),thin(0x100000c,0x80000000)],true,true)).is_err());
    }
}
