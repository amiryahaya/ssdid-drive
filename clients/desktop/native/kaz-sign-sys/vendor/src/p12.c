/*
 * KAZ-SIGN: PKCS#12 Keystore Create/Load Operations
 * Version 3.0
 *
 * Implements a custom password-protected container for KAZ-Sign keys
 * and certificates. Since KAZ-Sign uses custom OIDs, we build a custom
 * encrypted container rather than using OpenSSL's PKCS12_create().
 *
 * Container format (outer):
 *   MAGIC (4 bytes) | VERSION (1 byte) | SALT (16 bytes) |
 *   ITERATIONS (4 bytes big-endian) | IV (16 bytes) |
 *   HMAC_TAG (32 bytes) | ENCRYPTED_DATA (variable)
 *
 * Inner (plaintext before encryption):
 *   LEVEL (2 bytes big-endian) |
 *   NAME_LEN (2 bytes big-endian) | NAME (variable) |
 *   SK_LEN (2 bytes big-endian) | SK (variable) |
 *   PK_LEN (2 bytes big-endian) | PK (variable) |
 *   CERT_LEN (4 bytes big-endian) | CERT (variable)
 *
 * Encryption: PBKDF2-SHA256 key derivation + AES-256-CBC
 * Integrity: HMAC-SHA256 over entire container (except HMAC field itself)
 */

#include <string.h>
#include <stdlib.h>

#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/core_names.h>

#include "kaz/sign.h"
#include "kaz/security.h"

/* ============================================================================
 * Constants
 * ============================================================================ */

static const unsigned char P12_MAGIC[4] = { 'K', 'Z', 'P', '1' };
#define P12_VERSION        1
#define P12_SALT_LEN      16
#define P12_IV_LEN        16
#define P12_HMAC_LEN      32
#define P12_KEY_LEN       32    /* AES-256 key */
#define P12_ITERATIONS    10000
#define P12_HEADER_LEN    (4 + 1 + P12_SALT_LEN + 4 + P12_IV_LEN + P12_HMAC_LEN)

/* ============================================================================
 * Internal helpers
 * ============================================================================ */

static void write_u16(unsigned char *out, uint16_t val)
{
    out[0] = (unsigned char)(val >> 8);
    out[1] = (unsigned char)(val & 0xFF);
}

static uint16_t read_u16(const unsigned char *in)
{
    return (uint16_t)(((uint16_t)in[0] << 8) | (uint16_t)in[1]);
}

static void write_u32(unsigned char *out, uint32_t val)
{
    out[0] = (unsigned char)(val >> 24);
    out[1] = (unsigned char)((val >> 16) & 0xFF);
    out[2] = (unsigned char)((val >> 8) & 0xFF);
    out[3] = (unsigned char)(val & 0xFF);
}

static uint32_t read_u32(const unsigned char *in)
{
    return ((uint32_t)in[0] << 24) | ((uint32_t)in[1] << 16) |
           ((uint32_t)in[2] << 8)  | (uint32_t)in[3];
}

/**
 * Derive encryption key and HMAC key from password using PBKDF2-SHA256.
 * Derives 64 bytes: first 32 for AES key, next 32 for HMAC key.
 */
static int derive_keys(const char *password, const unsigned char *salt,
                       uint32_t iterations,
                       unsigned char *enc_key, unsigned char *hmac_key)
{
    unsigned char derived[64];

    if (!password) return KAZ_SIGN_ERROR_P12;

    if (PKCS5_PBKDF2_HMAC(password, (int)strlen(password),
                           salt, P12_SALT_LEN,
                           (int)iterations,
                           EVP_sha256(),
                           64, derived) != 1) {
        kaz_secure_zero(derived, sizeof(derived));
        return KAZ_SIGN_ERROR_P12;
    }

    memcpy(enc_key, derived, P12_KEY_LEN);
    memcpy(hmac_key, derived + P12_KEY_LEN, P12_HMAC_LEN);
    kaz_secure_zero(derived, sizeof(derived));
    return KAZ_SIGN_SUCCESS;
}

/**
 * Compute HMAC-SHA256 over the container, skipping the HMAC tag field.
 * The HMAC covers: MAGIC | VERSION | SALT | ITERATIONS | IV | ENCRYPTED_DATA
 * (i.e., everything except the 32-byte HMAC tag at offset P12_HEADER_LEN - P12_HMAC_LEN)
 */
