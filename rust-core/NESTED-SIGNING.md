# Personal signing contract

personal_sign retains input/profile/private_key/certificate and adds profiles (ordered extra profile paths), pairing_path and remove_extensions/remove_watch/remove_app_clips (false by default). target_udid is not consumed and cannot override transport identity. pairing_path must be the actual pairing file used by the existing transport. Rust connects via the existing tunnel, reads RSD UniqueDeviceID or Lockdown IdeviceInfo.udid, and drops the tunnel before bundle signing returns. No identifier is returned or explicitly logged here. This is a separate short connection before subsequent installation, not a shared live tunnel.

Success adds profile_verification (verified/unverified), warnings and device_authorization. profile_verification only describes CMS cryptography plus Apple signer-chain role authentication, NOT install readiness. Missing legacy status must never imply verified. Warnings contain code, Arabic message and zero-based profile_index in stable import order (main first, additional paths following). All imported profiles are checked; any unverified profile makes aggregate unverified. Each imported index contributes at most one CMS warning. Import reports device_authorization not_checked, signing checked only after actual live transport identity matches every retained profile. No cached/request identity fallback.

Owner policy explicitly allows CMS signature/unsupported-algorithm/trust failures with a visible unverified warning. Malformed profiles, invalid dates, wrong/missing actual device, wrong selected P12 certificate, bundle scope or essential entitlement failures remain hard errors. Enterprise profiles lacking an explicit ProvisionedDevices membership are rejected under the requested strict inclusion rule. No production-profile compatibility has been established.

RustCrypto cms parses DER and RSA verifies the SID-selected signer, required unique content-type/message-digest attributes and signed attributes DER SET with SHA1/SHA256 only; unsupported algorithms warn at policy layer. Apple trust is solely the direct iOS mirsa_verify_profile_signer_chain ABI. Linux cannot claim Apple trust. Bridge packet is BE u32 length plus DER for each certificate, bounded to 16, 64KiB each and 256KiB aggregate. Synthetic cryptographic positive tests establish signature verification, not Apple trust.

Inventory covers app/appex/framework descendants, derives nested IDs only under the main original prefix, updates documented identifier references and signs deepest first with per-bundle profiles and constrained requested entitlements. Optional removals are explicit and scoped to PlugIns/Watch/AppClips. Encrypted Mach-O is rejected before mutation with Arabic errors. Frameworks carry neither app entitlements nor app profile. Unsupported DER-only entitlements fail rather than discard essential grants. Exact profile matches precede the longest scoped wildcard; stable earliest import resolves equal patterns.

Validation on Linux is cargo test --lib. No device, live UDID, iOS bridge runtime, full signed nested IPA install or production CMS compatibility is established by synthetic tests. Device signing/installation acceptance remains necessary.

Mirsa hook compatibility engine

Injected Substrate, ElleKit, libhooker and substitute dependencies with known
engine basenames are redirected to the source-owned device-only
CydiaSubstrate.framework. Each selected target bundle gets its own framework
and a deterministic bundle identifier derived from its container-relative scope.
An importing image carries its own loader-relative LC_RPATH, so app extensions
and nested framework targets do not depend on a main app's inherited runpaths.
Normal nested signing still signs the engine before its enclosing target.
The bundled BSD license travels with the framework.

This is a limited clean-room compatibility shim, not a universal hook engine.
It replaces Objective-C implementations and rebinds eligible imported pointers.
It cannot patch direct C calls, executable instructions or arbitrary functions;
no inline hooking, JIT bypass, PAC or future-image/chained-fixup hook guarantees
are made. Engine-bound undefined symbols must exist in the bundled engine's
exports; unsupported APIs fail the disposable edit rather than creating a known
dyld launch failure. Dynamic symbol lookup by application code cannot be proven
statically and runtime compatibility is never guaranteed by packaging alone.
Unrelated symbols and system dependencies are not blanket rejected.

Existing foreign engine code is never overwritten. Reimports recognize exact
source-owned code bytes, permitting only an appended signing blob and the
required signature/header/linkedit size changes. Info.plist labels alone do not
prove ownership. Host/simulator binaries cannot serve as the embedded engine.
