# PII Extraction Service - Comprehensive Test Plan

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2026-01-21
**Authors**: QA Engineering Team
**Related Spec**: [PII Extraction Service Specification](10-pii-extraction-service.md)

---

## Table of Contents

1. [Test Strategy Overview](#1-test-strategy-overview)
2. [Unit Tests](#2-unit-tests)
3. [Integration Tests](#3-integration-tests)
4. [API Tests](#4-api-tests)
5. [Security Tests](#5-security-tests)
6. [Performance Tests](#6-performance-tests)
7. [End-to-End Tests](#7-end-to-end-tests)
8. [Edge Case Tests](#8-edge-case-tests)
9. [Test Environment Setup](#9-test-environment-setup)
10. [Test Data Management](#10-test-data-management)
11. [Test Execution Schedule](#11-test-execution-schedule)

---

## 1. Test Strategy Overview

### 1.1 Testing Objectives

The PII Extraction Service test plan ensures comprehensive validation of:

1. **Functional Correctness**: All features work as specified
2. **Security Guarantees**: Zero-knowledge principles maintained, PII never leaked
3. **Performance Requirements**: Meets SLA targets (< 3s total, < 500ms PII detection)
4. **Data Integrity**: Proper encryption, token mapping, and database state
5. **Event-Driven Sync**: Correct handling of file lifecycle events
6. **Multi-Model Detection**: Accurate PII detection across all tiers

### 1.2 Test Levels

| Level | Focus | Automation | Frequency |
|-------|-------|------------|-----------|
| Unit Tests | Individual components, pure functions | 100% | On every commit |
| Integration Tests | Component interactions, database | 100% | On every PR |
| API Tests | Endpoint validation, contracts | 100% | On every PR |
| Security Tests | Vulnerability scanning, penetration | 80% | Weekly + pre-release |
| Performance Tests | Load, stress, latency benchmarks | 90% | Daily + pre-release |
| E2E Tests | Complete user workflows | 100% | Daily + pre-release |
| Edge Case Tests | Boundary conditions, error paths | 100% | On every PR |

### 1.3 Test Priorities

**Critical (P0)**: Must pass before any deployment
- Security tests (memory zeroization, no PII leakage)
- Core PII detection and tokenization
- Encryption/decryption correctness
- ServiceShare validation

**High (P1)**: Must pass before release
- All API endpoints
- Conversation flow
- Event-driven synchronization
- Database integrity

**Medium (P2)**: Should pass, acceptable to defer for hotfixes
- Performance optimization
- Edge cases for rare file types
- UI/UX validation

**Low (P3)**: Nice to have, can be deferred
- Advanced ML model accuracy improvements
- Extended format support

### 1.4 Test Coverage Goals

- **Unit Test Coverage**: ≥ 90% for Elixir, ≥ 95% for Rust
- **API Test Coverage**: 100% of documented endpoints
- **Security Test Coverage**: 100% of attack vectors
- **E2E Test Coverage**: 100% of critical user paths

---

## 2. Unit Tests

### 2.1 Rust Secure Memory Handling

#### Test Case UT-RUST-001: Memory Locking Verification
**Priority**: Critical (P0)
**Component**: `SecureArena`
**Description**: Verify that allocated memory is properly locked using mlock

**Preconditions**:
- Test process has CAP_IPC_LOCK capability
- Sufficient memory available

**Test Steps**:
1. Create a `SecureArena` with 4KB size
2. Check `/proc/self/status` for VmLck field
3. Verify locked memory count increased by 4KB
4. Drop arena
5. Verify locked memory count decreased

**Expected Results**:
- Memory successfully locked (no ENOMEM error)
- VmLck increases by allocated size
- Memory properly unlocked on drop
- No memory leaks detected

**Test Data**: N/A

---

#### Test Case UT-RUST-002: Automatic Zeroization on Drop
**Priority**: Critical (P0)
**Component**: `SecureDek`, `SecurePIIProcessor`
**Description**: Ensure sensitive data is zeroized when dropped

**Preconditions**: None

**Test Steps**:
1. Create a `SecureDek` with known byte pattern (e.g., all 0xFF)
2. Get raw pointer to memory location (unsafe)
3. Drop the `SecureDek`
4. Read memory at previous location
5. Verify all bytes are 0x00

**Expected Results**:
- Memory contains original pattern before drop
- Memory contains all zeros after drop
- No panics during drop

**Test Data**:
```rust
let test_dek = vec![0xFF; 32]; // All 0xFF bytes
```

---

#### Test Case UT-RUST-003: Panic-Safe Cleanup
**Priority**: Critical (P0)
**Component**: `SecurePIIProcessor`
**Description**: Verify memory is zeroized even if panic occurs during processing

**Preconditions**: None

**Test Steps**:
1. Create `SecurePIIProcessor` with test data
2. Trigger intentional panic during processing
3. Catch panic with `std::panic::catch_unwind`
4. Verify memory was still zeroized via scopeguard
5. Check no memory leaks in cleanup path

**Expected Results**:
- Panic is properly caught
- Memory zeroized despite panic
- No memory leaks
- scopeguard cleanup executed

**Test Data**: Any test document that triggers panic

---

#### Test Case UT-RUST-004: No Core Dumps
**Priority**: Critical (P0)
**Component**: Process configuration
**Description**: Verify core dumps are disabled to prevent memory dump attacks

**Preconditions**: None

**Test Steps**:
1. Start PII service process
2. Check `prctl(PR_GET_DUMPABLE)` returns 0
3. Trigger process crash (test mode)
4. Verify no core dump file created

**Expected Results**:
- Dumpable flag is 0 (disabled)
- No core dump files generated on crash

**Test Data**: N/A

---

### 2.2 PII Detection Patterns

#### Test Case UT-PII-001: NRIC Pattern Detection
**Priority**: Critical (P0)
**Component**: `PatternDetector` (Tier 1)
**Description**: Validate Malaysian NRIC regex pattern and checksum validation

**Preconditions**: None

**Test Steps**:
1. Test valid NRIC: "901231-14-5678"
2. Test invalid NRIC (bad checksum): "901231-14-0000"
3. Test malformed NRIC: "123456-78-9012"
4. Test edge case: "000101-01-0001" (Jan 1, 2000)
5. Test with variations: spaces, no dashes

**Expected Results**:
- Valid NRIC detected with confidence 0.98
- Invalid checksum rejected
- Malformed patterns rejected
- Edge cases handled correctly
- Variations normalized and detected

**Test Data**:
```
Valid: 901231-14-5678, 850615-10-1234
Invalid: 901231-14-0000, 123-45-678
Edge: 000101-01-0001, 991231-14-9999
```

---

#### Test Case UT-PII-002: Email Pattern Detection
**Priority**: High (P1)
**Component**: `PatternDetector` (Tier 1)
**Description**: Validate email regex pattern

**Preconditions**: None

**Test Steps**:
1. Test standard email: "john.doe@example.com"
2. Test with plus addressing: "user+tag@example.com"
3. Test subdomain: "admin@mail.company.co.uk"
4. Test invalid: "not-an-email", "@example.com", "user@"
5. Test edge case: "a@b.c" (shortest valid)

**Expected Results**:
- All valid emails detected with confidence 0.95
- Invalid patterns rejected
- International TLDs supported

**Test Data**:
```
Valid: john@example.com, admin@mail.company.co.uk
Invalid: @example.com, john@, just.text
```

---

#### Test Case UT-PII-003: Phone Number Pattern Detection
**Priority**: High (P1)
**Component**: `PatternDetector` (Tier 1)
**Description**: Validate phone number patterns (Malaysian and international)

**Preconditions**: None

**Test Steps**:
1. Test Malaysian mobile: "+60-12-345-6789"
2. Test Malaysian landline: "+60-3-1234-5678"
3. Test US format: "+1-555-123-4567"
4. Test without country code: "012-345-6789"
5. Test with spaces/no dashes: "60123456789"

**Expected Results**:
- All formats detected with confidence 0.90
- Numbers normalized to consistent format
- Invalid patterns (too short/long) rejected

**Test Data**:
```
Valid: +60-12-345-6789, 012-345-6789, +1-555-123-4567
Invalid: 123, +60-1-23
```

---

#### Test Case UT-PII-004: Credit Card Pattern Detection
**Priority**: Critical (P0)
**Component**: `PatternDetector` (Tier 1)
**Description**: Validate credit card regex with Luhn algorithm

**Preconditions**: None

**Test Steps**:
1. Test valid Visa: "4532-1234-5678-9010"
2. Test valid Mastercard: "5425-2334-3010-9903"
3. Test valid Amex: "3782-822463-10005"
4. Test invalid Luhn: "4532-1234-5678-0000"
5. Test with/without dashes

**Expected Results**:
- Valid cards detected with confidence 0.99
- Luhn validation rejects invalid checksums
- Different card types recognized

**Test Data**:
```
Valid: 4532123456789010 (Visa), 5425233430109903 (MC)
Invalid: 4532123456780000 (bad Luhn)
```

---

### 2.3 Token Generation and Replacement

#### Test Case UT-TOKEN-001: Deterministic Token Generation
**Priority**: Critical (P0)
**Component**: `Tokenizer`
**Description**: Verify same PII value generates same token within conversation

**Preconditions**: None

**Test Steps**:
1. Create conversation with salt
2. Tokenize "John Doe" → get token T1
3. Tokenize "John Doe" again → get token T2
4. Verify T1 == T2
5. Create different conversation
6. Tokenize "John Doe" → get token T3
7. Verify T1 != T3 (different conversation salt)

**Expected Results**:
- Same value + same conversation = same token
- Same value + different conversation = different token
- Token format matches `<<PII_{TYPE}_{ID}>>`

**Test Data**:
```
Input: "John Doe", "Jane Smith", "John Doe"
Expected tokens: T1, T2, T1 (deterministic)
```

---

#### Test Case UT-TOKEN-002: Token Format Validation
**Priority**: High (P1)
**Component**: `Tokenizer`
**Description**: Ensure tokens follow correct format specification

**Preconditions**: None

**Test Steps**:
1. Generate tokens for various PII types
2. Validate format: `<<PII_{TYPE}_{6_CHAR_ID}>>`
3. Check TYPE is uppercase (NAME, NRIC, EMAIL, etc.)
4. Check ID is exactly 6 alphanumeric characters
5. Verify tokens are properly delimited with `<<` and `>>`

**Expected Results**:
- All tokens match regex: `<<PII_[A-Z_]+_[a-z0-9]{6}>>`
- IDs are collision-free within conversation
- Types map correctly to detected entity types

**Test Data**: Various PII entities across all types

---

#### Test Case UT-TOKEN-003: Token Map Encryption
**Priority**: Critical (P0)
**Component**: `TokenMapEncryptor`
**Description**: Verify token map is properly encrypted for client

**Preconditions**: Test session key available

**Test Steps**:
1. Create token map: `{"<<PII_NAME_a1b2>>": "John Doe"}`
2. Encrypt with session key using AES-256-GCM
3. Attempt to decrypt with wrong key → should fail
4. Decrypt with correct key → should match original
5. Verify nonce is unique per encryption

**Expected Results**:
- Encrypted map is not plaintext (no "John Doe" in bytes)
- Decryption with wrong key fails with error
- Decryption with correct key produces original map
- Nonce is 12 bytes (GCM standard)

**Test Data**:
```json
{
  "<<PII_NAME_a1b2>>": "John Doe",
  "<<PII_NRIC_c3d4>>": "901231-14-5678"
}
```

---

#### Test Case UT-TOKEN-004: Token Replacement in Content
**Priority**: High (P1)
**Component**: `Tokenizer`
**Description**: Verify PII is correctly replaced with tokens in document

**Preconditions**: None

**Test Steps**:
1. Input text: "Patient John Doe (NRIC: 901231-14-5678) visited clinic."
2. Detect PII: NAME="John Doe", NRIC="901231-14-5678"
3. Replace with tokens
4. Verify output: "Patient <<PII_NAME_...>> (NRIC: <<PII_NRIC_...>>) visited clinic."
5. Ensure no PII remains in output

**Expected Results**:
- All detected PII replaced with tokens
- Surrounding text unchanged
- Token positions correctly mapped
- Original formatting preserved

**Test Data**:
```
Input: "Patient John Doe (NRIC: 901231-14-5678) has diabetes."
Output: "Patient <<PII_NAME_abc123>> (NRIC: <<PII_NRIC_def456>>) has diabetes."
```

---

### 2.4 Token Map Encryption/Decryption

#### Test Case UT-CRYPTO-001: DEK Wrapping with PQC Keys
**Priority**: Critical (P0)
**Component**: `DEKWrapper`
**Description**: Verify DEK is properly wrapped using ML-KEM and KAZ-KEM

**Preconditions**:
- Service has ML-KEM and KAZ-KEM key pairs
- Test DEK (32 bytes) available

**Test Steps**:
1. Generate random 32-byte DEK
2. Wrap DEK with service ML-KEM public key
3. Wrap DEK with service KAZ-KEM public key
4. Unwrap using ML-KEM private key → should equal original DEK
5. Unwrap using KAZ-KEM private key → should equal original DEK
6. Verify wrapped ciphertexts are different

**Expected Results**:
- Both wrapping operations succeed
- Unwrapped DEK matches original
- ML-KEM and KAZ-KEM produce different ciphertexts
- Invalid private key fails to unwrap

**Test Data**: Random 32-byte DEK

---

#### Test Case UT-CRYPTO-002: Token Map AES-GCM Encryption
**Priority**: Critical (P0)
**Component**: `TokenMapEncryptor`
**Description**: Validate AES-256-GCM encryption of token map

**Preconditions**: Test DEK and token map available

**Test Steps**:
1. Serialize token map to JSON
2. Generate random 12-byte nonce
3. Encrypt with AES-256-GCM using DEK
4. Verify ciphertext != plaintext
5. Decrypt and verify matches original
6. Tamper with ciphertext → decryption should fail with auth tag error

**Expected Results**:
- Encryption produces ciphertext + auth tag
- Decryption recovers original JSON
- Tampered data fails authentication
- Nonce reuse detection (if implemented)

**Test Data**:
```json
{
  "<<PII_NAME_a1b2>>": "John Doe",
  "<<PII_EMAIL_c3d4>>": "john@example.com"
}
```

---

#### Test Case UT-CRYPTO-003: ServiceShare Signature Verification
**Priority**: Critical (P0)
**Component**: `ServiceShareValidator`
**Description**: Verify ServiceShare signature validation using ML-DSA and KAZ-Sign

**Preconditions**:
- User key pairs (ML-DSA, KAZ-Sign)
- Service public keys

**Test Steps**:
1. Create ServiceShare with valid signatures
2. Verify ML-DSA signature → should pass
3. Verify KAZ-Sign signature → should pass
4. Tamper with wrapped_key field
5. Re-verify signatures → should fail
6. Test with expired ServiceShare → should fail

**Expected Results**:
- Valid signatures pass verification
- Tampered data fails verification
- Expired ServiceShare rejected
- Both ML-DSA and KAZ-Sign must pass

**Test Data**: Valid and tampered ServiceShare objects

---

## 3. Integration Tests

### 3.1 Conversation Creation Flow

#### Test Case IT-CONV-001: Create Conversation with Single File
**Priority**: Critical (P0)
**Components**: ConversationManager, RedactionPipeline, Database
**Description**: Test complete conversation creation with one file

**Preconditions**:
- User authenticated
- Test file uploaded to main system
- ServiceShare created for file

**Test Steps**:
1. POST /conversations with 1 file_id and ServiceShare
2. Verify conversation created with status "processing"
3. Monitor conversation_files table for processing status
4. Wait for status = "ready"
5. Verify conversation has:
   - 1 file in conversation_files
   - 1 redacted_file created
   - 1 token_map created
   - total_pii_protected > 0
6. Check S3 bucket for redacted file

**Expected Results**:
- Conversation transitions: processing → ready
- Redacted file uploaded to S3
- Token map encrypted and stored
- Database state consistent
- Processing completes within 30 seconds

**Test Data**:
- test_medical_record.pdf (contains NAME, NRIC, EMAIL)

---

#### Test Case IT-CONV-002: Create Conversation with Multiple Files
**Priority**: High (P1)
**Components**: ConversationManager, RedactionPipeline, Database
**Description**: Test conversation creation with 5 files

**Preconditions**:
- 5 test files uploaded
- ServiceShares created for all files

**Test Steps**:
1. POST /conversations with 5 file_ids
2. Monitor individual file processing statuses
3. Verify files process in parallel (check timestamps)
4. Wait for all files to complete
5. Verify conversation status = "ready"
6. Check token map includes PII from all files
7. Verify 5 redacted files in S3

**Expected Results**:
- All 5 files processed successfully
- Parallel processing (some overlap in timestamps)
- Combined token map has PII from all sources
- Conversation ready when all files done
- Total processing < 60 seconds

**Test Data**:
- 5 different document types (medical, financial, legal, HR, general)

---

#### Test Case IT-CONV-003: Conversation Creation with File Processing Failure
**Priority**: High (P1)
**Components**: ConversationManager, RedactionPipeline, Database
**Description**: Handle graceful failure when one file fails to process

**Preconditions**:
- 3 valid files + 1 corrupted file
- ServiceShares for all

**Test Steps**:
1. POST /conversations with 4 file_ids (1 corrupted)
2. Monitor processing
3. Verify 3 files succeed, 1 fails
4. Check failed file has processing_status = "failed"
5. Check error message stored in processing_error field
6. Verify conversation status = "ready" (partial success)
7. Ensure token map only has PII from successful files

**Expected Results**:
- 3 files processed successfully
- 1 file marked as failed with error message
- Conversation still usable with 3 files
- No partial state (file either fully processed or fully failed)
- User notified of failure

**Test Data**:
- 3 valid PDFs + 1 corrupted file (truncated)

---

### 3.2 File Processing Pipeline

#### Test Case IT-PIPE-001: Decrypt → Detect → Tokenize → Save Flow
**Priority**: Critical (P0)
**Components**: SecurePIIProcessor, PatternDetector, Presidio, Database
**Description**: Validate complete file processing pipeline

**Preconditions**:
- Test file with known PII
- ServiceShare valid

**Test Steps**:
1. Trigger file processing
2. Verify file decrypted in secure memory (check logs for mlock)
3. Verify PII detection runs (all tiers: regex, NER, classification)
4. Verify tokens generated
5. Verify redacted content created
6. Verify redacted file encrypted and saved to S3
7. Verify token map saved to database (encrypted)
8. Verify plaintext zeroized (no PII in logs)

**Expected Results**:
- Each pipeline stage completes successfully
- No plaintext PII in logs or database
- Redacted file is valid and encrypted
- Token map properly encrypted
- Processing < 500ms (excluding LLM)

**Test Data**:
```
Input: "Patient: John Doe, NRIC: 901231-14-5678, Email: john@example.com"
Expected detections: NAME(1), NRIC(1), EMAIL(1)
```

---

#### Test Case IT-PIPE-002: Multi-Tier PII Detection Integration
**Priority**: High (P1)
**Components**: PatternDetector, Presidio, Phi3, Mistral
**Description**: Test all detection tiers working together

**Preconditions**:
- Presidio service running
- Ollama with Phi-3 and Mistral loaded

**Test Steps**:
1. Process document with varied PII types
2. Verify Tier 1 (Regex) detects: NRIC, email, phone, credit card
3. Verify Tier 2 (Presidio) detects: names, dates, addresses
4. Verify Tier 3 (Phi-3) classifies domain correctly
5. Verify Tier 4 (Mistral) validates uncertain entities
6. Check result merger combines all detections
7. Verify confidence scores boost for multi-tier agreement

**Expected Results**:
- All tiers run in parallel (< 350ms total)
- Results properly merged (no duplicates)
- Overlapping detections use highest confidence
- Domain-specific rules applied based on Phi-3 classification

**Test Data**:
- Medical document with patient names, doctor names, diagnoses

---

#### Test Case IT-PIPE-003: Memory Zeroization Verification
**Priority**: Critical (P0)
**Components**: SecurePIIProcessor, Rust NIFs
**Description**: Confirm no PII remains in memory after processing

**Preconditions**:
- Memory inspection tools available (gdb or similar)
- Test document with unique PII marker

**Test Steps**:
1. Create unique PII marker: "UNIQUE_TEST_PII_12345"
2. Process document containing marker
3. During processing: pause and search process memory for marker (should exist)
4. After processing complete: search memory again (should NOT exist)
5. Trigger garbage collection
6. Search memory third time (still should NOT exist)

**Expected Results**:
- Marker exists in memory during processing
- Marker zeroized after processing completes
- No traces found after GC
- Memory properly unlocked

**Test Data**: Document with unique marker string

---

### 3.3 Message Flow with Bidirectional PII Redaction

#### Test Case IT-MSG-001: Send User Query with PII
**Priority**: Critical (P0)
**Components**: ConversationManager, SecurePIIProcessor, LLMGateway
**Description**: Test user query containing PII gets tokenized

**Preconditions**:
- Conversation in "ready" status
- Existing token map from file processing

**Test Steps**:
1. User sends query: "What is John Doe's diagnosis?"
2. Verify query decrypted in secure memory
3. Verify PII detected in query: "John Doe"
4. Check if "John Doe" already in token map → reuse token
5. Verify query tokenized before sending to LLM
6. Verify LLM receives: "What is <<PII_NAME_a1b2>>'s diagnosis?"
7. Verify token map version incremented if new PII added
8. Store message with tokenized content

**Expected Results**:
- Query PII detected and tokenized
- Existing PII reuses same token (deterministic)
- New PII adds to token map (new version)
- LLM never sees plaintext PII
- Message stored with tokenized content

**Test Data**:
```
Query: "What is John Doe's diagnosis?"
Existing map: {"<<PII_NAME_a1b2>>": "John Doe"}
Expected: Reuse token, no version increment
```

---

#### Test Case IT-MSG-002: LLM Response with Tokens
**Priority**: Critical (P0)
**Components**: LLMGateway, MessageStore
**Description**: Test LLM response containing tokens is stored correctly

**Preconditions**:
- Message sent, LLM processing

**Test Steps**:
1. Wait for LLM response
2. Verify response contains tokens: "<<PII_NAME_a1b2>> has Type 2 Diabetes"
3. Store assistant message with tokenized content
4. Return response to client with encrypted token map
5. Client decrypts token map and replaces tokens
6. Verify user sees: "John Doe has Type 2 Diabetes"

**Expected Results**:
- LLM response stored as-is (tokenized)
- Token map sent to client (encrypted)
- Client successfully reconstructs plaintext
- No PII in server logs or database

**Test Data**: LLM response with embedded tokens

---

#### Test Case IT-MSG-003: Conversation History Resumption
**Priority**: High (P1)
**Components**: ConversationManager, MessageStore
**Description**: Test loading conversation history with multiple messages

**Preconditions**:
- Conversation with 10 previous messages
- Token map at version 5

**Test Steps**:
1. GET /conversations/{id}
2. Verify all 10 messages returned (tokenized)
3. Verify token_map included (encrypted)
4. Verify each message references correct token_map_version
5. Client decrypts token map
6. Client replaces tokens in all messages
7. Verify complete conversation history readable

**Expected Results**:
- All messages retrieved correctly
- Token map versions tracked per message
- Client can reconstruct full conversation
- Performance: < 500ms for 10 messages

**Test Data**: Conversation with varied message history

---

### 3.4 Event-Driven Synchronization

#### Test Case IT-EVENT-001: Handle file.deleted Event
**Priority**: Critical (P0)
**Components**: EventConsumer, Database, S3
**Description**: Test cleanup when original file deleted from main system

**Preconditions**:
- Conversation with file_123 processed
- Redacted file in S3

**Test Steps**:
1. Main system deletes file_123
2. Publish file.deleted event
3. Verify PII service receives event
4. Check conversation_files: entry for file_123 deleted
5. Check redacted_files: file deleted
6. Check S3: redacted file deleted
7. Check processed_events: event marked as processed
8. Verify conversation still exists (other files may be present)

**Expected Results**:
- File removed from conversation
- Redacted file deleted from database and S3
- Event marked as processed (idempotency)
- No errors or orphaned data
- Processing < 2 seconds

**Test Data**: file.deleted event payload

---

#### Test Case IT-EVENT-002: Handle file.updated Event
**Priority**: High (P1)
**Components**: EventConsumer, Database
**Description**: Test marking redacted file as stale when original updated

**Preconditions**:
- Conversation with file_123 v1
- Redacted file based on v1

**Test Steps**:
1. Main system updates file_123 to v2
2. Publish file.updated event
3. Verify PII service receives event
4. Check redacted_files: status changed to "stale"
5. Check invalidated_at timestamp set
6. Verify conversation still valid
7. Verify user can continue using stale version or regenerate

**Expected Results**:
- Redacted file marked as stale
- Conversation remains usable
- No automatic re-processing (manual trigger needed)
- Event processed idempotently

**Test Data**: file.updated event (v1 → v2)

---

#### Test Case IT-EVENT-003: Handle user.deleted Event
**Priority**: Critical (P0)
**Components**: EventConsumer, Database, S3
**Description**: Test complete user data deletion

**Preconditions**:
- User has 3 conversations, 5 redacted files

**Test Steps**:
1. Main system deletes user
2. Publish user.deleted event
3. Verify all user's conversations deleted (cascade to messages)
4. Verify all user's redacted files deleted
5. Verify all S3 objects for user deleted
6. Verify token maps deleted (cascade)
7. Check processed_events: event marked

**Expected Results**:
- All user data completely removed
- Cascading deletes work correctly
- S3 cleanup successful
- No orphaned records
- Processing < 5 seconds

**Test Data**: user.deleted event payload

---

#### Test Case IT-EVENT-004: Handle tenant.deleted Event
**Priority**: Critical (P0)
**Components**: EventConsumer, Database, S3
**Description**: Test complete tenant data deletion

**Preconditions**:
- Tenant has 50 conversations, 200 files

**Test Steps**:
1. Main system deletes tenant
2. Publish tenant.deleted event
3. Verify all conversations for tenant deleted
4. Verify all redacted files for tenant deleted
5. Verify entire S3 prefix deleted: `{tenant_id}/`
6. Verify audit logs for tenant deleted
7. Check no data remains for tenant_id

**Expected Results**:
- Complete tenant data removal
- S3 prefix deletion successful
- No orphaned data
- Processing completes (may take longer for large tenants)

**Test Data**: tenant.deleted event payload

---

#### Test Case IT-EVENT-005: Event Idempotency
**Priority**: High (P1)
**Components**: EventConsumer, Database
**Description**: Verify duplicate events are not processed twice

**Preconditions**: None

**Test Steps**:
1. Process file.deleted event with event_id = "evt_001"
2. Mark event as processed in processed_events table
3. Send same event again (duplicate delivery)
4. Verify event consumer checks processed_events
5. Verify event skipped (already processed)
6. Verify no database changes on second delivery

**Expected Results**:
- First event processed normally
- Duplicate event skipped
- processed_events table prevents re-processing
- No side effects from duplicate

**Test Data**: Same event sent twice

---

### 3.5 LLM Gateway Integration

#### Test Case IT-LLM-001: OpenAI Integration
**Priority**: Critical (P0)
**Components**: LLMGateway, OpenAI Adapter
**Description**: Test integration with OpenAI GPT-4

**Preconditions**:
- OpenAI API key configured
- Test conversation ready

**Test Steps**:
1. Send tokenized query to OpenAI GPT-4
2. Verify request format matches OpenAI API spec
3. Verify system prompt includes token explanation
4. Verify document context includes tokenized content
5. Receive response
6. Verify response parsed correctly
7. Check llm_metadata: model, tokens_used, finish_reason

**Expected Results**:
- Request successfully sent to OpenAI
- Response received and parsed
- Tokens preserved in response
- Metadata captured correctly
- Latency: < 2 seconds (OpenAI avg)

**Test Data**: Sample tokenized query and context

---

#### Test Case IT-LLM-002: Anthropic Claude Integration
**Priority**: High (P1)
**Components**: LLMGateway, Anthropic Adapter
**Description**: Test integration with Anthropic Claude

**Preconditions**:
- Anthropic API key configured

**Test Steps**:
1. Send tokenized query to Claude
2. Verify request format matches Anthropic API spec
3. Verify messages array structure
4. Receive response
5. Verify response parsed correctly
6. Check metadata captured

**Expected Results**:
- Claude integration works correctly
- Response format handled properly
- Metadata captured
- Latency: < 2 seconds

**Test Data**: Sample tokenized query

---

#### Test Case IT-LLM-003: Google Gemini Integration
**Priority**: High (P1)
**Components**: LLMGateway, Google Adapter
**Description**: Test integration with Google Gemini

**Preconditions**:
- Google API key configured

**Test Steps**:
1. Send tokenized query to Gemini
2. Verify request format matches Google API spec
3. Receive response
4. Verify response parsed correctly
5. Check metadata captured

**Expected Results**:
- Gemini integration works correctly
- Response handled properly
- Metadata captured
- Latency: < 2 seconds

**Test Data**: Sample tokenized query

---

#### Test Case IT-LLM-004: LLM Provider Failover
**Priority**: Medium (P2)
**Components**: LLMGateway
**Description**: Test automatic failover when primary LLM unavailable

**Preconditions**:
- Multiple LLM providers configured
- Primary set to OpenAI, fallback to Claude

**Test Steps**:
1. Simulate OpenAI API unavailable (503 error)
2. Verify gateway detects failure
3. Verify automatic failover to Claude
4. Verify query succeeds on Claude
5. Verify user notified of provider change
6. Check logs for failover event

**Expected Results**:
- Failure detected within 5 seconds
- Automatic failover to backup provider
- Query succeeds
- User experience minimally impacted
- Audit log records failover

**Test Data**: Query that triggers failover scenario

---

## 4. API Tests

### 4.1 Conversation Endpoints

#### Test Case API-CONV-001: POST /conversations - Create Conversation Success
**Priority**: Critical (P0)
**Endpoint**: `POST /api/v1/conversations`
**Description**: Test successful conversation creation

**Preconditions**:
- Valid authentication token
- File uploaded to main system
- ServiceShare created

**Test Steps**:
1. Send POST request with valid payload:
   ```json
   {
     "file_ids": ["file-123"],
     "llm_provider": "openai",
     "llm_model": "gpt-4-turbo",
     "pii_policy": {
       "detect_names": true,
       "detect_nric": true,
       "detect_email": true,
       "min_confidence": 0.8
     },
     "service_shares": [{
       "file_id": "file-123",
       "wrapped_key": "...",
       "kem_ciphertexts": {...},
       "signature": {...}
     }]
   }
   ```
2. Verify response status: 202 Accepted
3. Verify response body contains:
   - conversation_id (UUID)
   - status: "processing"
   - files array with file details

**Expected Results**:
- Status: 202 Accepted
- Valid conversation_id returned
- Response time: < 200ms
- Database record created

**Test Data**: Valid request payload

---

#### Test Case API-CONV-002: POST /conversations - Invalid ServiceShare
**Priority**: High (P1)
**Endpoint**: `POST /api/v1/conversations`
**Description**: Test rejection of invalid ServiceShare signature

**Preconditions**: Valid auth token

**Test Steps**:
1. Send POST with tampered ServiceShare signature
2. Verify response status: 403 Forbidden
3. Verify error message: "Invalid ServiceShare signature"

**Expected Results**:
- Status: 403 Forbidden
- Error message clear and specific
- No conversation created
- No processing attempted

**Test Data**: ServiceShare with invalid signature

---

#### Test Case API-CONV-003: POST /conversations - Missing Required Fields
**Priority**: High (P1)
**Endpoint**: `POST /api/v1/conversations`
**Description**: Test validation of required fields

**Preconditions**: Valid auth token

**Test Steps**:
1. Send POST without file_ids field
2. Verify 400 Bad Request
3. Send POST without llm_provider
4. Verify 400 Bad Request
5. Send POST without service_shares
6. Verify 400 Bad Request

**Expected Results**:
- Status: 400 Bad Request
- Error message specifies missing field
- No partial state created

**Test Data**: Invalid payloads missing fields

---

#### Test Case API-CONV-004: GET /conversations/{id}/status - Poll Status
**Priority**: Critical (P0)
**Endpoint**: `GET /api/v1/conversations/{id}/status`
**Description**: Test polling conversation processing status

**Preconditions**:
- Conversation created and processing

**Test Steps**:
1. Create conversation (returns conversation_id)
2. Immediately GET /conversations/{id}/status
3. Verify status: "processing", progress: 0-100
4. Poll every 2 seconds
5. Verify progress increases
6. Wait for status: "ready"
7. Verify files array shows all files completed

**Expected Results**:
- Status transitions: processing → ready
- Progress increments appropriately
- files array shows individual file statuses
- total_pii_protected populated when ready

**Test Data**: Conversation in processing state

---

#### Test Case API-CONV-005: GET /conversations - List User Conversations
**Priority**: High (P1)
**Endpoint**: `GET /api/v1/conversations`
**Description**: Test listing user's conversation history

**Preconditions**:
- User has 25 conversations

**Test Steps**:
1. GET /conversations?limit=20
2. Verify 20 conversations returned
3. Verify has_more: true
4. GET /conversations?limit=20&offset=20
5. Verify remaining 5 returned
6. Test filtering: GET /conversations?status=ready
7. Verify only ready conversations returned

**Expected Results**:
- Pagination works correctly
- Filtering by status works
- Conversations sorted by created_at DESC
- Response time: < 300ms

**Test Data**: User with multiple conversations

---

#### Test Case API-CONV-006: GET /conversations/{id} - Get Conversation Details
**Priority**: Critical (P0)
**Endpoint**: `GET /api/v1/conversations/{id}`
**Description**: Test retrieving full conversation with messages

**Preconditions**:
- Conversation with 5 messages exists

**Test Steps**:
1. GET /conversations/{id}
2. Verify response includes:
   - Conversation metadata
   - files array with redacted_file_ids
   - messages array (all tokenized)
   - token_map (encrypted)
3. Verify messages in correct order (sequence_num)
4. Verify token_map has correct version

**Expected Results**:
- Complete conversation data returned
- Token map included (encrypted)
- Messages in order
- Response time: < 500ms
- All PII in tokenized form

**Test Data**: Conversation with message history

---

#### Test Case API-CONV-007: DELETE /conversations/{id} - Archive Conversation
**Priority**: Medium (P2)
**Endpoint**: `DELETE /api/v1/conversations/{id}`
**Description**: Test archiving conversation

**Preconditions**:
- Conversation exists

**Test Steps**:
1. DELETE /conversations/{id}?mode=archive
2. Verify status: 200 OK
3. Verify conversation.status = "archived"
4. Verify conversation still retrievable
5. Verify files not deleted

**Expected Results**:
- Conversation marked as archived
- Data preserved
- Not shown in default list

**Test Data**: Any conversation

---

#### Test Case API-CONV-008: DELETE /conversations/{id} - Delete Conversation
**Priority**: High (P1)
**Endpoint**: `DELETE /api/v1/conversations/{id}`
**Description**: Test permanently deleting conversation

**Preconditions**:
- Conversation exists

**Test Steps**:
1. DELETE /conversations/{id}?mode=delete
2. Verify status: 200 OK
3. Verify conversation deleted from database
4. Verify messages deleted (cascade)
5. Verify token_map deleted (cascade)
6. Verify redacted files deleted
7. Verify S3 objects deleted

**Expected Results**:
- Complete deletion (conversation + children)
- S3 cleanup successful
- GET /conversations/{id} returns 404

**Test Data**: Any conversation

---

### 4.2 Message Endpoints

#### Test Case API-MSG-001: POST /conversations/{id}/messages - Send Message
**Priority**: Critical (P0)
**Endpoint**: `POST /api/v1/conversations/{id}/messages`
**Description**: Test sending user message and receiving AI response

**Preconditions**:
- Conversation in "ready" status

**Test Steps**:
1. Encrypt query: "What is the patient's diagnosis?"
2. POST /conversations/{id}/messages with:
   ```json
   {
     "encrypted_query": "...",
     "query_nonce": "...",
     "session_key_wrapped": "..."
   }
   ```
3. Verify status: 200 OK
4. Verify response includes:
   - message_id
   - user_message (tokenized)
   - assistant_message (tokenized)
   - token_map (encrypted, updated if new PII)

**Expected Results**:
- Status: 200 OK
- Both messages stored in database
- Token map updated if new PII in query
- Response time: < 3 seconds
- LLM metadata captured

**Test Data**: Encrypted user query

---

#### Test Case API-MSG-002: POST /conversations/{id}/messages - Query with New PII
**Priority**: High (P1)
**Endpoint**: `POST /api/v1/conversations/{id}/messages`
**Description**: Test query containing PII not in original documents

**Preconditions**:
- Conversation ready
- Token map v1 exists (from documents)

**Test Steps**:
1. Send query: "What about Dr. Sarah Smith's notes?"
2. Verify "Dr. Sarah Smith" detected as new PII
3. Verify token map version incremented to v2
4. Verify new token added to map
5. Verify message.token_map_version = 2

**Expected Results**:
- New PII detected in query
- Token map updated (version++)
- Deterministic token assigned
- Updated map returned to client

**Test Data**: Query with new name

---

#### Test Case API-MSG-003: POST /conversations/{id}/messages - Invalid Conversation
**Priority**: Medium (P2)
**Endpoint**: `POST /api/v1/conversations/{id}/messages`
**Description**: Test sending message to non-existent conversation

**Preconditions**: None

**Test Steps**:
1. POST /conversations/invalid-uuid/messages
2. Verify status: 404 Not Found
3. Verify error: "Conversation not found"

**Expected Results**:
- Status: 404
- No processing attempted
- Clear error message

**Test Data**: Invalid conversation_id

---

#### Test Case API-MSG-004: POST /conversations/{id}/messages - Conversation Not Ready
**Priority**: Medium (P2)
**Endpoint**: `POST /api/v1/conversations/{id}/messages`
**Description**: Test sending message before files processed

**Preconditions**:
- Conversation in "processing" status

**Test Steps**:
1. POST message to processing conversation
2. Verify status: 409 Conflict
3. Verify error: "Conversation not ready"

**Expected Results**:
- Status: 409 Conflict
- Informative error message
- Suggest polling status endpoint

**Test Data**: Conversation still processing

---

### 4.3 Redacted File Endpoints

#### Test Case API-FILE-001: GET /redacted-files/{id}/download - Download Success
**Priority**: High (P1)
**Endpoint**: `GET /api/v1/redacted-files/{id}/download`
**Description**: Test downloading encrypted redacted file

**Preconditions**:
- Redacted file exists in S3
- User owns the file

**Test Steps**:
1. GET /redacted-files/{id}/download
2. Verify status: 200 OK
3. Verify Content-Type: application/octet-stream
4. Verify Content-Disposition header includes filename
5. Verify file size matches database record
6. Verify content is encrypted (not plaintext)

**Expected Results**:
- Status: 200 OK
- Encrypted file bytes returned
- Correct filename in header
- Response time: < 2 seconds

**Test Data**: Valid redacted_file_id

---

#### Test Case API-FILE-002: GET /redacted-files/{id}/download - Unauthorized
**Priority**: High (P1)
**Endpoint**: `GET /api/v1/redacted-files/{id}/download`
**Description**: Test access control for file download

**Preconditions**:
- Redacted file owned by user A
- User B authenticated

**Test Steps**:
1. User B attempts GET /redacted-files/{id}/download
2. Verify status: 403 Forbidden
3. Verify error: "Access denied"

**Expected Results**:
- Status: 403
- No file content leaked
- Audit log records attempt

**Test Data**: File owned by different user

---

#### Test Case API-FILE-003: POST /conversations/{conv_id}/files/{file_id}/regenerate
**Priority**: High (P1)
**Endpoint**: `POST /api/v1/conversations/{conv_id}/files/{file_id}/regenerate`
**Description**: Test regenerating stale redacted file

**Preconditions**:
- Original file updated (v1 → v2)
- Redacted file marked as stale
- Fresh ServiceShare for v2

**Test Steps**:
1. POST with new ServiceShare for updated file
2. Verify status: 202 Accepted
3. Verify new redacted_file_id returned
4. Verify processing status: "processing"
5. Poll until completed
6. Verify new redacted file created
7. Verify token map updated if PII changed

**Expected Results**:
- Status: 202 Accepted
- New redacted file generated
- Token map updated appropriately
- Old redacted file invalidated
- Processing time similar to initial

**Test Data**: Updated file with ServiceShare

---

### 4.4 Legacy AI Query Endpoint (Stateless)

#### Test Case API-LEGACY-001: POST /ai/query - Stateless Query Success
**Priority**: Medium (P2)
**Endpoint**: `POST /api/v1/ai/query`
**Description**: Test one-off AI query without conversation

**Preconditions**:
- File available
- ServiceShare valid

**Test Steps**:
1. POST /ai/query with file ServiceShare and encrypted query
2. Verify status: 200 OK
3. Verify response includes:
   - session_id
   - tokenized_response
   - encrypted_token_map
   - entities_summary
   - processing_proof
   - llm_metadata

**Expected Results**:
- Status: 200 OK
- Token map encrypted and returned
- Processing proof signed by service
- No conversation created (stateless)
- Response time: < 3 seconds

**Test Data**: Valid query payload

---

#### Test Case API-LEGACY-002: POST /ai/query - Expired ServiceShare
**Priority**: High (P1)
**Endpoint**: `POST /api/v1/ai/query`
**Description**: Test rejection of expired ServiceShare

**Preconditions**:
- ServiceShare created with expires_at in past

**Test Steps**:
1. POST /ai/query with expired ServiceShare
2. Verify status: 403 Forbidden
3. Verify error: "ServiceShare expired"
4. Verify no processing attempted

**Expected Results**:
- Status: 403
- Clear error message
- No file decryption attempted

**Test Data**: Expired ServiceShare

---

### 4.5 Service Registration Endpoint

#### Test Case API-SVC-001: GET /services/pii-redaction/public-keys
**Priority**: High (P1)
**Endpoint**: `GET /api/v1/services/pii-redaction/public-keys`
**Description**: Test retrieving service public keys for ServiceShare creation

**Preconditions**: None (public endpoint)

**Test Steps**:
1. GET /services/pii-redaction/public-keys
2. Verify status: 200 OK
3. Verify response includes:
   - service_id
   - service_type: "pii_redaction"
   - public_keys (ml_kem, ml_dsa, kaz_kem, kaz_sign)
   - version
   - capabilities

**Expected Results**:
- Status: 200 OK
- All public keys present and valid format
- Capabilities list accurate
- Response cacheable

**Test Data**: N/A

---

### 4.6 LLM Provider Configuration

#### Test Case API-LLM-001: GET /ai/providers - List Providers
**Priority**: Medium (P2)
**Endpoint**: `GET /api/v1/ai/providers`
**Description**: Test listing configured LLM providers for tenant

**Preconditions**:
- Tenant has OpenAI configured

**Test Steps**:
1. GET /ai/providers
2. Verify status: 200 OK
3. Verify providers array includes:
   - provider: "openai", enabled: true, has_api_key: true
   - Other providers with enabled: false

**Expected Results**:
- Status: 200 OK
- Accurate provider status
- API keys not exposed (only has_api_key boolean)

**Test Data**: Tenant with partial LLM config

---

#### Test Case API-LLM-002: POST /ai/providers/{provider}/configure
**Priority**: Medium (P2)
**Endpoint**: `POST /api/v1/ai/providers/{provider}/configure`
**Description**: Test configuring LLM provider for tenant

**Preconditions**:
- Admin user authenticated

**Test Steps**:
1. POST /ai/providers/anthropic/configure with:
   ```json
   {
     "encrypted_api_key": "...",
     "api_key_nonce": "...",
     "config": {
       "default_model": "claude-3-opus",
       "max_tokens": 4000,
       "temperature": 0.7
     }
   }
   ```
2. Verify status: 200 OK
3. Verify provider enabled
4. Verify API key stored encrypted
5. Test AI query uses newly configured provider

**Expected Results**:
- Status: 200 OK
- Provider successfully configured
- API key encrypted in database
- Immediately usable for queries

**Test Data**: Valid API key (encrypted)

---

## 5. Security Tests

### 5.1 Secure Memory Validation

#### Test Case SEC-MEM-001: Memory Swap Prevention
**Priority**: Critical (P0)
**Component**: Secure Memory Arena
**Description**: Verify sensitive memory never swapped to disk

**Preconditions**:
- System under memory pressure (trigger swapping)
- PII processing active

**Test Steps**:
1. Fill system memory to force swapping
2. Process document with known PII
3. Check `/proc/meminfo` for SwapCached
4. Search swap partition for PII markers
5. Verify no PII found in swap

**Expected Results**:
- mlock successfully prevents swapping
- No PII appears in swap space
- System handles memory pressure gracefully

**Test Data**: Document with unique markers

---

#### Test Case SEC-MEM-002: Zeroization Timing Attack Resistance
**Priority**: Critical (P0)
**Component**: Zeroization Implementation
**Description**: Verify zeroization not optimized away by compiler

**Preconditions**: Access to compiled binary

**Test Steps**:
1. Inspect compiled Rust code (objdump/disassembly)
2. Verify memset_s or explicit_bzero used (not memset)
3. Verify volatile writes for zero operations
4. Test zeroization occurs even in optimized builds
5. Verify no compiler optimization removes zeroization

**Expected Results**:
- Secure zeroization primitives used
- Zeroization present in optimized builds
- Memory wiped even if "unused" after

**Test Data**: Compiled binary analysis

---

#### Test Case SEC-MEM-003: Core Dump Disabled
**Priority**: Critical (P0)
**Component**: Process Security
**Description**: Verify core dumps cannot leak sensitive memory

**Preconditions**: None

**Test Steps**:
1. Start PII service
2. Verify prctl(PR_GET_DUMPABLE) == 0
3. Send SIGSEGV to process (controlled crash)
4. Verify no core dump file created
5. Check `/var/crash` and `/tmp` for dumps

**Expected Results**:
- Core dumps disabled
- Crash does not produce dump file
- No memory leaked via core dumps

**Test Data**: Intentional crash signal

---

#### Test Case SEC-MEM-004: Memory Inspection Attack
**Priority**: Critical (P0)
**Component**: Secure Memory
**Description**: Verify memory cannot be read by another process

**Preconditions**:
- PII service running as non-root
- Attacker process with same user

**Test Steps**:
1. Process document with unique PII marker
2. Attempt to read PII service memory via `/proc/{pid}/mem`
3. Verify access denied (EPERM)
4. Attempt ptrace attach
5. Verify blocked by yama ptrace_scope or similar

**Expected Results**:
- Memory read attempts fail
- ptrace blocked
- No cross-process memory access

**Test Data**: Attacker process attempts

---

### 5.2 PII Leakage Prevention

#### Test Case SEC-LEAK-001: No PII in Logs
**Priority**: Critical (P0)
**Component**: Logging System
**Description**: Verify plaintext PII never appears in application logs

**Preconditions**: Debug logging enabled

**Test Steps**:
1. Process document containing: "John Doe", "901231-14-5678"
2. Grep all log files for "John Doe"
3. Grep for "901231-14-5678"
4. Verify only tokenized versions appear
5. Check Elixir logs, Rust logs, system logs

**Expected Results**:
- No plaintext PII in any logs
- Only tokens logged: `<<PII_NAME_a1b2>>`
- Error logs also sanitized

**Test Data**: Document with searchable PII

---

#### Test Case SEC-LEAK-002: No PII in Database
**Priority**: Critical (P0)
**Component**: Database Storage
**Description**: Verify no plaintext PII stored in database

**Preconditions**: Conversation processed

**Test Steps**:
1. Process document with PII
2. Dump entire database to SQL file
3. Search SQL dump for plaintext PII values
4. Verify only encrypted blobs and tokens present
5. Check messages.content_tokenized is tokenized
6. Check token_maps are encrypted blobs

**Expected Results**:
- No plaintext PII in database
- Only encrypted data and tokens
- Token maps encrypted

**Test Data**: Database dump analysis

---

#### Test Case SEC-LEAK-003: No PII in LLM Requests
**Priority**: Critical (P0)
**Component**: LLM Gateway
**Description**: Verify LLM providers never receive plaintext PII

**Preconditions**: Network traffic capture enabled

**Test Steps**:
1. Capture HTTPS traffic to LLM API (via proxy or SSL interception)
2. Send query with PII to LLM
3. Inspect captured request body
4. Verify only tokens sent: `<<PII_NAME_a1b2>>`
5. Verify no plaintext PII in prompt or context

**Expected Results**:
- All PII tokenized in LLM requests
- System prompt explains tokens
- No plaintext leaked to third-party

**Test Data**: Network traffic capture

---

#### Test Case SEC-LEAK-004: No PII in Error Messages
**Priority**: High (P1)
**Component**: Error Handling
**Description**: Verify error messages don't expose PII

**Preconditions**: Various error scenarios

**Test Steps**:
1. Trigger validation error with PII in query
2. Verify error message sanitized
3. Trigger decryption failure
4. Verify error doesn't include plaintext
5. Check all error responses to client

**Expected Results**:
- Errors don't contain plaintext PII
- Generic error messages
- Detailed errors only in server logs (tokenized)

**Test Data**: Various error triggers

---

### 5.3 Cryptographic Security

#### Test Case SEC-CRYPTO-001: ServiceShare Replay Attack Prevention
**Priority**: Critical (P0)
**Component**: ServiceShare Validation
**Description**: Verify ServiceShare cannot be reused

**Preconditions**: Valid ServiceShare

**Test Steps**:
1. Create ServiceShare for file_123
2. Use ServiceShare for AI query → succeeds
3. Mark ServiceShare as used (used_at timestamp)
4. Attempt to reuse same ServiceShare → should fail
5. Verify error: "ServiceShare already used"

**Expected Results**:
- First use succeeds
- Subsequent uses fail
- used_at timestamp prevents replay
- Audit log records both attempts

**Test Data**: Single ServiceShare used twice

---

#### Test Case SEC-CRYPTO-002: ServiceShare Expiration Enforcement
**Priority**: Critical (P0)
**Component**: ServiceShare Validation
**Description**: Verify expired ServiceShare rejected

**Preconditions**: ServiceShare with short expiry

**Test Steps**:
1. Create ServiceShare with expires_at = now + 5 seconds
2. Immediately use → succeeds
3. Wait 10 seconds
4. Attempt to use → should fail
5. Verify error: "ServiceShare expired"

**Expected Results**:
- Expiry strictly enforced
- Expired shares rejected
- Clock skew tolerance minimal (< 30s)

**Test Data**: ServiceShare with known expiry

---

#### Test Case SEC-CRYPTO-003: PQC Algorithm Validation
**Priority**: Critical (P0)
**Component**: Cryptography
**Description**: Verify post-quantum algorithms properly implemented

**Preconditions**: Test vectors from NIST

**Test Steps**:
1. Test ML-KEM encapsulation/decapsulation with known vectors
2. Test ML-DSA sign/verify with known vectors
3. Test KAZ-KEM (Kyber) with known vectors
4. Test KAZ-Sign (Dilithium) with known vectors
5. Verify all match reference implementation results

**Expected Results**:
- All test vectors pass
- Algorithms correctly implemented
- No implementation bugs

**Test Data**: NIST PQC test vectors

---

#### Test Case SEC-CRYPTO-004: AES-GCM Authentication Tag Validation
**Priority**: Critical (P0)
**Component**: Token Map Encryption
**Description**: Verify GCM authentication prevents tampering

**Preconditions**: Encrypted token map

**Test Steps**:
1. Encrypt token map with AES-256-GCM
2. Tamper with ciphertext (flip 1 bit)
3. Attempt decryption → should fail
4. Verify error: "Authentication tag verification failed"
5. Ensure no partial plaintext leaked

**Expected Results**:
- Tampered ciphertext rejected
- Authentication tag protects integrity
- No decryption without valid tag

**Test Data**: Tampered ciphertext

---

### 5.4 Access Control

#### Test Case SEC-ACCESS-001: Cross-Tenant Data Isolation
**Priority**: Critical (P0)
**Component**: Multi-Tenancy
**Description**: Verify tenant A cannot access tenant B's data

**Preconditions**:
- User A in tenant_1
- User B in tenant_2

**Test Steps**:
1. User A creates conversation
2. User B attempts GET /conversations/{user_a_conv_id}
3. Verify 403 Forbidden
4. User B attempts POST message to user A's conversation
5. Verify 403 Forbidden
6. Check database queries include tenant_id filter

**Expected Results**:
- All cross-tenant access denied
- Tenant ID enforced in all queries
- No data leakage

**Test Data**: Multi-tenant setup

---

#### Test Case SEC-ACCESS-002: User Authorization
**Priority**: High (P1)
**Component**: Access Control
**Description**: Verify users can only access their own conversations

**Preconditions**:
- User A and User B in same tenant

**Test Steps**:
1. User A creates conversation
2. User B (same tenant) attempts access
3. Verify 403 Forbidden
4. Verify user_id checked in addition to tenant_id

**Expected Results**:
- User-level access control enforced
- Same-tenant users isolated
- Authorization checks comprehensive

**Test Data**: Same-tenant users

---

#### Test Case SEC-ACCESS-003: ServiceShare Signature Validation
**Priority**: Critical (P0)
**Component**: ServiceShare Validation
**Description**: Verify tampered signatures rejected

**Preconditions**: Valid ServiceShare

**Test Steps**:
1. Create valid ServiceShare
2. Tamper with wrapped_key field
3. Attempt to use → verify signature fails
4. Tamper with signature itself
5. Verify signature verification fails
6. Test with mismatched user keys

**Expected Results**:
- All tampering detected
- Signature verification strict
- No unauthorized access via forged ServiceShare

**Test Data**: Tampered ServiceShare variants

---

### 5.5 Vulnerability Testing

#### Test Case SEC-VULN-001: SQL Injection Prevention
**Priority**: Critical (P0)
**Component**: Database Queries
**Description**: Test resistance to SQL injection attacks

**Preconditions**: API accessible

**Test Steps**:
1. Attempt SQL injection in conversation title: `'; DROP TABLE conversations; --`
2. Attempt in query parameters: `?status=ready' OR '1'='1`
3. Verify all queries parameterized
4. Verify no SQL errors exposed
5. Check database unchanged

**Expected Results**:
- No SQL injection possible
- Parameterized queries throughout
- Error messages generic

**Test Data**: Standard SQL injection payloads

---

#### Test Case SEC-VULN-002: Path Traversal Prevention
**Priority**: High (P1)
**Component**: File Download
**Description**: Test resistance to path traversal attacks

**Preconditions**: API accessible

**Test Steps**:
1. Attempt GET /redacted-files/../../etc/passwd
2. Attempt GET /redacted-files/%2e%2e%2f%2e%2e%2fetc%2fpasswd
3. Verify path validation rejects attempts
4. Verify only valid UUIDs accepted

**Expected Results**:
- All path traversal attempts fail
- Only valid UUIDs accepted as file IDs
- No file system access outside S3

**Test Data**: Path traversal payloads

---

#### Test Case SEC-VULN-003: Denial of Service - Large Files
**Priority**: High (P1)
**Component**: File Processing
**Description**: Test handling of excessively large files

**Preconditions**: Max file size configured

**Test Steps**:
1. Attempt to process file > max_file_size (e.g., 100MB)
2. Verify rejection before decryption
3. Verify error: "File too large"
4. Check no memory exhaustion
5. Verify service remains responsive

**Expected Results**:
- Large files rejected early
- No resource exhaustion
- Service stable

**Test Data**: 100MB+ file

---

#### Test Case SEC-VULN-004: Denial of Service - Rate Limiting
**Priority**: High (P1)
**Component**: API Rate Limiting
**Description**: Test rate limiting prevents abuse

**Preconditions**: Rate limits configured

**Test Steps**:
1. Send 100 requests/second to POST /conversations
2. Verify rate limit kicks in
3. Verify 429 Too Many Requests response
4. Verify Retry-After header present
5. Wait and verify service recovers

**Expected Results**:
- Rate limiting enforces limits
- Status 429 with Retry-After
- Service protected from abuse

**Test Data**: High request volume

---

## 6. Performance Tests

### 6.1 Latency Benchmarks

#### Test Case PERF-LAT-001: PII Detection Latency
**Priority**: Critical (P0)
**Component**: PII Detection Pipeline
**Description**: Verify PII detection meets < 500ms requirement

**Preconditions**:
- Warm cache (models loaded)
- Typical document size (5KB)

**Test Steps**:
1. Process 100 documents through PII detection
2. Measure latency for each:
   - Tier 1 (Regex): individual time
   - Tier 2 (Presidio): individual time
   - Tier 3 (Phi-3): individual time
   - Tier 4 (Mistral): conditional time
   - Total pipeline time
3. Calculate p50, p95, p99 latencies

**Expected Results**:
- p50: < 300ms
- p95: < 500ms
- p99: < 750ms
- Tier 1: < 10ms
- Tier 2: < 50ms
- Tier 3: < 100ms

**Test Data**: 100 varied documents

---

#### Test Case PERF-LAT-002: Full AI Query Latency
**Priority**: Critical (P0)
**Component**: End-to-End Query
**Description**: Verify total query time < 3 seconds (excluding LLM call)

**Preconditions**: LLM available

**Test Steps**:
1. Send 50 AI queries
2. Measure breakdown:
   - Client prep: time
   - Network: time
   - ServiceShare validation: time
   - Decryption: time
   - PII detection: time
   - Tokenization: time
   - LLM call: time (separately)
   - Response packaging: time
   - Total (excluding LLM): time
3. Calculate percentiles

**Expected Results**:
- Total (excluding LLM): < 1 second (p95)
- Full end-to-end: < 3 seconds (p95)
- LLM dominates latency (expected)

**Test Data**: 50 typical queries

---

#### Test Case PERF-LAT-003: Conversation Creation Latency
**Priority**: High (P1)
**Component**: Conversation Creation
**Description**: Measure conversation creation API response time

**Preconditions**: None

**Test Steps**:
1. Create 100 conversations (single file each)
2. Measure API response time (POST /conversations)
3. Note: Processing happens async, measure API latency only
4. Calculate p50, p95, p99

**Expected Results**:
- API response: < 200ms (p95)
- Processing completes: < 30s (p95)

**Test Data**: 100 test files

---

#### Test Case PERF-LAT-004: Message Retrieval Latency
**Priority**: Medium (P2)
**Component**: Message History
**Description**: Measure conversation retrieval with messages

**Preconditions**:
- Conversations with varying message counts (1, 10, 50, 100)

**Test Steps**:
1. GET /conversations/{id} for each size
2. Measure latency
3. Plot latency vs message count
4. Verify sub-linear growth (indexed queries)

**Expected Results**:
- 10 messages: < 200ms
- 50 messages: < 400ms
- 100 messages: < 600ms
- No N+1 queries

**Test Data**: Conversations with varied history

---

### 6.2 Throughput Tests

#### Test Case PERF-THR-001: Concurrent Conversation Processing
**Priority**: High (P1)
**Component**: Redaction Pipeline
**Description**: Test concurrent file processing throughput

**Preconditions**: Multi-core server

**Test Steps**:
1. Create 20 conversations simultaneously
2. Each with 3 files (60 files total)
3. Monitor processing:
   - Files processed concurrently
   - CPU utilization
   - Memory usage
4. Measure total time to complete all

**Expected Results**:
- All 60 files complete within 5 minutes
- CPU utilization > 70% (parallel processing)
- No resource exhaustion
- All conversations reach "ready" state

**Test Data**: 20 conversations x 3 files

---

#### Test Case PERF-THR-002: Sustained Query Load
**Priority**: High (P1)
**Component**: Message Processing
**Description**: Test sustained query throughput

**Preconditions**: LLM available

**Test Steps**:
1. Generate 100 queries/minute for 10 minutes (1000 total)
2. Monitor:
   - Queries per second
   - Error rate
   - p95 latency
   - Resource usage
3. Verify system stability

**Expected Results**:
- All 1000 queries succeed
- Error rate: < 0.1%
- p95 latency stable
- Memory usage stable (no leaks)

**Test Data**: 1000 generated queries

---

#### Test Case PERF-THR-003: Database Connection Pool
**Priority**: Medium (P2)
**Component**: Database
**Description**: Test database connection pool under load

**Preconditions**: Connection pool size: 20

**Test Steps**:
1. Generate 100 concurrent requests
2. Monitor database connections
3. Verify pool doesn't exhaust
4. Check for connection timeouts
5. Verify connection reuse

**Expected Results**:
- No connection exhaustion
- Pool efficiently reused
- No timeouts
- Max connections: ~20

**Test Data**: High concurrent load

---

### 6.3 Resource Usage Tests

#### Test Case PERF-RES-001: Memory Usage Under Load
**Priority**: High (P1)
**Component**: System Memory
**Description**: Monitor memory usage during sustained operation

**Preconditions**: Fresh service start

**Test Steps**:
1. Baseline memory usage (idle)
2. Process 100 conversations
3. Monitor memory growth
4. Force garbage collection
5. Check for memory leaks
6. Verify memory stabilizes

**Expected Results**:
- Idle: < 500MB
- Peak: < 20GB (with models loaded)
- No continuous growth (no leaks)
- Memory releases after GC

**Test Data**: 100 conversations over time

---

#### Test Case PERF-RES-002: CPU Utilization
**Priority**: Medium (P2)
**Component**: CPU
**Description**: Monitor CPU usage patterns

**Preconditions**: None

**Test Steps**:
1. Idle CPU baseline
2. Process 10 concurrent conversations
3. Monitor CPU per stage:
   - Decryption (Rust): expected high
   - PII detection: expected high
   - LLM call: expected low (network wait)
4. Verify efficient CPU usage

**Expected Results**:
- Idle: < 5%
- Active processing: 60-80% (parallel)
- No single-thread bottlenecks

**Test Data**: 10 concurrent operations

---

#### Test Case PERF-RES-003: GPU Utilization (Ollama Models)
**Priority**: Medium (P2)
**Component**: GPU for SLMs
**Description**: Monitor GPU usage for Phi-3 and Mistral

**Preconditions**: GPU available

**Test Steps**:
1. Process documents requiring SLM calls
2. Monitor GPU utilization (nvidia-smi)
3. Verify Phi-3 uses GPU
4. Verify Mistral uses GPU
5. Check for GPU memory leaks

**Expected Results**:
- GPU utilized during SLM inference
- GPU memory stable
- Efficient batch processing

**Test Data**: Documents requiring classification

---

### 6.4 Scalability Tests

#### Test Case PERF-SCALE-001: Large Conversation (Many Files)
**Priority**: Medium (P2)
**Component**: Conversation Processing
**Description**: Test conversation with 50 files

**Preconditions**: 50 test files available

**Test Steps**:
1. Create conversation with 50 files
2. Monitor processing time
3. Verify all files processed
4. Check token map size
5. Verify conversation usable

**Expected Results**:
- All 50 files processed successfully
- Total time: < 10 minutes
- Token map handles large size
- Queries work normally

**Test Data**: 50 varied files

---

#### Test Case PERF-SCALE-002: Large Token Map
**Priority**: Medium (P2)
**Component**: Token Map Handling
**Description**: Test handling of token map with 10,000+ tokens

**Preconditions**: Documents with extensive PII

**Test Steps**:
1. Process documents totaling 10,000 PII entities
2. Verify token map created
3. Measure encryption/decryption time
4. Verify client can handle large map
5. Test query performance

**Expected Results**:
- Token map handles 10,000+ entries
- Encryption: < 100ms
- Decryption (client): < 100ms
- Queries still performant

**Test Data**: High-PII documents

---

#### Test Case PERF-SCALE-003: Long Conversation History
**Priority**: Low (P3)
**Component**: Message History
**Description**: Test conversation with 500 messages

**Preconditions**: Conversation with history

**Test Steps**:
1. Create conversation with 500 messages
2. Test retrieval time
3. Verify pagination works
4. Test scrolling performance
5. Check database query efficiency

**Expected Results**:
- Retrieval with pagination: < 500ms
- Pagination prevents full load
- Queries optimized (LIMIT/OFFSET)

**Test Data**: Long-running conversation

---

## 7. End-to-End Tests

### 7.1 Complete User Workflows

#### Test Case E2E-001: First-Time User - Complete Flow
**Priority**: Critical (P0)
**Description**: Test complete user journey from file upload to AI chat

**Preconditions**:
- New user account
- Mobile app installed

**Test Steps**:
1. User uploads medical_record.pdf to SecureSharing
2. User taps "Ask AI" on file
3. User selects LLM provider (OpenAI)
4. System creates conversation (background processing)
5. User sees progress indicator
6. System detects PII: NAME, NRIC, DOB, EMAIL
7. System creates redacted file
8. Conversation becomes "ready"
9. User types query: "What is the patient's diagnosis?"
10. System detects "patient" (no PII), sends to LLM
11. LLM responds with tokens
12. Client decrypts token map and shows: "John Doe has Type 2 Diabetes"
13. User continues conversation

**Expected Results**:
- Seamless end-to-end flow
- No errors or crashes
- PII properly protected
- User sees natural responses
- Total time (upload → first response): < 2 minutes

**Test Data**: medical_record.pdf with known content

---

#### Test Case E2E-002: Multi-File Document Analysis
**Priority**: High (P1)
**Description**: Test analyzing multiple related documents

**Preconditions**: User has 5 related documents

**Test Steps**:
1. User selects folder with 5 financial documents
2. User taps "Ask AI" on folder
3. System creates conversation with all 5 files
4. Processing shows progress per file
5. All files reach "completed"
6. User asks: "What is the total balance across all accounts?"
7. LLM synthesizes information from all 5 files
8. User receives answer with account numbers tokenized
9. User downloads one redacted file to verify

**Expected Results**:
- All 5 files processed correctly
- LLM has context from all files
- Cross-file information synthesis works
- Redacted files downloadable and valid

**Test Data**: 5 related financial documents

---

#### Test Case E2E-003: Resume Previous Conversation
**Priority**: High (P1)
**Description**: Test resuming conversation from history

**Preconditions**:
- Conversation with 10 messages created yesterday

**Test Steps**:
1. User opens "AI Conversations" history
2. User selects yesterday's conversation
3. System loads full message history
4. Client decrypts token map
5. User sees full conversation with PII restored
6. User sends new query
7. System reuses existing token map
8. Conversation continues naturally

**Expected Results**:
- Full history loads correctly
- All PII properly restored
- New messages use same token map
- Seamless continuation

**Test Data**: Existing conversation

---

#### Test Case E2E-004: Handle File Update During Conversation
**Priority**: Medium (P2)
**Description**: Test workflow when original file updated mid-conversation

**Preconditions**:
- Active conversation with file_123

**Test Steps**:
1. User is chatting about report_v1.pdf
2. User edits original file (uploads report_v2.pdf)
3. System publishes file.updated event
4. PII service marks redacted file as "stale"
5. User continues conversation
6. System shows warning: "Document has been updated"
7. User chooses "Regenerate"
8. System re-processes file_123 v2
9. Token map updated
10. User continues with fresh content

**Expected Results**:
- Stale warning displayed
- User can choose to continue or regenerate
- Regeneration works correctly
- Token map updated appropriately

**Test Data**: File updated mid-conversation

---

#### Test Case E2E-005: Switch LLM Providers Mid-Conversation
**Priority**: Low (P3)
**Description**: Test changing LLM provider during conversation

**Preconditions**:
- Conversation using OpenAI
- Anthropic also configured

**Test Steps**:
1. User has ongoing conversation on OpenAI
2. User switches to Anthropic in settings
3. User sends new query
4. System uses Anthropic for response
5. Conversation history preserved
6. Response quality compared

**Expected Results**:
- Provider switch works seamlessly
- Token map reused (provider-agnostic)
- Full history preserved
- Response received from new provider

**Test Data**: Any conversation

---

### 7.2 Error Recovery Workflows

#### Test Case E2E-ERR-001: LLM Service Unavailable
**Priority**: High (P1)
**Description**: Test graceful handling when LLM service down

**Preconditions**:
- OpenAI API returns 503

**Test Steps**:
1. User sends query
2. System attempts OpenAI call
3. OpenAI returns 503 Service Unavailable
4. System shows error: "AI service temporarily unavailable"
5. User retries after 30 seconds
6. Service recovered, query succeeds

**Expected Results**:
- User informed of temporary issue
- No data loss
- Retry succeeds when service recovers
- PII still protected during failure

**Test Data**: Simulated LLM outage

---

#### Test Case E2E-ERR-002: Network Interruption During Processing
**Priority**: Medium (P2)
**Description**: Test handling network failure during file processing

**Preconditions**: Conversation processing

**Test Steps**:
1. Create conversation with 3 files
2. Interrupt network during file 2 processing
3. System loses connection to Presidio
4. File 2 processing fails
5. System marks file as "failed"
6. Files 1 and 3 complete successfully
7. User notified of partial failure

**Expected Results**:
- Graceful failure handling
- Partial success (files 1, 3 done)
- Failed file clearly indicated
- User can retry failed file

**Test Data**: Network interruption simulation

---

#### Test Case E2E-ERR-003: Corrupted File Upload
**Priority**: Medium (P2)
**Description**: Test handling corrupted file

**Preconditions**: Corrupted PDF file

**Test Steps**:
1. User selects corrupted file for AI chat
2. System attempts processing
3. Decryption succeeds (file encrypted correctly)
4. Content extraction fails (corrupted PDF)
5. System marks file as "failed"
6. User sees error: "Unable to process file"
7. User can remove file and continue

**Expected Results**:
- Error detected during processing
- Clear error message to user
- No partial state
- User can recover by removing file

**Test Data**: Corrupted PDF file

---

## 8. Edge Case Tests

### 8.1 Boundary Conditions

#### Test Case EDGE-001: Empty File
**Priority**: High (P1)
**Description**: Test processing completely empty file

**Preconditions**: 0-byte file uploaded

**Test Steps**:
1. Create conversation with empty file
2. System attempts processing
3. Verify graceful handling
4. Check redacted file created (also empty)
5. User can still chat (no file context)

**Expected Results**:
- Empty file handled gracefully
- No PII detected (none present)
- Redacted file created (empty)
- Conversation still usable

**Test Data**: 0-byte file

---

#### Test Case EDGE-002: File with No PII
**Priority**: High (P1)
**Description**: Test file containing no personal information

**Preconditions**: Technical document with no PII

**Test Steps**:
1. Process technical manual (no names, IDs, etc.)
2. Verify PII detection runs
3. Verify no entities detected
4. Check token map empty or minimal
5. Verify redacted file identical to original (no tokens)
6. User can still query document

**Expected Results**:
- PII detection completes (finds nothing)
- Token map empty
- Redacted file ~= original (encrypted differently)
- AI queries work normally

**Test Data**: technical_manual.pdf (no PII)

---

#### Test Case EDGE-003: Very Large File (100MB)
**Priority**: Medium (P2)
**Description**: Test processing maximum allowed file size

**Preconditions**: 100MB document

**Test Steps**:
1. Attempt to process 100MB file
2. Verify accepted or rejected based on max_file_size config
3. If accepted:
   - Monitor processing time
   - Verify memory usage stays within limits
   - Check timeout handling
4. If rejected:
   - Verify early rejection
   - Verify clear error message

**Expected Results**:
- Large file handled per config
- No memory exhaustion
- Processing completes or fails gracefully
- Timeout if > 5 minutes

**Test Data**: 100MB document

---

#### Test Case EDGE-004: Query with Only PII (No Context)
**Priority**: Medium (P2)
**Description**: Test user query that is entirely PII

**Preconditions**: Active conversation

**Test Steps**:
1. User sends query: "John Doe"
2. System detects entire query is PII
3. System tokenizes: "<<PII_NAME_a1b2>>"
4. Send to LLM
5. LLM responds based on token
6. User receives response

**Expected Results**:
- Query fully tokenized
- LLM handles token-only query
- Response makes sense contextually
- No errors

**Test Data**: Query: "John Doe"

---

#### Test Case EDGE-005: Conversation with All Files Failed
**Priority**: Medium (P2)
**Description**: Test conversation where every file fails to process

**Preconditions**: 3 corrupted files

**Test Steps**:
1. Create conversation with 3 corrupted files
2. All files fail processing
3. Verify conversation status = "failed"
4. User sees error: "All files failed to process"
5. User cannot send messages
6. User can delete conversation

**Expected Results**:
- Conversation marked as failed
- Clear error message
- Chat disabled (no context)
- User can clean up

**Test Data**: 3 corrupted files

---

### 8.2 Special Characters and Encoding

#### Test Case EDGE-CHAR-001: Unicode PII (Non-ASCII Names)
**Priority**: High (P1)
**Description**: Test PII detection for non-ASCII characters

**Preconditions**: Document with Unicode names

**Test Steps**:
1. Process document containing: "李明", "José García", "Михаил"
2. Verify NER detects Unicode names
3. Verify tokens generated correctly
4. Verify token map handles Unicode
5. Verify LLM response preserves Unicode

**Expected Results**:
- Unicode PII detected
- Token map stores Unicode correctly
- Client replacement works
- No encoding issues

**Test Data**: Document with Unicode names

---

#### Test Case EDGE-CHAR-002: Special Characters in File Names
**Priority**: Medium (P2)
**Description**: Test files with special characters in names

**Preconditions**: File named "report (final) [v2].pdf"

**Test Steps**:
1. Upload file with special chars in name
2. Create conversation
3. Verify file name stored correctly
4. Verify S3 key handling
5. Verify download works

**Expected Results**:
- Special characters handled correctly
- URL encoding applied where needed
- Download preserves original name

**Test Data**: Files with varied special chars

---

#### Test Case EDGE-CHAR-003: SQL Injection Attempt in PII
**Priority**: High (P1)
**Description**: Test PII containing SQL-like strings

**Preconditions**: Document with malicious content

**Test Steps**:
1. Process document with name: "John'; DROP TABLE users; --"
2. Verify name detected as PII
3. Verify tokenized safely
4. Verify no SQL injection in database
5. Verify client renders safely

**Expected Results**:
- PII detected and tokenized
- No SQL injection possible
- Parameterized queries prevent attack
- Safe rendering on client

**Test Data**: Document with SQL injection attempts

---

### 8.3 Concurrent Operations

#### Test Case EDGE-CONC-001: Concurrent Updates to Same Conversation
**Priority**: Medium (P2)
**Description**: Test multiple messages sent simultaneously

**Preconditions**: Active conversation

**Test Steps**:
1. Send 5 messages concurrently to same conversation
2. Verify all messages processed
3. Check message sequence_num unique and ordered
4. Verify token_map version handling (optimistic locking)
5. Verify no lost updates

**Expected Results**:
- All messages stored
- Sequence numbers correct
- Token map versions consistent
- No race conditions

**Test Data**: 5 concurrent messages

---

#### Test Case EDGE-CONC-002: File Deleted During Processing
**Priority**: High (P1)
**Description**: Test file deleted while being processed

**Preconditions**: File processing in progress

**Test Steps**:
1. Start processing file_123
2. Mid-processing, delete file_123 from main system
3. file.deleted event arrives
4. Verify processing completes or gracefully fails
5. Check conversation state consistent

**Expected Results**:
- Processing handles deletion gracefully
- No orphaned data
- Conversation state consistent
- User notified of deletion

**Test Data**: File deleted mid-processing

---

#### Test Case EDGE-CONC-003: User Deleted During Active Session
**Priority**: Medium (P2)
**Description**: Test user deletion while conversation active

**Preconditions**: User has active session

**Test Steps**:
1. User chatting in conversation
2. Admin deletes user account
3. user.deleted event arrives
4. Verify all user data deleted
5. Verify active session invalidated
6. User sees authentication error

**Expected Results**:
- User data completely removed
- Session invalidated
- User gracefully logged out
- No orphaned conversations

**Test Data**: User deletion during session

---

### 8.4 Model-Specific Edge Cases

#### Test Case EDGE-MODEL-001: Ambiguous Entity Classification
**Priority**: Medium (P2)
**Description**: Test entity that could be PII or non-PII based on context

**Preconditions**: Document with ambiguous entities

**Test Steps**:
1. Process medical doc with "Smith" (could be patient or doctor)
2. Verify Tier 4 (Mistral) validates context
3. Check domain-specific rules applied
4. Verify correct classification (doctor name kept, patient redacted)

**Expected Results**:
- Ambiguous entities resolved
- Domain rules applied correctly
- High confidence after validation

**Test Data**: Medical doc with "Dr. Smith treating patient Smith"

---

#### Test Case EDGE-MODEL-002: PII at Detection Confidence Threshold
**Priority**: Medium (P2)
**Description**: Test entity exactly at min_confidence threshold

**Preconditions**: PII policy with min_confidence = 0.8

**Test Steps**:
1. Process doc with entity detected at 0.80 confidence
2. Verify entity included (>= threshold)
3. Process entity at 0.79 confidence
4. Verify entity excluded (< threshold)
5. Check threshold applied consistently

**Expected Results**:
- Threshold strictly enforced
- Entities at threshold included
- Entities below threshold excluded
- Clear boundary behavior

**Test Data**: Entities with controlled confidence scores

---

#### Test Case EDGE-MODEL-003: Presidio Service Unavailable
**Priority**: High (P1)
**Description**: Test PII detection when Presidio (Tier 2) down

**Preconditions**: Presidio service stopped

**Test Steps**:
1. Attempt to process document
2. Verify Tier 1 (Regex) still runs
3. Verify Tier 2 (Presidio) fails gracefully
4. Verify Tier 3 (Phi-3) still runs
5. Check detection continues with available tiers
6. Verify degraded mode logging

**Expected Results**:
- Processing continues with available tiers
- Tier 2 failure logged
- Some PII still detected (Tier 1 + 3)
- User warned of degraded accuracy

**Test Data**: Document requiring NER

---

## 9. Test Environment Setup

### 9.1 Test Infrastructure

```yaml
# docker-compose.test.yml

version: '3.8'

services:
  pii-service-test:
    build:
      context: .
      dockerfile: Dockerfile.pii
    environment:
      - MIX_ENV=test
      - DATABASE_URL=postgres://test:test@postgres-test:5432/pii_test
      - OLLAMA_URL=http://ollama-test:11434
      - PRESIDIO_URL=http://presidio-test:5001
    depends_on:
      - postgres-test
      - ollama-test
      - presidio-test
    volumes:
      - ./test:/app/test

  postgres-test:
    image: postgres:16
    environment:
      - POSTGRES_DB=pii_test
      - POSTGRES_USER=test
      - POSTGRES_PASSWORD=test
    ports:
      - "5433:5432"

  ollama-test:
    image: ollama/ollama:latest
    volumes:
      - ollama_test_data:/root/.ollama
    command:
      - /bin/sh
      - -c
      - |
        ollama serve &
        sleep 10
        ollama pull phi3:mini
        ollama pull mistral:7b
        wait

  presidio-test:
    build: ./services/presidio
    environment:
      - PRESIDIO_ANALYZER_MODE=test

  minio-test:
    image: minio/minio:latest
    environment:
      - MINIO_ROOT_USER=test
      - MINIO_ROOT_PASSWORD=testtest
    command: server /data
    ports:
      - "9000:9000"

volumes:
  ollama_test_data:
```

### 9.2 Test Data Setup

```elixir
# test/support/fixtures.ex

defmodule PIIService.Fixtures do
  def medical_record_fixture do
    """
    Patient: John Doe
    NRIC: 901231-14-5678
    Date of Birth: December 31, 1990
    Email: john.doe@email.com
    Phone: +60-12-345-6789

    Diagnosis: Type 2 Diabetes Mellitus
    Treatment: Metformin 500mg twice daily

    Physician: Dr. Sarah Smith
    Hospital: General Hospital
    """
  end

  def financial_statement_fixture do
    """
    Account Holder: Jane Smith
    Account Number: 1234-5678-9012-3456
    Email: jane.smith@email.com

    Balance: RM 50,000.00

    Transactions:
    - 2026-01-15: Salary Deposit RM 8,000
    - 2026-01-10: Rent Payment RM 1,500
    """
  end

  def technical_document_fixture do
    """
    System Architecture Document

    The service uses PostgreSQL for data persistence.
    API endpoints follow REST conventions.
    Authentication via JWT tokens.

    No personal information in this document.
    """
  end

  def create_test_file(user, content, filename) do
    # Encrypt content with user's keys
    # Upload to test S3
    # Return file record
  end

  def create_service_share(file, service, user) do
    # Generate test ServiceShare with valid signatures
  end
end
```

### 9.3 Test Helpers

```elixir
# test/support/test_helpers.ex

defmodule PIIService.TestHelpers do
  def assert_pii_not_in_logs(pii_value) do
    logs = capture_log(fn -> :timer.sleep(100) end)
    refute String.contains?(logs, pii_value),
      "Found PII in logs: #{pii_value}"
  end

  def assert_memory_zeroized(marker) do
    # Use process memory inspection to verify marker cleared
  end

  def wait_for_conversation_ready(conv_id, timeout \\ 30_000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_ready_loop(conv_id, end_time)
  end

  defp wait_for_ready_loop(conv_id, end_time) do
    if System.monotonic_time(:millisecond) > end_time do
      raise "Timeout waiting for conversation #{conv_id}"
    end

    conv = Repo.get!(Conversation, conv_id)
    case conv.status do
      "ready" -> conv
      "failed" -> raise "Conversation processing failed"
      _ ->
        :timer.sleep(1000)
        wait_for_ready_loop(conv_id, end_time)
    end
  end
end
```

---

## 10. Test Data Management

### 10.1 Test Data Categories

| Category | Description | Examples |
|----------|-------------|----------|
| **Valid PII** | Realistic test data for detection | Names, NRICs, emails, phones |
| **Edge Case PII** | Boundary conditions | Unicode names, very long addresses |
| **Non-PII** | Data that should NOT be detected | Product names, generic terms |
| **Malicious** | Security test payloads | SQL injection, XSS, path traversal |
| **Corrupted** | Invalid file formats | Truncated PDFs, malformed JSON |

### 10.2 Synthetic Data Generation

```python
# scripts/generate_test_data.py

import faker
import random

fake = faker.Faker(['en_US', 'en_MY'])

def generate_medical_record():
    return f"""
    Patient: {fake.name()}
    NRIC: {generate_malaysian_nric()}
    DOB: {fake.date_of_birth()}
    Email: {fake.email()}
    Phone: {fake.phone_number()}

    Diagnosis: {random.choice(['Type 2 Diabetes', 'Hypertension', 'Asthma'])}
    Physician: Dr. {fake.name()}
    """

def generate_malaysian_nric():
    # Generate valid Malaysian NRIC with checksum
    year = random.randint(50, 99)
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    state = random.randint(1, 16)
    serial = random.randint(1, 9999)
    # Calculate checksum
    checksum = calculate_nric_checksum(year, month, day, state, serial)
    return f"{year:02d}{month:02d}{day:02d}-{state:02d}-{serial:04d}"
```

### 10.3 Test Data Cleanup

```elixir
# test/support/test_cleanup.ex

defmodule PIIService.TestCleanup do
  def cleanup_test_data do
    # Delete all conversations created in test
    Repo.delete_all(from c in Conversation, where: like(c.title, "TEST:%"))

    # Delete test S3 objects
    delete_s3_prefix("test-tenant/")

    # Clear processed events
    Repo.delete_all(ProcessedEvent)
  end
end
```

---

## 11. Test Execution Schedule

### 11.1 Continuous Integration (CI)

```yaml
# .github/workflows/test.yml

name: PII Service Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Unit Tests
        run: mix test test/unit/
      - name: Upload Coverage
        run: mix coveralls.github

  integration-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
      redis:
        image: redis:7
    steps:
      - uses: actions/checkout@v3
      - name: Run Integration Tests
        run: mix test test/integration/

  api-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Start Services
        run: docker-compose -f docker-compose.test.yml up -d
      - name: Run API Tests
        run: mix test test/api/
      - name: Stop Services
        run: docker-compose -f docker-compose.test.yml down

  security-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Security Scans
        run: |
          mix deps.audit
          mix sobelow --config
      - name: SAST Scan
        run: semgrep --config auto
```

### 11.2 Nightly Test Suite

```bash
#!/bin/bash
# scripts/nightly_tests.sh

echo "Starting nightly test suite..."

# Performance tests (longer running)
mix test test/performance/ --timeout 600000

# E2E tests (full stack)
mix test test/e2e/ --timeout 300000

# Security penetration tests
./scripts/security/pentest.sh

# Load tests
k6 run scripts/load_tests/sustained_load.js

# Generate report
./scripts/generate_test_report.sh
```

### 11.3 Pre-Release Test Checklist

- [ ] All unit tests pass (100% coverage goals)
- [ ] All integration tests pass
- [ ] All API tests pass
- [ ] Security audit completed (no critical issues)
- [ ] Performance benchmarks meet SLAs
- [ ] E2E tests pass on staging environment
- [ ] Manual exploratory testing completed
- [ ] Accessibility testing completed
- [ ] Cross-browser/platform testing completed
- [ ] Load testing completed (10x expected traffic)
- [ ] Failover/disaster recovery tested
- [ ] Documentation updated
- [ ] Test report reviewed by QA lead

---

## Summary

This comprehensive test plan covers all aspects of the PII Extraction Service:

- **322 test cases** across 7 categories
- **Critical security tests** ensuring zero-knowledge guarantees
- **Performance benchmarks** validating < 3s SLA
- **End-to-end workflows** covering complete user journeys
- **Edge cases** for robustness
- **Automated CI/CD pipeline** for continuous validation

**Test Coverage Goals**:
- Unit: ≥ 90% (Elixir), ≥ 95% (Rust)
- API: 100% of endpoints
- Security: 100% of attack vectors
- E2E: 100% of critical paths

**Execution Timeline**:
- CI: On every commit/PR
- Nightly: Performance + E2E suites
- Weekly: Security scans
- Pre-release: Full regression + manual testing

This test plan ensures the PII Extraction Service meets all functional, security, and performance requirements while maintaining SecureSharing's zero-knowledge architecture.
