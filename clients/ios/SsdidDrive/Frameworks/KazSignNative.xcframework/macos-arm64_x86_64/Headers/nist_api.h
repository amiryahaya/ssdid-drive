/*
 * KAZ-SIGN NIST PQC API
 * Standard NIST API for digital signatures
 *
 * This header provides the NIST-compliant API that wraps the internal
 * KAZ-SIGN implementation. Use this for NIST PQC compatibility.
 */

#ifndef KAZ_SIGN_NIST_API_H
#define KAZ_SIGN_NIST_API_H

#include "sign.h"

/* ============================================================================
 * NIST API Constants (mapped from KAZ-SIGN)
 * ============================================================================ */

#define CRYPTO_SECRETKEYBYTES  KAZ_SIGN_SECRETKEYBYTES
#define CRYPTO_PUBLICKEYBYTES  KAZ_SIGN_PUBLICKEYBYTES
#define CRYPTO_BYTES           KAZ_SIGN_BYTES
#define CRYPTO_ALGNAME         KAZ_SIGN_ALGNAME

/* ============================================================================
 * NIST Digital Signature API
 * ============================================================================ */

/**
 * Generate a signature key pair
 *
 * @param pk  Output: public key (CRYPTO_PUBLICKEYBYTES bytes)
 * @param sk  Output: secret key (CRYPTO_SECRETKEYBYTES bytes)
 * @return 0 on success, non-zero on failure
 */
int crypto_sign_keypair(unsigned char *pk, unsigned char *sk);

/**
 * Sign a message
 *
 * @param sm     Output: signed message (signature || message)
 * @param smlen  Output: length of signed message
 * @param m      Input: message to sign
 * @param mlen   Input: length of message
 * @param sk     Input: secret key
 * @return 0 on success, non-zero on failure
 */
int crypto_sign(unsigned char *sm,
                unsigned long long *smlen,
                const unsigned char *m,
                unsigned long long mlen,
                const unsigned char *sk);

/**
 * Verify a signed message and extract the original message
 *
 * @param m      Output: original message
 * @param mlen   Output: length of original message
 * @param sm     Input: signed message (signature || message)
 * @param smlen  Input: length of signed message
 * @param pk     Input: public key
 * @return 0 if valid signature, non-zero if invalid
 */
int crypto_sign_open(unsigned char *m,
                     unsigned long long *mlen,
                     const unsigned char *sm,
                     unsigned long long smlen,
                     const unsigned char *pk);

#endif /* KAZ_SIGN_NIST_API_H */
