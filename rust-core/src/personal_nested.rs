//! Conservative nested signing plan. Pure policy helpers are separately testable.
use super::{Options, matches_id};
use std::{path::{Path, PathBuf}, collections::{BTreeMap, BTreeSet}, fs};
use plist::{Value, Dictionary};
type Result<T> = std::result::Result<T, String>;
fn error(e: impl std::fmt::Display) -> String { e.to_string() }
pub(super) struct Node { pub path: PathBuf, pub id: String, pub framework: bool, pub info: Value }
impl Node {
    pub fn executable(&self) -> Result<PathBuf> {
        let name = self.info.as_dictionary().and_then(|d| d.get("CFBundleExecutable"))
            .and_then(Value::as_string).ok_or("اسم الملف التنفيذي مو موجود.")?;
        if name.is_empty() || name.contains(['/', '\\', ':']) || name == "." || name == ".." {
            return Err("مسار الملف التنفيذي غير آمن.".into());
        }
        Ok(self.path.join(name))
    }
}
pub(super) fn removed(root: &Path, path: &Path, o: &Options) -> bool {
    let Ok(p) = path.strip_prefix(root) else { return false };
    p.components().any(|c| {
        let s = c.as_os_str().to_str().unwrap_or("");
        (o.remove_extensions && s == "PlugIns") || (o.remove_watch && s == "Watch")
            || (o.remove_app_clips && s == "AppClips")
    })
}
pub(super) fn inventory(root: &Path, o: &Options) -> Result<Vec<Node>> {
    let mut files = vec![]; crate::ipa_editor::walk(root, &mut files)?;
    let paths = std::iter::once(root.to_path_buf()).chain(files.into_iter().filter(|p|
        p.is_dir() && matches!(p.extension().and_then(|s| s.to_str()), Some("app" | "appex" | "framework"))));
    let mut nodes = vec![]; let mut ids = BTreeSet::new();
    for path in paths.filter(|p| !removed(root, p, o)) {
        let info = Value::from_file(path.join("Info.plist")).map_err(|_| "معلومات تطبيق مضمّن غير صالحة.")?;
        let id = info.as_dictionary().and_then(|d| d.get("CFBundleIdentifier"))
            .and_then(Value::as_string).ok_or("معرّف تطبيق مضمّن مو موجود.")?.to_owned();
        if !valid_id(&id) || !ids.insert(id.clone()) { return Err("معرّف تطبيق غير صالح أو مكرر.".into()); }
        let framework = path.extension().and_then(|s| s.to_str()) == Some("framework");
        let node = Node { path, id, framework, info }; node.executable()?; nodes.push(node);
        if nodes.len() > 256 { return Err("عدد التطبيقات المضمّنة كبير جداً.".into()); }
    }
    Ok(nodes)
}
pub(super) fn valid_id(id: &str) -> bool { !id.is_empty() && id.len() <= 255 && id.split('.').all(|s|
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')) }
pub(super) fn id_map(nodes: &[Node], old: &str, new: &str) -> Result<BTreeMap<String,String>> {
    let mut map = BTreeMap::new(); let mut seen = BTreeSet::new();
    for n in nodes {
        let id = if n.framework || old == new { n.id.clone() }
        else if n.id == old { new.to_owned() }
        else if let Some(suffix) = n.id.strip_prefix(&format!("{old}.")) { format!("{new}.{suffix}") }
        else { return Err(format!("معرّف الإضافة {} مو تابع للتطبيق الرئيسي. استخدم بروفايل بنفس معرّف التطبيق الأصلي.", n.id)); };
        if !valid_id(&id) || !seen.insert(id.clone()) { return Err("تعارض معرّفات التطبيقات بعد التعديل.".into()); }
        map.insert(n.id.clone(), id);
    }
    Ok(map)
}
pub(super) fn select_profile(patterns: &[&str], id: &str) -> Option<usize> {
    let mut candidates = vec![];
    for (i,p) in patterns.iter().enumerate() {
        let Some((prefix,scope)) = p.split_once('.') else { continue };
        if !valid_id(prefix) { continue; }
        let valid = if let Some(s) = scope.strip_suffix('*') {
            s.is_empty() || (s.ends_with('.') && valid_id(s.trim_end_matches('.')))
        } else { valid_id(scope) };
        if !valid || scope.matches('*').count() > 1 { continue; }
        if matches_id(p, &format!("{prefix}.{id}")) {
            candidates.push((!scope.contains('*'), scope.len(), std::cmp::Reverse(i), i));
        }
    }
    candidates.sort(); candidates.last().map(|c| c.3)
}
// Only documented identifier-bearing keys are changed, never arbitrary strings.
fn rewrite_refs(v: &mut Value, map: &BTreeMap<String,String>) {
    match v {
        Value::Dictionary(d) => for (k,v) in d.iter_mut() {
            if matches!(k.as_str(), "CFBundleIdentifier" | "WKCompanionAppBundleIdentifier" | "WKAppBundleIdentifier" | "NSExtensionContainingAppBundleIdentifier") {
                if let Some(new) = v.as_string().and_then(|s| map.get(s)) { *v = Value::String(new.clone()); }
            } else { rewrite_refs(v,map); }
        },
        Value::Array(a) => for v in a { rewrite_refs(v,map); },
        _ => ()
    }
}
pub(super) fn rewrite(n: &mut Node, map: &BTreeMap<String,String>) -> Result<()> {
    rewrite_refs(&mut n.info,map);
    n.info.to_file_xml(n.path.join("Info.plist")).map_err(error)?;
    // A framework must not carry an old app provisioning profile.
    let p = n.path.join("embedded.mobileprovision");
    if n.framework && p.exists() { fs::remove_file(p).map_err(error)?; }
    Ok(())
}
pub(super) fn apply_removals(root: &Path, o: &Options) -> Result<()> {
    let mut files = vec![]; crate::ipa_editor::walk(root,&mut files)?;
    files.sort_by_key(|p| p.components().count());
    for path in files {
        if removed(root,&path,o) && path.exists() {
            if path.is_dir() { fs::remove_dir_all(path).map_err(error)?; } else { fs::remove_file(path).map_err(error)?; }
        }
    }
    Ok(())
}
fn authorized(request: &Value, allowed: &Value) -> bool {
    match (request,allowed) {
        (Value::String(r),Value::String(a)) => matches_id(a,r),
        (Value::Array(rs),Value::Array(as_)) => rs.iter().all(|r| as_.iter().any(|a| authorized(r,a))),
        (Value::Dictionary(rs),Value::Dictionary(as_)) => rs.iter().all(|(k,r)| as_.get(k).is_some_and(|a| authorized(r,a))),
        _ => request == allowed
    }
}
// Intersection never grants profile-only capabilities or expands requested wildcards.
fn intersection(request: &Value, allowed: &Value) -> Option<Value> {
    match (request, allowed) {
        (Value::Array(rs), Value::Array(as_)) => {
            let kept: Vec<_> = rs.iter().filter(|r| as_.iter().any(|a| authorized(r,a))).cloned().collect();
            if kept.is_empty() && !rs.is_empty() { None } else { Some(Value::Array(kept)) }
        },
        (Value::Dictionary(rs), Value::Dictionary(as_)) => {
            let mut kept = Dictionary::new();
            for (k,r) in rs { if let Some(v) = as_.get(k).and_then(|a| intersection(r,a)) { kept.insert(k.clone(),v); } }
            if kept.is_empty() && !rs.is_empty() { None } else { Some(Value::Dictionary(kept)) }
        },
        _ if authorized(request,allowed) => Some(request.clone()),
        _ => None,
    }
}
const APP_GROUPS: &str = "com.apple.security.application-groups";
fn concrete_group(s: &str) -> bool {
    s.starts_with("group.") && valid_id(s) && s.len() > "group.".len()
}
fn group_authorized(s: &str, allowed: &Dictionary) -> bool {
    concrete_group(s) && allowed.get(APP_GROUPS).and_then(Value::as_array)
        .is_some_and(|a| a.iter().any(|v| v.as_string().is_some_and(|p| matches_id(p,s))))
}
/// Plan once for the entire bundle tree. A shared original group must map to
/// one concrete ID authorized by EVERY profile whose app requests that group.
/// None is deliberate: disjoint capabilities must never silently split storage.
pub(super) fn app_group_plan(pairs: &[(&Dictionary, &Dictionary)]) -> BTreeMap<String, Option<String>> {
    let mut consumers: BTreeMap<String, Vec<&Dictionary>> = BTreeMap::new();
    for (request, allowed) in pairs {
        if let Some(groups) = request.get(APP_GROUPS).and_then(Value::as_array) {
            for group in groups.iter().filter_map(Value::as_string).filter(|s| concrete_group(s)) {
                consumers.entry(group.to_owned()).or_default().push(allowed);
            }
        }
    }
    let mut plan = BTreeMap::new();
    for (original, profiles) in consumers {
        let mut candidates = BTreeSet::new();
        for profile in &profiles {
            if let Some(groups) = profile.get(APP_GROUPS).and_then(Value::as_array) {
                for pattern in groups.iter().filter_map(Value::as_string) {
                    if concrete_group(pattern) { candidates.insert(pattern.to_owned()); }
                    // Instantiate only scoped, valid trailing wildcards. Never
                    // emit wildcard entitlements, invent grants, or use bundle IDs.
                    if let Some(scope) = pattern.strip_suffix(".*") {
                        if scope.starts_with("group.") && valid_id(scope) {
                            candidates.insert(format!("{scope}.{}", &original["group.".len()..]));
                        }
                    }
                }
            }
        }
        let mapped = if profiles.iter().all(|a| group_authorized(&original,a)) {
            Some(original.clone())
        } else {
            candidates.into_iter().find(|s| profiles.iter().all(|a| group_authorized(s,a)))
        };
        plan.insert(original, mapped);
    }
    plan
}
pub(super) fn constrain(request: &Dictionary, allowed: &Dictionary, prefix: &str, id: &str, team: &str,
    map: &BTreeMap<String,String>, strict: bool) -> Result<(Dictionary, Vec<String>)> {
    let groups = app_group_plan(&[(request, allowed)]);
    constrain_with_groups(request, allowed, prefix, id, team, map, strict, &groups)
}
pub(super) fn constrain_with_groups(request: &Dictionary, allowed: &Dictionary, prefix: &str, id: &str, team: &str,
    map: &BTreeMap<String,String>, strict: bool, groups: &BTreeMap<String,Option<String>>) -> Result<(Dictionary, Vec<String>)> {
    let mut out = Dictionary::new();
    let mut dropped = Vec::new();
    for (k,v) in request {
        if matches!(k.as_str(), "application-identifier" | "com.apple.developer.team-identifier" ) { continue; }
        let mut v = v.clone();
        if k == "keychain-access-groups" {
            if let Value::Array(groups) = &mut v {
                for group in groups {
                    if let Some(s) = group.as_string() {
                        if let Some((_,old)) = s.split_once('.') {
                            *group = format!("{prefix}.{}",map.get(old).map(String::as_str).unwrap_or(old)).into();
                        }
                    }
                }
            }
        }
        if k == APP_GROUPS && !strict {
            if let Some(requested) = v.as_array() {
                let mut mapped = Vec::new();
                for original in requested.iter().filter_map(Value::as_string) {
                    if let Some(Some(replacement)) = groups.get(original) {
                        if group_authorized(replacement, allowed) && !mapped.contains(&Value::String(replacement.clone())) {
                            mapped.push(Value::String(replacement.clone()));
                        }
                    }
                }
                v = Value::Array(mapped);
            }
        }
        let filtered = allowed.get(k).and_then(|a| intersection(&v,a))
            .filter(|v| k != APP_GROUPS || v.as_array().is_some_and(|a| !a.is_empty()));
        // Report substitutions as well as dropped entries, never as success with
        // the original app-group identity. Strict mode never uses the plan.
        let changed_groups = k == APP_GROUPS && &v != request.get(k).unwrap();

        if changed_groups || filtered.as_ref() != Some(&v) {
            if strict { return Err(format!("الصلاحية المطلوبة {k} مو موجودة بالبروفايل. استورد بروفايل يدعمها.")); }
            dropped.push(k.clone());
        }
        if let Some(v) = filtered { out.insert(k.clone(),v); }
    }
    out.insert("application-identifier".into(), format!("{prefix}.{id}").into());
    out.insert("com.apple.developer.team-identifier".into(), team.into());
    Ok((out,dropped))
}

fn be(d: &[u8], at: usize) -> Result<u32> { d.get(at..at+4).and_then(|s| s.try_into().ok()).map(u32::from_be_bytes).ok_or("توقيع Mach-O غير صالح.".into()) }
fn le(d: &[u8], at: usize) -> Result<u32> { d.get(at..at+4).and_then(|s| s.try_into().ok()).map(u32::from_le_bytes).ok_or("ملف Mach-O غير صالح.".into()) }
fn signature_entitlements(d: &[u8]) -> Result<Dictionary> {
    if be(d,0)? != 0xfade0cc0 { return Err("صيغة توقيع التطبيق غير مدعومة.".into()); }
    let len = be(d,4)? as usize; let count = be(d,8)? as usize;
    if len > d.len() || count > 1024 || 12+count*8 > len { return Err("جدول توقيع غير صالح.".into()); }
    let d = &d[..len]; let mut result = None; let mut der_only = false;
    for i in 0..count {
        let kind = be(d,12+i*8)?;
        let offset = be(d,16+i*8)? as usize;
        let magic = be(d,offset)?; let size = be(d,offset+4)? as usize;
        if offset < 12+count*8 || size < 8 || size > d.len().saturating_sub(offset) { return Err("حدود توقيع غير صالحة.".into()); }
        if kind == 5 {
            if magic != 0xfade7171 || result.is_some() { return Err("صلاحيات توقيع غير صالحة.".into()); }
            let value = Value::from_reader(std::io::Cursor::new(&d[offset+8..offset+size])).map_err(|_| "تعذّر قراءة صلاحيات التطبيق.")?;
            result = Some(value.into_dictionary().ok_or("صلاحيات التطبيق غير صالحة.")?);
        }
        if kind == 7 { der_only = true; }
    }
    if der_only && result.is_none() { return Err("صلاحيات DER فقط غير مدعومة بأمان حالياً.".into()); }
    Ok(result.unwrap_or_default())
}
pub(super) fn read_entitlements(d: &[u8]) -> Result<Dictionary> {
    crate::ipa_editor::encryption_status(d)?;
    let magic = be(d,0)?;
    if magic == 0xcafebabe || magic == 0xcafebabf {
        let stride = if magic == 0xcafebabf {32} else {20}; let count = be(d,4)? as usize;
        let mut result = None;
        for i in 0..count {
            let a = 8+i*stride;
            let (off,len) = if stride == 20 { (be(d,a+8)? as usize,be(d,a+12)? as usize) }
                else { (usize::try_from(u64::from_be_bytes(d[a+8..a+16].try_into().unwrap())).map_err(error)?,
                        usize::try_from(u64::from_be_bytes(d[a+16..a+24].try_into().unwrap())).map_err(error)?) };
            let ent = read_entitlements(&d[off..off+len])?;
            if result.as_ref().is_some_and(|r| r != &ent) { return Err("صلاحيات شرائح التطبيق مختلفة.".into()); }
            result = Some(ent);
        }
        return Ok(result.unwrap_or_default());
    }
    let mut at = 32; let mut found = None;
    for _ in 0..le(d,16)? {
        let size = le(d,at+4)? as usize;
        if le(d,at)? == 0x1d {
            if size < 16 || found.is_some() { return Err("أمر توقيع غير صالح.".into()); }
            let off = le(d,at+8)? as usize; let len = le(d,at+12)? as usize;
            let sig = d.get(off..off.checked_add(len).ok_or("تجاوز حدود التوقيع.")?).ok_or("حدود التوقيع غير صالحة.")?;
            found = Some(signature_entitlements(sig)?);
        }
        at += size;
    }
    Ok(found.unwrap_or_default())
}
pub(super) fn check_macho_file(path: &Path) -> Result<()> {
    use std::io::Read;
    let mut file = fs::File::open(path).map_err(error)?; let mut magic = [0;4];
    if file.read_exact(&mut magic).is_ok() && matches!(magic,
        [0xcf,0xfa,0xed,0xfe] | [0xfe,0xed,0xfa,0xcf] | [0xce,0xfa,0xed,0xfe] | [0xfe,0xed,0xfa,0xce] |
        [0xca,0xfe,0xba,0xbe] | [0xbe,0xba,0xfe,0xca] | [0xca,0xfe,0xba,0xbf] | [0xbf,0xba,0xfe,0xca]) {
        crate::ipa_editor::encryption_status(&fs::read(path).map_err(error)?)?;
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn exact_then_scoped_wildcard() {
        assert_eq!(select_profile(&["TEAM.*","TEAM.com.test.*","TEAM.com.test.app"],"com.test.app"),Some(2));
        assert_eq!(select_profile(&["TEAM.*","TEAM.com.test.*"],"com.test.app"),Some(1));
        assert_eq!(select_profile(&["TEAM.com.test.*"],"com.other.app"),None);
    }
    #[test] fn unauthorized_entitlements_fail() {
        let mut r=Dictionary::new(); r.insert("essential".into(),true.into());
        assert!(constrain(&r,&Dictionary::new(),"TEAM","com.test","TEAM",&BTreeMap::new(),true).is_err());
    }
    #[test] fn references_only_rewrite_known_keys() {
        let mut v=Value::Dictionary(Dictionary::new()); let d=v.as_dictionary_mut().unwrap();
        d.insert("WKCompanionAppBundleIdentifier".into(),"com.old".into()); d.insert("arbitrary".into(),"com.old".into());
        rewrite_refs(&mut v,&BTreeMap::from([("com.old".into(),"com.new".into())]));
        assert_eq!(v.as_dictionary().unwrap()["WKCompanionAppBundleIdentifier"].as_string(),Some("com.new"));
        assert_eq!(v.as_dictionary().unwrap()["arbitrary"].as_string(),Some("com.old"));
    }
}
#[cfg(test)]
mod removal_tests {
    use super::*;
    #[test] fn explicit_removal_scope() {
        let root=Path::new("/test/Main.app");
        let o=Options { remove_extensions:true,..Default::default() };
        assert!(removed(root,&root.join("PlugIns/A.appex/main"),&o));
        assert!(!removed(root,&root.join("Watch/A.app/main"),&o));
        assert!(!removed(root,&root.join("Frameworks/F.framework/main"),&o));
        assert!(!removed(root,Path::new("/other/PlugIns/A.appex"),&o));
    }
}

