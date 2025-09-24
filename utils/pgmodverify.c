/*
 * PhoenixGuard Module Signature Verification Library
 * Part of the edk2-bootkit-defense project
 * 
 * High-performance C library for verifying kernel module signatures
 * against PhoenixGuard certificates using OpenSSL APIs.
 */

#define _GNU_SOURCE  /* For strdup() */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <stdint.h>
#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/pem.h>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/cms.h>
#include <openssl/bio.h>

/* Module signature magic number and structure definitions */
#define MODULE_SIG_STRING "~Module signature appended~\n"
#define MODULE_SIG_STRING_LEN (sizeof(MODULE_SIG_STRING) - 1)

/* Module signature information structure */
struct module_signature {
    uint8_t  algo;        /* Public-key crypto algorithm [0] */
    uint8_t  hash;        /* Digest algorithm [0] */  
    uint8_t  id_type;     /* Key identifier type [1] */
    uint8_t  signer_len;  /* Length of signer's name [0] */
    uint8_t  key_id_len;  /* Length of key identifier [0] */
    uint8_t  __pad[3];
    uint32_t sig_len;     /* Length of signature data */
};

/* Public API structure for verification results */
typedef struct {
    int valid;
    int has_signature;
    char *signer;
    char *algorithm;
    char *hash_algorithm;
    char *error_message;
    long signature_offset;
    size_t signature_size;
    time_t verification_time;
} pg_verify_result_t;

/* Internal certificate cache structure */
typedef struct cert_cache_entry {
    X509 *cert;
    char *fingerprint;
    struct cert_cache_entry *next;
} cert_cache_entry_t;

static cert_cache_entry_t *cert_cache = NULL;
static int openssl_initialized = 0;

/* Initialize OpenSSL and certificate cache */
static int pg_init_openssl(void) {
    if (openssl_initialized) {
        return 1;
    }
    
    /* OpenSSL 3.0+ doesn't need explicit initialization */
#if OPENSSL_VERSION_NUMBER < 0x10100000L
    SSL_library_init();
    SSL_load_error_strings();
    OpenSSL_add_all_algorithms();
#elif OPENSSL_VERSION_NUMBER < 0x30000000L
    /* OpenSSL 1.1.0+ auto-initializes */
    OPENSSL_init_ssl(0, NULL);
    OPENSSL_init_crypto(0, NULL);
#else
    /* OpenSSL 3.0+ - no explicit initialization needed */
#endif
    
    openssl_initialized = 1;
    return 1;
}

/* Load certificate from file into cache */
static int pg_load_certificate(const char *cert_path) {
    FILE *cert_file;
    X509 *cert;
    cert_cache_entry_t *entry;
    
    if (!pg_init_openssl()) {
        return 0;
    }
    
    cert_file = fopen(cert_path, "r");
    if (!cert_file) {
        fprintf(stderr, "Failed to open certificate file: %s\n", cert_path);
        return 0;
    }
    
    cert = PEM_read_X509(cert_file, NULL, NULL, NULL);
    fclose(cert_file);
    
    if (!cert) {
        /* Try DER format */
        cert_file = fopen(cert_path, "rb");
        if (cert_file) {
            cert = d2i_X509_fp(cert_file, NULL);
            fclose(cert_file);
        }
    }
    
    if (!cert) {
        fprintf(stderr, "Failed to parse certificate: %s\n", cert_path);
        ERR_print_errors_fp(stderr);
        return 0;
    }
    
    /* Create cache entry */
    entry = malloc(sizeof(cert_cache_entry_t));
    if (!entry) {
        X509_free(cert);
        return 0;
    }
    
    entry->cert = cert;
    entry->fingerprint = malloc(64);
    entry->next = cert_cache;
    cert_cache = entry;
    
    /* Calculate fingerprint for identification */
    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int md_len;
    if (X509_digest(cert, EVP_sha256(), md, &md_len)) {
        for (unsigned int i = 0; i < md_len; i++) {
            sprintf(entry->fingerprint + (i * 2), "%02x", md[i]);
        }
        entry->fingerprint[md_len * 2] = '\0';
    } else {
        strcpy(entry->fingerprint, "unknown");
    }
    
    return 1;
}

/* Load all certificates from directory */
int pg_load_certificates_from_dir(const char *cert_dir) {
    char cert_path[512];
    int loaded = 0;
    
    /* Common certificate file patterns */
    const char *cert_files[] = {
        "user_secureboot.crt",
        "user_secureboot.pem", 
        "user_secureboot.der",
        "phoenixguard.crt",
        "phoenixguard.pem",
        NULL
    };
    
    for (int i = 0; cert_files[i]; i++) {
        snprintf(cert_path, sizeof(cert_path), "%s/%s", cert_dir, cert_files[i]);
        
        if (access(cert_path, R_OK) == 0) {
            if (pg_load_certificate(cert_path)) {
                printf("Loaded certificate: %s\n", cert_path);
                loaded++;
            }
        }
    }
    
    return loaded;
}