static int compute_hmac(const unsigned char *hmac_key,
                        const unsigned char *data, size_t data_len,
                        unsigned char *tag)
{
    /* HMAC offset: the HMAC tag starts at P12_HEADER_LEN - P12_HMAC_LEN */
    size_t hmac_offset = P12_HEADER_LEN - P12_HMAC_LEN;
    int ret = KAZ_SIGN_ERROR_P12;

    EVP_MAC *mac = EVP_MAC_fetch(NULL, "HMAC", NULL);
    if (!mac) return KAZ_SIGN_ERROR_P12;

    EVP_MAC_CTX *ctx = EVP_MAC_CTX_new(mac);
    EVP_MAC_free(mac);
    if (!ctx) return KAZ_SIGN_ERROR_P12;

    OSSL_PARAM params[2];
    params[0] = OSSL_PARAM_construct_utf8_string(OSSL_MAC_PARAM_DIGEST,
                                                   (char *)"SHA256", 0);
    params[1] = OSSL_PARAM_construct_end();

    if (EVP_MAC_init(ctx, hmac_key, P12_HMAC_LEN, params) != 1)
        goto cleanup;
    /* Hash data before HMAC tag */
    if (EVP_MAC_update(ctx, data, hmac_offset) != 1)
        goto cleanup;
    /* Hash data after HMAC tag (the encrypted payload) */
    if (data_len > P12_HEADER_LEN) {
        if (EVP_MAC_update(ctx, data + P12_HEADER_LEN,
                           data_len - P12_HEADER_LEN) != 1)
            goto cleanup;
    }
    size_t out_len = P12_HMAC_LEN;
    if (EVP_MAC_final(ctx, tag, &out_len, P12_HMAC_LEN) != 1)
        goto cleanup;

    ret = KAZ_SIGN_SUCCESS;

cleanup:
    EVP_MAC_CTX_free(ctx);
    return ret;
}

/**
 * Encrypt plaintext with AES-256-CBC. Returns ciphertext length including padding.
 * Caller must provide output buffer of at least (plaintext_len + 16) bytes.
 */
static int aes256_cbc_encrypt(const unsigned char *key, const unsigned char *iv,
                              const unsigned char *plaintext, size_t plaintext_len,
                              unsigned char *ciphertext, size_t *ciphertext_len)
{
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return KAZ_SIGN_ERROR_P12;

    int outl = 0, finl = 0;
    int ret = KAZ_SIGN_ERROR_P12;

    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, key, iv) != 1)
        goto cleanup;
    if (EVP_EncryptUpdate(ctx, ciphertext, &outl, plaintext, (int)plaintext_len) != 1)
        goto cleanup;
    if (EVP_EncryptFinal_ex(ctx, ciphertext + outl, &finl) != 1)
        goto cleanup;

    *ciphertext_len = (size_t)(outl + finl);
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    EVP_CIPHER_CTX_free(ctx);
    return ret;
}

/**
 * Decrypt ciphertext with AES-256-CBC. Returns plaintext length.
 * Caller must provide output buffer of at least ciphertext_len bytes.
 */
static int aes256_cbc_decrypt(const unsigned char *key, const unsigned char *iv,
                              const unsigned char *ciphertext, size_t ciphertext_len,
                              unsigned char *plaintext, size_t *plaintext_len)
{
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return KAZ_SIGN_ERROR_P12;

    int outl = 0, finl = 0;
    int ret = KAZ_SIGN_ERROR_P12;

    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, key, iv) != 1)
        goto cleanup;
    if (EVP_DecryptUpdate(ctx, plaintext, &outl, ciphertext, (int)ciphertext_len) != 1)
        goto cleanup;
    if (EVP_DecryptFinal_ex(ctx, plaintext + outl, &finl) != 1)
        goto cleanup;

    *plaintext_len = (size_t)(outl + finl);
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    EVP_CIPHER_CTX_free(ctx);
    return ret;
}

/* ============================================================================
 * Public API
 * ============================================================================ */

