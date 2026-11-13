// Executable offline reference store, not a replacement for the production DB.
// Authenticated principal must come from existing JWT + fix-device-token checks.
import {DatabaseSync} from 'node:sqlite';
export class StagedStore {
 constructor(path=':memory:') {
  this.db=new DatabaseSync(path);
  this.db.exec("PRAGMA foreign_keys=ON; PRAGMA busy_timeout=1000;");
  this.db.exec(`
   CREATE TABLE IF NOT EXISTS sources(
    user_id TEXT NOT NULL,device TEXT NOT NULL,tweak_id TEXT NOT NULL,
    bundle_id TEXT NOT NULL,source_hash TEXT NOT NULL,code TEXT NOT NULL,
    PRIMARY KEY(user_id,device,tweak_id,source_hash));
   CREATE TABLE IF NOT EXISTS uploads(
    id TEXT PRIMARY KEY,user_id TEXT NOT NULL,device TEXT NOT NULL,
    hash TEXT NOT NULL,bytes INTEGER NOT NULL,role TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'pending',expires INTEGER NOT NULL);
   CREATE TABLE IF NOT EXISTS enrollments(
    id TEXT PRIMARY KEY,user_id TEXT NOT NULL,device TEXT NOT NULL,
    tweak_id TEXT NOT NULL,bundle_id TEXT NOT NULL,source_hash TEXT NOT NULL,
    tweak_version TEXT NOT NULL,app_version TEXT NOT NULL,
    token_hash TEXT NOT NULL,expires INTEGER NOT NULL,revoked INTEGER NOT NULL DEFAULT 0,
    report_count INTEGER NOT NULL DEFAULT 0);
   CREATE TABLE IF NOT EXISTS hook_manifests(
 enrollment_id TEXT PRIMARY KEY REFERENCES enrollments(id),manifest_hash TEXT NOT NULL,manifest TEXT NOT NULL);
CREATE TRIGGER IF NOT EXISTS manifest_immutable BEFORE UPDATE ON hook_manifests
 BEGIN SELECT RAISE(ABORT,'immutable_manifest'); END;
CREATE TABLE IF NOT EXISTS events(
    enrollment TEXT NOT NULL REFERENCES enrollments(id),event_id TEXT NOT NULL,
    fingerprint TEXT NOT NULL,signal INTEGER NOT NULL,exception INTEGER NOT NULL,
    created INTEGER NOT NULL,PRIMARY KEY(enrollment,event_id),
    UNIQUE(enrollment,fingerprint));
   CREATE TABLE IF NOT EXISTS jobs(
    id TEXT PRIMARY KEY,kind TEXT NOT NULL,user_id TEXT NOT NULL,device TEXT NOT NULL,
    tweak_id TEXT NOT NULL,bundle_id TEXT NOT NULL,source_hash TEXT NOT NULL,
    payload TEXT NOT NULL,dedup TEXT NOT NULL UNIQUE,status TEXT NOT NULL DEFAULT 'queued',
    created INTEGER NOT NULL);
   CREATE TRIGGER IF NOT EXISTS source_immutable BEFORE UPDATE ON sources BEGIN SELECT RAISE(ABORT,'immutable_source'); END;
   CREATE TRIGGER IF NOT EXISTS upload_identity_immutable BEFORE UPDATE OF id,user_id,device,hash,bytes,role ON uploads BEGIN SELECT RAISE(ABORT,'immutable_upload'); END;
   CREATE TRIGGER IF NOT EXISTS enrollment_identity_immutable BEFORE UPDATE OF id,user_id,device,tweak_id,bundle_id,source_hash,tweak_version,app_version,token_hash ON enrollments BEGIN SELECT RAISE(ABORT,'immutable_enrollment'); END;
   CREATE TRIGGER IF NOT EXISTS job_identity_immutable BEFORE UPDATE OF id,kind,user_id,device,tweak_id,bundle_id,source_hash,payload,dedup ON jobs BEGIN SELECT RAISE(ABORT,'immutable_job'); END;
  `);
 }
 transaction(fn) {
  this.db.exec('BEGIN IMMEDIATE');
  try {const r=fn();this.db.exec('COMMIT');return r;}
  catch(e){this.db.exec('ROLLBACK');throw e;}
 }
 // Trusted migration/worker operation ONLY. Never exposed through request action.
 registerOwnedSource(s) {
  this.db.prepare('INSERT OR IGNORE INTO sources VALUES(?,?,?,?,?,?)')
   .run(s.user,s.device,s.tweakID,s.bundleID,s.sourceSHA256,s.code);
 }
 source(p,b) {
  return this.db.prepare('SELECT * FROM sources WHERE user_id=? AND device=? AND tweak_id=? AND bundle_id=? AND source_hash=?')
   .get(p.user,p.device,b.tweakID,b.bundleID,b.sourceSHA256);
 }
 upload(p,id) {return this.db.prepare('SELECT * FROM uploads WHERE id=? AND user_id=? AND device=?').get(id,p.user,p.device);}
 enrollment(p,id) {return this.db.prepare('SELECT * FROM enrollments WHERE id=? AND user_id=? AND device=?').get(id,p.user,p.device);}
 close(){this.db.close();}
}
