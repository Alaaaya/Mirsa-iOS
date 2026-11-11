// Mirsa adapter for apple-auth (MIT). No GPL implementation is used.
#include "CStoreAMD.h"
#include <apple_auth/core.hpp>
#include <algorithm>
#include <cstring>
using namespace apple_auth;
namespace {
HardwareId hardware_id(const uint8_t *bytes) {
    if (!bytes) throw std::invalid_argument("hardware");
    HardwareId result{}; std::copy_n(bytes, result.size(), result.begin()); return result;
}
int copy_bytes(ByteView bytes, uint8_t *out, size_t capacity, size_t *written) {
    if (!written) return 0;
    *written = bytes.size();
    if (!out || capacity < bytes.size()) return 0;
    std::copy(bytes.begin(), bytes.end(), out); return 1;
}
}
extern "C" {
void *mirsa_store_begin(const uint8_t *challenge, size_t count, const uint8_t *hardware, uint32_t seconds) {
    try {
        if (!challenge || count == 0 || count > 12288) return nullptr;
        return new ProvisioningSession(ByteView(challenge,count), hardware_id(hardware), seconds,
                                       ProfileKind::store);
    } catch (...) { return nullptr; }
}
int mirsa_store_request(void *session, uint8_t *out, size_t capacity, size_t *written) {
    try { return session ? copy_bytes(static_cast<ProvisioningSession*>(session)->request(),out,capacity,written) : 0; }
    catch (...) { return 0; }
}
void *mirsa_store_finish(void *session, const uint8_t *ptm, size_t count, const uint8_t *trust) {
    try {
        if (!session || !ptm || !trust || count == 0 || count > 65536) return nullptr;
        Block key{}; std::copy_n(trust,key.size(),key.begin());
        return new Profile(static_cast<ProvisioningSession*>(session)->finish(ByteView(ptm,count),key));
    } catch (...) { return nullptr; }
}
void mirsa_store_session_free(void *session) { delete static_cast<ProvisioningSession*>(session); }
void *mirsa_store_import(const uint8_t *data, size_t count, const uint8_t *hardware) {
    try {
        if (!data || count == 0 || count > 65536) return nullptr;
        auto profile = Profile::import_file(ByteView(data,count),hardware_id(hardware),"adi.pb");
        if (profile.kind() != ProfileKind::store) return nullptr;
        return new Profile(std::move(profile));
    } catch (...) { return nullptr; }
}
int mirsa_store_export(void *profile, const uint8_t *hardware, uint8_t *out, size_t capacity, size_t *written) {
    try {
        if (!profile) return 0;
        auto bytes = static_cast<Profile*>(profile)->export_file(hardware_id(hardware),"adi.pb");
        return copy_bytes(bytes,out,capacity,written);
    } catch (...) { return 0; }
}
int mirsa_store_headers(void *profile, uint32_t seconds, char *amd, size_t ac, char *machine, size_t mc) {
    try {
        if (!profile || !amd || !machine) return 0;
        auto *p = static_cast<Profile*>(profile);
        if (p->kind() != ProfileKind::store) return 0;
        auto a = p->otp_header(time_counter(seconds)); auto m = p->machine_id_header();
        if (a.size()+1 > ac || m.size()+1 > mc) return 0;
        std::memcpy(amd,a.c_str(),a.size()+1); std::memcpy(machine,m.c_str(),m.size()+1); return 1;
    } catch (...) { return 0; }
}
void mirsa_store_profile_free(void *profile) { delete static_cast<Profile*>(profile); }
}
