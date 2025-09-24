/*
 * PhoenixGuard Module Signature Verification Library - Header File
 * Part of the edk2-bootkit-defense project
 * 
 * Public API for verifying kernel module signatures against 
 * PhoenixGuard certificates using OpenSSL.
 */

#ifndef PGMODVERIFY_H
#define PGMODVERIFY_H

#include <time.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Public API structure for verification results */
typedef struct {
    int valid;                    /* 1 if signature is valid, 0 otherwise */
    int has_signature;           /* 1 if module has a signature, 0 otherwise */
    char *signer;               /* Fingerprint of signing certificate (malloc'd) */
    char *algorithm;            /* Signature algorithm used (malloc'd) */
    char *hash_algorithm;       /* Hash algorithm used (malloc'd) */
    char *error_message;        /* Error description if verification failed (malloc'd) */
    long signature_offset;      /* Offset of signature data in file */
    size_t signature_size;      /* Size of signature data in bytes */
    time_t verification_time;   /* Timestamp when verification was performed */
} pg_verify_result_t;

/* 
 * Load certificates from a directory
 * Returns number of certificates loaded, 0 on failure
 */
int pg_load_certificates_from_dir(const char *cert_dir);

/*
 * Verify a kernel module's signature against loaded certificates
 * Returns allocated result structure that must be freed with pg_free_verify_result()
 * Returns NULL on critical failure (memory allocation, etc.)
 */
pg_verify_result_t *pg_verify_module_signature(const char *module_path);

/*
 * Free verification result structure
 * Safe to call with NULL pointer
 */
void pg_free_verify_result(pg_verify_result_t *result);

/*
 * Clean up library resources and certificate cache
 * Should be called before program exit
 */
void pg_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif /* PGMODVERIFY_H */
