/* FairPlay decryption core, written from scratch for Mirsa (MIT).
 *
 * Mechanism (publicly documented): an App Store Mach-O marks its encrypted
 * __TEXT range with an LC_ENCRYPTION_INFO(_64) load command. Mapping the
 * file read-write and shared and passing the page-aligned range to the
 * kernel entry point mremap_encrypted() runs the pages through FairPlay;
 * fairplayd finds the per-account licence at <dir>/SC_Info/<name>.sinf
 * next to the binary and returns the key, so decryption only works for
 * apps the device's own Apple ID bought. The decrypted bytes are then
 * written back and cryptid is zeroed. Nothing here contains, derives or
 * transmits any key.
 *
 * The mapping is PROT_READ | PROT_WRITE / MAP_SHARED so the kernel
 * decrypts the pages in place and the changes propagate to the file.
 * Decryption runs on a throwaway copy in the app's temp dir, never on
 * the original encrypted IPA, so in-place decryption through the shared
 * mapping is safe. The pwrite loop afterwards re-writes the same bytes
 * and zeroes cryptid.
 *
 * When the kernel refuses with ENOMEM (errno 12, "Cannot allocate
 * memory"), its FairPlay decrypter could not validate the file: either
 * the licence is missing/wrong, or the kernel does not know this copy's
 * code signature. A fresh copy extracted from an IPA has never been
 * loaded, so the kernel has never seen its signature; registering it
 * first with fcntl(F_ADDFILESIGS_RETURN) using the LC_CODE_SIGNATURE
 * blob lets the decrypter validate the binary, and the same decrypt
 * call then succeeds. That registration is retried automatically when
 * the first attempt is refused.
 *
 * The cryptid value passed to the kernel only selects the kernel code path;
 * the FairPlay key lookup is by SINF path, not by cryptid. Passing 2
 * (the Core ML model encryption path) skips the kernel's requirement that
 * the mapping be executable, so a plain read-write mapping is enough and no
 * special entitlement is needed. If that is refused, the binary's stored
 * cryptid is retried once.
 *
 * The approach (signature registration before retrying the kernel call)
 * was learned by studying the open-source iPadn implementation; the code
 * here is Mirsa's own, written independently.
 */

#include "FairPlayDecrypt.h"

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

/* Mach-O constants (from <mach-o/loader.h>, public SDK header). */
#define FP_FAT_MAGIC 0xCAFEBABEu
#define FP_FAT_MAGIC_64 0xCAFEBABFu
#define FP_MH_MAGIC_64 0xFEEDFACFu
#define FP_MH_MAGIC 0xFEEDFACEu
#define FP_LC_ENCRYPTION_INFO 0x21u
#define FP_LC_ENCRYPTION_INFO_64 0x2Cu
#define FP_LC_CODE_SIGNATURE 0x1Du
#define FP_CPU_TYPE_ARM64 0x0100000Cu

/* Bounds matching the app's own IPA limits. */
#define FP_MAX_FILE_SIZE (1536u * 1024u * 1024u) /* 1.5 GiB */
#define FP_MAX_SLICES 16
#define FP_MAX_NCMDS 4096

/* Kernel code-path selector that skips the PROT_EXEC requirement
   (Core ML model encryption path). */
#define FP_CRYPTID_NOEXEC 2u

/* mremap_encrypted is a private entry point (xnu bsd/sys/mman.h, PRIVATE
   section): int mremap_encrypted(void *, size_t, uint32_t, uint32_t,
   uint32_t). It is resolved at runtime so a system without it fails
   cleanly instead of failing to link. */
typedef int (*fp_remap_fn)(void *, size_t, uint32_t, uint32_t, uint32_t);

static fp_remap_fn fp_resolve_remap(void) {
    static fp_remap_fn cached = NULL;
    static int looked_up = 0;
    if (!looked_up) {
        looked_up = 1;
        cached = (fp_remap_fn)dlsym(RTLD_DEFAULT, "mremap_encrypted");
    }
    return cached;
}

static void fp_note(char *buf, size_t len, const char *fmt, ...) {
    if (buf == NULL || len == 0) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, len, fmt, ap);
    va_end(ap);
}