#[cfg(test)]
mod compatibility_entitlement_tests {
    use super::*;
    fn dict(v: serde_json::Value) -> Dictionary {
        fn convert(v: serde_json::Value) -> Value {
            match v {
                serde_json::Value::Object(d) => { let mut out=Dictionary::new(); for (k,v) in d { out.insert(k,convert(v)); } Value::Dictionary(out) },
                serde_json::Value::Array(a) => Value::Array(a.into_iter().map(convert).collect()),
                serde_json::Value::String(s) => Value::String(s),
                serde_json::Value::Bool(b) => Value::Boolean(b),
                _ => panic!("unsupported fixture"),
            }
        }
        convert(v).into_dictionary().unwrap()
    }
    #[test] fn compatibility_drops_missing_groups_cloud_push_main_and_extension() {
        let request=dict(serde_json::json!({"com.apple.security.application-groups":["group.old"],
            "com.apple.developer.icloud-container-identifiers":["iCloud.old"],"aps-environment":"production"}));
        for id in ["com.lyftaios","com.kdt.livecontainer","com.lyftaios.widget"] {
            let (out,dropped)=constrain(&request,&Dictionary::new(),"NEW",id,"TEAM",&BTreeMap::new(),false).unwrap();
            assert_eq!(dropped.len(),3); assert_eq!(out.len(),2);
            assert_eq!(out["application-identifier"].as_string(),Some(format!("NEW.{id}").as_str()));
            assert!(constrain(&request,&Dictionary::new(),"NEW",id,"TEAM",&BTreeMap::new(),true).is_err());
        }
    }
    #[test] fn partial_arrays_and_dictionary_intersect_without_adding_grants() {
        let request=dict(serde_json::json!({"groups":["group.good","group.bad"],"nested":{"good":true,"bad":true},"flag":true}));
        let allowed=dict(serde_json::json!({"groups":["group.good","group.extra"],"nested":{"good":true,"extra":true},"flag":false,"extra":true}));
        let (out,dropped)=constrain(&request,&allowed,"P","com.test","T",&BTreeMap::new(),false).unwrap();
        assert_eq!(out["groups"].as_array().unwrap().len(),1);
        assert_eq!(out["nested"].as_dictionary().unwrap().len(),1);
        assert!(!out.contains_key("extra")); assert!(!out.contains_key("flag")); assert_eq!(dropped.len(),3);
    }
    #[test] fn keychain_shared_groups_rebase_to_profile_prefix_and_filter() {
        let request=dict(serde_json::json!({"keychain-access-groups":["OLD.com.old","OLD.shared","OLD.denied"]}));
        let allowed=dict(serde_json::json!({"keychain-access-groups":["PREFIX.com.new","PREFIX.shared"]}));
        let map=BTreeMap::from([("com.old".into(),"com.new".into())]);
        let (out,dropped)=constrain(&request,&allowed,"PREFIX","com.new","TEAM",&map,false).unwrap();
        let groups=out["keychain-access-groups"].as_array().unwrap();
        assert_eq!(groups.len(),2); assert_eq!(groups[0].as_string(),Some("PREFIX.com.new"));
        assert_eq!(groups[1].as_string(),Some("PREFIX.shared")); assert_eq!(dropped,vec!["keychain-access-groups"]);
    }
    #[test] fn authorized_values_preserved_and_wildcards_not_expanded() {
        let request=dict(serde_json::json!({"aps-environment":"development","groups":["group.one"]}));
        let allowed=dict(serde_json::json!({"aps-environment":"development","groups":["group.*"],"extra":true}));
        let (out,dropped)=constrain(&request,&allowed,"P","com.test","T",&BTreeMap::new(),true).unwrap();
        assert!(dropped.is_empty()); assert_eq!(out["groups"],request["groups"]); assert!(!out.contains_key("extra"));
        assert!(intersection(&"*".into(),&"specific".into()).is_none());
    }
}

