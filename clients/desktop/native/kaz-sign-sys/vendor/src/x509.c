/*
 * KAZ-SIGN: X.509 Certificate Operations
 * Version 3.0
 *
 * Implements PKCS#10 CSR generation/verification and X.509 v3 certificate
 * issuance/verification using manual ASN.1 DER construction.
 *
 * OpenSSL's X509 API cannot be used because KAZ-Sign uses custom OIDs
 * and a custom signature algorithm. All DER is built manually.
 *
 * Algorithm OIDs (enterprise arc 62395):
 *   KAZ-SIGN-128: 1.3.6.1.4.1.62395.2.2.1
 *   KAZ-SIGN-192: 1.3.6.1.4.1.62395.2.2.2
 *   KAZ-SIGN-256: 1.3.6.1.4.1.62395.2.2.3
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "kaz/sign.h"
#include "kaz/security.h"

/* ============================================================================
 * OID Definitions
 * ============================================================================
 *
 * Algorithm OID prefix: 1.3.6.1.4.1.62395.2.2
 *   Value bytes: 2B 06 01 04 01 83 E7 3B 02 02 (10 bytes) + level byte
 *   Full value: 11 bytes, TLV: 13 bytes
 */

static const unsigned char OID_PREFIX_X509[] = {
    0x2B, 0x06, 0x01, 0x04, 0x01, 0x83, 0xE7, 0x3B, 0x02, 0x02
};
#define OID_PREFIX_X509_LEN  10
#define OID_VALUE_X509_LEN   11   /* prefix + 1 level byte */
#define OID_TLV_X509_LEN    13   /* tag(1) + length(1) + value(11) */
#define ALGID_X509_LEN      (2 + OID_TLV_X509_LEN) /* 15 bytes */

/* X.500 attribute type OIDs */
static const unsigned char OID_CN[]  = { 0x55, 0x04, 0x03 }; /* 2.5.4.3 CommonName */
static const unsigned char OID_O[]   = { 0x55, 0x04, 0x0A }; /* 2.5.4.10 Organization */
static const unsigned char OID_OU[]  = { 0x55, 0x04, 0x0B }; /* 2.5.4.11 OrgUnit */

/* BasicConstraints OID: 2.5.29.19 */
static const unsigned char OID_BASIC_CONSTRAINTS[] = { 0x55, 0x1D, 0x13 };

/* ============================================================================
 * Internal DER helpers
 * ============================================================================ */

/**
 * Get OID final byte for a security level
 */
static int x509_oid_level_byte(kaz_sign_level_t level)
{
    switch (level) {
        case KAZ_LEVEL_128: return 0x01;
        case KAZ_LEVEL_192: return 0x02;
        case KAZ_LEVEL_256: return 0x03;
        default: return -1;
    }
}

/**
 * Compute bytes needed to DER-encode a length value.
 */
static size_t x509_der_length_size(size_t len)
{
    if (len < 128) return 1;
    if (len < 256) return 2;
    if (len < 65536) return 3;
    return 4;
}

/**
 * Write a DER length at `out`. Returns number of bytes written.
 */
static size_t x509_der_write_length(unsigned char *out, size_t len)
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
    out[0] = 0x83;
    out[1] = (unsigned char)(len >> 16);
    out[2] = (unsigned char)((len >> 8) & 0xFF);
    out[3] = (unsigned char)(len & 0xFF);
    return 4;
}

/**
 * Read a DER length. Returns bytes consumed, or 0 on error.
 */
static size_t x509_der_read_length(const unsigned char *in, size_t avail, size_t *len_out)
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
 * Write a complete TLV: tag + length + content.
 * Returns total bytes written.
 */
static size_t x509_der_write_tlv(unsigned char *out, unsigned char tag,
                                  const unsigned char *content, size_t content_len)
{
    unsigned char *p = out;
    *p++ = tag;
    p += x509_der_write_length(p, content_len);
    if (content && content_len > 0) {
        memcpy(p, content, content_len);
        p += content_len;
    }
    return (size_t)(p - out);
}

/**
 * Compute TLV size without writing.
 */
static size_t x509_der_tlv_size(unsigned char tag, size_t content_len)
{
    (void)tag;
    return 1 + x509_der_length_size(content_len) + content_len;
}

/**
 * Write the AlgorithmIdentifier SEQUENCE for a given level.
 * Format: SEQUENCE { OID }
 * Returns bytes written.
 */
static size_t x509_write_algorithm_id(unsigned char *out, kaz_sign_level_t level)
{
    int lb = x509_oid_level_byte(level);
    if (lb < 0) return 0;
    out[0] = 0x30; /* SEQUENCE tag */
    out[1] = (unsigned char)OID_TLV_X509_LEN;
    out[2] = 0x06; /* OID tag */
    out[3] = (unsigned char)OID_VALUE_X509_LEN;
    memcpy(out + 4, OID_PREFIX_X509, OID_PREFIX_X509_LEN);
    out[4 + OID_PREFIX_X509_LEN] = (unsigned char)lb;
    return ALGID_X509_LEN;
}

/**
 * Verify that the AlgorithmIdentifier at `in` matches the expected level.
 * Returns ALGID_X509_LEN on success, 0 on mismatch.
 */
static size_t x509_verify_algorithm_id(const unsigned char *in, size_t avail,
                                        kaz_sign_level_t level)
{
    int lb = x509_oid_level_byte(level);
    if (lb < 0) return 0;
    if (avail < ALGID_X509_LEN) return 0;
    if (in[0] != 0x30 || in[1] != OID_TLV_X509_LEN) return 0;
    if (in[2] != 0x06 || in[3] != OID_VALUE_X509_LEN) return 0;
    if (memcmp(in + 4, OID_PREFIX_X509, OID_PREFIX_X509_LEN) != 0) return 0;
    if (in[4 + OID_PREFIX_X509_LEN] != (unsigned char)lb) return 0;
    return ALGID_X509_LEN;
}

