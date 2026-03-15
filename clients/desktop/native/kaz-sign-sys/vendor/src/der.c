/*
 * KAZ-SIGN: DER Key Encoding/Decoding
 * Version 3.0
 *
 * Implements SubjectPublicKeyInfo (X.509) and PrivateKeyInfo (PKCS#8)
 * DER encoding for KAZ-Sign public and private keys.
 *
 * Uses manual TLV (tag-length-value) construction for portability.
 *
 * OIDs (private enterprise arc 62395):
 *   Algorithm OIDs (for signatures/certificates):
 *     KAZ-SIGN-128: 1.3.6.1.4.1.62395.1.2.1
 *     KAZ-SIGN-192: 1.3.6.1.4.1.62395.1.2.2
 *     KAZ-SIGN-256: 1.3.6.1.4.1.62395.1.2.3
 *   Key OIDs (for SubjectPublicKeyInfo / PrivateKeyInfo):
 *     Public key:  1.3.6.1.4.1.62395.1.1.2
 *     Private key: 1.3.6.1.4.1.62395.1.1.1
 */

#include <string.h>

#include "kaz/sign.h"
#include "kaz/security.h"

/* ============================================================================
 * OID Definitions
 * ============================================================================
 *
 * Enterprise number 62395 (0xF3BB) in base-128 varint:
 *   62395 / 128 = 487 remainder 59 -> 0x3B
 *   487 / 128 = 3 remainder 103 -> 103 | 0x80 = 0xE7
 *   3 -> 3 | 0x80 = 0x83
 *   Result: 0x83, 0xE7, 0x3B
 *
 * Key OIDs (fixed, no level byte):
 *   Public key:  1.3.6.1.4.1.62395.1.1.2
 *     Value: 2B 06 01 04 01 83 E7 3B 02 01 02  (11 bytes)
 *     TLV:   06 0B 2B 06 01 04 01 83 E7 3B 02 01 02  (13 bytes)
 *
 *   Private key: 1.3.6.1.4.1.62395.1.1.1
 *     Value: 2B 06 01 04 01 83 E7 3B 02 01 01  (11 bytes)
 *     TLV:   06 0B 2B 06 01 04 01 83 E7 3B 02 01 01  (13 bytes)
 */

/* Public key OID value bytes (fixed) */
static const unsigned char OID_PUBKEY[] = {
    0x2B, 0x06, 0x01, 0x04, 0x01, 0x83, 0xE7, 0x3B, 0x01, 0x01, 0x02
};
#define OID_PUBKEY_LEN    11   /* value bytes */
#define OID_PUBKEY_TLV    13   /* tag(1) + length(1) + OID_PUBKEY_LEN */

/* Private key OID value bytes (fixed) */
static const unsigned char OID_PRIVKEY[] = {
    0x2B, 0x06, 0x01, 0x04, 0x01, 0x83, 0xE7, 0x3B, 0x01, 0x01, 0x01
};
#define OID_PRIVKEY_LEN   11   /* value bytes */
#define OID_PRIVKEY_TLV   13   /* tag(1) + length(1) + OID_PRIVKEY_LEN */

/* AlgorithmIdentifier size for key OIDs: SEQUENCE tag(1) + len(1) + OID TLV */
#define ALGID_PUBKEY_LEN  (2 + OID_PUBKEY_TLV)   /* 15 bytes */
#define ALGID_PRIVKEY_LEN (2 + OID_PRIVKEY_TLV)   /* 15 bytes */

/* ============================================================================
 * Internal helpers
 * ============================================================================ */

/**
 * Compute the number of bytes needed to DER-encode a length value.
 * Returns 1 for lengths < 128, or 1 + N where N is the number of
 * bytes needed for the length value itself.
 */
static size_t der_length_size(size_t len)
{
    if (len < 128) return 1;
    if (len < 256) return 2;          /* 0x81 NN */
    if (len < 65536) return 3;        /* 0x82 NN NN */
    return 4;                          /* 0x83 NN NN NN (up to 16M) */
}

/**
 * Write a DER length at `out`. Returns number of bytes written.
 */
static size_t der_write_length(unsigned char *out, size_t len)
{
    if (len < 128) {
        out[0] = (unsigned char)len;
        return 1;
    }
    if (len < 256) {
        out[0] = 0x81;
        out[1] = (unsigned char)len;
        return 2;
    }
    if (len < 65536) {
        out[0] = 0x82;
        out[1] = (unsigned char)(len >> 8);
        out[2] = (unsigned char)(len & 0xFF);
        return 3;
    }
    /* up to 16MB */
    out[0] = 0x83;
    out[1] = (unsigned char)(len >> 16);
    out[2] = (unsigned char)((len >> 8) & 0xFF);
    out[3] = (unsigned char)(len & 0xFF);
    return 4;
}