#[cfg(test)]
mod app_group_mapping_tests {
    use super::*;
    fn groups(values: &[&str]) -> Dictionary {
        let mut d=Dictionary::new();
        d.insert(APP_GROUPS.into(), Value::Array(values.iter().map(|s| Value::String((*s).into())).collect()));
        d
    }
    fn values(d: &Dictionary) -> Vec<&str> {
        d.get(APP_GROUPS).and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_string).collect()).unwrap_or_default()
    }
    #[test] fn app_groups_preserve_explicit_and_wildcard_authorized_originals() {
        let r=groups(&["group.original.shared"]);
        for a in [groups(&["group.original.shared"]),groups(&["group.original.*"])] {
            for strict in [true,false] {
                let (out,w)=constrain(&r,&a,"PREFIX","com.gestaltx","TEAM",&BTreeMap::new(),strict).unwrap();
                assert_eq!(values(&out),vec!["group.original.shared"]); assert!(w.is_empty());
            }
        }
    }
    #[test] fn app_groups_substitute_only_requested_capability_and_report_change() {
        let r=groups(&["group.original"]);let a=groups(&["group.zeta","group.available"]);
        let (out,w)=constrain(&r,&a,"PREFIX","com.gestaltx","TEAM",&BTreeMap::new(),false).unwrap();
        assert_eq!(values(&out),vec!["group.available"]); assert_eq!(w,vec![APP_GROUPS]);
        assert_eq!(out["application-identifier"].as_string(),Some("PREFIX.com.gestaltx"));
        let (out,_)=constrain(&Dictionary::new(),&a,"PREFIX","com.gestaltx","TEAM",&BTreeMap::new(),false).unwrap();
        assert!(!out.contains_key(APP_GROUPS));
        assert!(constrain(&r,&a,"PREFIX","com.gestaltx","TEAM",&BTreeMap::new(),true).is_err());
    }
    #[test] fn app_groups_wildcard_substitution_is_concrete_and_authorized() {
        let r=groups(&["group.original.shared"]);let a=groups(&["group.authorized.*"]);
        let (out,_)=constrain(&r,&a,"P","com.gestaltx","T",&BTreeMap::new(),false).unwrap();
        assert_eq!(values(&out),vec!["group.authorized.original.shared"]);
        assert!(group_authorized(values(&out)[0],&a));
    }
    #[test] fn app_groups_parent_extensions_use_one_common_mapping_regardless_of_order() {
        let r=groups(&["group.original"]);
        let main=groups(&["group.main.only","group.shared"]);
        let extension=groups(&["group.extension.only","group.shared"]);
        for pairs in [vec![(&r,&main),(&r,&extension)],vec![(&r,&extension),(&r,&main)]] {
            let plan=app_group_plan(&pairs);
            for (id,a) in [("com.gestaltx",&main),("com.gestaltx.widget",&extension)] {
                let (out,_)=constrain_with_groups(&r,a,"P",id,"T",&BTreeMap::new(),false,&plan).unwrap();
                assert_eq!(values(&out),vec!["group.shared"]);
                assert_eq!(out["application-identifier"].as_string(),Some(format!("P.{id}").as_str()));
            }
        }
    }
    #[test] fn app_groups_missing_or_disjoint_profiles_never_invent_or_split_shared_storage() {
        let r=groups(&["group.original"]);let a=groups(&["group.first"]);
        for other in [Dictionary::new(), groups(&["group.second"])] {
            let plan=app_group_plan(&[(&r,&a),(&r,&other)]);
            for allowed in [&a,&other] {
                let (out,w)=constrain_with_groups(&r,allowed,"P","com.test","T",&BTreeMap::new(),false,&plan).unwrap();
                assert!(!out.contains_key(APP_GROUPS));assert_eq!(w,vec![APP_GROUPS]);
                assert!(constrain_with_groups(&r,allowed,"P","com.test","T",&BTreeMap::new(),true,&plan).is_err());
            }
        }
    }
    #[test] fn app_groups_ignore_malformed_and_wildcard_requested_identifiers() {
        for r in [groups(&["group.*"]),groups(&["group.bad/../path"]),groups(&["not.a.group"])] {
            let a=groups(&["group.authorized"]);
            let (out,_)=constrain(&r,&a,"P","com.test","T",&BTreeMap::new(),false).unwrap();
            assert!(!out.contains_key(APP_GROUPS));
        }
    }
    #[test] fn app_groups_keychain_rebases_shared_prefix_without_bundle_identity_changes() {
        let mut r=groups(&["group.original"]);
        r.insert("keychain-access-groups".into(),vec![Value::String("OLD.shared".into()),Value::String("OLD.com.gestaltx".into())].into());
        let mut a=groups(&["group.authorized"]);
        a.insert("keychain-access-groups".into(),vec![Value::String("PREFIX.*".into())].into());
        for id in ["com.gestaltx","com.gestaltx.widget"] {
            let (out,_)=constrain(&r,&a,"PREFIX",id,"TEAM",&BTreeMap::new(),false).unwrap();
            assert_eq!(values(&out),vec!["group.authorized"]);
            assert_eq!(out["keychain-access-groups"].as_array().unwrap()[0].as_string(),Some("PREFIX.shared"));
            assert_eq!(out["keychain-access-groups"].as_array().unwrap()[1].as_string(),Some("PREFIX.com.gestaltx"));
            assert_eq!(out["com.apple.developer.team-identifier"].as_string(),Some("TEAM"));
            assert_eq!(out["application-identifier"].as_string(),Some(format!("PREFIX.{id}").as_str()));
        }
    }
}
