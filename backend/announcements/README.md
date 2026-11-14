# Mirsa announcements

This independent Flask service stores developer announcements. It does not generate tweaks, enroll devices, change account authentication, or send push notifications. iOS clients fetch announcements and schedule local notifications. Background refresh is controlled by iOS.

Run `python -m unittest -v` in this directory after installing the exact requirements into an isolated virtual environment. Tests use an isolated temporary SQLite database and mocked identity authority, never production data or real recipients. The identity verifier itself is tested for signed-account/device-token binding and upstream failures. Physical-device delivery is not established by these tests.

## Private runtime configuration

Set MIRSA_BROADCAST_CONFIG to a private, readable JSON file outside the repository. Required fields are sessionKey, passwordHash, database and owner. Generate sessionKey cryptographically. passwordHash is Werkzeug's salted scrypt output; never store the plaintext password on the server. The owner object contains uid, device, tokenHash and authPublishableKey copied read-only from the existing verified owner binding and its existing identity configuration. authPublishableKey is a public Supabase project identifier, not a replacement for signed user authentication. The database is a separate file, not the Store or Forge database.

Store the generated plaintext password only in the owner's DEFAULT sandbox chmod-600 /home/kit/.mirsa_broadcast_admin_password. Never put it in command arguments, URLs, logs, source, responses, scripts or client code. No production fixture credentials.

Run Gunicorn with the factory `app:create_app()`, a dedicated unprivileged service account, two workers, loopback binding, a private umask and no access/request logging. Select an unused loopback port at deployment. Deny external binding. Use systemd filesystem restrictions permitting writes only to the separate announcement data directory.

Caddy owns public HTTPS. Proxy only /admin, /admin/* and /announcements/v1/messages to that loopback port. Overwrite X-Mirsa-Broadcast-Proxy with 1 and X-Mirsa-Broadcast-IP with the actual remote host. Preserve the public Host and scheme. Do not change other routes. Secure HttpOnly SameSite=Strict signed session cookies and Flask-WTF CSRF protect admin writes. POST also checks the exact public Origin. Password attempts and writes have transactional per-IP and global limits.

The composer defaults to owner-only. Real tests MUST target the verified owner, never all users and never just a language. Public read requests exclude all owner-only messages. Owner reads require both the existing signed Supabase account and its matching bound opaque device token. No service-role impersonation, minted session, or database auth changes are permitted.

## Deployment gate and rollback

Do not deploy before all five app workflows succeed on the same final commit, actual required test execution and launch smoke are inspected, and the unsigned IPA is validated. Test server code locally first. Before writing production, preserve the full existing Caddyfile, service unit/config/code if present, and a consistent SQLite backup if the separate database already exists. Record existence as well as contents. Save the exact installed source commit and SHA manifests privately.

Prepare and syntax-check a rollback script before switching routes. It must stop the new service, restore previous code/config/unit and the consistent database snapshot if present, restore the exact Caddyfile, daemon-reload, validate and reload Caddy, and restore the former service active/enabled state. If this is the first deployment, disable the new service and remove its public routes by restoring Caddy; do not delete unrelated files or any preexisting data. Keep deployment backup and rollback evidence.

After staging dependencies/config without exposing secrets, validate the systemd unit and Caddy configuration. Start the isolated service, check loopback read-only behavior, then switch only the approved routes. Verify public HTTPS wrong-password rejection, unauthenticated-write denial, correct admin login, owner-only send persistence and authorized owner fetch. Confirm anonymous and wrong-identity reads cannot see the owner message. A genuine current owner app session is necessary for that live acceptance test. If unavailable, report the blocker rather than minting credentials, broadcasting publicly, or claiming physical notification delivery.

A failed deployment requires restoring the backup and recording the actual failure. Do not publish either 2.5 feed until server acceptance succeeds. Retain GPL notices and ship this exact source, requirements, templates and tests with the full corresponding source for the release.