/**
 * Parse a DER length from `in` (max `avail` bytes).
 * Sets *len_out and returns bytes consumed, or 0 on error.
 */
static size_t der_read_length(const unsigned char *in, size_t avail, size_t *len_out)
{
    if (avail == 0) return 0;

    if (in[0] < 128) {
        *len_out = in[0];
        return 1;
    }

    size_t nbytes = in[0] & 0x7F;
    if (nbytes == 0 || nbytes > 3 || nbytes + 1 > avail) return 0;

    size_t val = 0;
    for (size_t i = 0; i < nbytes; i++) {
        val = (val << 8) | in[1 + i];
    }
    *len_out = val;
    return 1 + nbytes;
}

/**
 * Write the AlgorithmIdentifier SEQUENCE for a key OID (fixed, no level byte).
 * Format: SEQUENCE { OID }
 * Returns bytes written.
 */
static size_t write_key_algorithm_id(unsigned char *out,
                                      const unsigned char *oid, size_t oid_len,
                                      size_t oid_tlv_len)
{
    /* SEQUENCE tag */
    out[0] = 0x30;
    /* SEQUENCE length = OID TLV length */
    out[1] = (unsigned char)oid_tlv_len;
    /* OID tag */
    out[2] = 0x06;
    /* OID length */
    out[3] = (unsigned char)oid_len;
    /* OID value */
    memcpy(out + 4, oid, oid_len);

    return 2 + oid_tlv_len; /* SEQUENCE tag+len + OID TLV */
}

/**
 * Verify that the AlgorithmIdentifier at `in` matches the expected key OID.
 * Returns AlgID length on success, 0 on mismatch.
 */
static size_t verify_key_algorithm_id(const unsigned char *in, size_t avail,
                                       const unsigned char *oid, size_t oid_len,
                                       size_t oid_tlv_len, size_t algid_len)
{
    if (avail < algid_len) return 0;

    /* Check SEQUENCE tag + length */
    if (in[0] != 0x30 || in[1] != (unsigned char)oid_tlv_len) return 0;
    /* Check OID tag + length */
    if (in[2] != 0x06 || in[3] != (unsigned char)oid_len) return 0;
    /* Check OID value */
    if (memcmp(in + 4, oid, oid_len) != 0) return 0;

    return algid_len;
}

/* ============================================================================
 * Public Key DER Encoding (SubjectPublicKeyInfo)
 * ============================================================================
 *
 * SEQUENCE {
 *   SEQUENCE { OID }         -- AlgorithmIdentifier
 *   BIT STRING {             -- subjectPublicKey
 *     0x00                   -- unused bits
 *     kazwire_encoded_bytes  -- KazWire header + raw public key
 *   }
 * }
 */

