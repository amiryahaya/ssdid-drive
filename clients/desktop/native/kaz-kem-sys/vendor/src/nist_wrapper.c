/*
 * NIST API Wrapper for KAZ-KEM
 * Version 2.1.0
 *
 * Provides NIST-compliant API that wraps the internal KAZ-KEM implementation.
 * Supports both compile-time and runtime security level selection.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "kaz/nist_api.h"
#include "kaz/kem.h"

/* Algorithm name storage for runtime level */
static char g_algname[32] = "KAZ-KEM";

/**
 * Initialize KEM with a specific security level (runtime API).
 */
int crypto_kem_init(int security_level)
{
    int ret = kaz_kem_init(security_level);
    if (ret == KAZ_KEM_SUCCESS) {
        snprintf(g_algname, sizeof(g_algname), "KAZ-KEM-%d", security_level);
    }
    return ret;
}

/**
 * Get algorithm name for current security level.
 */
const char* crypto_kem_algname(void)
{
    if (kaz_kem_is_initialized()) {
        return g_algname;
    }
#ifdef KAZ_SECURITY_LEVEL
    return CRYPTO_ALGNAME;
#else
    return "KAZ-KEM";
#endif
}

/**
 * Generate a keypair.
 *
 * For compile-time API: Auto-initializes with KAZ_SECURITY_LEVEL
 * For runtime API: Must call crypto_kem_init() first
 */
int crypto_kem_keypair(unsigned char *pk, unsigned char *sk)
{
#ifdef KAZ_SECURITY_LEVEL
    /* Compile-time API: use legacy functions */
    int status = KAZ_KEM_KEYGEN(pk, sk);
    if (status == 0) return 0;
    else return -4;
#else
    /* Runtime API: must be initialized */
    if (!kaz_kem_is_initialized()) {
        return KAZ_KEM_ERROR_NOT_INIT;
    }
    int status = kaz_kem_keypair(pk, sk);
    if (status == 0) return 0;
    else return -4;
#endif
}

/**
 * Encapsulate a message.
 */
int crypto_encap(unsigned char *encapsulate, unsigned long long *encaplen,
                 const unsigned char *m, unsigned long long mlen,
                 const unsigned char *pk)
{
#ifdef KAZ_SECURITY_LEVEL
    /* Compile-time API: use legacy functions */
    int status = KAZ_KEM_ENCAPSULATION(encapsulate, encaplen, m, mlen, pk);
    if (status == 0) return 0;
    else return status;
#else
    /* Runtime API: must be initialized */
    if (!kaz_kem_is_initialized()) {
        return KAZ_KEM_ERROR_NOT_INIT;
    }
    int status = kaz_kem_encapsulate(encapsulate, encaplen, m, mlen, pk);
    if (status == 0) return 0;
    else return status;
#endif
}

/**
 * Decapsulate a ciphertext.
 */
int crypto_decap(unsigned char *decapsulate, unsigned long long *decaplen,
                 const unsigned char *encapsulate, unsigned long long encaplen,
                 const unsigned char *sk)
{
#ifdef KAZ_SECURITY_LEVEL
    /* Compile-time API: use legacy functions */
    int status = KAZ_KEM_DECAPSULATION(decapsulate, decaplen, encapsulate, encaplen, sk);
    if (status == 0) return 0;
    else return status;
#else
    /* Runtime API: must be initialized */
    if (!kaz_kem_is_initialized()) {
        return KAZ_KEM_ERROR_NOT_INIT;
    }
    int status = kaz_kem_decapsulate(decapsulate, decaplen, encapsulate, encaplen, sk);
    if (status == 0) return 0;
    else return status;
#endif
}
