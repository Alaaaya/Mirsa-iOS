#ifndef MIRSA_FAIRPLAY_DECRYPT_H
#define MIRSA_FAIRPLAY_DECRYPT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* FairPlay decryption for App Store IPAs, written from scratch for Mirsa.
 *
 * The technique is the publicly documented one: a FairPlay-encrypted Mach-O
 * carries an LC_ENCRYPTION_INFO(_64) load command describing the encrypted
 * byte range (cryptoff / cryptsize / cryptid). Mapping that range and asking
 * the kernel to run it through FairPlay (mremap_encrypted) decrypts the
 * pages in place; the licence is found by fairplayd at
 * <dir>/SC_Info/<name>.sinf next to the binary, so this only ever works for
 * apps the caller's own Apple ID bought. No key, password or secret is
 * involved anywhere in this code.
 *
 * MIT licensed, like the rest of Mirsa.
 */

/* Result codes returned by mirsa_fp_decrypt_macho(). */
typedef enum MirsaFPResult {
    MirsaFPSuccess = 0,    /* Step completed without error (alias of MirsaFPDecrypted). */
    MirsaFPDecrypted = 0,  /* File was encrypted and is now decrypted. */
    MirsaFPAlreadyClear = 1, /* No LC_ENCRYPTION_INFO, or cryptid already 0: file untouched. */
    MirsaFPNotMachO = -1,    /* Not a Mach-O or FAT Mach-O file. */
    MirsaFPBadMachO = -2,    /* Mach-O headers are malformed or inconsistent. */
    MirsaFPIOError = -3,     /* Could not open, map or write the file. */
    MirsaFPTooLarge = -4,    /* File exceeds the supported size. */
    MirsaFPOutOfMemory = -5, /* Allocation failure. */
    MirsaFPDecryptFailed = -6, /* The kernel refused to decrypt (see errbuf). */
    MirsaFPUnavailable = -7  /* mremap_encrypted is not present on this system. */
} MirsaFPResult;

/* Decrypts the Mach-O file at `path` in place.
 *
 * - Thin and FAT binaries are handled; every slice with cryptid != 0 is
 *   decrypted, other slices are left alone.
 * - The file is only written after every encrypted slice decrypted
 *   successfully in memory, so a failure leaves the file untouched.
 * - The decrypted bytes are written back and cryptid is set to 0, which
 *   also invalidates the file's code signature (the caller re-signs it).
 * - Returns a MirsaFPResult. On MirsaFPDecryptFailed, `errbuf` (when
 *   non-NULL) receives a short human-readable reason.
 */
MirsaFPResult mirsa_fp_decrypt_macho(const char *path, char *errbuf, size_t errbuf_len);

/* Short human-readable message for a result code (never NULL). */
const char *mirsa_fp_result_message(MirsaFPResult result);

#ifdef __cplusplus
}
#endif

#endif /* MIRSA_FAIRPLAY_DECRYPT_H */