/* Find module signature in file */
static long pg_find_module_signature(FILE *module_file, struct module_signature *sig) {
    char magic_buffer[MODULE_SIG_STRING_LEN];
    long file_size, sig_offset;
    
    /* Get file size */
    fseek(module_file, 0, SEEK_END);
    file_size = ftell(module_file);
    
    if (file_size < MODULE_SIG_STRING_LEN + sizeof(struct module_signature)) {
        return -1;
    }
    
    /* Check for signature magic at end of file */
    fseek(module_file, file_size - MODULE_SIG_STRING_LEN, SEEK_SET);
    if (fread(magic_buffer, 1, MODULE_SIG_STRING_LEN, module_file) != MODULE_SIG_STRING_LEN) {
        return -1;
    }
    
    if (memcmp(magic_buffer, MODULE_SIG_STRING, MODULE_SIG_STRING_LEN) != 0) {
        return -1; /* No signature found */
    }
    
    /* Read signature structure */
    sig_offset = file_size - MODULE_SIG_STRING_LEN - sizeof(struct module_signature);
    fseek(module_file, sig_offset, SEEK_SET);
    
    if (fread(sig, 1, sizeof(struct module_signature), module_file) != sizeof(struct module_signature)) {
        return -1;
    }
    
    /* Validate signature structure */
    if (sig->sig_len == 0 || sig->sig_len > (file_size / 2)) {
        return -1;
    }
    
    return sig_offset - sig->sig_len;
}

/* Extract signature data from module */
static unsigned char *pg_extract_signature(FILE *module_file, 
                                         const struct module_signature *sig,
                                         long sig_data_offset) {
    unsigned char *sig_data;
    
    sig_data = malloc(sig->sig_len);
    if (!sig_data) {
        return NULL;
    }
    
    fseek(module_file, sig_data_offset, SEEK_SET);
    if (fread(sig_data, 1, sig->sig_len, module_file) != sig->sig_len) {
        free(sig_data);
        return NULL;
    }
    
    return sig_data;
}

/* Calculate hash of module content (excluding signature) */
static unsigned char *pg_calculate_module_hash(FILE *module_file, 
                                             long content_end, 
                                             const EVP_MD *hash_algo,
                                             unsigned int *hash_len) {
    EVP_MD_CTX *ctx;
    unsigned char *hash;
    unsigned char buffer[8192];
    size_t bytes_read;
    long bytes_remaining;
    
    ctx = EVP_MD_CTX_new();
    if (!ctx) return NULL;
    
    if (!EVP_DigestInit_ex(ctx, hash_algo, NULL)) {
        EVP_MD_CTX_free(ctx);
        return NULL;
    }
    
    hash = malloc(EVP_MD_size(hash_algo));
    if (!hash) {
        EVP_MD_CTX_free(ctx);
        return NULL;
    }
    
    /* Hash module content up to signature */
    fseek(module_file, 0, SEEK_SET);
    bytes_remaining = content_end;
    
    while (bytes_remaining > 0) {
        size_t to_read = (bytes_remaining > sizeof(buffer)) ? sizeof(buffer) : bytes_remaining;
        bytes_read = fread(buffer, 1, to_read, module_file);
        
        if (bytes_read == 0) break;
        
        if (!EVP_DigestUpdate(ctx, buffer, bytes_read)) {
            free(hash);
            EVP_MD_CTX_free(ctx);
            return NULL;
        }
        
        bytes_remaining -= bytes_read;
    }
    
    if (!EVP_DigestFinal_ex(ctx, hash, hash_len)) {
        free(hash);
        hash = NULL;
    }
    
    EVP_MD_CTX_free(ctx);
    return hash;
}

/* Verify signature against certificate */
static int pg_verify_signature_with_cert(const unsigned char *hash,
                                        unsigned int hash_len,
                                        const unsigned char *signature,
                                        size_t sig_len,
                                        X509 *cert) {
    EVP_PKEY *pkey;
    EVP_PKEY_CTX *pkey_ctx;
    int result = 0;
    
    pkey = X509_get_pubkey(cert);
    if (!pkey) {
        return 0;
    }
    
    pkey_ctx = EVP_PKEY_CTX_new(pkey, NULL);
    if (!pkey_ctx) {
        EVP_PKEY_free(pkey);
        return 0;
    }
    
    if (EVP_PKEY_verify_init(pkey_ctx) <= 0) {
        goto cleanup;
    }
    
    if (EVP_PKEY_verify(pkey_ctx, signature, sig_len, hash, hash_len) == 1) {
        result = 1;
    }
    
cleanup:
    EVP_PKEY_CTX_free(pkey_ctx);
    EVP_PKEY_free(pkey);
    return result;
}

