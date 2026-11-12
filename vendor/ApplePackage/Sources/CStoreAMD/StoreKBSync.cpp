// MIT upstream kbSync packet generator; original crypto stays in the pinned archive.
#include "CStoreAMD.h"
#include "Upstream/store/kbsync/fresh.hpp"
#include <Security/Security.h>
#include <algorithm>
extern "C" int mirsa_store_kbsync(uint64_t dsid, const uint8_t *hardware, size_t hardware_size,
                                  uint8_t *out, size_t capacity, size_t *written) {
    if (!dsid || !hardware || hardware_size != 6 || !out || capacity < 212 || !written) return 0;
    *written = 0;
    std::array<uint8_t, 1024> entropy{};
    // Cleanup executes for success and exceptions. No account or device material is logged.
    struct Wipe { std::array<uint8_t, 1024>& bytes; ~Wipe() {
        volatile uint8_t *p = bytes.data(); for (size_t i=0;i<bytes.size();++i) p[i]=0;
    }} wipe{entropy};
    try {
        if (SecRandomCopyBytes(kSecRandomDefault, entropy.size(), entropy.data()) != errSecSuccess) return 0;
        auto packet = apple_auth::detail::kbsync::generate_packet(dsid, {hardware, hardware_size}, entropy);
        if (!packet) return 0;
        std::copy(packet->bytes.begin(), packet->bytes.end(), out);
        *written = packet->bytes.size(); return 1;
    } catch (...) { return 0; }
}
