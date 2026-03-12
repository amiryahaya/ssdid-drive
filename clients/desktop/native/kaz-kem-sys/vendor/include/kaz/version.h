/*
 * KAZ-KEM Version Information
 *
 * This file is part of the KAZ-KEM implementation.
 *
 * NIST-developed software is provided by NIST as a public service.
 */

#ifndef KAZ_KEM_VERSION_H
#define KAZ_KEM_VERSION_H

/* Version information - use ifndef to allow Makefile override */
#ifndef KAZ_KEM_VERSION_MAJOR
#define KAZ_KEM_VERSION_MAJOR 2
#endif
#ifndef KAZ_KEM_VERSION_MINOR
#define KAZ_KEM_VERSION_MINOR 0
#endif
#ifndef KAZ_KEM_VERSION_PATCH
#define KAZ_KEM_VERSION_PATCH 0
#endif

/* Version string */
#define KAZ_KEM_VERSION_STRING "2.0.0"

/* Version as a single number for comparison */
#define KAZ_KEM_VERSION_NUMBER ((KAZ_KEM_VERSION_MAJOR << 16) | \
                                 (KAZ_KEM_VERSION_MINOR << 8)  | \
                                 (KAZ_KEM_VERSION_PATCH))

/* Release date */
#define KAZ_KEM_RELEASE_DATE "2026-03-09"

/* Build information */
#define KAZ_KEM_BUILD_TYPE "release"

/* API version - increment when API changes incompatibly */
#define KAZ_KEM_API_VERSION 2

/* Features in this version */
#define KAZ_KEM_HAS_SECURE_IMPL 1      /* OpenSSL constant-time (production-ready) */
#define KAZ_KEM_HAS_OPTIMIZED_IMPL 1   /* GMP optimized (development only) */
#define KAZ_KEM_HAS_ORIGINAL_IMPL 1    /* GMP original (development only) */
#define KAZ_KEM_HAS_LEVEL_128 1
#define KAZ_KEM_HAS_LEVEL_192 1
#define KAZ_KEM_HAS_LEVEL_256 1

/* Version comparison macros */
#define KAZ_KEM_VERSION_AT_LEAST(major, minor, patch) \
    (KAZ_KEM_VERSION_NUMBER >= (((major) << 16) | ((minor) << 8) | (patch)))

/*
 * Runtime version functions are declared in kaz/kem.h and
 * implemented in kem_secure.c.  The macros above are available
 * for compile-time checks.
 */

#endif /* KAZ_KEM_VERSION_H */