int kaz_sign_create_p12(kaz_sign_level_t level,
                        const unsigned char *sk,
                        const unsigned char *pk,
                        const unsigned char *cert,
                        unsigned long long certlen,
                        const char *password,
                        const char *name,
                        unsigned char *p12,
                        unsigned long long *p12len)
{
    if (!sk || !pk || !password || !name || !p12len)
        return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    size_t sk_bytes = params->secret_key_bytes;
    size_t pk_bytes = params->public_key_bytes;
    size_t name_len = strlen(name);
    if (name_len > 0xFFFF) return KAZ_SIGN_ERROR_INVALID;
    if (certlen > 0xFFFFFFFFULL) return KAZ_SIGN_ERROR_INVALID;

    /* Build plaintext: level(2) + name_len(2) + name + sk_len(2) + sk +
     *                  pk_len(2) + pk + cert_len(4) + cert */
    size_t plain_len = 2 + 2 + name_len + 2 + sk_bytes + 2 + pk_bytes +
                       4 + (size_t)certlen;

    /* Encrypted length: plaintext + up to 16 bytes padding */
    size_t max_enc_len = plain_len + 16;

    /* Total output: header + encrypted data */
    size_t max_total = P12_HEADER_LEN + max_enc_len;

    /* If p12 is NULL, report needed size */
    if (!p12) {
        *p12len = (unsigned long long)max_total;
        return KAZ_SIGN_SUCCESS;
    }

    if ((unsigned long long)max_total > *p12len) {
        *p12len = (unsigned long long)max_total;
        return KAZ_SIGN_ERROR_BUFFER;
    }

    /* Allocate plaintext buffer */
    unsigned char *plaintext = malloc(plain_len);
    if (!plaintext) return KAZ_SIGN_ERROR_MEMORY;

    /* Build plaintext */
    unsigned char *pp = plaintext;

    /* Level */
    write_u16(pp, (uint16_t)level);
    pp += 2;

    /* Name */
    write_u16(pp, (uint16_t)name_len);
    pp += 2;
    if (name_len > 0) {
        memcpy(pp, name, name_len);
        pp += name_len;
    }

    /* Secret key */
    write_u16(pp, (uint16_t)sk_bytes);
    pp += 2;
    memcpy(pp, sk, sk_bytes);
    pp += sk_bytes;

    /* Public key */
    write_u16(pp, (uint16_t)pk_bytes);
    pp += 2;
    memcpy(pp, pk, pk_bytes);
    pp += pk_bytes;

    /* Certificate (optional — certlen already validated at function entry) */
    write_u32(pp, (uint32_t)certlen);
    pp += 4;
    if (cert && certlen > 0) {
        memcpy(pp, cert, (size_t)certlen);
        pp += (size_t)certlen;
    }

    /* Generate salt and IV */
    unsigned char salt[P12_SALT_LEN];
    unsigned char iv[P12_IV_LEN];
    if (RAND_bytes(salt, P12_SALT_LEN) != 1 ||
        RAND_bytes(iv, P12_IV_LEN) != 1) {
        kaz_secure_zero(plaintext, plain_len);
        free(plaintext);
        return KAZ_SIGN_ERROR_RNG;
    }

    /* Derive encryption and HMAC keys */
    unsigned char enc_key[P12_KEY_LEN];
    unsigned char hmac_key[P12_HMAC_LEN];
    int ret = derive_keys(password, salt, P12_ITERATIONS, enc_key, hmac_key);
    if (ret != KAZ_SIGN_SUCCESS) {
        kaz_secure_zero(plaintext, plain_len);
        free(plaintext);
        return ret;
    }

    /* Write header */
    unsigned char *out = p12;
    memcpy(out, P12_MAGIC, 4);
    out += 4;
    *out++ = P12_VERSION;
    memcpy(out, salt, P12_SALT_LEN);
    out += P12_SALT_LEN;
    write_u32(out, P12_ITERATIONS);
    out += 4;
    memcpy(out, iv, P12_IV_LEN);
    out += P12_IV_LEN;

    /* Reserve space for HMAC (will fill later) */
    unsigned char *hmac_slot = out;
    memset(out, 0, P12_HMAC_LEN);
    out += P12_HMAC_LEN;

    /* Encrypt */
    size_t enc_len = 0;
    ret = aes256_cbc_encrypt(enc_key, iv, plaintext, plain_len, out, &enc_len);

    /* Zeroize sensitive data */
    kaz_secure_zero(plaintext, plain_len);
    free(plaintext);
    kaz_secure_zero(enc_key, sizeof(enc_key));

    if (ret != KAZ_SIGN_SUCCESS) {
        kaz_secure_zero(hmac_key, sizeof(hmac_key));
        return ret;
    }

    size_t total_len = P12_HEADER_LEN + enc_len;

    /* Compute HMAC over the entire container (excluding the HMAC tag field) */
    unsigned char tag[P12_HMAC_LEN];
    ret = compute_hmac(hmac_key, p12, total_len, tag);
    kaz_secure_zero(hmac_key, sizeof(hmac_key));

    if (ret != KAZ_SIGN_SUCCESS) return ret;

    /* Write HMAC tag into its reserved slot */
    memcpy(hmac_slot, tag, P12_HMAC_LEN);

    *p12len = (unsigned long long)total_len;
    return KAZ_SIGN_SUCCESS;
}

