/*
 * KAZ-SIGN Security Utilities
 * Version 2.0
 *
 * Production hardening functions for secure memory handling,
 * constant-time operations, and side-channel resistance.
 *
 * WARNING: While these utilities improve security, full production
 * readiness requires external security audit and FIPS certification.
 */

#ifndef KAZ_SECURITY_H
#define KAZ_SECURITY_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Compiler Hints for Security
 * ============================================================================ */

/* Prevent compiler from optimizing away security-critical operations */
#if defined(__GNUC__) || defined(__clang__)
#define KAZ_NOINLINE __attribute__((noinline))
#define KAZ_SENSITIVE __attribute__((sensitive))
#else
#define KAZ_NOINLINE
#define KAZ_SENSITIVE
#endif

/* Memory barrier to prevent compiler reordering */
#if defined(__GNUC__) || defined(__clang__)
#define KAZ_MEMORY_BARRIER() __asm__ __volatile__("" ::: "memory")
#else
#define KAZ_MEMORY_BARRIER() do {} while(0)
#endif

/* ============================================================================
 * Secure Memory Zeroization
 * ============================================================================ */

/**
 * Securely zero memory that may contain sensitive data.
 * This function is designed to resist compiler optimization that might
 * remove "unnecessary" memory clearing operations.
 *
 * @param ptr   Pointer to memory to zero
 * @param len   Number of bytes to zero
 */
static inline void kaz_secure_zero(void *ptr, size_t len)
{
    if (ptr == NULL || len == 0) return;

    volatile unsigned char *p = (volatile unsigned char *)ptr;

    while (len--) {
        *p++ = 0;
    }

    KAZ_MEMORY_BARRIER();
}

/**
 * Secure memset that won't be optimized away.
 * Uses volatile pointer and memory barrier.
 *
 * @param ptr   Pointer to memory
 * @param val   Value to set
 * @param len   Number of bytes
 */
static inline void kaz_secure_memset(void *ptr, int val, size_t len)
{
    if (ptr == NULL || len == 0) return;

    volatile unsigned char *p = (volatile unsigned char *)ptr;
    unsigned char v = (unsigned char)val;

    while (len--) {
        *p++ = v;
    }

    KAZ_MEMORY_BARRIER();
}

/* ============================================================================
 * Constant-Time Operations
 * ============================================================================ */

/**
 * Constant-time memory comparison.
 * Compares all bytes regardless of mismatches to prevent timing attacks.
 *
 * @param a     First buffer
 * @param b     Second buffer
 * @param len   Number of bytes to compare
 * @return      0 if equal, non-zero if different
 */
static inline int kaz_ct_memcmp(const void *a, const void *b, size_t len)
{
    const volatile unsigned char *pa = (const volatile unsigned char *)a;
    const volatile unsigned char *pb = (const volatile unsigned char *)b;
    volatile unsigned char diff = 0;

    for (size_t i = 0; i < len; i++) {
        diff |= pa[i] ^ pb[i];
    }

    /* Return 0 if equal, 1 if different (constant-time) */
    return (1 & ((diff - 1) >> 8)) ^ 1;
}

/**
 * Constant-time conditional select.
 * Returns a if condition is 0, b if condition is non-zero.
 * Executes in constant time regardless of condition.
 *
 * @param condition  Selection condition
 * @param a          Value if condition is 0
 * @param b          Value if condition is non-zero
 * @return           Selected value
 */
static inline uint64_t kaz_ct_select(uint64_t condition, uint64_t a, uint64_t b)
{
    /* Convert condition to all-ones or all-zeros mask */
    uint64_t mask = (uint64_t)(-(int64_t)(condition != 0));
    return (a & ~mask) | (b & mask);
}

/**
 * Constant-time byte selection.
 *
 * @param condition  Selection condition
 * @param a          Value if condition is 0
 * @param b          Value if condition is non-zero
 * @return           Selected value
 */
static inline unsigned char kaz_ct_select_u8(unsigned char condition,
                                              unsigned char a,
                                              unsigned char b)
{
    unsigned char mask = (unsigned char)(-(condition != 0));
    return (a & ~mask) | (b & mask);
}