/**
 * Detect level from an AlgorithmIdentifier.
 * Returns the level, or 0 on failure.
 * Reserved for future use (e.g., auto-detecting level from certificates).
 */
#if 0
static kaz_sign_level_t x509_detect_level_from_algid(const unsigned char *in, size_t avail)
{
    if (avail < ALGID_X509_LEN) return (kaz_sign_level_t)0;
    if (in[0] != 0x30 || in[1] != OID_TLV_X509_LEN) return (kaz_sign_level_t)0;
    if (in[2] != 0x06 || in[3] != OID_VALUE_X509_LEN) return (kaz_sign_level_t)0;
    if (memcmp(in + 4, OID_PREFIX_X509, OID_PREFIX_X509_LEN) != 0) return (kaz_sign_level_t)0;

    unsigned char lb = in[4 + OID_PREFIX_X509_LEN];
    switch (lb) {
        case 0x01: return KAZ_LEVEL_128;
        case 0x02: return KAZ_LEVEL_192;
        case 0x03: return KAZ_LEVEL_256;
        default:   return (kaz_sign_level_t)0;
    }
}
#endif

/* ============================================================================
 * X.500 Name construction
 * ============================================================================
 *
 * A Name is a SEQUENCE of RDN SETs. Each RDN SET contains a single
 * SEQUENCE { OID, UTF8String(value) }.
 *
 * The subject string format is: "CN=name" or "CN=name/O=org/OU=unit"
 * Fields are separated by '/'.
 * ============================================================================ */

/**
 * Build a single AttributeTypeAndValue: SEQUENCE { OID, UTF8String(value) }
 * Returns bytes written, or 0 on error.
 */
static size_t x509_build_atv(unsigned char *out, size_t out_cap,
                              const unsigned char *oid, size_t oid_len,
                              const char *value, size_t value_len)
{
    /* Inner SEQUENCE content: OID TLV + UTF8String TLV */
    size_t oid_tlv_len = x509_der_tlv_size(0x06, oid_len);
    size_t utf8_tlv_len = x509_der_tlv_size(0x0C, value_len);
    size_t seq_content = oid_tlv_len + utf8_tlv_len;
    size_t seq_total = x509_der_tlv_size(0x30, seq_content);

    /* Wrap in SET */
    size_t set_total = x509_der_tlv_size(0x31, seq_total);

    if (out_cap < set_total) return 0;

    unsigned char *p = out;

    /* SET tag + length */
    *p++ = 0x31;
    p += x509_der_write_length(p, seq_total);

    /* SEQUENCE tag + length */
    *p++ = 0x30;
    p += x509_der_write_length(p, seq_content);

    /* OID */
    p += x509_der_write_tlv(p, 0x06, oid, oid_len);

    /* UTF8String */
    p += x509_der_write_tlv(p, 0x0C, (const unsigned char *)value, value_len);

    return (size_t)(p - out);
}

/**
 * Parse a subject string like "CN=name/O=org/OU=unit" and build an X.500 Name.
 * Returns bytes written to out, or 0 on error.
 */
static size_t x509_build_name(unsigned char *out, size_t out_cap,
                               const char *subject)
{
    if (!subject || !out) return 0;

    /* First pass: build RDN entries into a temp buffer to measure total */
    unsigned char temp[1024];
    size_t temp_used = 0;

    const char *p = subject;
    while (*p) {
        /* Skip leading '/' */
        if (*p == '/') { p++; continue; }

        /* Determine field type */
        const unsigned char *oid = NULL;
        size_t oid_len = 0;

        if (strncmp(p, "CN=", 3) == 0) {
            oid = OID_CN; oid_len = sizeof(OID_CN); p += 3;
        } else if (strncmp(p, "O=", 2) == 0) {
            oid = OID_O; oid_len = sizeof(OID_O); p += 2;
        } else if (strncmp(p, "OU=", 3) == 0) {
            oid = OID_OU; oid_len = sizeof(OID_OU); p += 3;
        } else {
            return 0; /* Unknown field */
        }

        /* Find end of value */
        const char *end = strchr(p, '/');
        size_t vlen = end ? (size_t)(end - p) : strlen(p);
        if (vlen == 0) return 0;

        if (temp_used >= sizeof(temp)) return 0;  /* Prevent size_t wraparound */
        size_t wrote = x509_build_atv(temp + temp_used, sizeof(temp) - temp_used,
                                       oid, oid_len, p, vlen);
        if (wrote == 0) return 0;
        temp_used += wrote;

        p += vlen;
    }

    if (temp_used == 0) return 0;

    /* Wrap in outer SEQUENCE */
    size_t total = x509_der_tlv_size(0x30, temp_used);
    if (total > out_cap) return 0;

    unsigned char *q = out;
    *q++ = 0x30;
    q += x509_der_write_length(q, temp_used);
    memcpy(q, temp, temp_used);
    q += temp_used;

    return (size_t)(q - out);
}

/**
 * Build SubjectPublicKeyInfo from raw public key.
 * SEQUENCE { AlgorithmIdentifier, BIT STRING { 0x00, pk } }
 * Returns bytes written.
 */