/* Main verification function */
pg_verify_result_t *pg_verify_module_signature(const char *module_path) {
    FILE *module_file;
    struct module_signature sig;
    long sig_data_offset;
    unsigned char *sig_data = NULL;
    unsigned char *module_hash = NULL;
    unsigned int hash_len;
    pg_verify_result_t *result;
    cert_cache_entry_t *cert_entry;
    const EVP_MD *hash_algo;
    int verified = 0;
    
    /* Allocate result structure */
    result = calloc(1, sizeof(pg_verify_result_t));
    if (!result) {
        return NULL;
    }
    
    result->verification_time = time(NULL);
    
    /* Open module file */
    module_file = fopen(module_path, "rb");
    if (!module_file) {
        result->error_message = strdup("Failed to open module file");
        return result;
    }
    
    /* Find signature */
    sig_data_offset = pg_find_module_signature(module_file, &sig);
    if (sig_data_offset < 0) {
        result->has_signature = 0;
        result->error_message = strdup("No signature found in module");
        goto cleanup;
    }
    
    result->has_signature = 1;
    result->signature_offset = sig_data_offset;
    result->signature_size = sig.sig_len;
    
    /* Extract signature data */
    sig_data = pg_extract_signature(module_file, &sig, sig_data_offset);
    if (!sig_data) {
        result->error_message = strdup("Failed to extract signature data");
        goto cleanup;
    }
    
    /* Determine hash algorithm */
    switch (sig.hash) {
        case 0: hash_algo = EVP_sha1(); result->hash_algorithm = strdup("sha1"); break;
        case 1: hash_algo = EVP_sha224(); result->hash_algorithm = strdup("sha224"); break;
        case 2: hash_algo = EVP_sha256(); result->hash_algorithm = strdup("sha256"); break;
        case 3: hash_algo = EVP_sha384(); result->hash_algorithm = strdup("sha384"); break;
        case 4: hash_algo = EVP_sha512(); result->hash_algorithm = strdup("sha512"); break;
        default:
            result->error_message = strdup("Unknown hash algorithm");
            goto cleanup;
    }
    
    /* Calculate module hash */
    module_hash = pg_calculate_module_hash(module_file, sig_data_offset, hash_algo, &hash_len);
    if (!module_hash) {
        result->error_message = strdup("Failed to calculate module hash");
        goto cleanup;
    }
    
    /* Try to verify against each loaded certificate */
    for (cert_entry = cert_cache; cert_entry; cert_entry = cert_entry->next) {
        if (pg_verify_signature_with_cert(module_hash, hash_len, sig_data, sig.sig_len, cert_entry->cert)) {
            result->valid = 1;
            result->signer = strdup(cert_entry->fingerprint);
            result->algorithm = strdup("rsa"); /* Assume RSA for now */
            verified = 1;
            break;
        }
    }
    
    if (!verified) {
        result->error_message = strdup("Signature verification failed against all certificates");
    }
    
cleanup:
    if (module_file) fclose(module_file);
    if (sig_data) free(sig_data);
    if (module_hash) free(module_hash);
    
    return result;
}

/* Free verification result */
void pg_free_verify_result(pg_verify_result_t *result) {
    if (!result) return;
    
    if (result->signer) free(result->signer);
    if (result->algorithm) free(result->algorithm);
    if (result->hash_algorithm) free(result->hash_algorithm);
    if (result->error_message) free(result->error_message);
    free(result);
}

/* Cleanup function */
void pg_cleanup(void) {
    cert_cache_entry_t *entry, *next;
    
    for (entry = cert_cache; entry; entry = next) {
        next = entry->next;
        X509_free(entry->cert);
        free(entry->fingerprint);
        free(entry);
    }
    
    cert_cache = NULL;
    
    if (openssl_initialized) {
#if OPENSSL_VERSION_NUMBER < 0x10100000L
        EVP_cleanup();
        ERR_free_strings();
#elif OPENSSL_VERSION_NUMBER < 0x30000000L
        /* OpenSSL 1.1.0+ auto-cleanup */
#else
        /* OpenSSL 3.0+ - no explicit cleanup needed */
#endif
    }
}

/* Test program */
#ifdef PG_TEST_MAIN
int main(int argc, char **argv) {
    pg_verify_result_t *result;
    
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <cert_dir> <module_path>\n", argv[0]);
        return 1;
    }
    
    printf("Loading certificates from: %s\n", argv[1]);
    int loaded = pg_load_certificates_from_dir(argv[1]);
    printf("Loaded %d certificates\n", loaded);
    
    if (loaded == 0) {
        fprintf(stderr, "No certificates loaded\n");
        return 1;
    }
    
    printf("Verifying module: %s\n", argv[2]);
    result = pg_verify_module_signature(argv[2]);
    
    if (!result) {
        fprintf(stderr, "Verification failed\n");
        return 1;
    }
    
    printf("Has signature: %s\n", result->has_signature ? "Yes" : "No");
    if (result->has_signature) {
        printf("Valid: %s\n", result->valid ? "Yes" : "No");
        printf("Signature offset: %ld\n", result->signature_offset);
        printf("Signature size: %zu\n", result->signature_size);
        if (result->hash_algorithm) printf("Hash algorithm: %s\n", result->hash_algorithm);
        if (result->signer) printf("Signer: %s\n", result->signer);
        if (result->error_message) printf("Error: %s\n", result->error_message);
    }
    
    pg_free_verify_result(result);
    pg_cleanup();
    
    return 0;
}
#endif
