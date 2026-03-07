/*
 * KAZ-SIGN NIST API Wrapper
 * Thin wrapper providing NIST-compliant API
 *
 * FIXED: Removed incorrect sizeof() checks on pointer parameters
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "kaz/nist_api.h"
#include "kaz/sign.h"

/* ============================================================================
 * NIST API Implementation
 * ============================================================================ */

int crypto_sign_keypair(unsigned char *pk, unsigned char *sk)
{
    /* Validate pointers (FIXED: removed incorrect sizeof checks) */
    if (pk == NULL || sk == NULL) {
        return -1;
    }

    int ret = kaz_sign_keypair(pk, sk);

    return (ret == KAZ_SIGN_SUCCESS) ? 0 : ret;
}

int crypto_sign(unsigned char *sm,
                unsigned long long *smlen,
                const unsigned char *m,
                unsigned long long mlen,
                const unsigned char *sk)
{
    /* Validate pointers */
    if (sm == NULL || smlen == NULL || m == NULL || sk == NULL) {
        return -1;
    }

    int ret = kaz_sign_signature(sm, smlen, m, mlen, sk);

    return (ret == KAZ_SIGN_SUCCESS) ? 0 : ret;
}

int crypto_sign_open(unsigned char *m,
                     unsigned long long *mlen,
                     const unsigned char *sm,
                     unsigned long long smlen,
                     const unsigned char *pk)
{
    /* Validate pointers */
    if (m == NULL || mlen == NULL || sm == NULL || pk == NULL) {
        return -1;
    }

    int ret = kaz_sign_verify(m, mlen, sm, smlen, pk);

    return (ret == KAZ_SIGN_SUCCESS) ? 0 : ret;
}