static size_t x509_build_spki(unsigned char *out, size_t out_cap,
                               kaz_sign_level_t level,
                               const unsigned char *pk, size_t pk_len)
{
    size_t bitstr_content = 1 + pk_len; /* unused-bits byte + key */
    size_t bitstr_tlv = x509_der_tlv_size(0x03, bitstr_content);
    size_t seq_content = ALGID_X509_LEN + bitstr_tlv;
    size_t total = x509_der_tlv_size(0x30, seq_content);

    if (total > out_cap) return 0;

    unsigned char *p = out;
    *p++ = 0x30;
    p += x509_der_write_length(p, seq_content);
    p += x509_write_algorithm_id(p, level);

    /* BIT STRING */
    *p++ = 0x03;
    p += x509_der_write_length(p, bitstr_content);
    *p++ = 0x00; /* unused bits */
    memcpy(p, pk, pk_len);
    p += pk_len;

    return (size_t)(p - out);
}

/**
 * Convert a Unix timestamp to DER UTCTime or GeneralizedTime.
 * UTCTime: YYMMDDHHmmSSZ (tag 0x17)
 * GeneralizedTime: YYYYMMDDHHmmSSZ (tag 0x18) for years >= 2050
 * Returns bytes written.
 */
static size_t x509_build_time(unsigned char *out, size_t out_cap, time_t t)
{
    struct tm utc;
#ifdef _WIN32
    gmtime_s(&utc, &t);
#else
    gmtime_r(&t, &utc);
#endif

    int year = utc.tm_year + 1900;
    char timebuf[20];
    size_t timelen;
    unsigned char tag;

    if (year >= 2050) {
        /* GeneralizedTime: YYYYMMDDHHMMSSZ */
        snprintf(timebuf, sizeof(timebuf), "%04d%02d%02d%02d%02d%02dZ",
                 year, utc.tm_mon + 1, utc.tm_mday,
                 utc.tm_hour, utc.tm_min, utc.tm_sec);
        timelen = 15;
        tag = 0x18;
    } else {
        /* UTCTime: YYMMDDHHMMSSZ */
        snprintf(timebuf, sizeof(timebuf), "%02d%02d%02d%02d%02d%02dZ",
                 year % 100, utc.tm_mon + 1, utc.tm_mday,
                 utc.tm_hour, utc.tm_min, utc.tm_sec);
        timelen = 13;
        tag = 0x17;
    }

    size_t total = x509_der_tlv_size(tag, timelen);
    if (total > out_cap) return 0;

    return x509_der_write_tlv(out, tag, (const unsigned char *)timebuf, timelen);
}

/**
 * Build Validity SEQUENCE { notBefore, notAfter } from current time + days.
 * Returns bytes written.
 */
static size_t x509_build_validity(unsigned char *out, size_t out_cap, int days)
{
    time_t now = time(NULL);
    time_t not_after = now + (time_t)days * 86400;

    unsigned char nb_buf[32], na_buf[32];
    size_t nb_len = x509_build_time(nb_buf, sizeof(nb_buf), now);
    size_t na_len = x509_build_time(na_buf, sizeof(na_buf), not_after);

    if (nb_len == 0 || na_len == 0) return 0;

    size_t content = nb_len + na_len;
    size_t total = x509_der_tlv_size(0x30, content);
    if (total > out_cap) return 0;

    unsigned char *p = out;
    *p++ = 0x30;
    p += x509_der_write_length(p, content);
    memcpy(p, nb_buf, nb_len); p += nb_len;
    memcpy(p, na_buf, na_len); p += na_len;

    return (size_t)(p - out);
}

/**
 * Build an INTEGER TLV from an unsigned 64-bit value.
 * Returns bytes written.
 */
static size_t x509_build_integer(unsigned char *out, size_t out_cap,
                                  unsigned long long val)
{
    /* Encode the value in big-endian, prepend 0x00 if high bit set */
    unsigned char valbuf[9];
    int nbytes = 0;

    if (val == 0) {
        valbuf[0] = 0x00;
        nbytes = 1;
    } else {
        /* Write big-endian */
        unsigned char tmp[8];
        int n = 0;
        unsigned long long v = val;
        while (v > 0) {
            tmp[n++] = (unsigned char)(v & 0xFF);
            v >>= 8;
        }
        /* Reverse and check high bit */
        int idx = 0;
        if (tmp[n-1] & 0x80) {
            valbuf[idx++] = 0x00; /* padding for positive */
        }
        for (int i = n - 1; i >= 0; i--) {
            valbuf[idx++] = tmp[i];
        }
        nbytes = idx;
    }

    size_t total = x509_der_tlv_size(0x02, (size_t)nbytes);
    if (total > out_cap) return 0;

    return x509_der_write_tlv(out, 0x02, valbuf, (size_t)nbytes);
}

/**
 * Parse a DER SEQUENCE: check tag 0x30, read length, return pointer to
 * content and content length. Returns total bytes consumed (tag+length+content),
 * or 0 on error.
 */
static size_t x509_parse_sequence(const unsigned char *in, size_t avail,
                                   const unsigned char **content, size_t *content_len)
{
    if (avail < 2 || in[0] != 0x30) return 0;

    size_t len;
    size_t hdr = 1 + x509_der_read_length(in + 1, avail - 1, &len);
    if (hdr <= 1) return 0; /* read_length failed */
    if (hdr + len > avail) return 0;

    *content = in + hdr;
    *content_len = len;
    return hdr + len;
}

/**
 * Parse any DER TLV: read tag, length, return content pointer and length.
 * Returns total bytes consumed, or 0 on error.
 */
