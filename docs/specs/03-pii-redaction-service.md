# PII Redaction Service (Future)

**Status**: Future development  
**Last Updated**: 2025-01

## 1. Motivation
- Allow automation (e.g., compliance bot) to act as a sharing recipient without breaking zero-trust/zero-knowledge.  
- Service receives encrypted package, strips or masks configured PII, and forwards sanitized artifact to the final recipient.
- It must prove it performed redaction through signed audit material and clear all temporary data afterward.

## 2. High-level concept
1. Client shares a file/grant with `share_target_type = "redactor"` using the service's public KEM/sign keys.
2. Service verifies share signature, decrypts the package, performs redaction policy, signs a `redaction_report`, re-encrypts the result for the final recipient, and updates audit logs.
3. All sensitive data (plaintext, keys, logs) is zeroized once the workflow completes.

## 3. API contract (future)

### 3.1 Service registration
- Endpoint: `POST /redactors`
- Payload: service identity metadata, public keys (ML-DSA, KAZ-SIGN, ML-KEM, KAZ-KEM), accepted redaction profiles.
- Response: persisted service ID, thumbprint, and optional policy bundle.

### 3.2 Redaction webhook
- Endpoint: `POST /redactors/{id}/redact`
- Request: encrypted file metadata (`encrypted_metadata`, `metadata_nonce`), `wrapped_dek` for service public keys, share link info, and client signature over share parameters (per `crypto/05-signature-protocol.md`).
- Response: `redaction_report` (signed by service), optionally re-wrapped KEK/DEK for downstream recipient if the service forwards the package.

### 3.3 Audit retrieval
- Endpoint: `GET /redactors/{id}/audit/{share_id}`
- Response: signed log describing PII patterns detected, redacted scopes, processing time, and evidence that temporary secrets were cleared.

## 4. Flow implications
1. Extend share flows to allow selecting a redaction service as the grantee (similar to folder shares).  
2. Service runs the existing download/decrypt logic internally, applies configured redaction rules, then re-encrypts metadata/content with a new DEK (or reuses original if PII removal is metadata-only).  
3. Client expects the service to include `redaction_report` in the share metadata; verification requires the service's public keys.  
4. Service publishes a signed zeroization statement each cycle ("redaction_done" event) and includes it in audit responses.

## 5. Security & hygiene
- Service must verify all incoming share signatures before touching ciphertext.  
- After redaction, the service securely wipes plaintext, keys, derived hashes, and logs only signed digests.  
- The service should rotate its signing keys regularly and publish them via metadata endpoint.  
- The redaction audit record is treated as part of the file's metadata (store in `files.redaction_report` or `share_links.redaction_history`) and signed by the service.

## 6. Integration notes
- Reuse existing key-wrapping/signing helpers from the flows so the service can plug into `combinedSign`/`combinedVerify`.  
- Document the new share target type in `docs/data-model/01-entities.md` and `docs/api/05-sharing.md` once approved.  
- When implementing, ensure observability (events, log entries) follow the current wire format and error codes (consider `E_REDACTION_FAILED`, `E_REDACTION_POLICY`).

> **Future development**: This service is not yet live. The above outlines the intended specification for planning and should be finalized before implementation begins.

