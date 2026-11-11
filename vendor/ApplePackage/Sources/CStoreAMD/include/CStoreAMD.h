#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// All returned handles belong to the caller. Errors never include input material.
void *mirsa_store_begin(const uint8_t *challenge, size_t count, const uint8_t *hardware, uint32_t seconds);
int mirsa_store_request(void *session, uint8_t *output, size_t capacity, size_t *written);
void *mirsa_store_finish(void *session, const uint8_t *ptm, size_t count, const uint8_t *trust);
void mirsa_store_session_free(void *session);
void *mirsa_store_import(const uint8_t *data, size_t count, const uint8_t *hardware);
int mirsa_store_export(void *profile, const uint8_t *hardware, uint8_t *output, size_t capacity, size_t *written);
int mirsa_store_headers(void *profile, uint32_t seconds, char *amd, size_t amd_capacity, char *machine, size_t machine_capacity);
void mirsa_store_profile_free(void *profile);
#ifdef __cplusplus
}
#endif