static size_t x509_parse_tlv(const unsigned char *in, size_t avail,
                              unsigned char *tag_out,
                              const unsigned char **content, size_t *content_len)
{
    if (avail < 2) return 0;

    *tag_out = in[0];
    size_t len;
    size_t lbytes = x509_der_read_length(in + 1, avail - 1, &len);
    if (lbytes == 0) return 0;

    size_t hdr = 1 + lbytes;
    if (hdr + len > avail) return 0;

    *content = in + hdr;
    *content_len = len;
    return hdr + len;
}

/**
 * Extract the raw public key bytes from a SubjectPublicKeyInfo at `in`.
 * Verifies the AlgorithmIdentifier matches the given level.
 * On success, sets *pk_out to point into `in` and sets *pk_len.
 * Returns total bytes consumed from `in`, or 0 on error.
 */
static size_t x509_parse_spki(const unsigned char *in, size_t avail,
                               kaz_sign_level_t level,
                               const unsigned char **pk_out, size_t *pk_len)
{
    const unsigned char *seq_content;
    size_t seq_len;
    size_t seq_total = x509_parse_sequence(in, avail, &seq_content, &seq_len);
    if (seq_total == 0) return 0;

    const unsigned char *p = seq_content;
    size_t remain = seq_len;

    /* AlgorithmIdentifier */
    size_t aid = x509_verify_algorithm_id(p, remain, level);
    if (aid == 0) return 0;
    p += aid; remain -= aid;

    /* BIT STRING */
    if (remain < 2 || p[0] != 0x03) return 0;
    size_t bs_len;
    size_t bs_hdr = x509_der_read_length(p + 1, remain - 1, &bs_len);
    if (bs_hdr == 0) return 0;
    p += 1 + bs_hdr;
    remain -= 1 + bs_hdr;
    if (bs_len > remain || bs_len < 1) return 0;

    /* First byte is unused-bits, must be 0 */
    if (p[0] != 0x00) return 0;

    *pk_out = p + 1;
    *pk_len = bs_len - 1;

    return seq_total;
}

/**
 * Extract the Name (subject or issuer) from within a parsed structure.
 * Copies the raw DER bytes of the Name SEQUENCE.
 * Returns total bytes consumed, or 0 on error.
 */
static size_t x509_parse_name(const unsigned char *in, size_t avail,
                               unsigned char *name_out, size_t name_cap,
                               size_t *name_len)
{
    const unsigned char *content;
    size_t content_len;
    size_t total = x509_parse_sequence(in, avail, &content, &content_len);
    if (total == 0) return 0;
    if (total > name_cap) return 0;

    memcpy(name_out, in, total);
    *name_len = total;
    return total;
}

/* ============================================================================
 * CSR Generation (PKCS#10)
 * ============================================================================
 *
 * CertificationRequest ::= SEQUENCE {
 *     certificationRequestInfo  SEQUENCE {
 *         version       INTEGER (0),
 *         subject       Name,
 *         subjectPKInfo SubjectPublicKeyInfo,
 *         attributes    [0] IMPLICIT SET {} (empty)
 *     },
 *     signatureAlgorithm  AlgorithmIdentifier,
 *     signatureValue      BIT STRING
 * }
 * ============================================================================ */

