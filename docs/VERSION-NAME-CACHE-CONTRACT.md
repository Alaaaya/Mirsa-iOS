# Shared version-name cache (STAGING CONTRACT ONLY, not deployed)

Public data only: appId (Int64 as string), externalVersionId (string), versionName (string, <=64 chars). No user, device, account or token data is uploaded or stored.

Client behaviour: local disk cache first (StoreVersionNameCache). On opening a version list, ONE bulk fetch for the whole list. After the client resolves a name from Apple, it uploads only the triple.

POST /store/v1/version-names/lookup  body {"appId":"123","externalVersionIds":["1","2"]}  (max 500 ids)
 -> 200 {"version":1,"names":{"1":"4.2.0"},"missing":["2"]}
POST /store/v1/version-names/contribute  body {"version":1,"appId":"123","names":{"2":"4.1.0"}} (max 100)
 -> 204
Auth: the same existing Mirsa bearer + device headers as other /store/v1 routes (no new identity). Server validates name charset, length, rejects conflicting overwrites (first verified write wins). Table: version_names(app_id, external_version_id, name, created_at) unique(app_id, external_version_id).
Client: fail closed (any error ignored, local cache path unchanged); disabled behind a flag until the server is deployed with owner approval. No endpoint is called until then.