/**
 * Constant-time conditional copy.
 * Copies src to dst only if condition is non-zero, in constant time.
 *
 * @param condition  Copy condition
 * @param dst        Destination buffer
 * @param src        Source buffer
 * @param len        Number of bytes
 */
static inline void kaz_ct_cmov(int condition, void *dst, const void *src, size_t len)
{
    volatile unsigned char *d = (volatile unsigned char *)dst;
    const volatile unsigned char *s = (const volatile unsigned char *)src;
    unsigned char mask = (unsigned char)(-(condition != 0));

    for (size_t i = 0; i < len; i++) {
        d[i] = (d[i] & ~mask) | (s[i] & mask);
    }

    KAZ_MEMORY_BARRIER();
}

/**
 * Constant-time check if value is zero.
 *
 * @param x  Value to check
 * @return   1 if x is zero, 0 otherwise
 */
static inline int kaz_ct_is_zero(uint64_t x)
{
    /* If x is 0, x-1 will have high bit set (underflow) */
    /* If x is non-zero, x-1 won't have high bit set unless x was negative */
    return (int)(1 & ((x - 1) >> 63));
}

/**
 * Constant-time check if two values are equal.
 *
 * @param a  First value
 * @param b  Second value
 * @return   1 if equal, 0 otherwise
 */
static inline int kaz_ct_eq(uint64_t a, uint64_t b)
{
    return kaz_ct_is_zero(a ^ b);
}

/* ============================================================================
 * Buffer Security
 * ============================================================================ */

/**
 * Secure buffer structure with automatic zeroization tracking.
 */
typedef struct {
    unsigned char *data;
    size_t len;
    size_t capacity;
    int needs_zeroize;
} kaz_secure_buffer_t;

/**
 * Initialize a secure buffer.
 *
 * @param buf       Buffer structure
 * @param data      Data pointer
 * @param capacity  Buffer capacity
 * @param sensitive Whether buffer contains sensitive data
 */
static inline void kaz_secure_buffer_init(kaz_secure_buffer_t *buf,
                                           unsigned char *data,
                                           size_t capacity,
                                           int sensitive)
{
    buf->data = data;
    buf->len = 0;
    buf->capacity = capacity;
    buf->needs_zeroize = sensitive;
}

/**
 * Clear a secure buffer, zeroizing if marked sensitive.
 *
 * @param buf  Buffer to clear
 */
static inline void kaz_secure_buffer_clear(kaz_secure_buffer_t *buf)
{
    if (buf->needs_zeroize && buf->data != NULL) {
        kaz_secure_zero(buf->data, buf->capacity);
    }
    buf->len = 0;
}

/* ============================================================================
 * Input Validation
 * ============================================================================ */

/**
 * Validate pointer is not NULL.
 *
 * @param ptr   Pointer to validate
 * @param name  Parameter name for error messages
 * @return      0 if valid, -1 if NULL
 */
static inline int kaz_validate_ptr(const void *ptr, const char *name)
{
    (void)name; /* Used for debugging */
    return (ptr == NULL) ? -1 : 0;
}

/**
 * Validate buffer size is within bounds.
 *
 * @param size      Actual size
 * @param min_size  Minimum required size
 * @param max_size  Maximum allowed size
 * @return          0 if valid, -1 if invalid
 */
static inline int kaz_validate_size(size_t size, size_t min_size, size_t max_size)
{
    return (size >= min_size && size <= max_size) ? 0 : -1;
}

/* ============================================================================
 * Security State
 * ============================================================================ */

/**
 * Global security state for runtime checks.
 */
typedef struct {
    int initialized;
    int constant_time_enabled;
    int zeroize_on_free;
    unsigned long operations_count;
} kaz_security_state_t;

/**
 * Get global security state (singleton).
 */
kaz_security_state_t *kaz_get_security_state(void);

/**
 * Initialize security state with secure defaults.
 */
void kaz_security_init(void);

/**
 * Cleanup security state.
 */
void kaz_security_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif /* KAZ_SECURITY_H */