int kaz_sign_generate_csr(kaz_sign_level_t level,
                          const unsigned char *sk,
                          const unsigned char *pk,
                          const char *subject,
                          unsigned char *csr,
                          unsigned long long *csrlen)
{
    if (!sk || !pk || !subject || !csrlen)
        return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    int ret;

    /* Build CertificationRequestInfo components */

    /* 1. version INTEGER 0: 02 01 00 */
    unsigned char version[] = { 0x02, 0x01, 0x00 };
    size_t version_len = 3;

    /* 2. subject Name */
    unsigned char name_buf[512];
    size_t name_len = x509_build_name(name_buf, sizeof(name_buf), subject);
    if (name_len == 0) return KAZ_SIGN_ERROR_X509;

    /* 3. SubjectPublicKeyInfo */
    unsigned char spki_buf[512];
    size_t spki_len = x509_build_spki(spki_buf, sizeof(spki_buf),
                                       level, pk, params->public_key_bytes);
    if (spki_len == 0) return KAZ_SIGN_ERROR_X509;

    /* 4. attributes [0] IMPLICIT SET {} (empty) */
    unsigned char attrs[] = { 0xA0, 0x00 };
    size_t attrs_len = 2;

    /* Build CertificationRequestInfo SEQUENCE */
    size_t cri_content = version_len + name_len + spki_len + attrs_len;
    size_t cri_total = x509_der_tlv_size(0x30, cri_content);

    unsigned char *tbs_buf = malloc(cri_total);
    if (!tbs_buf) return KAZ_SIGN_ERROR_MEMORY;

    {
        unsigned char *p = tbs_buf;
        *p++ = 0x30;
        p += x509_der_write_length(p, cri_content);
        memcpy(p, version, version_len); p += version_len;
        memcpy(p, name_buf, name_len); p += name_len;
        memcpy(p, spki_buf, spki_len); p += spki_len;
        memcpy(p, attrs, attrs_len); p += attrs_len;
        cri_total = (size_t)(p - tbs_buf);
    }

    /* Hash the TBS */
    unsigned char digest[64]; /* max SHA3-512 = 64 bytes */
    ret = kaz_sign_hash_ex(level, tbs_buf, cri_total, digest);
    if (ret != KAZ_SIGN_SUCCESS) {
        free(tbs_buf);
        return ret;
    }

    /* Sign the digest */
    size_t sig_size = params->signature_overhead;
    unsigned char *sig = malloc(sig_size);
    if (!sig) {
        free(tbs_buf);
        return KAZ_SIGN_ERROR_MEMORY;
    }

    unsigned long long siglen = 0;
    ret = kaz_sign_detached_prehashed_ex(level, sig, &siglen,
                                          digest, params->hash_bytes, sk);
    if (ret != KAZ_SIGN_SUCCESS) {
        free(tbs_buf);
        free(sig);
        return ret;
    }

    /* Build BIT STRING for signature: 0x00 (unused bits) + signature */
    size_t bitstr_content = 1 + (size_t)siglen;
    size_t bitstr_tlv = x509_der_tlv_size(0x03, bitstr_content);

    /* Total CSR: SEQUENCE { CRI, AlgID, BIT STRING } */
    size_t outer_content = cri_total + ALGID_X509_LEN + bitstr_tlv;
    size_t outer_total = x509_der_tlv_size(0x30, outer_content);

    if (!csr) {
        *csrlen = (unsigned long long)outer_total;
        free(tbs_buf);
        free(sig);
        return KAZ_SIGN_SUCCESS;
    }

    if ((unsigned long long)outer_total > *csrlen) {
        *csrlen = (unsigned long long)outer_total;
        free(tbs_buf);
        free(sig);
        return KAZ_SIGN_ERROR_BUFFER;
    }

    /* Assemble */
    {
        unsigned char *p = csr;
        *p++ = 0x30;
        p += x509_der_write_length(p, outer_content);

        /* CertificationRequestInfo */
        memcpy(p, tbs_buf, cri_total); p += cri_total;

        /* AlgorithmIdentifier */
        p += x509_write_algorithm_id(p, level);

        /* BIT STRING */
        *p++ = 0x03;
        p += x509_der_write_length(p, bitstr_content);
        *p++ = 0x00; /* unused bits */
        memcpy(p, sig, (size_t)siglen); p += (size_t)siglen;

        *csrlen = (unsigned long long)(p - csr);
    }

    free(tbs_buf);
    free(sig);
    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * CSR Verification
 * ============================================================================ */

int kaz_sign_verify_csr(kaz_sign_level_t level,
                        const unsigned char *csr,
                        unsigned long long csrlen)
{
    if (!csr || csrlen == 0) return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    /* Parse outer SEQUENCE */
    const unsigned char *outer_content;
    size_t outer_content_len;
    size_t outer_total = x509_parse_sequence(csr, (size_t)csrlen,
                                              &outer_content, &outer_content_len);
    if (outer_total == 0) return KAZ_SIGN_ERROR_X509;

    const unsigned char *p = outer_content;
    size_t remain = outer_content_len;

    /* Parse CertificationRequestInfo SEQUENCE - record start and end for TBS */
    const unsigned char *tbs_start = p;
    const unsigned char *cri_content;
    size_t cri_content_len;
    size_t cri_total = x509_parse_sequence(p, remain, &cri_content, &cri_content_len);
    if (cri_total == 0) return KAZ_SIGN_ERROR_X509;
    size_t tbs_len = cri_total;
    p += cri_total; remain -= cri_total;

    /* Skip version INTEGER */
    const unsigned char *cri_p = cri_content;
    size_t cri_remain = cri_content_len;
    if (cri_remain < 3 || cri_p[0] != 0x02 || cri_p[1] != 0x01 || cri_p[2] != 0x00)
        return KAZ_SIGN_ERROR_X509;
    cri_p += 3; cri_remain -= 3;

    /* Skip subject Name */
    const unsigned char *name_content;
    size_t name_content_len;
    size_t name_total = x509_parse_sequence(cri_p, cri_remain, &name_content, &name_content_len);
    if (name_total == 0) return KAZ_SIGN_ERROR_X509;
    cri_p += name_total; cri_remain -= name_total;

    /* Parse SubjectPublicKeyInfo to extract pk */
    const unsigned char *pk_data;
    size_t pk_data_len;
    size_t spki_total = x509_parse_spki(cri_p, cri_remain, level, &pk_data, &pk_data_len);
    if (spki_total == 0) return KAZ_SIGN_ERROR_X509;
    if (pk_data_len != params->public_key_bytes) return KAZ_SIGN_ERROR_X509;

    /* Verify AlgorithmIdentifier after CRI */
    if (remain < ALGID_X509_LEN) return KAZ_SIGN_ERROR_X509;
    size_t aid = x509_verify_algorithm_id(p, remain, level);
    if (aid == 0) return KAZ_SIGN_ERROR_X509;
    p += aid; remain -= aid;

    /* Parse BIT STRING for signature */
    if (remain < 2 || p[0] != 0x03) return KAZ_SIGN_ERROR_X509;
    size_t bs_len;
    size_t bs_hdr = x509_der_read_length(p + 1, remain - 1, &bs_len);
    if (bs_hdr == 0 || bs_len < 1) return KAZ_SIGN_ERROR_X509;
    {
        size_t bs_advance = 1 + bs_hdr;
        if (bs_advance > remain || bs_len > remain - bs_advance)
            return KAZ_SIGN_ERROR_X509;
        p += bs_advance;
        remain -= bs_advance;
    }
    /* unused bits byte */
    if (p[0] != 0x00) return KAZ_SIGN_ERROR_X509;
    p++;
    const unsigned char *sig_data = p;
    size_t sig_len = bs_len - 1;

    /* Hash TBS */
    unsigned char digest[64];
    int ret = kaz_sign_hash_ex(level, tbs_start, tbs_len, digest);
    if (ret != KAZ_SIGN_SUCCESS) return ret;

    /* Verify */
    ret = kaz_sign_verify_detached_prehashed_ex(level, sig_data, sig_len,
                                                 digest, params->hash_bytes, pk_data);
    return ret;
}

/* ============================================================================
 * Certificate Issuance
 * ============================================================================
 *
 * Certificate ::= SEQUENCE {
 *     tbsCertificate SEQUENCE {
 *         version         [0] EXPLICIT INTEGER (2),  -- v3
 *         serialNumber    INTEGER,
 *         signature       AlgorithmIdentifier,
 *         issuer          Name,
 *         validity        SEQUENCE { notBefore, notAfter },
 *         subject         Name (from CSR),
 *         subjectPKInfo   SubjectPublicKeyInfo (from CSR),
 *         extensions      [3] EXPLICIT SEQUENCE { ... }  -- if is_ca
 *     },
 *     signatureAlgorithm  AlgorithmIdentifier,
 *     signatureValue      BIT STRING
 * }
 * ============================================================================ */

int kaz_sign_issue_certificate(kaz_sign_level_t level,
                               const unsigned char *issuer_sk,
                               const unsigned char *issuer_pk,
                               const char *issuer_name,
                               const unsigned char *csr,
                               unsigned long long csrlen,
                               unsigned long long serial,
                               int days,
                               unsigned char *cert,
                               unsigned long long *certlen)
{
    if (!issuer_sk || !issuer_pk || !issuer_name || !csr || !certlen)
        return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    int ret;

    /* Verify the CSR first */
    ret = kaz_sign_verify_csr(level, csr, csrlen);
    if (ret != KAZ_SIGN_SUCCESS) return KAZ_SIGN_ERROR_X509;

    /* Parse CSR to extract subject Name and SPKI */
    const unsigned char *outer_content;
    size_t outer_content_len;
    size_t outer_total = x509_parse_sequence(csr, (size_t)csrlen,
                                              &outer_content, &outer_content_len);
    if (outer_total == 0) return KAZ_SIGN_ERROR_X509;

    /* Parse CRI */
    const unsigned char *cri_content;
    size_t cri_content_len;
    size_t cri_total = x509_parse_sequence(outer_content, outer_content_len,
                                            &cri_content, &cri_content_len);
    if (cri_total == 0) return KAZ_SIGN_ERROR_X509;

    const unsigned char *cri_p = cri_content;
    size_t cri_remain = cri_content_len;

    /* Validate version: must be INTEGER 0 = { 0x02, 0x01, 0x00 } */
    if (cri_remain < 3 || cri_p[0] != 0x02 || cri_p[1] != 0x01 || cri_p[2] != 0x00)
        return KAZ_SIGN_ERROR_X509;
    cri_p += 3; cri_remain -= 3;

    /* Extract subject Name DER */
    unsigned char subject_name[512];
    size_t subject_name_len = 0;
    size_t name_consumed = x509_parse_name(cri_p, cri_remain,
                                            subject_name, sizeof(subject_name),
                                            &subject_name_len);
    if (name_consumed == 0) return KAZ_SIGN_ERROR_X509;
    cri_p += name_consumed; cri_remain -= name_consumed;

    /* Extract SPKI DER */
    const unsigned char *spki_start = cri_p;
    const unsigned char *sub_pk_data;
    size_t sub_pk_len;
    size_t spki_total = x509_parse_spki(cri_p, cri_remain, level,
                                         &sub_pk_data, &sub_pk_len);
    if (spki_total == 0) return KAZ_SIGN_ERROR_X509;
    /* We need the raw SPKI DER bytes */
    unsigned char spki_der[512];
    if (spki_total > sizeof(spki_der)) return KAZ_SIGN_ERROR_X509;
    memcpy(spki_der, spki_start, spki_total);

    /* Build issuer Name */
    unsigned char issuer_name_der[512];
    size_t issuer_name_len = x509_build_name(issuer_name_der, sizeof(issuer_name_der),
                                              issuer_name);
    if (issuer_name_len == 0) return KAZ_SIGN_ERROR_X509;

    /* Build TBS Certificate */

    /* version [0] EXPLICIT INTEGER(2) */
    unsigned char ver_buf[] = { 0xA0, 0x03, 0x02, 0x01, 0x02 };
    size_t ver_len = 5;

    /* serialNumber INTEGER */
    unsigned char serial_buf[16];
    size_t serial_len = x509_build_integer(serial_buf, sizeof(serial_buf), serial);
    if (serial_len == 0) return KAZ_SIGN_ERROR_X509;

    /* signature AlgorithmIdentifier */
    unsigned char algid_buf[ALGID_X509_LEN];
    if (x509_write_algorithm_id(algid_buf, level) == 0) return KAZ_SIGN_ERROR_X509;

    /* validity */
    unsigned char validity_buf[64];
    size_t validity_len = x509_build_validity(validity_buf, sizeof(validity_buf), days);
    if (validity_len == 0) return KAZ_SIGN_ERROR_X509;

    /* Determine if this is a self-signed cert (issuer == subject check by name comparison).
     * We always build, but only add BasicConstraints CA:TRUE extension when
     * the issuer and subject names match (self-signed = CA cert). */
    int is_ca = 0;
    if (issuer_name_len == subject_name_len &&
        memcmp(issuer_name_der, subject_name, subject_name_len) == 0) {
        is_ca = 1;
    }

    /* Extensions [3] EXPLICIT SEQUENCE { ... } - only for CA */
    unsigned char ext_buf[64];
    size_t ext_len = 0;
    if (is_ca) {
        /*
         * BasicConstraints extension:
         * SEQUENCE {
         *   OID 2.5.29.19,
         *   BOOLEAN TRUE (critical),
         *   OCTET STRING { SEQUENCE { BOOLEAN TRUE } }
         * }
         */
        unsigned char bc_value[] = { 0x30, 0x03, 0x01, 0x01, 0xFF }; /* SEQUENCE { BOOLEAN TRUE } */
        unsigned char bc_oct[7]; /* OCTET STRING wrapping */
        size_t bc_oct_len = x509_der_write_tlv(bc_oct, 0x04, bc_value, sizeof(bc_value));

        /* Extension SEQUENCE */
        size_t ext_seq_content = x509_der_tlv_size(0x06, sizeof(OID_BASIC_CONSTRAINTS))
                                 + 2 /* BOOLEAN TRUE: 01 01 FF */
                                 + bc_oct_len;
        unsigned char ext_seq[64];
        unsigned char *ep = ext_seq;
        *ep++ = 0x30;
        ep += x509_der_write_length(ep, ext_seq_content);
        ep += x509_der_write_tlv(ep, 0x06, OID_BASIC_CONSTRAINTS, sizeof(OID_BASIC_CONSTRAINTS));
        /* BOOLEAN TRUE (critical) */
        *ep++ = 0x01; *ep++ = 0x01; *ep++ = 0xFF;
        memcpy(ep, bc_oct, bc_oct_len); ep += bc_oct_len;
        size_t ext_seq_total = (size_t)(ep - ext_seq);

        /* Wrap in SEQUENCE of extensions */
        unsigned char exts_seq[64];
        unsigned char *sp = exts_seq;
        *sp++ = 0x30;
        sp += x509_der_write_length(sp, ext_seq_total);
        memcpy(sp, ext_seq, ext_seq_total); sp += ext_seq_total;
        size_t exts_seq_total = (size_t)(sp - exts_seq);

        /* Wrap in [3] EXPLICIT */
        unsigned char *xp = ext_buf;
        *xp++ = 0xA3;
        xp += x509_der_write_length(xp, exts_seq_total);
        memcpy(xp, exts_seq, exts_seq_total); xp += exts_seq_total;
        ext_len = (size_t)(xp - ext_buf);
    }

    /* TBS content */
    size_t tbs_content = ver_len + serial_len + ALGID_X509_LEN
                         + issuer_name_len + validity_len
                         + subject_name_len + spki_total + ext_len;
    size_t tbs_total = x509_der_tlv_size(0x30, tbs_content);

    unsigned char *tbs_buf = malloc(tbs_total);
    if (!tbs_buf) return KAZ_SIGN_ERROR_MEMORY;

    {
        unsigned char *p = tbs_buf;
        *p++ = 0x30;
        p += x509_der_write_length(p, tbs_content);
        memcpy(p, ver_buf, ver_len); p += ver_len;
        memcpy(p, serial_buf, serial_len); p += serial_len;
        memcpy(p, algid_buf, ALGID_X509_LEN); p += ALGID_X509_LEN;
        memcpy(p, issuer_name_der, issuer_name_len); p += issuer_name_len;
        memcpy(p, validity_buf, validity_len); p += validity_len;
        memcpy(p, subject_name, subject_name_len); p += subject_name_len;
        memcpy(p, spki_der, spki_total); p += spki_total;
        if (ext_len > 0) {
            memcpy(p, ext_buf, ext_len); p += ext_len;
        }
        tbs_total = (size_t)(p - tbs_buf);
    }

    /* Hash TBS */
    unsigned char digest[64];
    ret = kaz_sign_hash_ex(level, tbs_buf, tbs_total, digest);
    if (ret != KAZ_SIGN_SUCCESS) {
        free(tbs_buf);
        return ret;
    }

    /* Sign digest with issuer key */
    size_t sig_size = params->signature_overhead;
    unsigned char *sig = malloc(sig_size);
    if (!sig) {
        free(tbs_buf);
        return KAZ_SIGN_ERROR_MEMORY;
    }

    unsigned long long siglen = 0;
    ret = kaz_sign_detached_prehashed_ex(level, sig, &siglen,
                                          digest, params->hash_bytes, issuer_sk);
    if (ret != KAZ_SIGN_SUCCESS) {
        free(tbs_buf);
        free(sig);
        return ret;
    }

    /* BIT STRING for signature */
    size_t bitstr_content = 1 + (size_t)siglen;
    size_t bitstr_tlv = x509_der_tlv_size(0x03, bitstr_content);

    /* Outer SEQUENCE */
    size_t cert_content = tbs_total + ALGID_X509_LEN + bitstr_tlv;
    size_t cert_total = x509_der_tlv_size(0x30, cert_content);

    if (!cert) {
        *certlen = (unsigned long long)cert_total;
        free(tbs_buf);
        free(sig);
        return KAZ_SIGN_SUCCESS;
    }

    if ((unsigned long long)cert_total > *certlen) {
        *certlen = (unsigned long long)cert_total;
        free(tbs_buf);
        free(sig);
        return KAZ_SIGN_ERROR_BUFFER;
    }

    {
        unsigned char *p = cert;
        *p++ = 0x30;
        p += x509_der_write_length(p, cert_content);
        memcpy(p, tbs_buf, tbs_total); p += tbs_total;
        p += x509_write_algorithm_id(p, level);
        *p++ = 0x03;
        p += x509_der_write_length(p, bitstr_content);
        *p++ = 0x00;
        memcpy(p, sig, (size_t)siglen); p += (size_t)siglen;
        *certlen = (unsigned long long)(p - cert);
    }

    free(tbs_buf);
    free(sig);
    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * Certificate Public Key Extraction
 * ============================================================================ */

int kaz_sign_cert_extract_pubkey(kaz_sign_level_t level,
                                 const unsigned char *cert,
                                 unsigned long long certlen,
                                 unsigned char *pk)
{
    if (!cert || !pk || certlen == 0) return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    /* Parse outer SEQUENCE */
    const unsigned char *outer_content;
    size_t outer_len;
    if (x509_parse_sequence(cert, (size_t)certlen, &outer_content, &outer_len) == 0)
        return KAZ_SIGN_ERROR_X509;

    /* Parse TBS Certificate SEQUENCE */
    const unsigned char *tbs_content;
    size_t tbs_content_len;
    size_t tbs_total = x509_parse_sequence(outer_content, outer_len,
                                            &tbs_content, &tbs_content_len);
    if (tbs_total == 0) return KAZ_SIGN_ERROR_X509;

    const unsigned char *p = tbs_content;
    size_t remain = tbs_content_len;

    /* version [0] EXPLICIT - optional but we require v3 */
    if (remain < 5) return KAZ_SIGN_ERROR_X509;
    if (p[0] == 0xA0) {
        /* [0] EXPLICIT context tag */
        size_t vlen;
        size_t vhdr = x509_der_read_length(p + 1, remain - 1, &vlen);
        if (vhdr == 0) return KAZ_SIGN_ERROR_X509;
        size_t vtotal = 1 + vhdr + vlen;
        if (vtotal > remain) return KAZ_SIGN_ERROR_X509;
        p += vtotal; remain -= vtotal;
    }

    /* serialNumber INTEGER */
    unsigned char tag;
    const unsigned char *int_content;
    size_t int_len;
    size_t int_total = x509_parse_tlv(p, remain, &tag, &int_content, &int_len);
    if (int_total == 0 || tag != 0x02) return KAZ_SIGN_ERROR_X509;
    p += int_total; remain -= int_total;

    /* signature AlgorithmIdentifier */
    size_t aid = x509_verify_algorithm_id(p, remain, level);
    if (aid == 0) return KAZ_SIGN_ERROR_X509;
    p += aid; remain -= aid;

    /* issuer Name */
    const unsigned char *name_content;
    size_t name_content_len;
    size_t issuer_total = x509_parse_sequence(p, remain, &name_content, &name_content_len);
    if (issuer_total == 0) return KAZ_SIGN_ERROR_X509;
    p += issuer_total; remain -= issuer_total;

    /* validity SEQUENCE */
    const unsigned char *val_content;
    size_t val_content_len;
    size_t val_total = x509_parse_sequence(p, remain, &val_content, &val_content_len);
    if (val_total == 0) return KAZ_SIGN_ERROR_X509;
    p += val_total; remain -= val_total;

    /* subject Name */
    size_t subj_total = x509_parse_sequence(p, remain, &name_content, &name_content_len);
    if (subj_total == 0) return KAZ_SIGN_ERROR_X509;
    p += subj_total; remain -= subj_total;

    /* SubjectPublicKeyInfo */
    const unsigned char *pk_data;
    size_t pk_data_len;
    size_t spki_total = x509_parse_spki(p, remain, level, &pk_data, &pk_data_len);
    if (spki_total == 0) return KAZ_SIGN_ERROR_X509;
    if (pk_data_len != params->public_key_bytes) return KAZ_SIGN_ERROR_X509;

    memcpy(pk, pk_data, pk_data_len);
    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * Certificate Verification
 * ============================================================================ */

int kaz_sign_verify_certificate(kaz_sign_level_t level,
                                const unsigned char *cert,
                                unsigned long long certlen,
                                const unsigned char *issuer_pk)
{
    if (!cert || !issuer_pk || certlen == 0) return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) return KAZ_SIGN_ERROR_INVALID;

    /* Parse outer SEQUENCE */
    const unsigned char *outer_content;
    size_t outer_len;
    if (x509_parse_sequence(cert, (size_t)certlen, &outer_content, &outer_len) == 0)
        return KAZ_SIGN_ERROR_X509;

    const unsigned char *p = outer_content;
    size_t remain = outer_len;

    /* TBS Certificate - record raw bytes */
    const unsigned char *tbs_start = p;
    const unsigned char *tbs_content;
    size_t tbs_content_len;
    size_t tbs_total = x509_parse_sequence(p, remain, &tbs_content, &tbs_content_len);
    if (tbs_total == 0) return KAZ_SIGN_ERROR_X509;
    p += tbs_total; remain -= tbs_total;

    /* AlgorithmIdentifier */
    size_t aid = x509_verify_algorithm_id(p, remain, level);
    if (aid == 0) return KAZ_SIGN_ERROR_X509;
    p += aid; remain -= aid;

    /* BIT STRING signature */
    if (remain < 2 || p[0] != 0x03) return KAZ_SIGN_ERROR_X509;
    size_t bs_len;
    size_t bs_hdr = x509_der_read_length(p + 1, remain - 1, &bs_len);
    if (bs_hdr == 0 || bs_len < 1) return KAZ_SIGN_ERROR_X509;
    {
        size_t bs_advance = 1 + bs_hdr;
        if (bs_advance > remain || bs_len > remain - bs_advance)
            return KAZ_SIGN_ERROR_X509;
        p += bs_advance;
        remain -= bs_advance;
    }
    if (p[0] != 0x00) return KAZ_SIGN_ERROR_X509;
    p++;
    const unsigned char *sig_data = p;
    size_t sig_len = bs_len - 1;

    /* Hash TBS */
    unsigned char digest[64];
    int ret = kaz_sign_hash_ex(level, tbs_start, tbs_total, digest);
    if (ret != KAZ_SIGN_SUCCESS) return ret;

    /* Verify signature */
    ret = kaz_sign_verify_detached_prehashed_ex(level, sig_data, sig_len,
                                                 digest, params->hash_bytes, issuer_pk);
    return ret;
}
