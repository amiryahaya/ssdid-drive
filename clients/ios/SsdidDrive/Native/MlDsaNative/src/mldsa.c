/*
 * ML-DSA Native Implementation using liboqs
 * NIST FIPS 204 ML-DSA-65 Digital Signature Algorithm
 */

#include "mldsa.h"
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
static OQS_SIG *g_sig = NULL;
#endif

/* ============================================================================
 * Version Information
 * ============================================================================ */

static const char *VERSION = "1.0.0";
static const char *ALGORITHM = "ML-DSA-65";

const char* ml_dsa_version(void) {
    return VERSION;
}

const char* ml_dsa_algorithm(void) {
    return ALGORITHM;
}

/* ============================================================================
 * Size Functions
 * ============================================================================ */

size_t ml_dsa_publickey_bytes(void) {
    return ML_DSA_65_PUBLIC_KEY_BYTES;
}

size_t ml_dsa_secretkey_bytes(void) {
    return ML_DSA_65_SECRET_KEY_BYTES;
}

size_t ml_dsa_signature_bytes(void) {
    return ML_DSA_65_SIGNATURE_BYTES;
}

/* ============================================================================
 * Initialization and Cleanup
 * ============================================================================ */

int ml_dsa_init(void) {
    if (g_initialized) {
        return ML_DSA_SUCCESS;
    }

#ifdef USE_LIBOQS
    /* Initialize liboqs */
    OQS_init();

    /* Check if ML-DSA-65 is supported */
    if (!OQS_SIG_alg_is_enabled(OQS_SIG_alg_ml_dsa_65)) {
        return ML_DSA_ERROR_LIBOQS;
    }

    /* Create signature instance */
    g_sig = OQS_SIG_new(OQS_SIG_alg_ml_dsa_65);
    if (g_sig == NULL) {
        return ML_DSA_ERROR_LIBOQS;
    }

    /* Verify sizes match our expectations */
    if (g_sig->length_public_key != ML_DSA_65_PUBLIC_KEY_BYTES ||
        g_sig->length_secret_key != ML_DSA_65_SECRET_KEY_BYTES ||
        g_sig->length_signature != ML_DSA_65_SIGNATURE_BYTES) {
        OQS_SIG_free(g_sig);
        g_sig = NULL;
        return ML_DSA_ERROR_INVALID_SIZE;
    }
#endif

    g_initialized = 1;
    return ML_DSA_SUCCESS;
}

int ml_dsa_is_initialized(void) {
    return g_initialized;
}

void ml_dsa_cleanup(void) {
    if (!g_initialized) {
        return;
    }

#ifdef USE_LIBOQS
    if (g_sig != NULL) {
        OQS_SIG_free(g_sig);
        g_sig = NULL;
    }
    OQS_destroy();
#endif

    g_initialized = 0;
}

/* ============================================================================
 * Key Generation
 * ============================================================================ */

int ml_dsa_keypair(unsigned char *pk, unsigned char *sk) {
    if (!g_initialized) {
        return ML_DSA_ERROR_NOT_INIT;
    }

    if (pk == NULL || sk == NULL) {
        return ML_DSA_ERROR_INVALID_PARAM;
    }

#ifdef USE_LIBOQS
    if (g_sig == NULL) {
        return ML_DSA_ERROR_NOT_INIT;
    }

    OQS_STATUS status = OQS_SIG_keypair(g_sig, pk, sk);
    if (status != OQS_SUCCESS) {
        return ML_DSA_ERROR_CRYPTO;
    }

    return ML_DSA_SUCCESS;
#else
    return ML_DSA_ERROR_LIBOQS;
#endif
}

/* ============================================================================
 * Signing
 * ============================================================================ */

int ml_dsa_sign(unsigned char *sig, size_t *siglen,
                const unsigned char *msg, size_t msglen,
                const unsigned char *sk) {
    if (!g_initialized) {
        return ML_DSA_ERROR_NOT_INIT;
    }

    if (sig == NULL || siglen == NULL || msg == NULL || sk == NULL) {
        return ML_DSA_ERROR_INVALID_PARAM;
    }

#ifdef USE_LIBOQS
    if (g_sig == NULL) {
        return ML_DSA_ERROR_NOT_INIT;
    }

    OQS_STATUS status = OQS_SIG_sign(g_sig, sig, siglen, msg, msglen, sk);
    if (status != OQS_SUCCESS) {
        return ML_DSA_ERROR_CRYPTO;
    }

    return ML_DSA_SUCCESS;
#else
    return ML_DSA_ERROR_LIBOQS;
#endif
}

/* ============================================================================
 * Verification
 * ============================================================================ */

int ml_dsa_verify(const unsigned char *msg, size_t msglen,
                  const unsigned char *sig, size_t siglen,
                  const unsigned char *pk) {
    if (!g_initialized) {
        return ML_DSA_ERROR_NOT_INIT;
    }

    if (msg == NULL || sig == NULL || pk == NULL) {
        return ML_DSA_ERROR_INVALID_PARAM;
    }

#ifdef USE_LIBOQS
    if (g_sig == NULL) {
        return ML_DSA_ERROR_NOT_INIT;
    }

    OQS_STATUS status = OQS_SIG_verify(g_sig, msg, msglen, sig, siglen, pk);
    if (status != OQS_SUCCESS) {
        return ML_DSA_ERROR_VERIFY_FAILED;
    }

    return ML_DSA_SUCCESS;
#else
    return ML_DSA_ERROR_LIBOQS;
#endif
}