static uint32_t fp_read32le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint32_t fp_read32be(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static uint64_t fp_align_down(uint64_t v, uint64_t align) {
    return v & ~(align - 1);
}

static uint64_t fp_align_up(uint64_t v, uint64_t align) {
    return (v + align - 1) & ~(align - 1);
}

/* One encrypted byte range inside one Mach-O slice. Offsets are absolute
   file offsets, except cs_off which is relative to the slice start
   (the form the kernel's file-signature registration wants). */
typedef struct fp_range {
    uint64_t crypt_off;   /* Absolute file offset of the encrypted bytes. */
    uint32_t crypt_size;
    uint32_t cryptid;     /* Stored cryptid value from the load command. */
    uint64_t cryptid_off; /* Absolute file offset of the cryptid field. */
    uint32_t cputype;
    uint32_t cpusubtype;
    uint64_t slice_off;   /* File offset where this slice starts (0 = thin). */
    uint32_t cs_off;      /* Code-signature blob offset, relative to slice. */
    uint32_t cs_size;     /* Code-signature blob size (0 = none found). */
} fp_range;

const char *mirsa_fp_result_message(MirsaFPResult result) {
    switch (result) {
        case MirsaFPDecrypted: return "Decrypted.";
        case MirsaFPAlreadyClear: return "Not encrypted.";
        case MirsaFPNotMachO: return "Not a Mach-O file.";
        case MirsaFPBadMachO: return "Malformed Mach-O headers.";
        case MirsaFPIOError: return "Could not read or write the file.";
        case MirsaFPTooLarge: return "File is too large.";
        case MirsaFPOutOfMemory: return "Out of memory.";
        case MirsaFPDecryptFailed: return "The system refused to decrypt this file.";
        case MirsaFPUnavailable: return "Decryption is not available on this system.";
        default: return "Unknown error.";
    }
}

/* Parses one thin slice starting at `base` (slice file offset `slice_off`)
   and records its encrypted range, if any, in `out`. Returns 0 on success,
   a negative MirsaFPResult on failure. */
static MirsaFPResult fp_parse_slice(const uint8_t *base, uint64_t slice_off, uint64_t slice_size,
                                    uint64_t file_size, fp_range *out, int *found) {
    *found = 0;
    if (slice_off + slice_size > file_size) {
        return MirsaFPBadMachO;
    }
    if (slice_size < 4) {
        return MirsaFPNotMachO;
    }
    const uint8_t *h = base + slice_off;
    uint32_t magic = fp_read32le(h);
    int is64;
    uint32_t header_size;
    if (magic == FP_MH_MAGIC_64) {
        is64 = 1;
        header_size = 32;
    } else if (magic == FP_MH_MAGIC) {
        is64 = 0;
        header_size = 28;
    } else {
        return MirsaFPNotMachO;
    }
    if (slice_size < header_size) {
        return MirsaFPBadMachO;
    }
    uint32_t cputype = fp_read32le(h + 4);
    uint32_t cpusubtype = fp_read32le(h + 8);
    uint32_t ncmds = fp_read32le(h + 16);
    uint32_t sizeofcmds = fp_read32le(h + 20);
    if (ncmds > FP_MAX_NCMDS || (uint64_t)header_size + sizeofcmds > slice_size) {
        return MirsaFPBadMachO;
    }
    (void)is64;
    /* The code signature is only used for the file-signature retry below,
       so a missing or malformed one is ignored, not a failure. */
    out->slice_off = slice_off;
    out->cs_off = 0;
    out->cs_size = 0;
    uint32_t off = header_size;
    int seen = 0;
    for (uint32_t i = 0; i < ncmds; i++) {
        if (off + 8 > header_size + sizeofcmds) {
            return MirsaFPBadMachO;
        }
        const uint8_t *cmd = h + off;
        uint32_t type = fp_read32le(cmd);
        uint32_t cmdsize = fp_read32le(cmd + 4);
        if (cmdsize < 8 || off + cmdsize > header_size + sizeofcmds) {
            return MirsaFPBadMachO;
        }
        if (type == FP_LC_CODE_SIGNATURE) {
            if (cmdsize >= 16) {
                out->cs_off = fp_read32le(cmd + 8);
                out->cs_size = fp_read32le(cmd + 12);
            }
        } else if (type == FP_LC_ENCRYPTION_INFO || type == FP_LC_ENCRYPTION_INFO_64) {
            if (cmdsize < 20) {
                return MirsaFPBadMachO;
            }
            if (seen) {
                /* Binaries carry a single encryption command. */
                return MirsaFPBadMachO;
            }
            seen = 1;
            uint32_t cryptoff = fp_read32le(cmd + 8);
            uint32_t cryptsize = fp_read32le(cmd + 12);
            uint32_t cryptid = fp_read32le(cmd + 16);
            if (cryptid != 0) {
                if (cryptoff == 0 || cryptsize == 0 ||
                    (uint64_t)slice_off + cryptoff + cryptsize > file_size) {
                    return MirsaFPBadMachO;
                }
                out->crypt_off = slice_off + cryptoff;
                out->crypt_size = cryptsize;
                out->cryptid = cryptid;
                out->cryptid_off = slice_off + off + 16;
                out->cputype = cputype;
                out->cpusubtype = cpusubtype;
                *found = 1;
            }
        }
        off += cmdsize;
    }
    return MirsaFPSuccess;
}

/* Registers one slice's code signature with the kernel so the FairPlay
   decrypter can validate the binary. The kernel only knows the signature
   of files it has loaded before; a fresh copy extracted from an IPA has
   never been loaded, so without this the decrypter refuses the file
   (errno 12) even though the licence next to it is valid. Returns 0 on
   success, -1 when there is no signature to register or the kernel
   would not take it. */
static int fp_register_signature(int fd, const fp_range *r) {
#if defined(F_ADDFILESIGS_RETURN)
    if (r->cs_size == 0) {
        return -1;
    }
    fsignatures_t fs;
    fs.fs_file_start = (off_t)r->slice_off;
    fs.fs_blob_start = (void *)(uintptr_t)r->cs_off;
    fs.fs_blob_size = (size_t)r->cs_size;
    return fcntl(fd, F_ADDFILESIGS_RETURN, &fs);
#else
    (void)fd;
    (void)r;
    return -1;
#endif
}

MirsaFPResult mirsa_fp_decrypt_macho(const char *path, char *errbuf, size_t errbuf_len) {
    if (path == NULL || path[0] == '\0') {
        return MirsaFPIOError;
    }

    int fd = open(path, O_RDWR);
    if (fd < 0) {
        fp_note(errbuf, errbuf_len, "Cannot open file: %s.", strerror(errno));
        return MirsaFPIOError;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size <= 0 || (uint64_t)st.st_size > FP_MAX_FILE_SIZE) {
        close(fd);
        fp_note(errbuf, errbuf_len, "File is missing or too large.");
        return st.st_size > 0 ? MirsaFPTooLarge : MirsaFPIOError;
    }
    uint64_t file_size = (uint64_t)st.st_size;

    uint8_t *map = mmap(NULL, (size_t)file_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        close(fd);
        fp_note(errbuf, errbuf_len, "Cannot map file: %s.", strerror(errno));
        return MirsaFPIOError;
    }

    /* Collect the encrypted ranges: FAT header first, thin otherwise. */
    fp_range ranges[FP_MAX_SLICES];
    int range_count = 0;
    MirsaFPResult result = MirsaFPSuccess;
    if (file_size < 4) {
        munmap(map, (size_t)file_size);
        close(fd);
        return MirsaFPNotMachO;
    }
    uint32_t magic_be = fp_read32be(map);
    if (magic_be == FP_FAT_MAGIC || magic_be == FP_FAT_MAGIC_64) {
        if (file_size < 8) {
            result = MirsaFPBadMachO;
        } else {
            uint32_t narch = fp_read32be(map + 4);
            if (narch == 0 || narch > FP_MAX_SLICES || 8 + (uint64_t)narch * 20 > file_size) {
                result = MirsaFPBadMachO;
            } else {
                for (uint32_t i = 0; i < narch && result == MirsaFPSuccess; i++) {
                    const uint8_t *arch = map + 8 + (size_t)i * 20;
                    uint64_t off = fp_read32be(arch + 8);
                    uint64_t size = fp_read32be(arch + 12);
                    if (off + size > file_size || size < 28) {
                        result = MirsaFPBadMachO;
                        break;
                    }
                    int found = 0;
                    result = fp_parse_slice(map, off, size, file_size, &ranges[range_count], &found);
                    if (result == MirsaFPSuccess && found) {
                        range_count++;
                    } else if (result == MirsaFPNotMachO) {
                        result = MirsaFPBadMachO;
                    }
                }
            }
        }
    } else {
        int found = 0;
        result = fp_parse_slice(map, 0, file_size, file_size, &ranges[0], &found);
        if (result == MirsaFPSuccess && found) {
            range_count = 1;
        }
    }
    if (result != MirsaFPSuccess) {
        munmap(map, (size_t)file_size);
        close(fd);
        fp_note(errbuf, errbuf_len, "%s", mirsa_fp_result_message(result));
        return result;
    }
    if (range_count == 0) {
        munmap(map, (size_t)file_size);
        close(fd);
        return MirsaFPAlreadyClear;
    }

    /* The kernel entry point is only needed when something is actually
       encrypted, so clear files and parse errors are reported the same way
       on every system (including the simulator, which has no FairPlay). */
    fp_remap_fn remap = fp_resolve_remap();
    if (remap == NULL) {
        munmap(map, (size_t)file_size);
        close(fd);
        fp_note(errbuf, errbuf_len, "mremap_encrypted is not available on this system.");
        return MirsaFPUnavailable;
    }

    /* Decrypt every range in the shared mapping. The kernel writes the
       decrypted pages through to the file as it goes; the pwrite loop
       below re-writes the same bytes and zeroes cryptid. */
    long page = getpagesize();
    if (page <= 0) {
        page = 16384;
    }
    uint64_t pagesize = (uint64_t)page;
    for (int i = 0; i < range_count; i++) {
        fp_range *r = &ranges[i];
        uint64_t start = fp_align_down(r->crypt_off, pagesize);
        uint64_t end = fp_align_up(r->crypt_off + r->crypt_size, pagesize);
        if (end > file_size || end <= start) {
            munmap(map, (size_t)file_size);
            close(fd);
            fp_note(errbuf, errbuf_len, "Encrypted range is outside the file.");
            return MirsaFPBadMachO;
        }
        int rc = remap(map + start, (size_t)(end - start), FP_CRYPTID_NOEXEC, r->cputype, r->cpusubtype);
        if (rc != 0) {
            /* The kernel may not know this copy's code signature yet.
               Register it, then retry with the same cryptid. */
            if (fp_register_signature(fd, r) == 0) {
                rc = remap(map + start, (size_t)(end - start), FP_CRYPTID_NOEXEC, r->cputype, r->cpusubtype);
            }
        }
        if (rc != 0 && r->cryptid != FP_CRYPTID_NOEXEC) {
            /* Retry once with the binary's own stored cryptid
               (the signature is already registered by now, if any). */
            rc = remap(map + start, (size_t)(end - start), r->cryptid, r->cputype, r->cpusubtype);
        }
        if (rc != 0) {
            int e = errno;
            munmap(map, (size_t)file_size);
            close(fd);
            fp_note(errbuf, errbuf_len, "Kernel refused to decrypt (errno %d: %s). "
                    "The app licence (SC_Info/*.sinf) may be missing or belong to another account.",
                    e, strerror(e));
            return MirsaFPDecryptFailed;
        }
    }

    /* All ranges decrypted in memory: write the bytes back and zero cryptid. */
    for (int i = 0; i < range_count; i++) {
        fp_range *r = &ranges[i];
        size_t remaining = r->crypt_size;
        const uint8_t *src = map + r->crypt_off;
        uint64_t pos = r->crypt_off;
        while (remaining > 0) {
            ssize_t w = pwrite(fd, src, remaining, (off_t)pos);
            if (w <= 0) {
                munmap(map, (size_t)file_size);
                close(fd);
                fp_note(errbuf, errbuf_len, "Cannot write decrypted bytes: %s.", strerror(errno));
                return MirsaFPIOError;
            }
            src += (size_t)w;
            pos += (uint64_t)w;
            remaining -= (size_t)w;
        }
        uint32_t zero = 0;
        if (pwrite(fd, &zero, sizeof(zero), (off_t)r->cryptid_off) != (ssize_t)sizeof(zero)) {
            munmap(map, (size_t)file_size);
            close(fd);
            fp_note(errbuf, errbuf_len, "Cannot clear cryptid: %s.", strerror(errno));
            return MirsaFPIOError;
        }
    }
    (void)fsync(fd);
    munmap(map, (size_t)file_size);
    close(fd);
    return MirsaFPDecrypted;
}
