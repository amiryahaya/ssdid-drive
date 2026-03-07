/*
 * ML-KEM Native Implementation using liboqs
 * NIST FIPS 203 ML-KEM-768 Key Encapsulation Mechanism
 */

#include "mlkem.h"
#include <stdlib.h>
#include <string.h>

#ifdef USE_LIBOQS
#include <oqs/oqs.h>
#endif

/* ============================================================================
 * Static State
 * ============================================================================ */

static int g_initialized = 0;

#ifdef USE_LIBOQS
static OQS_KEM *g_kem = NULL;
#endif

/* ============================================================================
 * Version Information
 * ============================================================================ */

static const char *VERSION = "1.0.0";
static const char *ALGORITHM = "ML-KEM-768";

const char* ml_kem_version(void) {
    return VERSION;
}

const char* ml_kem_algorithm(void) {
    return ALGORITHM;
}

/* ============================================================================
 * Size Functions
 * ============================================================================ */

size_t ml_kem_publickey_bytes(void) {
    return ML_KEM_768_PUBLIC_KEY_BYTES;
}

size_t ml_kem_secretkey_bytes(void) {
    return ML_KEM_768_SECRET_KEY_BYTES;
}

size_t ml_kem_ciphertext_bytes(void) {
    return ML_KEM_768_CIPHERTEXT_BYTES;
}

size_t ml_kem_shared_secret_bytes(void) {
    return ML_KEM_768_SHARED_SECRET_BYTES;
}

/* ============================================================================
 * Initialization and Cleanup
 * ============================================================================ */

int ml_kem_init(void) {
    if (g_initialized) {
        return ML_KEM_SUCCESS;
    }

#ifdef USE_LIBOQS
    /* Initialize liboqs */
    OQS_init();

    /* Check if ML-KEM-768 is supported */
    if (!OQS_KEM_alg_is_enabled(OQS_KEM_alg_ml_kem_768)) {
        return ML_KEM_ERROR_LIBOQS;
    }

    /* Create KEM instance */
    g_kem = OQS_KEM_new(OQS_KEM_alg_ml_kem_768);
    if (g_kem == NULL) {
        return ML_KEM_ERROR_LIBOQS;
    }

    /* Verify sizes match our expectations */
    if (g_kem->length_public_key != ML_KEM_768_PUBLIC_KEY_BYTES ||
        g_kem->length_secret_key != ML_KEM_768_SECRET_KEY_BYTES ||
        g_kem->length_ciphertext != ML_KEM_768_CIPHERTEXT_BYTES ||
        g_kem->length_shared_secret != ML_KEM_768_SHARED_SECRET_BYTES) {
        OQS_KEM_free(g_kem);
        g_kem = NULL;
        return ML_KEM_ERROR_INVALID_SIZE;
    }
#endif

    g_initialized = 1;
    return ML_KEM_SUCCESS;
}

int ml_kem_is_initialized(void) {
    return g_initialized;
}

void ml_kem_cleanup(void) {
    if (!g_initialized) {
        return;
    }

#ifdef USE_LIBOQS
    if (g_kem != NULL) {
        OQS_KEM_free(g_kem);
        g_kem = NULL;
    }
    OQS_destroy();
#endif

    g_initialized = 0;
}

/* ============================================================================
 * Key Generation
 * ============================================================================ */

int ml_kem_keypair(unsigned char *pk, unsigned char *sk) {
    if (!g_initialized) {
        return ML_KEM_ERROR_NOT_INIT;
    }

    if (pk == NULL || sk == NULL) {
        return ML_KEM_ERROR_INVALID_PARAM;
    }

#ifdef USE_LIBOQS
    if (g_kem == NULL) {
        return ML_KEM_ERROR_NOT_INIT;
    }

    OQS_STATUS status = OQS_KEM_keypair(g_kem, pk, sk);
    if (status != OQS_SUCCESS) {
        return ML_KEM_ERROR_CRYPTO;
    }

    return ML_KEM_SUCCESS;
#else
    /* Placeholder: generate deterministic keys for testing */
    /* In production, this should never be reached */
    return ML_KEM_ERROR_LIBOQS;
#endif
}

/* ============================================================================
 * Encapsulation
 * ============================================================================ */

int ml_kem_encapsulate(unsigned char *ct, unsigned char *ss,
                       const unsigned char *pk) {
    if (!g_initialized) {
        return ML_KEM_ERROR_NOT_INIT;
    }

    if (ct == NULL || ss == NULL || pk == NULL) {
        return ML_KEM_ERROR_INVALID_PARAM;
    }

#ifdef USE_LIBOQS
    if (g_kem == NULL) {
        return ML_KEM_ERROR_NOT_INIT;
    }

    OQS_STATUS status = OQS_KEM_encaps(g_kem, ct, ss, pk);
    if (status != OQS_SUCCESS) {
        return ML_KEM_ERROR_CRYPTO;
    }

    return ML_KEM_SUCCESS;
#else
    return ML_KEM_ERROR_LIBOQS;
#endif
}

/* ============================================================================
 * Decapsulation
 * ============================================================================ */

int ml_kem_decapsulate(unsigned char *ss,
                       const unsigned char *ct,
                       const unsigned char *sk) {
    if (!g_initialized) {
        return ML_KEM_ERROR_NOT_INIT;
    }

    if (ss == NULL || ct == NULL || sk == NULL) {
        return ML_KEM_ERROR_INVALID_PARAM;
    }

#ifdef USE_LIBOQS
    if (g_kem == NULL) {
        return ML_KEM_ERROR_NOT_INIT;
    }

    OQS_STATUS status = OQS_KEM_decaps(g_kem, ss, ct, sk);
    if (status != OQS_SUCCESS) {
        return ML_KEM_ERROR_CRYPTO;
    }

    return ML_KEM_SUCCESS;
#else
    return ML_KEM_ERROR_LIBOQS;
#endif
}
