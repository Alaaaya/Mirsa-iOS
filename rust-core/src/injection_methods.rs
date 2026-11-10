//! Method capabilities are read-only. Shared eligibility uses exact resolved
//! bundled dependency identities, never a filename guess. Missing/inherited
//! rpaths and ambiguous resolutions fail closed, not "best effort".
use super::*;
use serde::Serialize;

fn thin(path: &Path, library: bool) -> Result<()> {
    let bytes = read_macho(path)?;
    if bytes.get(..4) != Some(&[0xcf, 0xfa, 0xed, 0xfe]) {
        return Err("shared_unsupported_fat_or_abi".into());
    }
    macho(bytes, library).map(|_| ())
}
fn reachable(
    app: &Path,
    id: &str,
    edges: &BTreeMap<String, Vec<Option<String>>>,
    active: &mut HashSet<String>,
    done: &mut HashSet<String>,
    libraries: &mut HashSet<String>,
    depth: usize,
) -> Result<()> {
    if depth > 128 || done.len() > 4096 { return Err("shared_graph_limit".into()); }
    if active.contains(id) { return Err("shared_dependency_cycle".into()); }
    if done.contains(id) { return Ok(()); }
    let path = app.join(relative(id)?);
    // Filetype, full command bounds, encryption and generic arm64 checked before
    // exposing any candidate. Even a different unsupported reachable dependency
    // disables this optimization rather than silently losing a process slice.
    thin(&path, depth != 0)?;
    active.insert(id.into());
    if let Some(deps) = edges.get(id) {
        for target in deps {
            let target = target.as_ref().ok_or("shared_unresolved_or_ambiguous_dependency")?;
            libraries.insert(target.clone());
            reachable(app,target,edges,active,done,libraries,depth+1)?;
        }
    }
    active.remove(id);
    done.insert(id.into());
    Ok(())
}
pub(super) fn shared_candidates(app: &Path, processes: &[String]) -> Result<Vec<String>> {
    tweak_targets::checked_tree(app)?;
    let app = fs::canonicalize(app).map_err(err)?;
    let targets = tweak_targets::targets(&app)?;
    if processes.len() < 2 || processes.len() > 65 { return Err("shared_requires_main_and_extension".into()); }
    let mut seen = HashSet::new();
    for id in processes {
        if !seen.insert(id) { return Err("duplicate_process_target".into()); }
        if !targets.iter().any(|t|t.id == *id && matches!(t.kind.as_str(),"main"|"extension")) {
            return Err("shared_requires_process_targets".into());
        }
    }
    if !processes.iter().any(|p|targets.iter().any(|t|t.id == *p && t.kind == "main"))
        || !processes.iter().any(|p|targets.iter().any(|t|t.id == *p && t.kind == "extension")) {
        return Err("shared_requires_main_and_extension".into());
    }
    let mut edges:BTreeMap<String, Vec<Option<String>>> = BTreeMap::new();
    for library in existing_libraries::graph(&app)? {
        if !matches!(library.kind.as_str(),"load"|"reexport") { continue; }
        // A library's executable-relative path is process-context dependent.
        // Existing graph inspection intentionally has no inherited process context.
        // Never treat its root-app resolution as proof for an extension.
        let resolved = if library.load_path.starts_with("@executable_path/")
            && !targets.iter().any(|t| t.id == library.owner && matches!(t.kind.as_str(),"main"|"extension")) {
            None
        } else { library.bundled_path };
        edges.entry(library.owner).or_default().push(resolved);
    }
    let mut common:Option<HashSet<String>> = None;
    for process in processes {
        let mut libraries = HashSet::new();
        reachable(&app, process, &edges, &mut HashSet::new(), &mut HashSet::new(), &mut libraries,0)?;
        common = Some(match common { None => libraries, Some(c) => c.intersection(&libraries).cloned().collect() });
    }
    let mut result:Vec<_> = common.unwrap_or_default().into_iter().collect();
    result.sort();
    if result.is_empty() { return Err("shared_no_common_dependency".into()); }
    Ok(result)
}
#[derive(Serialize)]
struct Method { id: &'static str, enabled: bool, reason: Option<&'static str> }
#[derive(Serialize)]
struct Candidate { id:String, label:String, processes:Vec<String> }
pub(super) fn capabilities(app:&Path,out:&Path)->Result<()> { capabilities_for(app,&[],out) }
pub(super) fn capabilities_for(app:&Path,items:&[tweak_targets::Injection],out:&Path)->Result<()> {
    if items.len()>64{return Err("capability_item_limit".into())}
    let targets = tweak_targets::targets(app)?;
    if targets.len()>128 {return Err("capability_target_limit".into())}
    let main=targets.iter().find(|t|t.kind=="main").ok_or("Missing main target")?;
    let extensions:Vec<_>=targets.iter().filter(|t|t.kind=="extension").collect();
    if extensions.len()>64{return Err("capability_extension_limit".into())}
    let mut components=Vec::new();
    for item in items {
        let mut methods=Vec::new();
        let mut eligible=serde_json::Map::new();
        for method in ["direct","load_control","separate_extension"] {
            let mut ids=Vec::new();let mut reason=None;
            for target in &targets {
                if method=="load_control" && target.kind=="framework" {continue}
                if method=="separate_extension" && target.kind!="extension" {continue}
                let mut probe=item.clone();probe.method=Some(method.into());
                probe.target=target.id.clone();probe.targets=vec![target.id.clone()];probe.shared_target=None;
                match probe_method(app,&probe) {Ok(())=>ids.push(target.id.clone()),Err(e)=>reason=Some(e)}
            }
            let enabled=!ids.is_empty();
            methods.push(serde_json::json!({"id":method,"enabled":enabled,"reason":if enabled{None}else{reason.or(Some("no_eligible_targets".into()))}}));
            eligible.insert(method.into(),serde_json::json!(ids));
        }
        let mut verified=Vec::new();let mut shared_reason=None;
        // Each actual main+appex pair is inspected independently. Unselected
        // extensions cannot hide valid shared targets. No combinatorial subsets.
        for extension in &extensions {
            let processes=vec![main.id.clone(),extension.id.clone()];
            match shared_candidates(app,&processes) {
                Ok(candidates)=>for id in candidates {
                    let mut probe=item.clone();probe.method=Some("shared_library".into());
                    probe.target=main.id.clone();probe.targets=processes.clone();probe.shared_target=Some(id.clone());
                    match probe_method(app,&probe) {
                        Ok(())=>verified.push(Candidate{id:id.clone(),label:id,processes:processes.clone()}),
                        Err(e)=>shared_reason=Some(e)
                    }
                },
                Err(e)=>shared_reason=Some(e)
            }
        }
        let enabled=!verified.is_empty();
        methods.insert(2,serde_json::json!({"id":"shared_library","enabled":enabled,"reason":if enabled{None}else{shared_reason.or(Some("shared_requires_main_and_extension".into()))}}));
        components.push(serde_json::json!({"id":item.id,"methods":methods,"eligibleTargets":eligible,"sharedCandidates":verified}));
    }
    let targets = tweak_targets::targets(app)?;
    let processes:Vec<_> = targets.iter().filter(|t|matches!(t.kind.as_str(),"main"|"extension")).map(|t|t.id.clone()).collect();
    let has_extension = targets.iter().any(|t|t.kind=="extension");
    let (shared,reason) = match shared_candidates(app,&processes) {
        Ok(ids)=>(ids.into_iter().map(|id|Candidate{label:id.clone(),id,processes:processes.clone()}).collect::<Vec<_>>(),None),
        Err(e)=>(Vec::new(),Some(e))
    };
    let methods = vec![
        Method{id:"direct",enabled:true,reason:None},
        Method{id:"load_control",enabled:true,reason:None},
        Method{id:"shared_library",enabled:!shared.is_empty(),reason:if shared.is_empty(){Some("shared_unavailable")}else{None}},
        Method{id:"separate_extension",enabled:has_extension,reason:if has_extension{None}else{Some("no_extensions")}},
    ];
    fs::write(out,serde_json::to_vec(&serde_json::json!({
        "targets":targets,"methods":methods,"sharedCandidates":shared,"sharedDisabledReason":reason,"components":components
    })).map_err(err)?).map_err(err)
}


// Capabilities for an imported component use the real transaction/injector,
// with isolated copies. No user code runs, and original IPA data is never edited.
fn probe_method(app:&Path,item:&tweak_targets::Injection)->Result<()> {
    use std::sync::atomic::{AtomicU64,Ordering};
    static NEXT:AtomicU64=AtomicU64::new(0);
    let root=std::env::temp_dir().join(format!("mirsa-capability-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::Relaxed)));
    fs::create_dir(&root).map_err(err)?;
    let work=root.join("Probe.app");
    let result=(||{tweak_targets::checked_tree(app)?;copy_tree(app,&work)?;
        tweak_targets::inject_plan(&work,&[item.clone()],&[],false,false)})();
    let _=fs::remove_dir_all(&root);result
}