int kaz_sign_load_p12(kaz_sign_level_t level,
                      const unsigned char *p12,
                      unsigned long long p12len,
                      const char *password,
                      unsigned char *sk,
                      unsigned char *pk,
                      unsigned char *cert,
                      unsigned long long *certlen)
{
    if (!p12 || !password)
        return KAZ_SIGN_ERROR_INVALID;

    if ((size_t)p12len < P12_HEADER_LEN + 16) /* minimum: header + one AES block */
        return KAZ_SIGN_ERROR_P12;

    const unsigned char *ptr = p12;

    /* Verify magic */
    if (memcmp(ptr, P12_MAGIC, 4) != 0)
        return KAZ_SIGN_ERROR_P12;
    ptr += 4;

    /* Verify version */
    if (*ptr != P12_VERSION)
        return KAZ_SIGN_ERROR_P12;
    ptr++;

    /* Read salt */
    const unsigned char *salt = ptr;
    ptr += P12_SALT_LEN;

    /* Read iterations */
    uint32_t iterations = read_u32(ptr);
    ptr += 4;

    /* Read IV */
    const unsigned char *iv = ptr;
    ptr += P12_IV_LEN;

    /* Read stored HMAC */
    const unsigned char *stored_hmac = ptr;
    ptr += P12_HMAC_LEN;

    /* Validate iteration count to prevent CPU DoS from crafted blobs */
    if (iterations == 0 || iterations > 10000000u)
        return KAZ_SIGN_ERROR_P12;

    /* Derive keys */
    unsigned char enc_key[P12_KEY_LEN];
    unsigned char hmac_key[P12_HMAC_LEN];
    int ret = derive_keys(password, salt, iterations, enc_key, hmac_key);
    if (ret != KAZ_SIGN_SUCCESS)
        return ret;

    /* Verify HMAC integrity */
    unsigned char computed_tag[P12_HMAC_LEN];
    ret = compute_hmac(hmac_key, p12, (size_t)p12len, computed_tag);
    kaz_secure_zero(hmac_key, sizeof(hmac_key));

    if (ret != KAZ_SIGN_SUCCESS) {
        kaz_secure_zero(enc_key, sizeof(enc_key));
        return ret;
    }

    if (kaz_ct_memcmp(stored_hmac, computed_tag, P12_HMAC_LEN) != 0) {
        kaz_secure_zero(enc_key, sizeof(enc_key));
        return KAZ_SIGN_ERROR_P12; /* wrong password or tampered data */
    }

    /* Decrypt */
    size_t enc_len = (size_t)p12len - P12_HEADER_LEN;
    unsigned char *plaintext = malloc(enc_len);
    if (!plaintext) {
        kaz_secure_zero(enc_key, sizeof(enc_key));
        return KAZ_SIGN_ERROR_MEMORY;
    }

    size_t plain_len = 0;
    ret = aes256_cbc_decrypt(enc_key, iv, ptr, enc_len, plaintext, &plain_len);
    kaz_secure_zero(enc_key, sizeof(enc_key));

    if (ret != KAZ_SIGN_SUCCESS) {
        kaz_secure_zero(plaintext, enc_len);
        free(plaintext);
        return KAZ_SIGN_ERROR_P12;
    }

    /* Parse plaintext */
    const unsigned char *rp = plaintext;
    size_t remain = plain_len;

    /* Level check */
    if (remain < 2) goto parse_error;
    uint16_t stored_level = read_u16(rp);
    rp += 2; remain -= 2;

    if ((kaz_sign_level_t)stored_level != level) goto parse_error;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) goto parse_error;

    /* Name (skip) */
    if (remain < 2) goto parse_error;
    uint16_t name_len = read_u16(rp);
    rp += 2; remain -= 2;
    if (remain < name_len) goto parse_error;
    rp += name_len; remain -= name_len;

    /* Secret key */
    if (remain < 2) goto parse_error;
    uint16_t sk_len = read_u16(rp);
    rp += 2; remain -= 2;
    if (remain < sk_len) goto parse_error;
    if (sk_len != params->secret_key_bytes) goto parse_error;
    if (sk) memcpy(sk, rp, sk_len);
    rp += sk_len; remain -= sk_len;

    /* Public key */
    if (remain < 2) goto parse_error;
    uint16_t pk_len = read_u16(rp);
    rp += 2; remain -= 2;
    if (remain < pk_len) goto parse_error;
    if (pk_len != params->public_key_bytes) goto parse_error;
    if (pk) memcpy(pk, rp, pk_len);
    rp += pk_len; remain -= pk_len;

    /* Certificate */
    if (remain < 4) goto parse_error;
    uint32_t cert_len = read_u32(rp);
    rp += 4; remain -= 4;
    if (remain < cert_len) goto parse_error;

    if (cert && certlen) {
        if (cert_len > 0 && (unsigned long long)cert_len > *certlen) {
            kaz_secure_zero(plaintext, enc_len);
            free(plaintext);
            *certlen = (unsigned long long)cert_len;
            return KAZ_SIGN_ERROR_BUFFER;
        }
        if (cert_len > 0) {
            memcpy(cert, rp, cert_len);
        }
        *certlen = (unsigned long long)cert_len;
    } else if (certlen) {
        *certlen = (unsigned long long)cert_len;
    }

    kaz_secure_zero(plaintext, enc_len);
    free(plaintext);
    return KAZ_SIGN_SUCCESS;

parse_error:
    kaz_secure_zero(plaintext, enc_len);
    free(plaintext);
    return KAZ_SIGN_ERROR_P12;
}
