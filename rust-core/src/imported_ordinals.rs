//! Width-preserving ordinal rewriting. Sources: Apple's fixup-chains.h and
//! LLVM BinaryFormat/MachO.h. No relocation, no binding pointer chain changes.
use super::*;
fn mapped(n:u64,map:&[Option<usize>])->Result<u64>{
    if n==0{return Ok(0)}
    map.get(n as usize).ok_or("Binding ordinal outside dependency list")?.map(|v|v as u64).ok_or("Removed dependency still has symbol bindings".into())
}
fn leb(d:&[u8],p:&mut usize)->Result<u64>{
    let mut n=0u64;for shift in (0..70).step_by(7){let b=*d.get(*p).ok_or("Truncated binding LEB")?;*p+=1;if shift==63 && b&0x7e!=0{return Err("Binding LEB overflow".into())}n|=((b&127) as u64)<<shift;if b&128==0{return Ok(n)}}Err("Binding LEB overflow".into())
}
fn replace_leb(d:&mut[u8],start:usize,end:usize,n:u64)->Result<()>{
    let mut n=n;let mut out=Vec::new();loop{let b=(n&127)as u8;n>>=7;out.push(b|if n>0{128}else{0});if n==0{break}}
    if out.len()!=end-start{return Err("Binding ordinal LEB width change is unsupported".into())}d[start..end].copy_from_slice(&out);Ok(())
}
fn stream(d:&mut[u8],map:&[Option<usize>],lazy:bool)->Result<()>{
    let mut p=0;let mut ordinal=0u64;while p<d.len(){let at=p;let op=d[p];p+=1;match op&0xf0{
        0x00=>{if op!=0{return Err("Unknown bind opcode".into())}if !lazy{if d[p..].iter().any(|&b|b!=0){return Err("Trailing bind bytes".into())}return Ok(())}ordinal=0;},
        0x10=>{ordinal=(op&15)as u64;let n=mapped(ordinal,map)?;if n>15{return Err("Immediate binding ordinal growth unsupported".into())}d[at]=0x10|n as u8;},
        0x20=>{if op!=0x20{return Err("Invalid ordinal opcode".into())}let start=p;ordinal=leb(d,&mut p)?;replace_leb(d,start,p,mapped(ordinal,map)?)?;},
        0x30=>{ordinal=0;}, // special self/main/flat/weak values stay bit-identical
        0x40=>{let end=d[p..].iter().position(|&b|b==0).ok_or("Unterminated bind symbol")?;p+=end+1;},
        0x50=>{if !(1..=3).contains(&(op&15)){return Err("Unknown binding type".into())}},
        0x60=>{ // SLEB skip, accepts negative addends without interpreting them.
            let mut count=0;loop{let b=*d.get(p).ok_or("Truncated bind addend")?;p+=1;count+=1;if count>10{return Err("Bind addend overflow".into())}if b&128==0{break}}
        },
        0x70|0x80=>{leb(d,&mut p)?;},
        0x90=>{mapped(ordinal,map)?;},
        0xa0=>{mapped(ordinal,map)?;leb(d,&mut p)?;},
        0xb0=>{mapped(ordinal,map)?;},
        0xc0=>{mapped(ordinal,map)?;leb(d,&mut p)?;leb(d,&mut p)?;},
        _=>return Err("Threaded or unknown binding opcodes unsupported".into()),
    }}Ok(())
}
fn region<'a>(d:&'a mut[u8],at:usize,size:usize,minimum:usize)->Result<&'a mut[u8]>{
    if size==0{return Ok(&mut d[0..0])}
    if at<minimum{return Err("Binding payload overlaps headers".into())}
    d.get_mut(at..at.checked_add(size).ok_or("Binding range overflow")?).ok_or("Binding payload outside slice".into())
}
fn exports(d:&[u8])->Result<()> {
    if d.is_empty(){return Ok(())}let mut pending=vec![0usize];let mut seen=HashSet::new();
    while let Some(node)=pending.pop(){if !seen.insert(node){return Err("Cyclic or shared export trie unsupported".into())}if seen.len()>100000{return Err("Export trie budget exceeded".into())}
        let mut p=node;let size=leb(d,&mut p)?as usize;let end=p.checked_add(size).ok_or("Export trie overflow")?;if end>d.len(){return Err("Truncated export trie".into())}
        if size>0{let flags=leb(&d[..end],&mut p)?;if flags&8!=0{return Err("Reexport trie ordinal rewriting unsupported".into())}}
        p=end;let children=*d.get(p).ok_or("Truncated export children")?;p+=1;
        for _ in 0..children{let end=d.get(p..).ok_or("Invalid export edge")?.iter().position(|&b|b==0).ok_or("Unterminated export edge")?;p+=end+1;let next=leb(d,&mut p)?as usize;if next>=d.len(){return Err("Export node outside trie".into())}pending.push(next);}
    }Ok(())
}
pub(super) fn rewrite(m:&mut Mach,map:&[Option<usize>])->Result<()>{
    let min=m.first_data;
    // Segment envelopes intentionally overlap sections and LINKEDIT. Only concrete
    // live payloads participate. Writable regions must not alias ANY other payload.
    let mut regions:Vec<(usize,usize,bool)>=Vec::new();
    let mut add=|a:usize,n:usize,w:bool|->Result<()>{
        if n==0{return Ok(())}let b=a.checked_add(n).ok_or("Payload range overflow")?;
        if a<32+u32at(&m.data,20)?as usize || b>m.data.len(){return Err("Payload outside file or overlaps headers".into())}
        if regions.iter().any(|&(x,y,other)|a<y&&x<b&&(w||other)){return Err("Ordinal payload aliases another live payload".into())}
        regions.push((a,b,w));Ok(())
    };
    for c in &m.commands{
        let pair=|o:usize,width:usize|->Result<(usize,usize)>{Ok((u32at(&c.data,o)?as usize,(u32at(&c.data,o+4)?as usize).checked_mul(width).ok_or("Payload count overflow")?))};
        match c.kind{
            0x22|0x80000022=>for o in [8,16,24,32,40]{let(a,n)=pair(o,1)?;add(a,n,matches!(o,16|24|32))?},
            0x2=>{let(a,n)=pair(8,16)?;add(a,n,true)?;let(a,n)=pair(16,1)?;add(a,n,false)?},
            0xb=>for(o,w)in [(32,8),(40,56),(48,4),(56,4),(64,8),(72,8)]{let(a,n)=pair(o,w)?;add(a,n,false)?},
            0x1d|0x1e|0x26|0x29|0x2b|0x2e|0x80000033|0x80000034|0x36|0x2c|0x21=>{
                let(a,n)=pair(8,1)?;add(a,n,c.kind==0x80000034)?;
            },
            0x19=>{
                for i in 0..u32at(&c.data,64)?as usize{
                    let o=72+i*80;let typ=u32at(&c.data,o+64)?&255;
                    if !matches!(typ,1|0xc|0x12){add(u32at(&c.data,o+48)?as usize,usize::try_from(u64at(&c.data,o+40)?).map_err(err)?,false)?}
                    let(a,n)=pair(o+56,8)?;add(a,n,false)?;
                }
            },
            _=>{},
        }
    }
    for c in &m.commands{match c.kind{
        0x22|0x80000022=>{
            {let at=u32at(&c.data,40)?as usize;let n=u32at(&c.data,44)?as usize;exports(region(&mut m.data,at,n,min)?)?;}
            for (o,lazy) in [(16,false),(24,false),(32,true)]{let at=u32at(&c.data,o)?as usize;let n=u32at(&c.data,o+4)?as usize;stream(region(&mut m.data,at,n,min)?,map,lazy)?;}
        },
        0x80000033=>{let at=u32at(&c.data,8)?as usize;let n=u32at(&c.data,12)?as usize;exports(region(&mut m.data,at,n,min)?)?;},
        0xb=>{if [28,36,44,68,76].iter().any(|&o|u32at(&c.data,o).unwrap_or(1)!=0){return Err("Legacy module/reference/relocation tables unsupported".into())}},
        0x2=>{
            let at=u32at(&c.data,8)?as usize;let n=u32at(&c.data,12)?as usize;
            let syms=region(&mut m.data,at,n.checked_mul(16).ok_or("Symbol count overflow")?,min)?;
            for sym in syms.chunks_exact_mut(16){let typ=sym[4];if typ&0xe0==0 && typ&0x0e==0xc{return Err("Prebound undefined symbols unsupported".into())}if typ&0xe0==0 && typ&0x0e==0 && typ&1!=0{
                let ord=sym[7];if ord>0 && ord<0xfe {let n=mapped(ord as u64,map)?;if n>=0xfe{return Err("Symbol library ordinal overflow".into())}sym[7]=n as u8;}
            }}
        },
        0x80000034=>{
            let at=u32at(&c.data,8)?as usize;let n=u32at(&c.data,12)?as usize;if n==0{continue}
            let d=region(&mut m.data,at,n,min)?;
            if d.len()<28||u32at(d,0)?!=0||u32at(d,24)?!=0{return Err("Unsupported chained fixup header".into())}
            let base=u32at(d,8)?as usize;let count=u32at(d,16)?as usize;let format=u32at(d,20)?;
            let width=match format{1=>4,2=>8,3=>16,_=>return Err("Unsupported chained imports format".into())};
            if base<28 || base.checked_add(count.checked_mul(width).ok_or("Chained count overflow")?).ok_or("Chained range overflow")?>d.len(){return Err("Chained imports outside payload".into())}
            for i in 0..count{let p=base+i*width;let (ord,max)=if format==3{(u16::from_le_bytes([d[p],d[p+1]]) as u64,0xfff0)}else{(d[p]as u64,0xf0)};
                // Apple's packed ordinals reserve -15..-1, not all signed i8 negatives.
                if ord==0||ord>max{continue}let n=mapped(ord,map)?;if n>max{return Err("Chained library ordinal overflow".into())}d[p]=n as u8;if format==3{d[p+1]=(n>>8)as u8;}
            }
        },
        _=>{},
    }}Ok(())
}

#[cfg(test)]pub(super) fn test_stream(d:&mut[u8],map:&[Option<usize>])->Result<()>{stream(d,map,false)}