int kaz_sign_pubkey_to_der(kaz_sign_level_t level,
                           const unsigned char *pk,
                           unsigned char *der,
                           unsigned long long *derlen)
{
    if (!pk || !derlen) return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    size_t pk_bytes = params->public_key_bytes;
    size_t wire_bytes = KAZ_WIRE_HEADER_LEN + pk_bytes;

    /* BIT STRING content = 1 (unused-bits byte) + wire_bytes */
    size_t bitstr_content_len = 1 + wire_bytes;
    /* BIT STRING TLV: tag(1) + length_bytes + content */
    size_t bitstr_len_size = der_length_size(bitstr_content_len);
    size_t bitstr_tlv_len = 1 + bitstr_len_size + bitstr_content_len;

    /* Outer SEQUENCE content = AlgID + BIT STRING TLV */
    size_t seq_content_len = ALGID_PUBKEY_LEN + bitstr_tlv_len;
    size_t seq_len_size = der_length_size(seq_content_len);
    size_t total_len = 1 + seq_len_size + seq_content_len;

    /* If der is NULL, just report the needed size */
    if (!der) {
        *derlen = (unsigned long long)total_len;
        return KAZ_SIGN_SUCCESS;
    }

    /* Check buffer size */
    if ((unsigned long long)total_len > *derlen) {
        *derlen = (unsigned long long)total_len;
        return KAZ_SIGN_ERROR_BUFFER;
    }

    /* KazWire-encode the public key into a stack buffer */
    unsigned char wire_buf[KAZ_WIRE_HEADER_LEN + 128]; /* max pk is 118 bytes */
    size_t wire_len = sizeof(wire_buf);
    int rc = kaz_sign_pubkey_to_wire(level, pk, pk_bytes, wire_buf, &wire_len);
    if (rc != KAZ_SIGN_SUCCESS) return rc;
    if (wire_len != wire_bytes) return KAZ_SIGN_ERROR_DER;

    unsigned char *p = der;

    /* Outer SEQUENCE */
    *p++ = 0x30;
    p += der_write_length(p, seq_content_len);

    /* AlgorithmIdentifier (public key OID) */
    p += write_key_algorithm_id(p, OID_PUBKEY, OID_PUBKEY_LEN, OID_PUBKEY_TLV);

    /* BIT STRING wrapping KazWire-encoded public key */
    *p++ = 0x03;
    p += der_write_length(p, bitstr_content_len);
    *p++ = 0x00; /* unused bits */
    memcpy(p, wire_buf, (size_t)wire_len);
    p += wire_len;

    *derlen = (unsigned long long)(p - der);
    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * Public Key DER Decoding
 * ============================================================================ */

int kaz_sign_pubkey_from_der(kaz_sign_level_t level,
                             const unsigned char *der,
                             unsigned long long derlen,
                             unsigned char *pk)
{
    if (!der || !pk) return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    size_t pk_bytes = params->public_key_bytes;
    size_t wire_bytes = KAZ_WIRE_HEADER_LEN + pk_bytes;
    const unsigned char *p = der;
    size_t remain = (size_t)derlen;

    /* Outer SEQUENCE */
    if (remain < 2 || p[0] != 0x30) return KAZ_SIGN_ERROR_DER;
    p++; remain--;

    size_t seq_len;
    size_t consumed = der_read_length(p, remain, &seq_len);
    if (consumed == 0) return KAZ_SIGN_ERROR_DER;
    p += consumed; remain -= consumed;

    if (seq_len > remain) return KAZ_SIGN_ERROR_DER;
    /* Limit remaining to sequence content */
    remain = seq_len;

    /* AlgorithmIdentifier (public key OID) */
    size_t aid_len = verify_key_algorithm_id(p, remain,
                                              OID_PUBKEY, OID_PUBKEY_LEN,
                                              OID_PUBKEY_TLV, ALGID_PUBKEY_LEN);
    if (aid_len == 0) return KAZ_SIGN_ERROR_DER;
    p += aid_len; remain -= aid_len;

    /* BIT STRING */
    if (remain < 2 || p[0] != 0x03) return KAZ_SIGN_ERROR_DER;
    p++; remain--;

    size_t bitstr_len;
    consumed = der_read_length(p, remain, &bitstr_len);
    if (consumed == 0) return KAZ_SIGN_ERROR_DER;
    p += consumed; remain -= consumed;

    if (bitstr_len > remain) return KAZ_SIGN_ERROR_DER;
    /* First byte is unused-bits count, must be 0 */
    if (bitstr_len < 1 || p[0] != 0x00) return KAZ_SIGN_ERROR_DER;
    p++; remain--; /* skip unused-bits byte */

    size_t key_len = bitstr_len - 1;
    if (key_len != wire_bytes) return KAZ_SIGN_ERROR_DER;

    /* KazWire-decode: extract raw public key and verify level matches */
    kaz_sign_level_t decoded_level;
    size_t decoded_pk_len = pk_bytes;
    int rc = kaz_sign_pubkey_from_wire(p, key_len,
                                       &decoded_level, pk, &decoded_pk_len);
    if (rc != KAZ_SIGN_SUCCESS) return KAZ_SIGN_ERROR_DER;
    if (decoded_level != level) return KAZ_SIGN_ERROR_DER;

    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * Private Key DER Encoding (PKCS#8 PrivateKeyInfo)
 * ============================================================================
 *
 * SEQUENCE {
 *   INTEGER 0                -- version
 *   SEQUENCE { OID }         -- AlgorithmIdentifier
 *   OCTET STRING {           -- privateKey
 *     kazwire_encoded_bytes  -- KazWire header + raw secret key
 *   }
 * }
 */

int kaz_sign_privkey_to_der(kaz_sign_level_t level,
                            const unsigned char *sk,
                            unsigned char *der,
                            unsigned long long *derlen)
{
    if (!sk || !derlen) return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    size_t sk_bytes = params->secret_key_bytes;
    size_t wire_bytes = KAZ_WIRE_HEADER_LEN + sk_bytes;

    /* INTEGER 0: tag(1) + length(1) + value(1) = 3 bytes */
    size_t int_tlv_len = 3;

    /* OCTET STRING content = wire_bytes (KazWire header + raw key) */
    size_t oct_len_size = der_length_size(wire_bytes);
    size_t oct_tlv_len = 1 + oct_len_size + wire_bytes;

    /* Outer SEQUENCE content = version INTEGER + AlgID + OCTET STRING */
    size_t seq_content_len = int_tlv_len + ALGID_PRIVKEY_LEN + oct_tlv_len;
    size_t seq_len_size = der_length_size(seq_content_len);
    size_t total_len = 1 + seq_len_size + seq_content_len;

    /* If der is NULL, just report the needed size */
    if (!der) {
        *derlen = (unsigned long long)total_len;
        return KAZ_SIGN_SUCCESS;
    }

    /* Check buffer size */
    if ((unsigned long long)total_len > *derlen) {
        *derlen = (unsigned long long)total_len;
        return KAZ_SIGN_ERROR_BUFFER;
    }

    /* KazWire-encode the private key into a stack buffer (max sk is 194 bytes) */
    unsigned char wire_buf[KAZ_WIRE_HEADER_LEN + 200];
    size_t wire_len = sizeof(wire_buf);
    int rc = kaz_sign_privkey_to_wire(level, sk, sk_bytes, wire_buf, &wire_len);
    if (rc != KAZ_SIGN_SUCCESS) return rc;
    if (wire_len != wire_bytes) return KAZ_SIGN_ERROR_DER;

    unsigned char *p = der;

    /* Outer SEQUENCE */
    *p++ = 0x30;
    p += der_write_length(p, seq_content_len);

    /* Version INTEGER 0 */
    *p++ = 0x02; /* INTEGER tag */
    *p++ = 0x01; /* length = 1 */
    *p++ = 0x00; /* value = 0 */

    /* AlgorithmIdentifier (private key OID) */
    p += write_key_algorithm_id(p, OID_PRIVKEY, OID_PRIVKEY_LEN, OID_PRIVKEY_TLV);

    /* OCTET STRING wrapping KazWire-encoded private key */
    *p++ = 0x04;
    p += der_write_length(p, wire_bytes);
    memcpy(p, wire_buf, (size_t)wire_len);
    p += wire_len;

    /* Securely zero the wire buffer containing private key material */
    kaz_secure_zero(wire_buf, sizeof(wire_buf));

    *derlen = (unsigned long long)(p - der);
    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * Private Key DER Decoding
 * ============================================================================ */

int kaz_sign_privkey_from_der(kaz_sign_level_t level,
                              const unsigned char *der,
                              unsigned long long derlen,
                              unsigned char *sk)
{
    if (!der || !sk) return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    size_t sk_bytes = params->secret_key_bytes;
    size_t wire_bytes = KAZ_WIRE_HEADER_LEN + sk_bytes;
    const unsigned char *p = der;
    size_t remain = (size_t)derlen;

    /* Outer SEQUENCE */
    if (remain < 2 || p[0] != 0x30) return KAZ_SIGN_ERROR_DER;
    p++; remain--;

    size_t seq_len;
    size_t consumed = der_read_length(p, remain, &seq_len);
    if (consumed == 0) return KAZ_SIGN_ERROR_DER;
    p += consumed; remain -= consumed;

    if (seq_len > remain) return KAZ_SIGN_ERROR_DER;
    remain = seq_len;

    /* Version INTEGER: must be 02 01 00 */
    if (remain < 3) return KAZ_SIGN_ERROR_DER;
    if (p[0] != 0x02 || p[1] != 0x01 || p[2] != 0x00) return KAZ_SIGN_ERROR_DER;
    p += 3; remain -= 3;

    /* AlgorithmIdentifier (private key OID) */
    size_t aid_len = verify_key_algorithm_id(p, remain,
                                              OID_PRIVKEY, OID_PRIVKEY_LEN,
                                              OID_PRIVKEY_TLV, ALGID_PRIVKEY_LEN);
    if (aid_len == 0) return KAZ_SIGN_ERROR_DER;
    p += aid_len; remain -= aid_len;

    /* OCTET STRING */
    if (remain < 2 || p[0] != 0x04) return KAZ_SIGN_ERROR_DER;
    p++; remain--;

    size_t oct_len;
    consumed = der_read_length(p, remain, &oct_len);
    if (consumed == 0) return KAZ_SIGN_ERROR_DER;
    p += consumed; remain -= consumed;

    if (oct_len > remain) return KAZ_SIGN_ERROR_DER;
    if (oct_len != wire_bytes) return KAZ_SIGN_ERROR_DER;

    /* KazWire-decode: extract raw private key and verify level matches */
    kaz_sign_level_t decoded_level;
    size_t decoded_sk_len = sk_bytes;
    int rc = kaz_sign_privkey_from_wire(p, oct_len,
                                        &decoded_level, sk, &decoded_sk_len);
    if (rc != KAZ_SIGN_SUCCESS) return KAZ_SIGN_ERROR_DER;
    if (decoded_level != level) return KAZ_SIGN_ERROR_DER;

    return KAZ_SIGN_SUCCESS;
}
