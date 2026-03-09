# PII Extraction Service

**Version**: 2.0.0
**Status**: Draft
**Last Updated**: 2026-01-21
**Authors**: System Architecture Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Design Goals](#3-design-goals)
4. [Architecture Overview](#4-architecture-overview)
5. [Standalone Database Design](#5-standalone-database-design)
6. [Conversation Model](#6-conversation-model)
7. [Data Flow](#7-data-flow)
8. [Security Model](#8-security-model)
9. [PII Detection Strategy](#9-pii-detection-strategy)
10. [Event-Driven Synchronization](#10-event-driven-synchronization)
11. [API Specification](#11-api-specification)
12. [Implementation Plan](#12-implementation-plan)
13. [Deployment Architecture](#13-deployment-architecture)
14. [Server Sizing](#14-server-sizing)
15. [Monitoring & Operations](#15-monitoring--operations)
16. [Future Enhancements](#16-future-enhancements)
17. [Client Integration Design](#17-client-integration-design)

---

## 1. Executive Summary

The PII Extraction Service is a **standalone microservice** that enables SSDID Drive users to:

1. **Generate redacted copies** of their encrypted documents with PII automatically detected and tokenized
2. **Query AI services** (ChatGPT, Gemini, Claude) about documents while protecting personal information
3. **Maintain conversation history** with full chat persistence and multi-file context

The service operates as an **independent system** with its own database, communicating with the main SSDID Drive system via APIs and events.

### Key Features

- **Standalone Service**: Independent database, storage, and deployment from main SSDID Drive
- **Persistent Redacted Files**: Auto-save redacted documents to user storage (per tenant)
- **Conversation Model**: Full chat sessions with file selection, message history, and resumable conversations
- **Bidirectional Tokenization**: Both document content AND user queries are tokenized
- **Conversation-Level Token Map**: Accumulates PII from documents and all user queries
- **Zero-Knowledge Preservation**: Server processes PII in secure memory, zeroizes immediately after
- **Multi-Model Detection**: Combines regex patterns, ML-based NER, and LLM context validation
- **Domain-Aware**: Different PII handling for medical, financial, legal, and HR documents
- **Event-Driven Sync**: Handles file deletions/updates from main system via events

### Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| Orchestration | Elixir/OTP | Service coordination, fault tolerance |
| Database | PostgreSQL (standalone) | Conversations, redacted files, token maps |
| Object Storage | S3 (separate bucket) | Redacted file storage |
| Secure Processing | Rust NIFs | Memory-safe PII handling with zeroization |
| Pattern Detection | Rust regex | Fast, high-confidence pattern matching |
| ML-based NER | Presidio + spaCy | Named entity recognition |
| Document Classification | Phi-3 (3.8B) | Domain classification |
| Context Validation | Mistral 7B | Ambiguous entity validation |
| LLM Gateway | Elixir + Finch | Multi-provider LLM integration |
| Event Bus | RabbitMQ/Redis Streams | Cross-service communication |

---

## 2. Problem Statement

### The Challenge

SSDID Drive is a zero-knowledge file sharing platform where the server cannot read file contents. Users want to query AI services about their documents, but:

1. **LLM Privacy Risk**: Sending documents to LLMs exposes PII to third parties
2. **Zero-Knowledge Conflict**: Enabling AI features seems to require breaking zero-knowledge
3. **Context Matters**: PII handling differs by document type (medical vs financial)
4. **User Experience**: Protection should be transparent, not burdensome

### The Solution

Implement a **PII Tokenization Proxy** that:

1. User grants temporary, explicit access to the PII service (via ServiceShare)
2. Service decrypts document in secure memory
3. Service detects and replaces PII with tokens (e.g., `<<PII_NAME_a1b2>>`)
4. Tokenized content sent to LLM (LLM never sees actual PII)
5. LLM response contains tokens, sent back to client
6. Client replaces tokens with original values locally
7. All sensitive data zeroized from server memory

---

## 3. Design Goals

### Primary Goals

| Goal | Description | Metric |
|------|-------------|--------|
| **G1: Privacy** | LLM providers never see actual PII values | 100% tokenization of detected PII |
| **G2: Transparency** | Users interact naturally, tokenization invisible | No workflow changes for users |
| **G3: Security** | Maintain zero-knowledge principles | Plaintext in memory < 5 seconds |
| **G4: Accuracy** | High PII detection accuracy | > 95% recall for high-sensitivity PII |
| **G5: Performance** | Acceptable latency for interactive use | < 3 seconds for typical queries |

### Non-Goals

- Real-time streaming responses (batch processing acceptable)
- 100% PII detection (users can review/adjust)
- On-device processing (requires server-side for accuracy)

---

## 4. Architecture Overview

### High-Level Architecture (Standalone Service)

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                    STANDALONE PII EXTRACTION SERVICE ARCHITECTURE                    │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│   MAIN SYSTEM                          PII SERVICE                    EXTERNAL      │
│   ═══════════                          ═══════════                    ════════      │
│                                                                                      │
│  ┌─────────────────┐                  ┌─────────────────┐                          │
│  │  SSDID Drive   │                  │  PII Extraction │                          │
│  │     API         │                  │     Service     │                          │
│  │  (ASP.NET)      │    ◄──REST──►    │    (Elixir)     │                          │
│  │                 │                  │                 │                          │
│  │ • Auth          │                  │ • Conversations │                          │
│  │ • Files         │    ──Events──►   │ • Redaction     │                          │
│  │ • Shares        │                  │ • Token Maps    │                          │
│  │ • Users         │                  │ • Chat/Messages │                          │
│  └────────┬────────┘                  └────────┬────────┘                          │
│           │                                    │                                    │
│           ▼                                    ▼                                    │
│  ┌─────────────────┐                  ┌─────────────────┐                          │
│  │   PostgreSQL    │                  │   PostgreSQL    │                          │
│  │   (Main DB)     │                  │   (PII DB)      │    ◄── SEPARATE DB       │
│  │                 │                  │                 │                          │
│  │ • users         │                  │ • conversations │                          │
│  │ • files         │                  │ • conv_files    │                          │
│  │ • tenants       │                  │ • redacted_files│                          │
│  │ • shares        │                  │ • token_maps    │                          │
│  └─────────────────┘                  │ • messages      │                          │
│           │                           └────────┬────────┘                          │
│           ▼                                    │                                    │
│  ┌─────────────────┐                           │                                    │
│  │   S3 Bucket     │                           ▼                                    │
│  │   (Main Files)  │                  ┌─────────────────┐                          │
│  │                 │                  │   S3 Bucket     │    ◄── SEPARATE BUCKET   │
│  │ • Encrypted     │                  │   (Redacted)    │                          │
│  │   originals     │                  │                 │                          │
│  └─────────────────┘                  │ • Encrypted     │                          │
│                                       │   redacted files│                          │
│                                       └─────────────────┘                          │
│                                                │                                    │
│  ─────────────────────────────────────────────┼────────────────────────────────    │
│                                                │                                    │
│                                    ┌───────────┴───────────┐                       │
│                                    │                       │                       │
│                                    ▼                       ▼                       │
│                           ┌───────────────┐       ┌───────────────┐               │
│                           │   Presidio    │       │    Ollama     │               │
│                           │   (NER)       │       │   (SLMs)      │               │
│                           └───────────────┘       └───────────────┘               │
│                                                            │                       │
│                                                            ▼                       │
│                                                   ┌───────────────┐               │
│                                                   │  Tenant LLM   │               │
│                                                   │  (OpenAI/     │               │
│                                                   │   Anthropic/  │               │
│                                                   │   Google)     │               │
│                                                   └───────────────┘               │
│                                                                                    │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### Service Independence

| Aspect | Main System | PII Service |
|--------|-------------|-------------|
| **Database** | PostgreSQL (main) | PostgreSQL (pii) - separate instance |
| **Storage** | S3 bucket (originals) | S3 bucket (redacted) - separate bucket |
| **Deployment** | Independent | Independent |
| **Scaling** | Based on file operations | Based on PII processing load |
| **Data Coupling** | None (uses IDs only) | References main system IDs (no FKs) |

### Component Interaction

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         PII SERVICE INTERNAL COMPONENTS                              │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                           API LAYER (Phoenix)                                │   │
│  │                                                                             │   │
│  │  /conversations    /messages    /redacted-files    /token-maps             │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                         │                                           │
│              ┌──────────────────────────┼──────────────────────────┐               │
│              │                          │                          │               │
│              ▼                          ▼                          ▼               │
│  ┌───────────────────┐    ┌───────────────────┐    ┌───────────────────┐         │
│  │  Conversation     │    │   Redaction       │    │   Event           │         │
│  │  Manager          │    │   Pipeline        │    │   Consumer        │         │
│  │  (GenServer)      │    │   (GenServer)     │    │   (GenServer)     │         │
│  │                   │    │                   │    │                   │         │
│  │ • Create conv     │    │ • PII detection   │    │ • file.deleted    │         │
│  │ • Manage files    │    │ • Tokenization    │    │ • file.updated    │         │
│  │ • Chat messages   │    │ • Redacted files  │    │ • user.deleted    │         │
│  │ • Token maps      │    │ • Token maps      │    │ • tenant.deleted  │         │
│  └───────────────────┘    └───────────────────┘    └───────────────────┘         │
│              │                          │                                          │
│              │                          │                                          │
│              ▼                          ▼                                          │
│  ┌───────────────────┐    ┌───────────────────┐                                   │
│  │   Rust Secure     │    │   Model Router    │                                   │
│  │   Processor       │    │   (GenServer)     │                                   │
│  │                   │    │                   │                                   │
│  │ • Decrypt content │    │ • Pattern detect  │                                   │
│  │ • Create tokens   │    │ • Presidio NER    │                                   │
│  │ • Encrypt map     │    │ • Phi-3 classify  │                                   │
│  │ • Zeroize memory  │    │ • Mistral validate│                                   │
│  └───────────────────┘    └───────────────────┘                                   │
│           │                         │                                              │
│           ▼                         ▼                                              │
│  ┌───────────────────┐    ┌───────────────────────────────────────────┐          │
│  │   Secure Memory   │    │   ML Services                             │          │
│  │   Arena (mlock)   │    │   ┌─────────┐  ┌─────────┐  ┌─────────┐  │          │
│  └───────────────────┘    │   │Presidio │  │ Phi-3   │  │Mistral  │  │          │
│                           │   └─────────┘  └─────────┘  └─────────┘  │          │
│                           └───────────────────────────────────────────┘          │
│                                                                                    │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Standalone Database Design

The PII Service has its own PostgreSQL database, completely separate from the main SSDID Drive database. This enables independent deployment, scaling, and development.

### 5.1 Database Schema

```sql
-- ═══════════════════════════════════════════════════════════════════════════════
-- PII SERVICE DATABASE SCHEMA (Standalone)
-- No foreign keys to main system - uses IDs as references only
-- ═══════════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────────
-- CONVERSATIONS
-- Chat sessions with file selection and settings
-- ───────────────────────────────────────────────────────────────────────────────

CREATE TABLE conversations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- References to main system (NO FK - just IDs)
    tenant_id           UUID NOT NULL,
    user_id             UUID NOT NULL,

    -- Conversation metadata
    title               TEXT,                   -- Auto-generated or user-defined

    -- LLM configuration
    llm_provider        TEXT NOT NULL,          -- 'openai', 'anthropic', 'google'
    llm_model           TEXT,                   -- 'gpt-4', 'claude-3-opus', etc.

    -- PII policy for this conversation
    pii_policy          JSONB NOT NULL,

    -- Status
    status              TEXT NOT NULL DEFAULT 'processing',
                        -- processing, ready, failed, archived

    -- Stats (denormalized for quick display)
    file_count          INTEGER NOT NULL DEFAULT 0,
    message_count       INTEGER NOT NULL DEFAULT 0,
    total_pii_protected INTEGER NOT NULL DEFAULT 0,

    -- Timestamps
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at     TIMESTAMPTZ,

    CONSTRAINT valid_status CHECK (status IN ('processing', 'ready', 'failed', 'archived'))
);

CREATE INDEX idx_conversations_user ON conversations(tenant_id, user_id, created_at DESC);
CREATE INDEX idx_conversations_status ON conversations(status) WHERE status = 'processing';


-- ───────────────────────────────────────────────────────────────────────────────
-- CONVERSATION FILES
-- Junction table: which files are in which conversation
-- ───────────────────────────────────────────────────────────────────────────────

CREATE TABLE conversation_files (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id     UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,

    -- Original file reference (from main system - NO FK)
    original_file_id    UUID NOT NULL,
    original_file_name  TEXT NOT NULL,          -- Cached for display
    original_version    INTEGER NOT NULL,

    -- Redacted file (created by PII service)
    redacted_file_id    UUID REFERENCES redacted_files(id) ON DELETE SET NULL,

    -- Processing status for this file
    processing_status   TEXT NOT NULL DEFAULT 'pending',
                        -- pending, processing, completed, failed
    processing_error    TEXT,                   -- Error message if failed

    -- PII stats for this file
    entities_detected   JSONB,                  -- {NAME: 2, NRIC: 1, ...}

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at        TIMESTAMPTZ,

    CONSTRAINT unique_file_per_conversation UNIQUE (conversation_id, original_file_id)
);

CREATE INDEX idx_conv_files_conversation ON conversation_files(conversation_id);
CREATE INDEX idx_conv_files_original ON conversation_files(original_file_id);
CREATE INDEX idx_conv_files_status ON conversation_files(processing_status)
    WHERE processing_status IN ('pending', 'processing');


-- ───────────────────────────────────────────────────────────────────────────────
-- REDACTED FILES
-- Stored redacted versions of original files
-- ───────────────────────────────────────────────────────────────────────────────

CREATE TABLE redacted_files (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- References to main system (NO FK - just IDs)
    tenant_id           UUID NOT NULL,
    user_id             UUID NOT NULL,
    original_file_id    UUID NOT NULL,
    original_version    INTEGER NOT NULL,

    -- Link to conversation
    conversation_id     UUID REFERENCES conversations(id) ON DELETE CASCADE,

    -- Storage (PII service's own S3 bucket)
    storage_bucket      TEXT NOT NULL,
    storage_key         TEXT NOT NULL,

    -- Encryption (independent DEK)
    encrypted_dek       BYTEA NOT NULL,
    kem_ciphertext_ml   BYTEA NOT NULL,
    kem_ciphertext_kaz  BYTEA NOT NULL,

    -- Metadata
    file_name           TEXT NOT NULL,          -- e.g., "report_redacted.pdf"
    mime_type           TEXT NOT NULL,
    size_bytes          BIGINT NOT NULL,

    -- Redaction info
    redaction_policy    JSONB NOT NULL,
    entities_redacted   JSONB NOT NULL,         -- {NAME: 5, NRIC: 2, EMAIL: 3}

    -- Status
    status              TEXT NOT NULL DEFAULT 'valid',  -- valid, stale

    -- Timestamps
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    invalidated_at      TIMESTAMPTZ,

    CONSTRAINT unique_redaction UNIQUE (original_file_id, original_version, redaction_policy)
);

CREATE INDEX idx_redacted_by_original ON redacted_files(original_file_id);
CREATE INDEX idx_redacted_by_user ON redacted_files(user_id);
CREATE INDEX idx_redacted_by_tenant ON redacted_files(tenant_id);
CREATE INDEX idx_redacted_by_conversation ON redacted_files(conversation_id);


-- ───────────────────────────────────────────────────────────────────────────────
-- CONVERSATION TOKEN MAPS
-- Encrypted PII token mappings at conversation level
-- Accumulates tokens from all files AND user queries
-- ───────────────────────────────────────────────────────────────────────────────

CREATE TABLE conversation_token_maps (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id     UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,

    -- Encrypted token map (only client can decrypt)
    encrypted_map       BYTEA NOT NULL,
    map_nonce           BYTEA NOT NULL,

    -- DEK for this token map, wrapped for user's PQC keys
    encrypted_dek       BYTEA NOT NULL,
    kem_ciphertext_ml   BYTEA NOT NULL,
    kem_ciphertext_kaz  BYTEA NOT NULL,

    -- Metadata (no actual values - just counts)
    token_count         INTEGER NOT NULL DEFAULT 0,
    entity_types        TEXT[] NOT NULL DEFAULT '{}',

    -- Version for optimistic locking (map grows as queries add new PII)
    version             INTEGER NOT NULL DEFAULT 1,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT one_map_per_conversation UNIQUE (conversation_id)
);


-- ───────────────────────────────────────────────────────────────────────────────
-- MESSAGES
-- Chat messages in conversations (stored tokenized)
-- ───────────────────────────────────────────────────────────────────────────────

CREATE TABLE messages (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id     UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,

    -- Message content
    role                TEXT NOT NULL,              -- 'user', 'assistant', 'system'

    -- Content (ALWAYS tokenized - server never stores plaintext PII)
    content_tokenized   TEXT NOT NULL,

    -- Which version of token map was used for this message
    token_map_version   INTEGER NOT NULL,

    -- PII found specifically in THIS message (for user messages)
    pii_in_message      JSONB,                      -- {NAME: 1, NRIC: 1}

    -- For assistant messages: LLM metadata
    llm_metadata        JSONB,                      -- {model, tokens_used, finish_reason}

    -- Ordering
    sequence_num        INTEGER NOT NULL,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, sequence_num);


-- ───────────────────────────────────────────────────────────────────────────────
-- EVENT PROCESSING (Idempotency tracking)
-- ───────────────────────────────────────────────────────────────────────────────

CREATE TABLE processed_events (
    event_id            UUID PRIMARY KEY,
    event_type          TEXT NOT NULL,
    processed_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata            JSONB
);

CREATE INDEX idx_processed_events_cleanup ON processed_events(processed_at);


-- ───────────────────────────────────────────────────────────────────────────────
-- AUDIT LOG
-- ───────────────────────────────────────────────────────────────────────────────

CREATE TABLE redaction_audit_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL,
    user_id             UUID NOT NULL,

    action              TEXT NOT NULL,  -- 'conversation_created', 'file_redacted',
                                        -- 'message_sent', 'redacted_downloaded',
                                        -- 'conversation_deleted'

    conversation_id     UUID,
    original_file_id    UUID,
    redacted_file_id    UUID,

    metadata            JSONB,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_tenant ON redaction_audit_log(tenant_id, created_at DESC);
```

### 5.2 Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                    PII SERVICE ENTITY RELATIONSHIPS                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│   conversations                                                                      │
│   ─────────────                                                                      │
│   PK id                                                                             │
│      tenant_id ─────────────────┐                                                   │
│      user_id ───────────────────┤ (references to main system, NO FK)               │
│      title                      │                                                   │
│      llm_provider               │                                                   │
│      pii_policy                 │                                                   │
│      status                     │                                                   │
│        │                        │                                                   │
│        │ 1:N                    │                                                   │
│        ▼                        │                                                   │
│   conversation_files            │                                                   │
│   ──────────────────            │                                                   │
│   PK id                         │                                                   │
│   FK conversation_id            │                                                   │
│      original_file_id ──────────┤ (reference to main system, NO FK)                │
│      original_file_name         │                                                   │
│   FK redacted_file_id ──────────┼─────────┐                                        │
│      processing_status          │         │                                        │
│                                 │         │                                        │
│   conversations                 │         ▼                                        │
│        │                        │   redacted_files                                  │
│        │ 1:1                    │   ───────────────                                 │
│        ▼                        │   PK id                                          │
│   conversation_token_maps       │      tenant_id                                    │
│   ───────────────────────       │      user_id                                      │
│   PK id                         │   FK conversation_id                              │
│   FK conversation_id            │      original_file_id ◄─────── (main system ref) │
│      encrypted_map              │      storage_key                                  │
│      token_count                │      encrypted_dek                                │
│      version                    │      entities_redacted                            │
│                                 │      status                                       │
│   conversations                 │                                                   │
│        │                        │                                                   │
│        │ 1:N                    │                                                   │
│        ▼                        │                                                   │
│   messages                      │                                                   │
│   ────────                      │                                                   │
│   PK id                         │                                                   │
│   FK conversation_id            │                                                   │
│      role                       │                                                   │
│      content_tokenized          │                                                   │
│      token_map_version          │                                                   │
│      pii_in_message             │                                                   │
│      llm_metadata               │                                                   │
│      sequence_num               │                                                   │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Storage Structure

```
S3 Bucket (pii-service-redacted-files)
└── {tenant_id}/
    └── {user_id}/
        └── {conversation_id}/
            ├── {redacted_file_id_1}.enc    # Encrypted redacted file
            ├── {redacted_file_id_2}.enc
            └── ...
```

---

## 6. Conversation Model

### 6.1 User Flow Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         ASK AI - COMPLETE USER FLOW                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  STEP 1: User clicks "Ask AI"                                                       │
│  ════════════════════════════                                                       │
│  → Shows file/folder selection screen                                               │
│                                                                                      │
│  ┌─────────────────────────────────────────┐                                       │
│  │  Select files for AI conversation       │                                       │
│  │                                         │                                       │
│  │  ☑ report.pdf                          │                                       │
│  │  ☑ medical_record.pdf                  │                                       │
│  │  ☐ image.png                           │                                       │
│  │  ☑ lab_results.pdf                     │                                       │
│  │                                         │                                       │
│  │  Or select folder:                      │                                       │
│  │  [📁 Patient Records    ▼]              │                                       │
│  │                                         │                                       │
│  │           [Cancel]  [Continue →]        │                                       │
│  └─────────────────────────────────────────┘                                       │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 2: Processing (background)                                                    │
│  ═══════════════════════════════                                                    │
│  → Create conversation                                                              │
│  → For each file: PII detection → Generate redacted file → Save token map          │
│                                                                                      │
│  ┌─────────────────────────────────────────┐                                       │
│  │                                         │                                       │
│  │     Preparing your files...             │                                       │
│  │                                         │                                       │
│  │     ████████████░░░░░░░░  60%           │                                       │
│  │                                         │                                       │
│  │     ✓ report.pdf (5 items protected)    │                                       │
│  │     ✓ medical_record.pdf (3 items)      │                                       │
│  │     ⟳ lab_results.pdf (processing)      │                                       │
│  │                                         │                                       │
│  └─────────────────────────────────────────┘                                       │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 3: Chat (when ready)                                                          │
│  ═════════════════════════                                                          │
│  → Show chat interface                                                              │
│  → User queries also go through PII detection                                      │
│  → Messages saved to conversation history                                          │
│                                                                                      │
│  ┌─────────────────────────────────────────┐                                       │
│  │  ← Medical Records Chat          ⚙️     │                                       │
│  │                                         │                                       │
│  │  📎 3 files • 8 items protected         │                                       │
│  │                                         │                                       │
│  │  ┌─────────────────────────────────┐   │                                       │
│  │  │ 🤖 I've analyzed 3 documents.   │   │                                       │
│  │  │    Ask me anything about them.  │   │                                       │
│  │  └─────────────────────────────────┘   │                                       │
│  │                                         │                                       │
│  │                    ┌─────────────────┐  │                                       │
│  │                    │ What is John    │  │  ← User query with PII               │
│  │                    │ Doe's diagnosis?│  │                                       │
│  │                    └─────────────────┘  │                                       │
│  │                                         │                                       │
│  │  ┌─────────────────────────────────┐   │                                       │
│  │  │ 🤖 Based on the records,        │   │  ← Response with PII restored        │
│  │  │    John Doe was diagnosed...    │   │                                       │
│  │  └─────────────────────────────────┘   │                                       │
│  │                                         │                                       │
│  │  [Ask a question...            ] [▶️]   │                                       │
│  └─────────────────────────────────────────┘                                       │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 4: History (accessible later)                                                 │
│  ══════════════════════════════════                                                 │
│  → User can view past conversations                                                 │
│  → Resume conversations                                                             │
│  → Download redacted files                                                          │
│                                                                                      │
│  ┌─────────────────────────────────────────┐                                       │
│  │  AI Conversations                       │                                       │
│  │                                         │                                       │
│  │  Today                                  │                                       │
│  │  ├─ Medical Records Chat (3 files)     │                                       │
│  │  └─ Contract Review (1 file)           │                                       │
│  │                                         │                                       │
│  │  Yesterday                              │                                       │
│  │  └─ Financial Report Analysis          │                                       │
│  │                                         │                                       │
│  └─────────────────────────────────────────┘                                       │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Conversation-Level Token Map

The token map is maintained at the **conversation level** and accumulates PII from:
1. All files in the conversation (during initial processing)
2. All user queries (during chat)

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                    CONVERSATION TOKEN MAP                                            │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  Token map grows over conversation lifetime:                                        │
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  ENCRYPTED TOKEN MAP (only client can decrypt)                              │   │
│  │                                                                             │   │
│  │  {                                                                          │   │
│  │    // From documents (added during initial processing)                      │   │
│  │    "<<PII_NAME_a1b2>>": "John Doe",                                        │   │
│  │    "<<PII_NRIC_c3d4>>": "901231-14-5678",                                  │   │
│  │    "<<PII_EMAIL_e5f6>>": "john@email.com",                                 │   │
│  │                                                                             │   │
│  │    // From user queries (added during chat)                                │   │
│  │    "<<PII_NAME_g7h8>>": "Dr. Smith",        // User asked about doctor     │   │
│  │    "<<PII_DATE_i9j0>>": "1990-12-31",       // User mentioned DOB          │   │
│  │  }                                                                          │   │
│  │                                                                             │   │
│  │  DETERMINISTIC: Same value = Same token within conversation                 │   │
│  │  "John Doe" always maps to <<PII_NAME_a1b2>> in this conversation          │   │
│  │                                                                             │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  Token Map Versioning:                                                              │
│  • Version 1: After initial document processing                                     │
│  • Version 2: After user query adds new PII                                        │
│  • Version N: Grows as conversation continues                                      │
│                                                                                      │
│  Each message records which token_map_version it was created with                  │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 6.3 Bidirectional PII Redaction

Both documents AND user queries go through PII detection:

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                    BIDIRECTIONAL PII REDACTION                                       │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  PII SOURCE                    WHEN PROCESSED              TOKEN MAP UPDATE         │
│  ──────────────────────────────────────────────────────────────────────────────     │
│                                                                                      │
│  1. Documents                  Conversation creation       ✓ Added (initial)        │
│     (files in conversation)    (before chat ready)                                  │
│                                                                                      │
│  2. User queries               Each message sent           ✓ Added (if new PII)     │
│     "What about John Doe?"                                                          │
│                                                                                      │
│  3. LLM responses              Each response received      ✗ No (uses existing)     │
│     (already uses tokens)                                                           │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  EXAMPLE FLOW:                                                                       │
│                                                                                      │
│  Document contains: "John Doe", "jane@email.com"                                    │
│  → Token map v1: {NAME: 1, EMAIL: 1}, 2 tokens                                      │
│                                                                                      │
│  User asks: "What about Dr. Smith's notes?"                                         │
│  → "Dr. Smith" is NEW PII (not in documents)                                        │
│  → Token map v2: {NAME: 2, EMAIL: 1}, 3 tokens                                      │
│                                                                                      │
│  User asks: "And John Doe's follow-up?"                                             │
│  → "John Doe" ALREADY in map                                                        │
│  → Token map unchanged, reuse existing token                                        │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  WHAT LLM SEES (never actual PII):                                                  │
│                                                                                      │
│  Documents: "Patient <<PII_NAME_a1b2>> has email <<PII_EMAIL_e5f6>>..."            │
│  Query: "What about <<PII_NAME_g7h8>>'s notes?"                                    │
│                                                                                      │
│  WHAT USER SEES (after client token replacement):                                   │
│                                                                                      │
│  Response: "Dr. Smith's notes indicate that John Doe..."                           │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 6.4 Token Format

```
<<PII_{TYPE}_{ID}>>

Where:
- TYPE: Entity type (NAME, EMAIL, NRIC, PHONE, DOB, ADDRESS, etc.)
- ID: 6-character hash derived from value + conversation salt

Examples:
- <<PII_NAME_a1b2c3>>     → "John Doe"
- <<PII_NRIC_d4e5f6>>     → "901231-14-5678"
- <<PII_EMAIL_g7h8i9>>    → "john@email.com"
- <<PII_PHONE_j0k1l2>>    → "+60-12-345-6789"
- <<PII_DOB_m3n4o5>>      → "1990-12-31"

Same value = Same token within a conversation (deterministic)
```

---

## 7. Data Flow

### 7.1 Conversation Creation Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                    CONVERSATION CREATION & FILE PROCESSING                           │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  CLIENT                              PII SERVICE                    MAIN SYSTEM     │
│  ══════                              ═══════════                    ═══════════     │
│                                                                                      │
│  1. User selects files               │                              │               │
│     and clicks "Continue"            │                              │               │
│          │                           │                              │               │
│          │ POST /conversations       │                              │               │
│          │ {file_ids, pii_policy,    │                              │               │
│          │  llm_provider}            │                              │               │
│          └──────────────────────────►│                              │               │
│                                      │                              │               │
│                                      │  2. Create conversation      │               │
│                                      │     (status: processing)     │               │
│                                      │                              │               │
│                                      │  3. For each file:           │               │
│                                      │     │                        │               │
│                                      │     │  GET /files/{id}       │               │
│                                      │     └───────────────────────►│               │
│                                      │                              │               │
│                                      │◄─────────────────────────────┤               │
│                                      │     (encrypted file blob,    │               │
│                                      │      wrapped DEK, metadata)  │               │
│                                      │                              │               │
│          ◄───────────────────────────┤  4. Return conversation_id   │               │
│          {conversation_id,           │     (processing continues    │               │
│           status: processing}        │      in background)          │               │
│                                      │                              │               │
│  5. Poll for status                  │                              │               │
│     GET /conversations/{id}/status   │                              │               │
│          │                           │                              │               │
│          └──────────────────────────►│                              │               │
│                                      │                              │               │
│          ◄───────────────────────────┤                              │               │
│          {status, progress,          │                              │               │
│           files: [{status}...]}      │                              │               │
│                                      │                              │               │
│                                      │  ═══════════════════════════════════════    │
│                                      │  BACKGROUND PROCESSING (per file)           │
│                                      │  ═══════════════════════════════════════    │
│                                      │                                              │
│                                      │  ┌────────────────────────────────────┐     │
│                                      │  │ a. Decrypt file in secure memory   │     │
│                                      │  │ b. Run PII detection pipeline      │     │
│                                      │  │ c. Generate tokenized content      │     │
│                                      │  │ d. Create redacted file (encrypt)  │     │
│                                      │  │ e. Upload to PII S3 bucket         │     │
│                                      │  │ f. Update conversation token map   │     │
│                                      │  │ g. Update conversation_files       │     │
│                                      │  │ h. Zeroize all plaintext           │     │
│                                      │  └────────────────────────────────────┘     │
│                                      │                                              │
│                                      │  When all files done:                        │
│                                      │  → Update conversation status = 'ready'     │
│                                      │  → Send push notification                    │
│                                      │                              │               │
│  6. Status = ready                   │                              │               │
│     Show chat UI                     │                              │               │
│                                      │                              │               │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Message Flow (Chat)

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         COMPLETE AI QUERY DATA FLOW                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  STEP 1: CLIENT PREPARATION                                                         │
│  ══════════════════════════                                                         │
│                                                                                      │
│  User types: "What is John Doe's diagnosis from NRIC 901231-14-5678?"              │
│                                                                                      │
│  Client actions:                                                                     │
│  1. Generate ephemeral session key (for token map encryption)                       │
│  2. Create ServiceShare (grant PII service access to file)                          │
│  3. Encrypt query with session key                                                  │
│  4. Send request to backend                                                         │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 2: BACKEND SECURE PROCESSING                                                  │
│  ═════════════════════════════════                                                  │
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  RUST SECURE MEMORY ZONE (mlocked, zeroizes on exit)                        │   │
│  │                                                                             │   │
│  │  2a. Verify ServiceShare signature                                          │   │
│  │  2b. Decapsulate DEK using service's PQC private keys                       │   │
│  │  2c. Decrypt document content into secure arena                             │   │
│  │  2d. Decrypt user query into secure arena                                   │   │
│  │                                                                             │   │
│  │  Document plaintext:                                                        │   │
│  │  "Patient: John Doe, NRIC: 901231-14-5678, Email: john@email.com           │   │
│  │   Diagnosis: Type 2 Diabetes, Treatment: Metformin 500mg"                  │   │
│  │                                                                             │   │
│  │  Query plaintext:                                                           │   │
│  │  "What is John Doe's diagnosis from NRIC 901231-14-5678?"                  │   │
│  │                                                                             │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 3: PII DETECTION (Parallel)                                                   │
│  ════════════════════════════════                                                   │
│                                                                                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                  │
│  │ Regex       │ │ Presidio    │ │ Phi-3       │ │ Mistral 7B  │                  │
│  │ Patterns    │ │ NER         │ │ Classifier  │ │ (if needed) │                  │
│  │             │ │             │ │             │ │             │                  │
│  │ • NRIC ✓    │ │ • Names ✓   │ │ Domain:     │ │ Validate    │                  │
│  │ • Email ✓   │ │ • Orgs      │ │ "medical"   │ │ uncertain   │                  │
│  │ • Phone     │ │ • Dates     │ │ Conf: 0.94  │ │ entities    │                  │
│  │             │ │             │ │             │ │             │                  │
│  │ ~5ms        │ │ ~30ms       │ │ ~50ms       │ │ ~300ms      │                  │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘                  │
│         │               │               │               │                          │
│         └───────────────┴───────────────┴───────────────┘                          │
│                                   │                                                 │
│                                   ▼                                                 │
│                         ┌─────────────────┐                                        │
│                         │ Result Merger   │                                        │
│                         │                 │                                        │
│                         │ Detected PII:   │                                        │
│                         │ • John Doe      │                                        │
│                         │ • 901231-14-5678│                                        │
│                         │ • john@email.com│                                        │
│                         └─────────────────┘                                        │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 4: TOKENIZATION                                                               │
│  ════════════════════                                                               │
│                                                                                      │
│  Token Map Created:                                                                  │
│  ┌───────────────────────────────────────────────────────────────┐                 │
│  │  <<PII_NAME_a1b2>>   →  "John Doe"                            │                 │
│  │  <<PII_NRIC_c3d4>>   →  "901231-14-5678"                      │                 │
│  │  <<PII_EMAIL_e5f6>>  →  "john@email.com"                      │                 │
│  └───────────────────────────────────────────────────────────────┘                 │
│                                                                                      │
│  Tokenized Document:                                                                 │
│  "Patient: <<PII_NAME_a1b2>>, NRIC: <<PII_NRIC_c3d4>>,                             │
│   Email: <<PII_EMAIL_e5f6>>                                                         │
│   Diagnosis: Type 2 Diabetes, Treatment: Metformin 500mg"                          │
│                                                                                      │
│  Tokenized Query:                                                                    │
│  "What is <<PII_NAME_a1b2>>'s diagnosis from NRIC <<PII_NRIC_c3d4>>?"              │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 5: ZEROIZATION                                                                │
│  ═══════════════════                                                                │
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  SECURE MEMORY CLEANUP                                                      │   │
│  │                                                                             │   │
│  │  ✓ DEK bytes zeroized                                                       │   │
│  │  ✓ Document plaintext zeroized                                              │   │
│  │  ✓ Query plaintext zeroized                                                 │   │
│  │  ✓ Token map plaintext zeroized (encrypted copy kept for response)         │   │
│  │  ✓ Memory unlocked and freed                                                │   │
│  │                                                                             │   │
│  │  Server memory now contains ONLY tokenized content                          │   │
│  │                                                                             │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 6: LLM QUERY                                                                  │
│  ═════════════════                                                                  │
│                                                                                      │
│  Prompt sent to tenant's LLM (e.g., OpenAI GPT-4):                                 │
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  "You are analyzing a medical document. Privacy tokens like                 │   │
│  │   <<PII_NAME_xxx>> represent protected information.                         │   │
│  │                                                                             │   │
│  │   Document:                                                                 │   │
│  │   Patient: <<PII_NAME_a1b2>>, NRIC: <<PII_NRIC_c3d4>>,                     │   │
│  │   Email: <<PII_EMAIL_e5f6>>                                                │   │
│  │   Diagnosis: Type 2 Diabetes, Treatment: Metformin 500mg                   │   │
│  │                                                                             │   │
│  │   Question: What is <<PII_NAME_a1b2>>'s diagnosis from                     │   │
│  │   NRIC <<PII_NRIC_c3d4>>?"                                                 │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  LLM Response:                                                                       │
│  "Based on the medical record, <<PII_NAME_a1b2>> (NRIC: <<PII_NRIC_c3d4>>)         │
│   has been diagnosed with Type 2 Diabetes. The prescribed treatment is             │
│   Metformin 500mg."                                                                 │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 7: RESPONSE TO CLIENT                                                         │
│  ══════════════════════════                                                         │
│                                                                                      │
│  Response package:                                                                   │
│  {                                                                                   │
│    tokenized_response: "Based on the medical record, <<PII_NAME_a1b2>>...",        │
│    encrypted_token_map: <AES-256-GCM encrypted with session key>,                  │
│    entities_summary: {NAME: 1, NRIC: 1, EMAIL: 1}                                  │
│  }                                                                                   │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 8: CLIENT TOKEN REPLACEMENT                                                   │
│  ════════════════════════════════                                                   │
│                                                                                      │
│  Client actions:                                                                     │
│  1. Decrypt token map using session key                                             │
│  2. Replace all tokens with original values                                         │
│  3. Display final response to user                                                  │
│                                                                                      │
│  Final Response (displayed to user):                                                │
│  "Based on the medical record, John Doe (NRIC: 901231-14-5678) has been            │
│   diagnosed with Type 2 Diabetes. The prescribed treatment is Metformin 500mg."   │
│                                                                                      │
│  ✓ User sees complete response with actual values                                   │
│  ✓ LLM never saw actual PII                                                        │
│  ✓ Server no longer has any sensitive data                                          │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 7.3 Timing Breakdown

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         TYPICAL REQUEST TIMING                                       │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  Phase                              Duration        Cumulative                       │
│  ─────────────────────────────────────────────────────────────────                  │
│                                                                                      │
│  Client preparation                 50ms            50ms                             │
│  Network (client → server)          20ms            70ms                             │
│  ServiceShare validation            10ms            80ms                             │
│  Decryption (Rust)                  30ms            110ms                            │
│  PII Detection (parallel)           100ms           210ms                            │
│    ├─ Regex patterns                5ms                                              │
│    ├─ Presidio NER                  30ms                                             │
│    ├─ Phi-3 classification          50ms                                             │
│    └─ Result merging                15ms                                             │
│  Context validation (if needed)     300ms           510ms                            │
│  Tokenization                       20ms            530ms                            │
│  Zeroization                        5ms             535ms                            │
│  LLM API call                       1500ms          2035ms                           │
│  Response packaging                 10ms            2045ms                           │
│  Network (server → client)          20ms            2065ms                           │
│  Client token replacement           15ms            2080ms                           │
│  ─────────────────────────────────────────────────────────────────                  │
│  TOTAL                              ~2.1 seconds                                     │
│                                                                                      │
│  Note: LLM API call dominates; local processing is ~500ms                           │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Security Model

### 8.1 Data Visibility Matrix

| Actor | Plaintext Doc | Plaintext Query | Token Map | Final Response |
|-------|---------------|-----------------|-----------|----------------|
| Client | ✓ (decrypts) | ✓ (creates) | ✓ (decrypts) | ✓ (rebuilds) |
| Backend (Rust) | ✓ (briefly*) | ✓ (briefly*) | ✓ (briefly*) | ✗ |
| Backend (Elixir) | ✗ | ✗ | ✗ | ✗ (tokenized only) |
| LLM Provider | ✗ (tokens) | ✗ (tokens) | ✗ | ✗ (tokens) |
| Database | ✗ | ✗ | ✗ | ✗ |
| Logs | ✗ | ✗ | ✗ | ✗ |

*Briefly = in secure memory, zeroized immediately after use

### 8.2 Secure Memory Guarantees

```rust
/// Security properties enforced by Rust implementation

// 1. Memory locking - prevents swap
unsafe {
    libc::mlock(ptr as *const libc::c_void, size);
}

// 2. Automatic zeroization on drop
#[derive(ZeroizeOnDrop)]
pub struct SecureDek {
    inner: Secret<[u8; 32]>,
}

// 3. Panic-safe cleanup
let _cleanup = scopeguard::guard((), |_| {
    self.zeroize_all();
});

// 4. No core dumps
prctl::set_dumpable(false);
```

### 8.3 Threat Mitigations

| Threat | Mitigation |
|--------|------------|
| Memory dump attack | mlock prevents swap; core dumps disabled |
| Process crash leaking data | scopeguard ensures cleanup on any exit path |
| Elixir GC exposure | Sensitive data never enters Elixir heap |
| Log leakage | Only tokenized content logged |
| LLM data retention | Tokens meaningless without map |
| Man-in-the-middle | TLS 1.3 for all connections; mTLS for internal |
| Replay attack | ServiceShare is single-use with short expiry |

### 8.4 ServiceShare Security

ServiceShare grants temporary, scoped access to the PII service:

```elixir
%ServiceShare{
  user_id: "user-123",
  service_id: "pii-service",
  resource_type: "file",
  resource_id: "file-456",

  # Cryptographic access
  wrapped_key: <<...>>,      # DEK wrapped for service's public keys
  kem_ciphertexts: [...],    # PQC encapsulation

  # User's signature (proves authorization)
  signature: %{
    ml_dsa: <<...>>,
    kaz_sign: <<...>>
  },

  # Constraints
  purpose: "ai_query",
  expires_at: ~U[2026-01-21 12:05:00Z],  # 5 minute expiry
  used_at: nil  # Single use
}
```

---

## 9. PII Detection Strategy

### 9.1 Multi-Tier Detection Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         PII DETECTION PIPELINE                                       │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  INPUT DOCUMENT                                                                      │
│       │                                                                              │
│       ▼                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  TIER 1: PATTERN MATCHING (Rust, ~5ms)                                      │   │
│  │                                                                             │   │
│  │  High-confidence, deterministic patterns:                                   │   │
│  │  • SSN:         \d{3}-\d{2}-\d{4}                                          │   │
│  │  • NRIC:        \d{6}-\d{2}-\d{4} (with checksum validation)               │   │
│  │  • Email:       [a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}             │   │
│  │  • Phone:       Multiple patterns (MY, US, international)                  │   │
│  │  • Credit Card: Luhn-validated card patterns                               │   │
│  │  • IP Address:  IPv4 and IPv6 patterns                                     │   │
│  │                                                                             │   │
│  │  Confidence: 0.90-0.99                                                      │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│       │                                                                              │
│       ▼                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  TIER 2: ML-BASED NER (Presidio + spaCy, ~30ms)                            │   │
│  │                                                                             │   │
│  │  Named entity recognition:                                                  │   │
│  │  • PERSON:      Names of individuals                                        │   │
│  │  • ORG:         Organization names                                          │   │
│  │  • GPE:         Geographic/political entities                               │   │
│  │  • DATE:        Date expressions                                            │   │
│  │  • ADDRESS:     Physical addresses                                          │   │
│  │                                                                             │   │
│  │  Custom recognizers:                                                        │   │
│  │  • MY_NRIC:     Malaysian NRIC with context                                │   │
│  │  • MY_MYKAD:    MyKad references                                           │   │
│  │  • MRN:         Medical record numbers                                      │   │
│  │                                                                             │   │
│  │  Confidence: 0.70-0.90                                                      │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│       │                                                                              │
│       ▼                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  TIER 3: DOCUMENT CLASSIFICATION (Phi-3, ~50ms)                            │   │
│  │                                                                             │   │
│  │  Classify document domain:                                                  │   │
│  │  • medical:    Patient records, lab results, prescriptions                 │   │
│  │  • financial:  Bank statements, invoices, tax documents                    │   │
│  │  • legal:      Contracts, court documents, agreements                      │   │
│  │  • hr:         Employee records, resumes, performance reviews              │   │
│  │  • general:    Other documents                                             │   │
│  │                                                                             │   │
│  │  Enables domain-specific PII rules                                          │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│       │                                                                              │
│       ▼                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  TIER 4: CONTEXT VALIDATION (Mistral 7B, ~300ms, conditional)              │   │
│  │                                                                             │   │
│  │  For uncertain entities (confidence < 0.8):                                 │   │
│  │  • Is "Dr. Smith" a patient or provider?                                   │   │
│  │  • Is "Acme Corp" a client or public reference?                            │   │
│  │  • Is this date a DOB or a document date?                                  │   │
│  │                                                                             │   │
│  │  Domain-specific rules applied:                                             │   │
│  │  • Medical: Keep doctor names, redact patient names                        │   │
│  │  • Legal: Keep judge names, redact party names                             │   │
│  │  • Financial: Keep institution names, redact account holder names          │   │
│  │                                                                             │   │
│  │  Confidence: 0.85-0.95                                                      │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│       │                                                                              │
│       ▼                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  RESULT AGGREGATION                                                         │   │
│  │                                                                             │   │
│  │  • Merge overlapping detections                                             │   │
│  │  • Boost confidence for multi-model agreement                               │   │
│  │  • Apply user's PII policy                                                  │   │
│  │  • Generate final entity list with positions                               │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│       │                                                                              │
│       ▼                                                                              │
│  OUTPUT: List of PII entities with type, position, confidence                       │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 9.2 Supported PII Types

| Category | Type | Detection Method | Confidence |
|----------|------|------------------|------------|
| **High Sensitivity** | | | |
| | SSN | Regex + checksum | 0.99 |
| | NRIC (Malaysian) | Regex + validation | 0.98 |
| | Credit Card | Regex + Luhn | 0.99 |
| | Bank Account | Context + pattern | 0.85 |
| | Passport | Pattern + context | 0.90 |
| **Medium Sensitivity** | | | |
| | Email | Regex | 0.95 |
| | Phone | Multi-pattern | 0.90 |
| | Address | NER + pattern | 0.80 |
| | Date of Birth | NER + context | 0.85 |
| **Context-Dependent** | | | |
| | Person Name | NER + LLM validation | 0.75-0.95 |
| | Organization | NER | 0.70 |
| | Location | NER | 0.70 |

### 9.3 Domain-Specific Rules

```elixir
@domain_rules %{
  medical: %{
    always_redact: [:patient_name, :mrn, :ssn, :dob, :diagnosis],
    usually_keep: [:provider_name, :facility_name],
    context_dependent: [:medication, :treatment]
  },

  financial: %{
    always_redact: [:account_number, :ssn, :tax_id, :balance],
    usually_keep: [:institution_name, :merchant_name],
    context_dependent: [:transaction_amount, :date]
  },

  legal: %{
    always_redact: [:party_name, :witness_name, :ssn],
    usually_keep: [:attorney_name, :judge_name, :court_name],
    context_dependent: [:case_number, :address]
  },

  hr: %{
    always_redact: [:employee_name, :ssn, :salary, :performance_rating],
    usually_keep: [:company_name, :department],
    context_dependent: [:manager_name, :job_title]
  }
}
```

---

## 10. Event-Driven Synchronization

Since the PII Service has its own database (no foreign keys to main system), we need event-driven synchronization to handle file lifecycle events.

### 10.1 Event Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                    EVENT-DRIVEN SYNC BETWEEN SYSTEMS                                 │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│   MAIN SYSTEM                    EVENT BUS                    PII SERVICE           │
│   ═══════════                    ═════════                    ═══════════           │
│                                  (RabbitMQ/                                         │
│                                   Redis Streams)                                    │
│                                                                                      │
│   File Deleted ────────────►  file.deleted  ────────────►  Delete redacted file    │
│   {file_id, tenant_id,                                     Delete from conv_files  │
│    user_id}                                                Invalidate conversations │
│                                                                                      │
│   File Updated ────────────►  file.updated  ────────────►  Mark redacted as stale  │
│   {file_id, new_version,                                   (status = 'stale')       │
│    tenant_id}                                              Keep conversation valid  │
│                                                                                      │
│   User Deleted ────────────►  user.deleted  ────────────►  Delete ALL user's:      │
│   {user_id, tenant_id}                                     - conversations          │
│                                                            - redacted_files         │
│                                                            - messages               │
│                                                                                      │
│   Tenant Deleted ──────────►  tenant.deleted ───────────►  Delete ALL tenant's:    │
│   {tenant_id}                                              - conversations          │
│                                                            - redacted_files         │
│                                                            - token_maps             │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 10.2 Event Schemas

```json
// file.deleted event
{
  "event_id": "evt_01HZ...",
  "event_type": "file.deleted",
  "timestamp": "2026-01-21T10:30:00Z",
  "payload": {
    "file_id": "file-123",
    "tenant_id": "tenant-456",
    "user_id": "user-789",
    "deleted_by": "user-789"
  }
}

// file.updated event
{
  "event_id": "evt_01HZ...",
  "event_type": "file.updated",
  "timestamp": "2026-01-21T10:30:00Z",
  "payload": {
    "file_id": "file-123",
    "tenant_id": "tenant-456",
    "user_id": "user-789",
    "previous_version": 1,
    "new_version": 2,
    "update_type": "content"  // or "metadata"
  }
}

// user.deleted event
{
  "event_id": "evt_01HZ...",
  "event_type": "user.deleted",
  "timestamp": "2026-01-21T10:30:00Z",
  "payload": {
    "user_id": "user-789",
    "tenant_id": "tenant-456"
  }
}

// tenant.deleted event
{
  "event_id": "evt_01HZ...",
  "event_type": "tenant.deleted",
  "timestamp": "2026-01-21T10:30:00Z",
  "payload": {
    "tenant_id": "tenant-456"
  }
}
```

### 10.3 Event Consumer Implementation

```elixir
defmodule PIIService.EventConsumer do
  use GenServer
  require Logger

  @moduledoc """
  Consumes events from main system to maintain data consistency.
  Implements idempotent processing with event deduplication.
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Subscribe to relevant event channels
    :ok = EventBus.subscribe("file.*")
    :ok = EventBus.subscribe("user.*")
    :ok = EventBus.subscribe("tenant.*")

    {:ok, %{}}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Event Handlers
  # ──────────────────────────────────────────────────────────────────────────

  def handle_info({:event, "file.deleted", event}, state) do
    with :ok <- ensure_not_processed(event.event_id),
         :ok <- handle_file_deleted(event.payload) do
      mark_processed(event.event_id, "file.deleted")
    end
    {:noreply, state}
  end

  def handle_info({:event, "file.updated", event}, state) do
    with :ok <- ensure_not_processed(event.event_id),
         :ok <- handle_file_updated(event.payload) do
      mark_processed(event.event_id, "file.updated")
    end
    {:noreply, state}
  end

  def handle_info({:event, "user.deleted", event}, state) do
    with :ok <- ensure_not_processed(event.event_id),
         :ok <- handle_user_deleted(event.payload) do
      mark_processed(event.event_id, "user.deleted")
    end
    {:noreply, state}
  end

  def handle_info({:event, "tenant.deleted", event}, state) do
    with :ok <- ensure_not_processed(event.event_id),
         :ok <- handle_tenant_deleted(event.payload) do
      mark_processed(event.event_id, "tenant.deleted")
    end
    {:noreply, state}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Handler Implementations
  # ──────────────────────────────────────────────────────────────────────────

  defp handle_file_deleted(%{file_id: file_id, tenant_id: tenant_id}) do
    Logger.info("Processing file.deleted for file #{file_id}")

    Repo.transaction(fn ->
      # 1. Delete all redacted files for this original
      {deleted_count, _} =
        from(r in RedactedFile, where: r.original_file_id == ^file_id)
        |> Repo.delete_all()

      # 2. Remove from conversation_files
      from(cf in ConversationFile, where: cf.original_file_id == ^file_id)
      |> Repo.delete_all()

      # 3. Delete S3 objects
      delete_s3_objects_for_file(file_id, tenant_id)

      # 4. Check if any conversations now have zero files → archive them
      archive_empty_conversations()

      Logger.info("Deleted #{deleted_count} redacted files for #{file_id}")
    end)
  end

  defp handle_file_updated(%{file_id: file_id, new_version: new_version}) do
    Logger.info("Processing file.updated for file #{file_id} to version #{new_version}")

    # Mark redacted files as stale (don't delete - user might want to keep old version)
    {updated_count, _} =
      from(r in RedactedFile,
        where: r.original_file_id == ^file_id and r.original_version < ^new_version
      )
      |> Repo.update_all(set: [status: "stale", invalidated_at: DateTime.utc_now()])

    Logger.info("Marked #{updated_count} redacted files as stale")
    :ok
  end

  defp handle_user_deleted(%{user_id: user_id, tenant_id: tenant_id}) do
    Logger.info("Processing user.deleted for user #{user_id}")

    Repo.transaction(fn ->
      # Delete all user's conversations (cascades to messages, conversation_files)
      {conv_count, _} =
        from(c in Conversation, where: c.user_id == ^user_id and c.tenant_id == ^tenant_id)
        |> Repo.delete_all()

      # Delete redacted files not linked to conversations
      {file_count, _} =
        from(r in RedactedFile, where: r.user_id == ^user_id and r.tenant_id == ^tenant_id)
        |> Repo.delete_all()

      # Delete S3 objects
      delete_s3_objects_for_user(user_id, tenant_id)

      Logger.info("Deleted #{conv_count} conversations, #{file_count} redacted files for user #{user_id}")
    end)
  end

  defp handle_tenant_deleted(%{tenant_id: tenant_id}) do
    Logger.info("Processing tenant.deleted for tenant #{tenant_id}")

    Repo.transaction(fn ->
      # Delete all tenant's data (cascading)
      from(c in Conversation, where: c.tenant_id == ^tenant_id) |> Repo.delete_all()
      from(r in RedactedFile, where: r.tenant_id == ^tenant_id) |> Repo.delete_all()

      # Delete entire S3 prefix
      delete_s3_prefix("#{tenant_id}/")

      Logger.info("Deleted all data for tenant #{tenant_id}")
    end)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Idempotency
  # ──────────────────────────────────────────────────────────────────────────

  defp ensure_not_processed(event_id) do
    case Repo.get(ProcessedEvent, event_id) do
      nil -> :ok
      _   -> {:error, :already_processed}
    end
  end

  defp mark_processed(event_id, event_type) do
    %ProcessedEvent{}
    |> ProcessedEvent.changeset(%{event_id: event_id, event_type: event_type})
    |> Repo.insert!()
  end
end
```

### 10.4 Main System Event Publisher

The main SSDID Drive system must publish events when files/users/tenants are modified:

```elixir
# In main SSDID Drive system

defmodule SecureSharing.Files do
  def delete_file(file_id, user_id) do
    # ... delete file logic ...

    # Publish event for PII service
    EventBus.publish("file.deleted", %{
      event_id: Ecto.UUID.generate(),
      event_type: "file.deleted",
      timestamp: DateTime.utc_now(),
      payload: %{
        file_id: file_id,
        tenant_id: file.tenant_id,
        user_id: user_id,
        deleted_by: user_id
      }
    })
  end

  def update_file(file_id, updates, user_id) do
    # ... update file logic ...

    # Only publish if content changed (not just metadata)
    if updates[:content_changed] do
      EventBus.publish("file.updated", %{
        event_id: Ecto.UUID.generate(),
        event_type: "file.updated",
        timestamp: DateTime.utc_now(),
        payload: %{
          file_id: file_id,
          tenant_id: file.tenant_id,
          user_id: user_id,
          previous_version: file.version,
          new_version: file.version + 1,
          update_type: "content"
        }
      })
    end
  end
end
```

### 10.5 Reconciliation Job

Periodic job to catch any missed events and clean up orphaned data:

```elixir
defmodule PIIService.ReconciliationJob do
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Running reconciliation job")

    # 1. Find redacted files whose originals no longer exist
    orphaned_files = find_orphaned_redacted_files()
    Enum.each(orphaned_files, &delete_orphaned_file/1)

    # 2. Find conversations with all files removed
    empty_conversations = find_empty_conversations()
    Enum.each(empty_conversations, &archive_conversation/1)

    # 3. Clean up old processed_events (keep 7 days)
    cleanup_old_events()

    Logger.info("Reconciliation complete: #{length(orphaned_files)} orphaned files, #{length(empty_conversations)} empty conversations")

    :ok
  end

  defp find_orphaned_redacted_files do
    # Query main system API to verify files still exist
    from(r in RedactedFile, where: r.status == "valid")
    |> Repo.all()
    |> Enum.filter(fn rf ->
      case MainSystemClient.file_exists?(rf.original_file_id) do
        {:ok, true} -> false
        _ -> true  # File doesn't exist or API error - mark as orphaned
      end
    end)
  end
end
```

### 10.6 Handling Stale Redacted Files

When a file is updated in the main system, the redacted version becomes stale:

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                    STALE REDACTED FILE HANDLING                                      │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  SCENARIO: User updates original file                                               │
│                                                                                      │
│  Original file: report.pdf (version 1)                                              │
│  Redacted file: report_redacted.pdf (based on v1)                                   │
│                                                                                      │
│  User edits report.pdf → version 2                                                  │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  OPTIONS FOR USER:                                                                   │
│                                                                                      │
│  1. CONTINUE WITH STALE VERSION                                                     │
│     • Chat continues using old redacted content                                     │
│     • Warning shown: "Document has been updated since redaction"                    │
│     • User can download old redacted version                                        │
│                                                                                      │
│  2. REGENERATE REDACTED FILE                                                        │
│     • Trigger re-processing of updated file                                         │
│     • Token map updated with any new/changed PII                                   │
│     • Chat continues with fresh content                                             │
│                                                                                      │
│  3. START NEW CONVERSATION                                                          │
│     • Archive old conversation                                                      │
│     • Create new conversation with updated file                                     │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  UI INDICATION:                                                                      │
│                                                                                      │
│  ┌─────────────────────────────────────────┐                                       │
│  │  📎 report.pdf                          │                                       │
│  │  ⚠️ Document updated - redacted version │                                       │
│  │     is from an older version            │                                       │
│  │                                         │                                       │
│  │  [Regenerate]  [Continue Anyway]        │                                       │
│  └─────────────────────────────────────────┘                                       │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 11. API Specification

### 11.1 Conversation Endpoints

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# Create Conversation
# ─────────────────────────────────────────────────────────────────────────────

POST /api/v1/conversations

Description: Create a new AI conversation with selected files

Headers:
  Authorization: Bearer <session_token>
  Content-Type: application/json

Request Body:
  file_ids: [string]          # IDs of files to include
  folder_id: string           # OR specify a folder (includes all files)

  llm_provider: string        # "openai" | "anthropic" | "google"
  llm_model: string           # Optional, e.g., "gpt-4-turbo"

  pii_policy:
    detect_names: boolean
    detect_nric: boolean
    detect_email: boolean
    detect_phone: boolean
    detect_credit_card: boolean
    min_confidence: number    # 0.0-1.0

  # ServiceShare for file access (one per file)
  service_shares:
    - file_id: string
      wrapped_key: string (base64)
      kem_ciphertexts:
        ml_kem: string (base64)
        kaz_kem: string (base64)
      signature:
        ml_dsa: string (base64)
        kaz_sign: string (base64)

Response (202 Accepted):
  conversation_id: string (UUID)
  status: "processing"
  files:
    - file_id: string
      file_name: string
      processing_status: "pending"

# ─────────────────────────────────────────────────────────────────────────────
# Get Conversation Status
# ─────────────────────────────────────────────────────────────────────────────

GET /api/v1/conversations/{id}/status

Description: Check processing status of conversation

Response (200 OK):
  conversation_id: string
  status: "processing" | "ready" | "failed"
  progress: number              # 0-100
  files:
    - file_id: string
      file_name: string
      processing_status: "pending" | "processing" | "completed" | "failed"
      entities_detected: { NAME: number, NRIC: number, ... }
      error: string             # If failed

  total_pii_protected: number
  estimated_completion: string  # ISO 8601 timestamp

# ─────────────────────────────────────────────────────────────────────────────
# List Conversations
# ─────────────────────────────────────────────────────────────────────────────

GET /api/v1/conversations

Description: List user's conversations (history)

Query Parameters:
  status: string              # Filter by status
  limit: number               # Default 20
  offset: number              # For pagination

Response (200 OK):
  conversations:
    - id: string
      title: string
      status: string
      file_count: number
      message_count: number
      total_pii_protected: number
      llm_provider: string
      created_at: string
      last_message_at: string

  total: number
  has_more: boolean

# ─────────────────────────────────────────────────────────────────────────────
# Get Conversation Details
# ─────────────────────────────────────────────────────────────────────────────

GET /api/v1/conversations/{id}

Description: Get full conversation with messages

Response (200 OK):
  id: string
  title: string
  status: string
  llm_provider: string
  llm_model: string
  pii_policy: object

  files:
    - file_id: string
      file_name: string
      redacted_file_id: string
      entities_detected: object
      is_stale: boolean

  messages:
    - id: string
      role: "user" | "assistant" | "system"
      content_tokenized: string
      pii_in_message: object
      llm_metadata: object
      created_at: string

  token_map:
    encrypted_map: string (base64)
    map_nonce: string (base64)
    token_count: number
    version: number

  created_at: string
  updated_at: string

# ─────────────────────────────────────────────────────────────────────────────
# Archive/Delete Conversation
# ─────────────────────────────────────────────────────────────────────────────

DELETE /api/v1/conversations/{id}

Description: Archive or delete conversation

Query Parameters:
  mode: "archive" | "delete"  # Default: archive

Response (200 OK):
  success: true
```

### 11.2 Message Endpoints

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# Send Message (Chat)
# ─────────────────────────────────────────────────────────────────────────────

POST /api/v1/conversations/{id}/messages

Description: Send a message in conversation (query goes through PII redaction)

Headers:
  Authorization: Bearer <session_token>
  Content-Type: application/json

Request Body:
  encrypted_query: string (base64)    # User's query encrypted with session key
  query_nonce: string (base64)
  session_key_wrapped: string (base64) # For token map encryption

Response (200 OK):
  message_id: string

  # User message (tokenized)
  user_message:
    content_tokenized: string
    pii_in_message: { NAME: number, ... }

  # Assistant response (tokenized)
  assistant_message:
    content_tokenized: string
    llm_metadata:
      model: string
      tokens_used: number
      finish_reason: string

  # Updated token map (if new PII found in query)
  token_map:
    encrypted_map: string (base64)
    map_nonce: string (base64)
    version: number
    token_count: number
```

### 11.3 Redacted File Endpoints

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# Download Redacted File
# ─────────────────────────────────────────────────────────────────────────────

GET /api/v1/redacted-files/{id}/download

Description: Download encrypted redacted file

Response (200 OK):
  Content-Type: application/octet-stream
  Content-Disposition: attachment; filename="report_redacted.pdf"

  Body: <encrypted redacted file bytes>

# ─────────────────────────────────────────────────────────────────────────────
# Regenerate Redacted File
# ─────────────────────────────────────────────────────────────────────────────

POST /api/v1/conversations/{conv_id}/files/{file_id}/regenerate

Description: Regenerate redacted file from updated original

Request Body:
  service_share:              # Fresh ServiceShare for updated file
    wrapped_key: string (base64)
    kem_ciphertexts: ...
    signature: ...

Response (202 Accepted):
  redacted_file_id: string
  status: "processing"
```

### 11.4 Legacy AI Query Endpoint (Stateless)

For simple one-off queries without conversation history:

```yaml
POST /api/v1/ai/query

Description: Submit an AI query with automatic PII tokenization

Headers:
  Authorization: Bearer <session_token>
  Content-Type: application/json

Request Body:
  service_share:
    wrapped_key: string (base64)
    kem_ciphertexts:
      ml_kem: string (base64)
      kaz_kem: string (base64)
    signature:
      ml_dsa: string (base64)
      kaz_sign: string (base64)

  encrypted_query: string (base64)
  query_nonce: string (base64)

  session_key_wrapped: string (base64)  # For token map encryption

  llm_provider: string  # "openai" | "anthropic" | "google"
  llm_model: string     # Optional, e.g., "gpt-4-turbo"

  pii_policy:
    detect_names: boolean
    detect_nric: boolean
    detect_email: boolean
    detect_phone: boolean
    detect_credit_card: boolean
    min_confidence: number  # 0.0-1.0

Response (200 OK):
  session_id: string (UUID)
  tokenized_response: string
  encrypted_token_map: string (base64)
  token_map_nonce: string (base64)

  entities_summary:
    NAME: { count: number, in_document: number, in_query: number }
    NRIC: { count: number, in_document: number, in_query: number }
    # ... other types

  processing_proof:
    document_hash: string (SHA-256 of encrypted blob)
    timestamp: string (ISO 8601)
    service_signature:
      ml_dsa: string (base64)
      kaz_sign: string (base64)

  llm_metadata:
    model: string
    tokens_used: number
    finish_reason: string

Error Responses:
  400: Invalid request (missing fields, invalid format)
  401: Unauthorized (invalid session)
  403: Forbidden (invalid ServiceShare or expired)
  429: Rate limited
  500: Internal error
  503: LLM provider unavailable
```

### 11.5 Service Registration Endpoint

```yaml
GET /api/v1/services/pii-redaction/public-keys

Description: Get PII service public keys for creating ServiceShare

Response (200 OK):
  service_id: string (UUID)
  service_type: "pii_redaction"
  public_keys:
    ml_kem: string (base64)
    ml_dsa: string (base64)
    kaz_kem: string (base64)
    kaz_sign: string (base64)
  version: string
  capabilities:
    supported_pii_types: [string]
    supported_file_types: [string]
    max_file_size_mb: number
    supported_llm_providers: [string]
```

### 11.6 LLM Provider Configuration

```yaml
GET /api/v1/ai/providers

Description: List configured LLM providers for tenant

Response (200 OK):
  providers:
    - provider: "openai"
      enabled: boolean
      has_api_key: boolean
      models: ["gpt-4", "gpt-4-turbo"]
    - provider: "anthropic"
      enabled: boolean
      has_api_key: boolean
      models: ["claude-3-sonnet", "claude-3-opus"]

---

POST /api/v1/ai/providers/{provider}/configure

Description: Configure LLM provider for tenant

Request Body:
  encrypted_api_key: string (base64)  # Encrypted with tenant key
  api_key_nonce: string (base64)
  config:
    default_model: string
    max_tokens: number
    temperature: number

Response (200 OK):
  configured: true
  provider: string
```

---

## 12. Implementation Plan

### 12.1 Phase Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         IMPLEMENTATION PHASES                                        │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  PHASE 1: Foundation (4 weeks)                                                      │
│  ════════════════════════════                                                       │
│  • Service registration and ServiceShare entities                                   │
│  • Rust secure memory arena implementation                                          │
│  • Basic pattern-based PII detection                                               │
│  • Single LLM provider (OpenAI) integration                                        │
│                                                                                      │
│  PHASE 2: ML Detection (3 weeks)                                                    │
│  ═══════════════════════════════                                                    │
│  • Presidio service deployment                                                      │
│  • Custom Malaysian recognizers (NRIC, MyKad)                                       │
│  • Document classification with Phi-3                                              │
│  • Context validation with Mistral 7B                                              │
│                                                                                      │
│  PHASE 3: Bidirectional Tokenization (2 weeks)                                     │
│  ═════════════════════════════════════════════                                     │
│  • Query PII detection and tokenization                                            │
│  • Token map encryption for client                                                 │
│  • Client-side token replacement (iOS, Android)                                    │
│                                                                                      │
│  PHASE 4: Multi-Provider & Polish (2 weeks)                                        │
│  ══════════════════════════════════════════                                        │
│  • Anthropic Claude integration                                                    │
│  • Google Gemini integration                                                       │
│  • Tenant LLM configuration UI                                                     │
│  • Audit logging and monitoring                                                    │
│                                                                                      │
│  PHASE 5: Testing & Security (2 weeks)                                             │
│  ═════════════════════════════════════                                             │
│  • Security audit                                                                  │
│  • Penetration testing                                                             │
│  • Performance optimization                                                        │
│  • Documentation                                                                   │
│                                                                                      │
│  TOTAL: 13 weeks                                                                    │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 12.2 Phase 1: Foundation (Weeks 1-4)

**Week 1-2: Database & Service Registration**

```elixir
# New database tables
- services
- service_shares
- ai_query_sessions
- llm_provider_configs
```

**Deliverables:**
- [ ] Service entity and registration API
- [ ] ServiceShare entity and creation flow
- [ ] AI query session tracking
- [ ] Database migrations

**Week 3: Rust Secure Memory**

```rust
// Core secure memory implementation
- SecureArena (mlocked memory)
- SecureDek (zeroizing key wrapper)
- SecurePIIProcessor (main processor)
```

**Deliverables:**
- [ ] Rust NIF setup in project
- [ ] Secure memory arena with mlock
- [ ] Zeroizing wrappers for sensitive data
- [ ] Basic decryption in secure memory

**Week 4: Pattern Detection & OpenAI**

**Deliverables:**
- [ ] Regex-based PII detection (SSN, email, phone, NRIC)
- [ ] Tokenization and token map generation
- [ ] OpenAI API integration
- [ ] End-to-end flow (without ML detection)

### 12.3 Phase 2: ML Detection (Weeks 5-7)

**Week 5: Presidio Service**

**Deliverables:**
- [ ] Presidio Docker service
- [ ] spaCy model integration
- [ ] Elixir HTTP client for Presidio
- [ ] Custom Malaysian recognizers

**Week 6: Ollama Setup**

**Deliverables:**
- [ ] Ollama deployment with GPU support
- [ ] Phi-3 model for classification
- [ ] Mistral 7B for validation
- [ ] Elixir Ollama client

**Week 7: Detection Pipeline**

**Deliverables:**
- [ ] Parallel detection orchestration
- [ ] Result merging and confidence scoring
- [ ] Domain-specific rules engine
- [ ] Context validation for uncertain entities

### 12.4 Phase 3: Bidirectional Tokenization (Weeks 8-9)

**Week 8: Full Tokenization**

**Deliverables:**
- [ ] Query PII detection
- [ ] Consistent token generation (same value = same token)
- [ ] Token map encryption with session key
- [ ] Response packaging

**Week 9: Client Integration**

**Deliverables:**
- [ ] iOS token replacement implementation
- [ ] Android token replacement implementation
- [ ] Client session key generation
- [ ] UI for AI query feature

### 12.5 Phase 4: Multi-Provider & Polish (Weeks 10-11)

**Week 10: Additional Providers**

**Deliverables:**
- [ ] Anthropic Claude adapter
- [ ] Google Gemini adapter
- [ ] Provider health checking
- [ ] Automatic failover

**Week 11: Configuration & Monitoring**

**Deliverables:**
- [ ] Tenant LLM configuration API
- [ ] Usage tracking and quotas
- [ ] Audit logging
- [ ] Prometheus metrics

### 12.6 Phase 5: Testing & Security (Weeks 12-13)

**Week 12: Security**

**Deliverables:**
- [ ] Security audit by external team
- [ ] Penetration testing
- [ ] Fix identified vulnerabilities
- [ ] Security documentation

**Week 13: Performance & Documentation**

**Deliverables:**
- [ ] Performance profiling
- [ ] Latency optimization
- [ ] Load testing
- [ ] User documentation
- [ ] API documentation

---

## 13. Deployment Architecture

### 13.1 Staging Deployment

```yaml
# docker-compose.staging.yml

version: '3.8'

services:
  # Main SSDID Drive API
  api:
    build:
      context: .
      dockerfile: Dockerfile.api
    ports:
      - "4000:4000"
    environment:
      - DATABASE_URL=postgres://securesharing:${DB_PASS}@postgres:5432/securesharing
      - PII_SERVICE_URL=http://pii-service:4001
      - REDIS_URL=redis://redis:6379
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '4'
    depends_on:
      - postgres
      - redis
      - pii-service

  # PII Extraction Service
  pii-service:
    build:
      context: .
      dockerfile: Dockerfile.pii
    ports:
      - "4001:4001"
    environment:
      - OLLAMA_URL=http://ollama:11434
      - PRESIDIO_URL=http://presidio:5001
    deploy:
      resources:
        limits:
          memory: 20G
          cpus: '4'
    cap_add:
      - IPC_LOCK
    ulimits:
      memlock:
        soft: -1
        hard: -1
    security_opt:
      - no-new-privileges:true
    depends_on:
      - ollama
      - presidio

  # Ollama LLM Server
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        /bin/ollama serve &
        sleep 10
        ollama pull phi3:mini
        ollama pull mistral:7b
        wait

  # Presidio PII Detection
  presidio:
    build:
      context: ./services/presidio
      dockerfile: Dockerfile
    ports:
      - "5001:5001"
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2'

  # PostgreSQL
  postgres:
    image: postgres:16
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=securesharing
      - POSTGRES_USER=securesharing
      - POSTGRES_PASSWORD=${DB_PASS}
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2'

  # Redis
  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data
    deploy:
      resources:
        limits:
          memory: 1G

volumes:
  postgres_data:
  redis_data:
  ollama_data:
```

### 13.2 Production Deployment

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         PRODUCTION DEPLOYMENT                                        │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌─────────────────────────────┐       ┌─────────────────────────────┐             │
│  │      LOAD BALANCER          │       │      LOAD BALANCER          │             │
│  │        (API)                │       │       (PII Service)         │             │
│  └──────────────┬──────────────┘       └──────────────┬──────────────┘             │
│                 │                                      │                            │
│      ┌──────────┼──────────┐                ┌─────────┼─────────┐                  │
│      │          │          │                │         │         │                  │
│      ▼          ▼          ▼                ▼         ▼         ▼                  │
│  ┌───────┐  ┌───────┐  ┌───────┐      ┌───────┐ ┌───────┐ ┌───────┐              │
│  │ API-1 │  │ API-2 │  │ API-3 │      │ PII-1 │ │ PII-2 │ │ PII-3 │              │
│  │       │  │       │  │       │      │ +GPU  │ │ +GPU  │ │ +GPU  │              │
│  └───────┘  └───────┘  └───────┘      └───────┘ └───────┘ └───────┘              │
│                                                                                      │
│  SERVER POOL 1 (API)                  SERVER POOL 2 (PII + GPU)                    │
│  • 3x instances                       • 3x instances with GPU                       │
│  • 8 vCPU, 32GB RAM each             • 8 vCPU, 64GB RAM, RTX 4090 each            │
│  • No GPU required                    • Ollama, Presidio co-located                 │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  SHARED SERVICES:                                                                    │
│                                                                                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                    │
│  │   PostgreSQL    │  │      Redis      │  │   Object Store  │                    │
│  │   (Primary +    │  │   (Cluster)     │  │   (S3/MinIO)    │                    │
│  │    Replica)     │  │                 │  │                 │                    │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                    │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 13.3 Kubernetes Deployment (Optional)

```yaml
# k8s/pii-service.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: pii-service
  namespace: securesharing
spec:
  replicas: 3
  selector:
    matchLabels:
      app: pii-service
  template:
    metadata:
      labels:
        app: pii-service
    spec:
      containers:
        - name: pii-service
          image: securesharing/pii-service:latest
          resources:
            limits:
              memory: "20Gi"
              cpu: "4"
              nvidia.com/gpu: "1"
            requests:
              memory: "16Gi"
              cpu: "2"
          securityContext:
            capabilities:
              add:
                - IPC_LOCK
            allowPrivilegeEscalation: false
          env:
            - name: OLLAMA_URL
              value: "http://ollama:11434"
            - name: PRESIDIO_URL
              value: "http://presidio:5001"
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Exists"
          effect: "NoSchedule"
```

---

## 14. Server Sizing

### 14.1 Staging Environment

**Target:** 5-20 concurrent users, development and QA testing

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         STAGING SERVER SPECIFICATION                                 │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  SINGLE SERVER (Co-located services)                                                │
│                                                                                      │
│  HARDWARE:                                                                           │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│  CPU:        AMD Ryzen 9 7900X (12 cores / 24 threads)                             │
│  RAM:        64GB DDR5-5600                                                         │
│  GPU:        NVIDIA RTX 4070 Ti SUPER (16GB VRAM)                                  │
│  Storage:    2TB NVMe SSD (Samsung 990 Pro)                                        │
│  Network:    1Gbps Ethernet                                                         │
│                                                                                      │
│  ESTIMATED COST: ~$2,500 (one-time hardware)                                        │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  RESOURCE ALLOCATION:                                                                │
│                                                                                      │
│  Service              RAM        CPU       GPU/VRAM    Disk                         │
│  ─────────────────────────────────────────────────────────────────                  │
│  Elixir API           4 GB       4 cores   -           -                            │
│  PII Service          20 GB      4 cores   -           -                            │
│  Ollama               8 GB       2 cores   16 GB       20 GB                        │
│  Presidio             4 GB       2 cores   -           2 GB                         │
│  PostgreSQL           4 GB       2 cores   -           50 GB                        │
│  Redis                1 GB       0.5 cores -           1 GB                         │
│  OS + Buffers         8 GB       1.5 cores -           50 GB                        │
│  Reserved             15 GB      -         -           -                            │
│  ─────────────────────────────────────────────────────────────────                  │
│  TOTAL                64 GB      16 cores  16 GB       ~125 GB                      │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  PERFORMANCE EXPECTATIONS:                                                           │
│                                                                                      │
│  Operation                        Latency          Throughput                       │
│  ─────────────────────────────────────────────────────────────────                  │
│  File operations                  50-200ms         50 req/s                         │
│  PII detection (no LLM)           200-500ms        20 req/s                         │
│  Full AI query                    2-4 seconds      5 req/s                          │
│                                                                                      │
│  Concurrent users: 10-15 (medium usage)                                             │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 14.2 Production Environment

**Target:** 100-500 concurrent users, enterprise deployment

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         PRODUCTION SERVER SPECIFICATION                              │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  SEPARATE SERVER POOLS                                                              │
│                                                                                      │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│  API SERVER POOL (3 instances)                                                      │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│                                                                                      │
│  Per Instance:                                                                       │
│  CPU:        8 vCPU (Intel Xeon or AMD EPYC)                                       │
│  RAM:        32GB                                                                   │
│  Storage:    500GB SSD                                                             │
│  GPU:        None required                                                          │
│                                                                                      │
│  Cloud Equivalent:                                                                   │
│  • AWS: c6i.2xlarge ($0.34/hr) × 3 = ~$750/month                                   │
│  • GCP: n2-standard-8 ($0.39/hr) × 3 = ~$850/month                                 │
│  • Azure: Standard_D8s_v5 ($0.38/hr) × 3 = ~$820/month                             │
│                                                                                      │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│  PII SERVICE POOL (3 instances)                                                     │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│                                                                                      │
│  Per Instance:                                                                       │
│  CPU:        8 vCPU                                                                 │
│  RAM:        64GB (for secure memory arenas)                                        │
│  GPU:        NVIDIA A10 (24GB) or RTX 4090                                         │
│  Storage:    500GB SSD                                                             │
│                                                                                      │
│  Cloud Equivalent:                                                                   │
│  • AWS: g5.2xlarge ($1.21/hr) × 3 = ~$2,600/month                                  │
│  • GCP: a2-highgpu-1g ($3.67/hr) × 3 = ~$7,900/month                               │
│  • Azure: Standard_NC4as_T4_v3 ($0.53/hr) × 3 = ~$1,150/month                      │
│                                                                                      │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│  SHARED SERVICES                                                                    │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│                                                                                      │
│  PostgreSQL:                                                                         │
│  • Primary: 8 vCPU, 32GB RAM, 1TB SSD                                              │
│  • Replica: 4 vCPU, 16GB RAM, 1TB SSD                                              │
│  • AWS RDS: db.r6g.2xlarge = ~$700/month                                           │
│                                                                                      │
│  Redis:                                                                              │
│  • 3-node cluster, 8GB each                                                         │
│  • AWS ElastiCache: cache.r6g.large = ~$300/month                                  │
│                                                                                      │
│  Object Storage:                                                                     │
│  • S3/GCS/Azure Blob                                                               │
│  • Estimated: ~$100/month per TB                                                   │
│                                                                                      │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│  TOTAL ESTIMATED MONTHLY COST                                                       │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│                                                                                      │
│  AWS (recommended):                                                                  │
│  • API Pool:      $750                                                              │
│  • PII Pool:      $2,600                                                            │
│  • Database:      $700                                                              │
│  • Redis:         $300                                                              │
│  • Storage:       $200                                                              │
│  • Network:       $150                                                              │
│  ─────────────────────────                                                          │
│  TOTAL:           ~$4,700/month                                                     │
│                                                                                      │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│  PERFORMANCE EXPECTATIONS                                                           │
│  ═══════════════════════════════════════════════════════════════════════════════   │
│                                                                                      │
│  Operation                        Latency          Throughput                       │
│  ─────────────────────────────────────────────────────────────────                  │
│  File operations                  50-100ms         500 req/s                        │
│  PII detection (no LLM)           100-300ms        100 req/s                        │
│  Full AI query                    2-3 seconds      30 req/s                         │
│                                                                                      │
│  Concurrent users: 100-200 (medium usage)                                           │
│  Peak capacity: 500 users                                                           │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 14.3 Scaling Guidelines

| Metric | Trigger | Action |
|--------|---------|--------|
| API CPU > 70% | Sustained 5 min | Add API instance |
| PII CPU > 70% | Sustained 5 min | Add PII instance |
| GPU utilization > 80% | Sustained 5 min | Add PII instance |
| Memory > 85% | Any instance | Investigate leak or add capacity |
| AI query latency > 5s | P95 | Add PII instance or optimize |
| Queue depth > 100 | Sustained 1 min | Add PII instances |

---

## 15. Monitoring & Operations

### 15.1 Key Metrics

```yaml
# Prometheus metrics

# PII Detection Metrics
pii_detection_requests_total{status="success|failure"}
pii_detection_duration_seconds{phase="decrypt|detect|tokenize|total"}
pii_entities_detected_total{type="name|email|nric|..."}
pii_secure_memory_bytes{state="allocated|used"}

# LLM Metrics
llm_requests_total{provider="openai|anthropic|google", status="success|failure"}
llm_request_duration_seconds{provider}
llm_tokens_used_total{provider, type="input|output"}

# Security Metrics
service_share_validations_total{status="valid|invalid|expired"}
secure_memory_zeroizations_total
memory_lock_failures_total

# System Health
pii_service_healthy{instance}
ollama_model_loaded{model="phi3|mistral"}
presidio_healthy
```

### 15.2 Alerting Rules

```yaml
# Prometheus alerting rules

groups:
  - name: pii-service
    rules:
      - alert: PIIServiceHighLatency
        expr: histogram_quantile(0.95, pii_detection_duration_seconds) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PII detection latency high"

      - alert: PIIServiceErrorRate
        expr: rate(pii_detection_requests_total{status="failure"}[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "PII service error rate > 5%"

      - alert: MemoryLockFailure
        expr: increase(memory_lock_failures_total[5m]) > 0
        labels:
          severity: critical
        annotations:
          summary: "Secure memory lock failed - potential security issue"

      - alert: OllamaModelNotLoaded
        expr: ollama_model_loaded == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Ollama model not loaded"
```

### 15.3 Logging

```elixir
# Structured logging (no PII in logs)

Logger.info("AI query processed", %{
  session_id: session_id,
  user_id: user_id,
  tenant_id: tenant_id,
  file_id: file_id,

  # Metadata only, no actual values
  entities_detected: %{name: 2, email: 1, nric: 1},
  domain_detected: "medical",
  llm_provider: "openai",

  # Timing
  duration_ms: 2150,
  phases: %{
    decrypt: 30,
    detect: 100,
    tokenize: 20,
    llm_call: 2000
  }
})
```

---

## 16. Future Enhancements

### 16.1 Planned Improvements

| Enhancement | Priority | Description |
|-------------|----------|-------------|
| Streaming responses | High | Stream LLM responses as they're generated |
| Custom PII patterns | High | Allow tenants to define custom PII patterns |
| Fine-tuned models | Medium | Train domain-specific NER models |
| Caching | Medium | Cache detection results for repeated queries |
| Batch processing | Medium | Process multiple files in single request |
| TEE support | Low | Run in Trusted Execution Environment |
| On-device option | Low | Local processing for ultra-sensitive data |

### 16.2 Model Upgrade Path

```
Current:
├── Phi-3-mini (3.8B) - Classification
└── Mistral 7B - Validation

Future (with fine-tuning):
├── Phi-3-mini-ft (3.8B) - Fine-tuned on your document types
├── Mistral 7B-ft - Fine-tuned for domain-specific validation
├── Medical-NER - Specialized medical entity recognition
├── Financial-NER - Specialized financial entity recognition
└── Legal-NER - Specialized legal entity recognition
```

### 16.3 Integration Roadmap

- **Q2 2026:** Additional LLM providers (Cohere, AI21)
- **Q3 2026:** Document summarization before query
- **Q4 2026:** Multi-document queries
- **Q1 2027:** Conversational context (follow-up questions)

---

## 15. Client Integration Design

This section details how iOS, Android, and Desktop clients integrate with the PII Extraction Service to provide the "Ask AI" feature.

### 15.1 Client Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         CLIENT INTEGRATION ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                           CLIENT APPLICATION                                 │   │
│  ├─────────────────────────────────────────────────────────────────────────────┤   │
│  │                                                                             │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐            │   │
│  │  │   UI Layer      │  │  AI Query       │  │  Token          │            │   │
│  │  │                 │  │  Coordinator    │  │  Replacement    │            │   │
│  │  │ • Chat interface│  │                 │  │  Engine         │            │   │
│  │  │ • File selector │  │ • Session mgmt  │  │                 │            │   │
│  │  │ • History view  │  │ • Query flow    │  │ • Token parsing │            │   │
│  │  │ • Settings      │  │ • Error handling│  │ • Map decryption│            │   │
│  │  │                 │  │                 │  │ • Value replace │            │   │
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘            │   │
│  │           │                    │                    │                      │   │
│  │           └────────────────────┼────────────────────┘                      │   │
│  │                                │                                            │   │
│  │                                ▼                                            │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │   │
│  │  │                    AI Service Client                                 │  │   │
│  │  │                                                                      │  │   │
│  │  │  • ServiceShare creation (grant PII service access to file)         │  │   │
│  │  │  • Session key generation (for token map encryption)                │  │   │
│  │  │  • Query encryption (encrypt user query with session key)           │  │   │
│  │  │  • Response processing (decrypt token map, replace tokens)          │  │   │
│  │  │                                                                      │  │   │
│  │  └─────────────────────────────────────────────────────────────────────┘  │   │
│  │                                │                                            │   │
│  │                                ▼                                            │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │   │
│  │  │                    Crypto Layer (Native)                             │  │   │
│  │  │                                                                      │  │   │
│  │  │  • AES-256-GCM for session key operations                           │  │   │
│  │  │  • PQC key encapsulation (ML-KEM, KAZ-KEM)                          │  │   │
│  │  │  • Digital signatures (ML-DSA, KAZ-SIGN)                            │  │   │
│  │  │  • Secure random generation                                         │  │   │
│  │  │                                                                      │  │   │
│  │  └─────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                             │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 15.2 Client Flow Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         CLIENT-SIDE AI QUERY FLOW                                    │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  STEP 1: User Initiates AI Query                                                    │
│  ═══════════════════════════════                                                    │
│                                                                                      │
│  User actions:                                                                       │
│  1. Opens file in viewer                                                            │
│  2. Taps "Ask AI" button                                                            │
│  3. Types question: "What is the patient's diagnosis?"                              │
│  4. Taps "Send"                                                                     │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 2: Client Preparation                                                         │
│  ══════════════════════════                                                         │
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  2a. Fetch PII Service Public Keys (if not cached)                          │   │
│  │      GET /api/v1/services/pii-redaction/public-keys                         │   │
│  │                                                                             │   │
│  │  2b. Generate Ephemeral Session Key                                         │   │
│  │      session_key = random_bytes(32)  // AES-256                             │   │
│  │                                                                             │   │
│  │  2c. Create ServiceShare                                                    │   │
│  │      • Wrap file's DEK for PII service public keys                          │   │
│  │      • Sign with user's ML-DSA + KAZ-SIGN keys                              │   │
│  │      • Set 5-minute expiry                                                  │   │
│  │                                                                             │   │
│  │  2d. Encrypt Query                                                          │   │
│  │      encrypted_query = AES-GCM(session_key, query_plaintext)                │   │
│  │                                                                             │   │
│  │  2e. Wrap Session Key for Service                                           │   │
│  │      session_key_wrapped = KEM_Encapsulate(session_key, service_public_key) │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 3: Send Request to Backend                                                    │
│  ═══════════════════════════════                                                    │
│                                                                                      │
│  POST /api/v1/ai/query                                                              │
│  {                                                                                   │
│    service_share: { wrapped_key, kem_ciphertexts, signature },                      │
│    encrypted_query: <base64>,                                                       │
│    query_nonce: <base64>,                                                           │
│    session_key_wrapped: <base64>,                                                   │
│    llm_provider: "openai",                                                          │
│    pii_policy: { detect_names: true, detect_nric: true, ... }                       │
│  }                                                                                   │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 4: Receive Tokenized Response                                                 │
│  ══════════════════════════════════                                                 │
│                                                                                      │
│  Response received:                                                                  │
│  {                                                                                   │
│    tokenized_response: "Based on the record, <<PII_NAME_a1b2>> has...",            │
│    encrypted_token_map: <base64>,                                                   │
│    token_map_nonce: <base64>,                                                       │
│    entities_summary: { NAME: 2, NRIC: 1 }                                           │
│  }                                                                                   │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  STEP 5: Client Token Replacement                                                   │
│  ════════════════════════════════                                                   │
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  5a. Decrypt Token Map                                                      │   │
│  │      token_map = AES-GCM_Decrypt(session_key, encrypted_token_map, nonce)   │   │
│  │                                                                             │   │
│  │      Token map:                                                             │   │
│  │      {                                                                      │   │
│  │        "<<PII_NAME_a1b2>>": "John Doe",                                     │   │
│  │        "<<PII_NRIC_c3d4>>": "901231-14-5678"                                │   │
│  │      }                                                                      │   │
│  │                                                                             │   │
│  │  5b. Replace Tokens in Response                                             │   │
│  │      for each (token, value) in token_map:                                  │   │
│  │          response = response.replace(token, value)                          │   │
│  │                                                                             │   │
│  │  5c. Display Final Response to User                                         │   │
│  │      "Based on the record, John Doe has..."                                 │   │
│  │                                                                             │   │
│  │  5d. Securely Clear Session Key                                             │   │
│  │      session_key.zeroize()                                                  │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 15.3 iOS Implementation (Swift)

#### 15.3.1 Core Components

```swift
// MARK: - AI Service Client

import Foundation
import CryptoKit

/// Manages AI query requests with PII protection
final class AIServiceClient {

    // MARK: - Dependencies

    private let apiClient: APIClient
    private let cryptoService: CryptoService
    private let keyManager: KeyManager

    // MARK: - Cached Service Keys

    private var cachedServiceKeys: PIIServicePublicKeys?
    private var serviceKeysCacheExpiry: Date?

    // MARK: - Initialization

    init(apiClient: APIClient, cryptoService: CryptoService, keyManager: KeyManager) {
        self.apiClient = apiClient
        self.cryptoService = cryptoService
        self.keyManager = keyManager
    }

    // MARK: - Public API

    /// Execute an AI query with automatic PII tokenization
    func executeQuery(
        _ query: String,
        forFile file: SecureFile,
        llmProvider: LLMProvider,
        piiPolicy: PIIPolicy
    ) async throws -> AIQueryResult {

        // 1. Get service public keys (cached)
        let serviceKeys = try await fetchServicePublicKeys()

        // 2. Generate ephemeral session key
        let sessionKey = SymmetricKey(size: .bits256)

        // 3. Create ServiceShare for file
        let serviceShare = try await createServiceShare(
            forFile: file,
            serviceKeys: serviceKeys
        )

        // 4. Encrypt query with session key
        let (encryptedQuery, queryNonce) = try cryptoService.encrypt(
            data: query.data(using: .utf8)!,
            using: sessionKey
        )

        // 5. Wrap session key for service
        let wrappedSessionKey = try cryptoService.kemEncapsulate(
            key: sessionKey,
            recipientPublicKey: serviceKeys.mlKemPublicKey
        )

        // 6. Send request
        let request = AIQueryRequest(
            serviceShare: serviceShare,
            encryptedQuery: encryptedQuery.base64EncodedString(),
            queryNonce: queryNonce.base64EncodedString(),
            sessionKeyWrapped: wrappedSessionKey.base64EncodedString(),
            llmProvider: llmProvider.rawValue,
            piiPolicy: piiPolicy
        )

        let response: AIQueryResponse = try await apiClient.post(
            endpoint: "/api/v1/ai/query",
            body: request
        )

        // 7. Process response with token replacement
        let finalResponse = try processResponse(response, sessionKey: sessionKey)

        // 8. Securely clear session key
        // Note: CryptoKit handles secure memory, but we nil the reference

        return AIQueryResult(
            response: finalResponse,
            entitiesSummary: response.entitiesSummary,
            llmMetadata: response.llmMetadata
        )
    }

    // MARK: - Private Methods

    private func fetchServicePublicKeys() async throws -> PIIServicePublicKeys {
        // Check cache
        if let cached = cachedServiceKeys,
           let expiry = serviceKeysCacheExpiry,
           expiry > Date() {
            return cached
        }

        // Fetch from server
        let response: PIIServicePublicKeysResponse = try await apiClient.get(
            endpoint: "/api/v1/services/pii-redaction/public-keys"
        )

        let keys = PIIServicePublicKeys(
            serviceId: response.serviceId,
            mlKemPublicKey: Data(base64Encoded: response.publicKeys.mlKem)!,
            mlDsaPublicKey: Data(base64Encoded: response.publicKeys.mlDsa)!,
            kazKemPublicKey: Data(base64Encoded: response.publicKeys.kazKem)!,
            kazSignPublicKey: Data(base64Encoded: response.publicKeys.kazSign)!
        )

        // Cache for 1 hour
        cachedServiceKeys = keys
        serviceKeysCacheExpiry = Date().addingTimeInterval(3600)

        return keys
    }

    private func createServiceShare(
        forFile file: SecureFile,
        serviceKeys: PIIServicePublicKeys
    ) async throws -> ServiceShareDTO {

        // Get user's private keys for signing
        let userPrivateKeys = try keyManager.getUserPrivateKeys()

        // Get file's DEK
        let fileDek = try await keyManager.unwrapFileDek(for: file)

        // Wrap DEK for service using dual PQC (ML-KEM + KAZ-KEM)
        let mlKemCiphertext = try cryptoService.kemEncapsulate(
            key: fileDek,
            recipientPublicKey: serviceKeys.mlKemPublicKey
        )

        let kazKemCiphertext = try cryptoService.kazKemEncapsulate(
            key: fileDek,
            recipientPublicKey: serviceKeys.kazKemPublicKey
        )

        // Create signature payload
        let signaturePayload = ServiceShareSignaturePayload(
            userId: keyManager.currentUserId,
            serviceId: serviceKeys.serviceId,
            resourceType: "file",
            resourceId: file.id,
            purpose: "ai_query",
            expiresAt: Date().addingTimeInterval(300) // 5 minutes
        )

        let payloadData = try JSONEncoder().encode(signaturePayload)

        // Sign with both ML-DSA and KAZ-SIGN
        let mlDsaSignature = try cryptoService.mlDsaSign(
            data: payloadData,
            privateKey: userPrivateKeys.mlDsaPrivate
        )

        let kazSignSignature = try cryptoService.kazSign(
            data: payloadData,
            privateKey: userPrivateKeys.kazSignPrivate
        )

        return ServiceShareDTO(
            wrappedKey: mlKemCiphertext.base64EncodedString(),
            kemCiphertexts: KEMCiphertextsDTO(
                mlKem: mlKemCiphertext.base64EncodedString(),
                kazKem: kazKemCiphertext.base64EncodedString()
            ),
            signature: SignatureDTO(
                mlDsa: mlDsaSignature.base64EncodedString(),
                kazSign: kazSignSignature.base64EncodedString()
            ),
            purpose: "ai_query",
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        )
    }

    private func processResponse(
        _ response: AIQueryResponse,
        sessionKey: SymmetricKey
    ) throws -> String {

        // Decrypt token map
        guard let encryptedMapData = Data(base64Encoded: response.encryptedTokenMap),
              let nonceData = Data(base64Encoded: response.tokenMapNonce) else {
            throw AIServiceError.invalidResponse
        }

        let tokenMapData = try cryptoService.decrypt(
            data: encryptedMapData,
            using: sessionKey,
            nonce: nonceData
        )

        let tokenMap = try JSONDecoder().decode(
            [String: String].self,
            from: tokenMapData
        )

        // Replace tokens in response
        var finalResponse = response.tokenizedResponse
        for (token, actualValue) in tokenMap {
            finalResponse = finalResponse.replacingOccurrences(of: token, with: actualValue)
        }

        return finalResponse
    }
}
```

#### 15.3.2 DTOs and Models

```swift
// MARK: - Request/Response DTOs

struct AIQueryRequest: Codable {
    let serviceShare: ServiceShareDTO
    let encryptedQuery: String
    let queryNonce: String
    let sessionKeyWrapped: String
    let llmProvider: String
    let piiPolicy: PIIPolicy
}

struct AIQueryResponse: Codable {
    let sessionId: String
    let tokenizedResponse: String
    let encryptedTokenMap: String
    let tokenMapNonce: String
    let entitiesSummary: [String: EntitySummary]
    let llmMetadata: LLMMetadata
}

struct ServiceShareDTO: Codable {
    let wrappedKey: String
    let kemCiphertexts: KEMCiphertextsDTO
    let signature: SignatureDTO
    let purpose: String
    let expiresAt: String
}

struct KEMCiphertextsDTO: Codable {
    let mlKem: String
    let kazKem: String
}

struct SignatureDTO: Codable {
    let mlDsa: String
    let kazSign: String
}

struct PIIPolicy: Codable {
    var detectNames: Bool = true
    var detectNric: Bool = true
    var detectEmail: Bool = true
    var detectPhone: Bool = true
    var detectCreditCard: Bool = true
    var minConfidence: Double = 0.7
}

struct EntitySummary: Codable {
    let count: Int
    let inDocument: Int
    let inQuery: Int
}

struct LLMMetadata: Codable {
    let model: String
    let tokensUsed: Int
    let finishReason: String
}

// MARK: - Result Models

struct AIQueryResult {
    let response: String
    let entitiesSummary: [String: EntitySummary]
    let llmMetadata: LLMMetadata
}

enum LLMProvider: String, Codable, CaseIterable {
    case openai = "openai"
    case anthropic = "anthropic"
    case google = "google"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI GPT-4"
        case .anthropic: return "Anthropic Claude"
        case .google: return "Google Gemini"
        }
    }
}
```

#### 15.3.3 UI Components

```swift
// MARK: - Ask AI View Controller

import UIKit

final class AskAIViewController: UIViewController {

    // MARK: - Dependencies

    private let aiService: AIServiceClient
    private let file: SecureFile

    // MARK: - UI Components

    private lazy var chatCollectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { section, env in
            return Self.createChatLayout()
        }
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private lazy var inputContainerView: AIInputContainerView = {
        let view = AIInputContainerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        return view
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - State

    private var messages: [ChatMessage] = []
    private var selectedProvider: LLMProvider = .openai
    private var piiPolicy = PIIPolicy()

    // MARK: - Initialization

    init(aiService: AIServiceClient, file: SecureFile) {
        self.aiService = aiService
        self.file = file
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigation()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(chatCollectionView)
        view.addSubview(inputContainerView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            chatCollectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chatCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatCollectionView.bottomAnchor.constraint(equalTo: inputContainerView.topAnchor),

            inputContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // Add welcome message
        addWelcomeMessage()
    }

    private func setupNavigation() {
        title = "Ask AI"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(showSettings)
        )
    }

    private func addWelcomeMessage() {
        let welcome = ChatMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: "I can help you understand this document. Your privacy is protected - personal information is automatically redacted before being sent to the AI.",
            timestamp: Date()
        )
        messages.append(welcome)
        chatCollectionView.reloadData()
    }

    // MARK: - Actions

    @objc private func showSettings() {
        let settingsVC = AISettingsViewController(
            selectedProvider: selectedProvider,
            piiPolicy: piiPolicy
        )
        settingsVC.delegate = self
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }

    private func sendQuery(_ query: String) {
        // Add user message
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: query,
            timestamp: Date()
        )
        messages.append(userMessage)
        chatCollectionView.reloadData()
        scrollToBottom()

        // Show loading
        loadingIndicator.startAnimating()
        inputContainerView.setEnabled(false)

        Task {
            do {
                let result = try await aiService.executeQuery(
                    query,
                    forFile: file,
                    llmProvider: selectedProvider,
                    piiPolicy: piiPolicy
                )

                await MainActor.run {
                    loadingIndicator.stopAnimating()
                    inputContainerView.setEnabled(true)

                    // Add AI response
                    let aiMessage = ChatMessage(
                        id: UUID().uuidString,
                        role: .assistant,
                        content: result.response,
                        timestamp: Date(),
                        metadata: ChatMessageMetadata(
                            entitiesProtected: result.entitiesSummary.values.reduce(0) { $0 + $1.count },
                            llmModel: result.llmMetadata.model
                        )
                    )
                    messages.append(aiMessage)
                    chatCollectionView.reloadData()
                    scrollToBottom()
                }

            } catch {
                await MainActor.run {
                    loadingIndicator.stopAnimating()
                    inputContainerView.setEnabled(true)
                    showError(error)
                }
            }
        }
    }

    private func scrollToBottom() {
        guard !messages.isEmpty else { return }
        let indexPath = IndexPath(item: messages.count - 1, section: 0)
        chatCollectionView.scrollToItem(at: indexPath, at: .bottom, animated: true)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static func createChatLayout() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(100)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(100)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

        return section
    }
}

// MARK: - AIInputContainerViewDelegate

extension AskAIViewController: AIInputContainerViewDelegate {
    func inputContainerView(_ view: AIInputContainerView, didSubmitQuery query: String) {
        sendQuery(query)
    }
}

// MARK: - AISettingsViewControllerDelegate

extension AskAIViewController: AISettingsViewControllerDelegate {
    func settingsViewController(
        _ vc: AISettingsViewController,
        didUpdateProvider provider: LLMProvider,
        piiPolicy: PIIPolicy
    ) {
        self.selectedProvider = provider
        self.piiPolicy = piiPolicy
    }
}
```

### 15.4 Android Implementation (Kotlin)

#### 15.4.1 Core Components

```kotlin
// AIServiceClient.kt

package com.securesharing.ai

import com.securesharing.crypto.CryptoService
import com.securesharing.crypto.KeyManager
import com.securesharing.network.ApiClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec

/**
 * Manages AI query requests with PII protection.
 */
class AIServiceClient(
    private val apiClient: ApiClient,
    private val cryptoService: CryptoService,
    private val keyManager: KeyManager
) {

    // Cached service keys
    private var cachedServiceKeys: PIIServicePublicKeys? = null
    private var serviceKeysCacheExpiry: Long = 0

    /**
     * Execute an AI query with automatic PII tokenization.
     */
    suspend fun executeQuery(
        query: String,
        file: SecureFile,
        llmProvider: LLMProvider,
        piiPolicy: PIIPolicy
    ): AIQueryResult = withContext(Dispatchers.IO) {

        // 1. Get service public keys (cached)
        val serviceKeys = fetchServicePublicKeys()

        // 2. Generate ephemeral session key
        val sessionKey = generateSessionKey()

        try {
            // 3. Create ServiceShare for file
            val serviceShare = createServiceShare(file, serviceKeys)

            // 4. Encrypt query with session key
            val (encryptedQuery, queryNonce) = cryptoService.encrypt(
                data = query.toByteArray(Charsets.UTF_8),
                key = sessionKey
            )

            // 5. Wrap session key for service
            val wrappedSessionKey = cryptoService.kemEncapsulate(
                key = sessionKey.encoded,
                recipientPublicKey = serviceKeys.mlKemPublicKey
            )

            // 6. Send request
            val request = AIQueryRequest(
                serviceShare = serviceShare,
                encryptedQuery = Base64.getEncoder().encodeToString(encryptedQuery),
                queryNonce = Base64.getEncoder().encodeToString(queryNonce),
                sessionKeyWrapped = Base64.getEncoder().encodeToString(wrappedSessionKey),
                llmProvider = llmProvider.value,
                piiPolicy = piiPolicy
            )

            val response = apiClient.post<AIQueryRequest, AIQueryResponse>(
                endpoint = "/api/v1/ai/query",
                body = request
            )

            // 7. Process response with token replacement
            val finalResponse = processResponse(response, sessionKey)

            AIQueryResult(
                response = finalResponse,
                entitiesSummary = response.entitiesSummary,
                llmMetadata = response.llmMetadata
            )

        } finally {
            // 8. Securely clear session key
            // Note: We can't truly zeroize in JVM, but we release the reference
            // and rely on garbage collection
        }
    }

    private suspend fun fetchServicePublicKeys(): PIIServicePublicKeys {
        // Check cache
        if (cachedServiceKeys != null && System.currentTimeMillis() < serviceKeysCacheExpiry) {
            return cachedServiceKeys!!
        }

        // Fetch from server
        val response = apiClient.get<PIIServicePublicKeysResponse>(
            endpoint = "/api/v1/services/pii-redaction/public-keys"
        )

        val keys = PIIServicePublicKeys(
            serviceId = response.serviceId,
            mlKemPublicKey = Base64.getDecoder().decode(response.publicKeys.mlKem),
            mlDsaPublicKey = Base64.getDecoder().decode(response.publicKeys.mlDsa),
            kazKemPublicKey = Base64.getDecoder().decode(response.publicKeys.kazKem),
            kazSignPublicKey = Base64.getDecoder().decode(response.publicKeys.kazSign)
        )

        // Cache for 1 hour
        cachedServiceKeys = keys
        serviceKeysCacheExpiry = System.currentTimeMillis() + 3600_000

        return keys
    }

    private suspend fun createServiceShare(
        file: SecureFile,
        serviceKeys: PIIServicePublicKeys
    ): ServiceShareDTO {

        // Get user's private keys for signing
        val userPrivateKeys = keyManager.getUserPrivateKeys()

        // Get file's DEK
        val fileDek = keyManager.unwrapFileDek(file)

        // Wrap DEK for service using dual PQC (ML-KEM + KAZ-KEM)
        val mlKemCiphertext = cryptoService.kemEncapsulate(
            key = fileDek,
            recipientPublicKey = serviceKeys.mlKemPublicKey
        )

        val kazKemCiphertext = cryptoService.kazKemEncapsulate(
            key = fileDek,
            recipientPublicKey = serviceKeys.kazKemPublicKey
        )

        // Create signature payload
        val expiresAt = System.currentTimeMillis() + 300_000 // 5 minutes
        val signaturePayload = ServiceShareSignaturePayload(
            userId = keyManager.currentUserId,
            serviceId = serviceKeys.serviceId,
            resourceType = "file",
            resourceId = file.id,
            purpose = "ai_query",
            expiresAt = expiresAt
        )

        val payloadBytes = signaturePayload.toJson().toByteArray(Charsets.UTF_8)

        // Sign with both ML-DSA and KAZ-SIGN
        val mlDsaSignature = cryptoService.mlDsaSign(
            data = payloadBytes,
            privateKey = userPrivateKeys.mlDsaPrivate
        )

        val kazSignSignature = cryptoService.kazSign(
            data = payloadBytes,
            privateKey = userPrivateKeys.kazSignPrivate
        )

        return ServiceShareDTO(
            wrappedKey = Base64.getEncoder().encodeToString(mlKemCiphertext),
            kemCiphertexts = KEMCiphertextsDTO(
                mlKem = Base64.getEncoder().encodeToString(mlKemCiphertext),
                kazKem = Base64.getEncoder().encodeToString(kazKemCiphertext)
            ),
            signature = SignatureDTO(
                mlDsa = Base64.getEncoder().encodeToString(mlDsaSignature),
                kazSign = Base64.getEncoder().encodeToString(kazSignSignature)
            ),
            purpose = "ai_query",
            expiresAt = formatIso8601(expiresAt)
        )
    }

    private fun processResponse(
        response: AIQueryResponse,
        sessionKey: SecretKey
    ): String {

        // Decrypt token map
        val encryptedMapData = Base64.getDecoder().decode(response.encryptedTokenMap)
        val nonceData = Base64.getDecoder().decode(response.tokenMapNonce)

        val tokenMapBytes = cryptoService.decrypt(
            data = encryptedMapData,
            key = sessionKey,
            nonce = nonceData
        )

        val tokenMap: Map<String, String> = parseJsonMap(
            String(tokenMapBytes, Charsets.UTF_8)
        )

        // Replace tokens in response
        var finalResponse = response.tokenizedResponse
        for ((token, actualValue) in tokenMap) {
            finalResponse = finalResponse.replace(token, actualValue)
        }

        return finalResponse
    }

    private fun generateSessionKey(): SecretKey {
        val keyBytes = ByteArray(32)
        SecureRandom().nextBytes(keyBytes)
        return SecretKeySpec(keyBytes, "AES")
    }
}
```

#### 15.4.2 ViewModel and UI

```kotlin
// AskAIViewModel.kt

package com.securesharing.ui.ai

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.ai.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class AskAIViewModel @Inject constructor(
    private val aiServiceClient: AIServiceClient
) : ViewModel() {

    private val _uiState = MutableStateFlow(AskAIUiState())
    val uiState: StateFlow<AskAIUiState> = _uiState.asStateFlow()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private var file: SecureFile? = null

    fun initialize(file: SecureFile) {
        this.file = file
        addWelcomeMessage()
    }

    fun sendQuery(query: String) {
        val currentFile = file ?: return

        // Add user message
        addMessage(ChatMessage(
            role = ChatRole.USER,
            content = query,
            timestamp = System.currentTimeMillis()
        ))

        // Set loading state
        _uiState.value = _uiState.value.copy(isLoading = true)

        viewModelScope.launch {
            try {
                val result = aiServiceClient.executeQuery(
                    query = query,
                    file = currentFile,
                    llmProvider = _uiState.value.selectedProvider,
                    piiPolicy = _uiState.value.piiPolicy
                )

                // Add AI response
                addMessage(ChatMessage(
                    role = ChatRole.ASSISTANT,
                    content = result.response,
                    timestamp = System.currentTimeMillis(),
                    metadata = ChatMessageMetadata(
                        entitiesProtected = result.entitiesSummary.values
                            .sumOf { it.count },
                        llmModel = result.llmMetadata.model
                    )
                ))

                _uiState.value = _uiState.value.copy(isLoading = false)

            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    error = e.message
                )
            }
        }
    }

    fun updateProvider(provider: LLMProvider) {
        _uiState.value = _uiState.value.copy(selectedProvider = provider)
    }

    fun updatePiiPolicy(policy: PIIPolicy) {
        _uiState.value = _uiState.value.copy(piiPolicy = policy)
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }

    private fun addWelcomeMessage() {
        addMessage(ChatMessage(
            role = ChatRole.ASSISTANT,
            content = "I can help you understand this document. Your privacy is protected - personal information is automatically redacted before being sent to the AI.",
            timestamp = System.currentTimeMillis()
        ))
    }

    private fun addMessage(message: ChatMessage) {
        _messages.value = _messages.value + message
    }
}

data class AskAIUiState(
    val isLoading: Boolean = false,
    val error: String? = null,
    val selectedProvider: LLMProvider = LLMProvider.OPENAI,
    val piiPolicy: PIIPolicy = PIIPolicy()
)

data class ChatMessage(
    val id: String = java.util.UUID.randomUUID().toString(),
    val role: ChatRole,
    val content: String,
    val timestamp: Long,
    val metadata: ChatMessageMetadata? = null
)

data class ChatMessageMetadata(
    val entitiesProtected: Int,
    val llmModel: String
)

enum class ChatRole {
    USER, ASSISTANT
}
```

#### 15.4.3 Compose UI

```kotlin
// AskAIScreen.kt

package com.securesharing.ui.ai

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AskAIScreen(
    file: SecureFile,
    onNavigateToSettings: () -> Unit,
    viewModel: AskAIViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val messages by viewModel.messages.collectAsState()

    var queryText by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    LaunchedEffect(file) {
        viewModel.initialize(file)
    }

    // Auto-scroll to bottom when new messages arrive
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Ask AI") },
                actions = {
                    IconButton(onClick = onNavigateToSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Chat messages
            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                state = listState,
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(messages, key = { it.id }) { message ->
                    ChatMessageItem(message = message)
                }

                // Loading indicator
                if (uiState.isLoading) {
                    item {
                        Box(
                            modifier = Modifier.fillMaxWidth(),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                }
            }

            // Input area
            Surface(
                modifier = Modifier.fillMaxWidth(),
                tonalElevation = 2.dp
            ) {
                Row(
                    modifier = Modifier
                        .padding(16.dp)
                        .fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = queryText,
                        onValueChange = { queryText = it },
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("Ask a question...") },
                        enabled = !uiState.isLoading,
                        maxLines = 4
                    )

                    Spacer(modifier = Modifier.width(8.dp))

                    IconButton(
                        onClick = {
                            if (queryText.isNotBlank()) {
                                viewModel.sendQuery(queryText)
                                queryText = ""
                            }
                        },
                        enabled = !uiState.isLoading && queryText.isNotBlank()
                    ) {
                        Icon(Icons.Default.Send, contentDescription = "Send")
                    }
                }
            }
        }
    }

    // Error dialog
    uiState.error?.let { error ->
        AlertDialog(
            onDismissRequest = { viewModel.clearError() },
            title = { Text("Error") },
            text = { Text(error) },
            confirmButton = {
                TextButton(onClick = { viewModel.clearError() }) {
                    Text("OK")
                }
            }
        )
    }
}

@Composable
fun ChatMessageItem(message: ChatMessage) {
    val isUser = message.role == ChatRole.USER

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        Surface(
            modifier = Modifier.widthIn(max = 280.dp),
            shape = MaterialTheme.shapes.medium,
            color = if (isUser) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surfaceVariant
            }
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                Text(
                    text = message.content,
                    style = MaterialTheme.typography.bodyMedium
                )

                message.metadata?.let { metadata ->
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "${metadata.entitiesProtected} items protected • ${metadata.llmModel}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                    )
                }
            }
        }
    }
}
```

### 15.5 Desktop Implementation (Tauri/Rust)

#### 15.5.1 Rust Backend Commands

```rust
// src-tauri/src/ai/mod.rs

use serde::{Deserialize, Serialize};
use tauri::State;
use crate::crypto::{CryptoService, KeyManager};
use crate::api::ApiClient;

#[derive(Debug, Serialize, Deserialize)]
pub struct AIQueryRequest {
    pub file_id: String,
    pub query: String,
    pub llm_provider: String,
    pub pii_policy: PIIPolicy,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AIQueryResult {
    pub response: String,
    pub entities_summary: std::collections::HashMap<String, EntitySummary>,
    pub llm_metadata: LLMMetadata,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PIIPolicy {
    pub detect_names: bool,
    pub detect_nric: bool,
    pub detect_email: bool,
    pub detect_phone: bool,
    pub detect_credit_card: bool,
    pub min_confidence: f64,
}

#[tauri::command]
pub async fn execute_ai_query(
    request: AIQueryRequest,
    api_client: State<'_, ApiClient>,
    crypto_service: State<'_, CryptoService>,
    key_manager: State<'_, KeyManager>,
) -> Result<AIQueryResult, String> {

    // 1. Get service public keys
    let service_keys = fetch_service_public_keys(&api_client).await
        .map_err(|e| e.to_string())?;

    // 2. Generate ephemeral session key (32 bytes for AES-256)
    let session_key = crypto_service.generate_random_key(32)
        .map_err(|e| e.to_string())?;

    // Use scopeguard to ensure session key is zeroized
    let _session_key_guard = scopeguard::guard(session_key.clone(), |mut key| {
        zeroize::Zeroize::zeroize(&mut key);
    });

    // 3. Get file and create ServiceShare
    let file = key_manager.get_file(&request.file_id)
        .map_err(|e| e.to_string())?;

    let service_share = create_service_share(
        &file,
        &service_keys,
        &crypto_service,
        &key_manager,
    ).await.map_err(|e| e.to_string())?;

    // 4. Encrypt query with session key
    let (encrypted_query, query_nonce) = crypto_service.aes_gcm_encrypt(
        request.query.as_bytes(),
        &session_key,
    ).map_err(|e| e.to_string())?;

    // 5. Wrap session key for service
    let wrapped_session_key = crypto_service.kem_encapsulate(
        &session_key,
        &service_keys.ml_kem_public_key,
    ).map_err(|e| e.to_string())?;

    // 6. Send request
    let api_request = ApiAIQueryRequest {
        service_share,
        encrypted_query: base64::encode(&encrypted_query),
        query_nonce: base64::encode(&query_nonce),
        session_key_wrapped: base64::encode(&wrapped_session_key),
        llm_provider: request.llm_provider,
        pii_policy: request.pii_policy,
    };

    let response: ApiAIQueryResponse = api_client
        .post("/api/v1/ai/query", &api_request)
        .await
        .map_err(|e| e.to_string())?;

    // 7. Process response with token replacement
    let final_response = process_response(&response, &session_key, &crypto_service)
        .map_err(|e| e.to_string())?;

    Ok(AIQueryResult {
        response: final_response,
        entities_summary: response.entities_summary,
        llm_metadata: response.llm_metadata,
    })
}

fn process_response(
    response: &ApiAIQueryResponse,
    session_key: &[u8],
    crypto_service: &CryptoService,
) -> Result<String, Box<dyn std::error::Error>> {

    // Decrypt token map
    let encrypted_map = base64::decode(&response.encrypted_token_map)?;
    let nonce = base64::decode(&response.token_map_nonce)?;

    let token_map_bytes = crypto_service.aes_gcm_decrypt(
        &encrypted_map,
        session_key,
        &nonce,
    )?;

    let token_map: std::collections::HashMap<String, String> =
        serde_json::from_slice(&token_map_bytes)?;

    // Replace tokens in response
    let mut final_response = response.tokenized_response.clone();
    for (token, actual_value) in &token_map {
        final_response = final_response.replace(token, actual_value);
    }

    Ok(final_response)
}
```

#### 15.5.2 TypeScript Frontend

```typescript
// src/lib/ai/AIService.ts

import { invoke } from '@tauri-apps/api/tauri';

export interface AIQueryRequest {
  fileId: string;
  query: string;
  llmProvider: LLMProvider;
  piiPolicy: PIIPolicy;
}

export interface AIQueryResult {
  response: string;
  entitiesSummary: Record<string, EntitySummary>;
  llmMetadata: LLMMetadata;
}

export interface PIIPolicy {
  detectNames: boolean;
  detectNric: boolean;
  detectEmail: boolean;
  detectPhone: boolean;
  detectCreditCard: boolean;
  minConfidence: number;
}

export type LLMProvider = 'openai' | 'anthropic' | 'google';

export interface EntitySummary {
  count: number;
  inDocument: number;
  inQuery: number;
}

export interface LLMMetadata {
  model: string;
  tokensUsed: number;
  finishReason: string;
}

export class AIService {
  async executeQuery(request: AIQueryRequest): Promise<AIQueryResult> {
    return invoke<AIQueryResult>('execute_ai_query', {
      request: {
        file_id: request.fileId,
        query: request.query,
        llm_provider: request.llmProvider,
        pii_policy: {
          detect_names: request.piiPolicy.detectNames,
          detect_nric: request.piiPolicy.detectNric,
          detect_email: request.piiPolicy.detectEmail,
          detect_phone: request.piiPolicy.detectPhone,
          detect_credit_card: request.piiPolicy.detectCreditCard,
          min_confidence: request.piiPolicy.minConfidence,
        },
      },
    });
  }
}
```

#### 15.5.3 Svelte Component

```svelte
<!-- src/routes/files/[id]/ask-ai/+page.svelte -->

<script lang="ts">
  import { onMount } from 'svelte';
  import { AIService, type AIQueryResult, type LLMProvider, type PIIPolicy } from '$lib/ai/AIService';
  import ChatMessage from '$lib/components/ChatMessage.svelte';
  import { page } from '$app/stores';

  interface Message {
    id: string;
    role: 'user' | 'assistant';
    content: string;
    timestamp: Date;
    metadata?: {
      entitiesProtected: number;
      llmModel: string;
    };
  }

  const aiService = new AIService();

  let messages: Message[] = [];
  let queryText = '';
  let isLoading = false;
  let error: string | null = null;
  let selectedProvider: LLMProvider = 'openai';
  let piiPolicy: PIIPolicy = {
    detectNames: true,
    detectNric: true,
    detectEmail: true,
    detectPhone: true,
    detectCreditCard: true,
    minConfidence: 0.7,
  };

  $: fileId = $page.params.id;

  onMount(() => {
    addWelcomeMessage();
  });

  function addWelcomeMessage() {
    messages = [{
      id: crypto.randomUUID(),
      role: 'assistant',
      content: 'I can help you understand this document. Your privacy is protected - personal information is automatically redacted before being sent to the AI.',
      timestamp: new Date(),
    }];
  }

  async function sendQuery() {
    if (!queryText.trim() || isLoading) return;

    const query = queryText;
    queryText = '';

    // Add user message
    messages = [...messages, {
      id: crypto.randomUUID(),
      role: 'user',
      content: query,
      timestamp: new Date(),
    }];

    isLoading = true;
    error = null;

    try {
      const result = await aiService.executeQuery({
        fileId,
        query,
        llmProvider: selectedProvider,
        piiPolicy,
      });

      // Add AI response
      messages = [...messages, {
        id: crypto.randomUUID(),
        role: 'assistant',
        content: result.response,
        timestamp: new Date(),
        metadata: {
          entitiesProtected: Object.values(result.entitiesSummary)
            .reduce((sum, s) => sum + s.count, 0),
          llmModel: result.llmMetadata.model,
        },
      }];
    } catch (e) {
      error = e instanceof Error ? e.message : 'An error occurred';
    } finally {
      isLoading = false;
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      sendQuery();
    }
  }
</script>

<div class="flex flex-col h-full">
  <!-- Header -->
  <header class="flex items-center justify-between p-4 border-b">
    <h1 class="text-lg font-semibold">Ask AI</h1>
    <button class="btn btn-ghost btn-sm" on:click={() => { /* open settings */ }}>
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
      </svg>
    </button>
  </header>

  <!-- Messages -->
  <div class="flex-1 overflow-y-auto p-4 space-y-4">
    {#each messages as message (message.id)}
      <ChatMessage {message} />
    {/each}

    {#if isLoading}
      <div class="flex justify-center">
        <div class="loading loading-spinner loading-md"></div>
      </div>
    {/if}
  </div>

  <!-- Error -->
  {#if error}
    <div class="alert alert-error mx-4">
      <span>{error}</span>
      <button class="btn btn-ghost btn-sm" on:click={() => error = null}>Dismiss</button>
    </div>
  {/if}

  <!-- Input -->
  <div class="p-4 border-t">
    <div class="flex gap-2">
      <textarea
        bind:value={queryText}
        on:keydown={handleKeydown}
        placeholder="Ask a question..."
        class="textarea textarea-bordered flex-1 resize-none"
        rows="2"
        disabled={isLoading}
      />
      <button
        class="btn btn-primary"
        on:click={sendQuery}
        disabled={isLoading || !queryText.trim()}
      >
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"/>
        </svg>
      </button>
    </div>
  </div>
</div>
```

### 15.6 UI/UX Design Guidelines

#### 15.6.1 Entry Points

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         ASK AI ENTRY POINTS                                          │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  1. FILE VIEWER                                                                      │
│  ───────────────                                                                     │
│  • Floating action button (FAB) in bottom-right                                     │
│  • Shows AI sparkle icon (✨)                                                        │
│  • Tap opens Ask AI sheet/modal                                                     │
│                                                                                      │
│  ┌─────────────────────────────────┐                                                │
│  │  📄 report.pdf                  │                                                │
│  │                                 │                                                │
│  │  [Document content preview]     │                                                │
│  │                                 │                                                │
│  │                           ┌───┐ │                                                │
│  │                           │ ✨ │ │  ← Ask AI FAB                                 │
│  │                           └───┘ │                                                │
│  └─────────────────────────────────┘                                                │
│                                                                                      │
│  2. FILE CONTEXT MENU                                                               │
│  ────────────────────                                                               │
│  • Long-press on file shows context menu                                            │
│  • "Ask AI about this file" option                                                  │
│                                                                                      │
│  ┌─────────────────────────────────┐                                                │
│  │  📄 report.pdf                  │                                                │
│  ├─────────────────────────────────┤                                                │
│  │  📤 Share                       │                                                │
│  │  ✏️ Rename                       │                                                │
│  │  📥 Download                    │                                                │
│  │  ✨ Ask AI                      │  ← Context menu option                         │
│  │  🗑️ Delete                       │                                                │
│  └─────────────────────────────────┘                                                │
│                                                                                      │
│  3. TOOLBAR/ACTION BAR                                                              │
│  ─────────────────────                                                              │
│  • On desktop: Toolbar button when file selected                                    │
│  • Icon: AI sparkle with file icon                                                  │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

#### 15.6.2 Chat Interface Design

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         CHAT INTERFACE DESIGN                                        │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  ← Ask AI                                                           ⚙️      │   │
│  ├─────────────────────────────────────────────────────────────────────────────┤   │
│  │                                                                             │   │
│  │  ┌───────────────────────────────────────────────────────────┐            │   │
│  │  │  🤖 I can help you understand this document.              │            │   │
│  │  │     Your privacy is protected - personal information      │            │   │
│  │  │     is automatically redacted before being sent to        │            │   │
│  │  │     the AI.                                               │            │   │
│  │  └───────────────────────────────────────────────────────────┘            │   │
│  │                                                                             │   │
│  │                        ┌───────────────────────────────────────────────┐   │   │
│  │                        │  What is the patient's diagnosis?              │   │   │
│  │                        └───────────────────────────────────────────────┘   │   │
│  │                                                                             │   │
│  │  ┌───────────────────────────────────────────────────────────┐            │   │
│  │  │  🤖 Based on the medical record, John Doe has been        │            │   │
│  │  │     diagnosed with Type 2 Diabetes. The prescribed        │            │   │
│  │  │     treatment is Metformin 500mg.                         │            │   │
│  │  │                                                           │            │   │
│  │  │  🔒 3 items protected • GPT-4                             │            │   │
│  │  └───────────────────────────────────────────────────────────┘            │   │
│  │                                                                             │   │
│  │                        ┌───────────────────────────────────────────────┐   │   │
│  │                        │  What medications were prescribed?             │   │   │
│  │                        └───────────────────────────────────────────────┘   │   │
│  │                                                                             │   │
│  │  ┌───────────────────────────────────────────────────────────┐            │   │
│  │  │  🤖 The following medications were prescribed:            │            │   │
│  │  │     • Metformin 500mg - twice daily                       │            │   │
│  │  │     • Lisinopril 10mg - once daily                        │            │   │
│  │  │                                                           │            │   │
│  │  │  🔒 2 items protected • GPT-4                             │            │   │
│  │  └───────────────────────────────────────────────────────────┘            │   │
│  │                                                                             │   │
│  ├─────────────────────────────────────────────────────────────────────────────┤   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │   │
│  │  │  Ask a question...                                            [▶️]  │   │   │
│  │  └─────────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  DESIGN NOTES:                                                                       │
│  • User messages aligned right, AI messages aligned left                            │
│  • Privacy indicator shows entities protected                                       │
│  • Model name displayed for transparency                                            │
│  • Input field at bottom with send button                                           │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

#### 15.6.3 Settings Screen

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         AI SETTINGS SCREEN                                           │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  ← AI Settings                                                   Done       │   │
│  ├─────────────────────────────────────────────────────────────────────────────┤   │
│  │                                                                             │   │
│  │  LLM PROVIDER                                                               │   │
│  │  ─────────────                                                              │   │
│  │                                                                             │   │
│  │  ◉ OpenAI GPT-4                                                            │   │
│  │      Best for general questions                                            │   │
│  │                                                                             │   │
│  │  ○ Anthropic Claude                                                        │   │
│  │      Best for detailed analysis                                            │   │
│  │                                                                             │   │
│  │  ○ Google Gemini                                                           │   │
│  │      Best for multimodal content                                           │   │
│  │                                                                             │   │
│  │  ─────────────────────────────────────────────────────────────────────────  │   │
│  │                                                                             │   │
│  │  PRIVACY PROTECTION                                                         │   │
│  │  ─────────────────                                                          │   │
│  │                                                                             │   │
│  │  Detect and protect the following:                                          │   │
│  │                                                                             │   │
│  │  [✓] Names                    People's names                               │   │
│  │  [✓] NRIC / ID Numbers        Malaysian NRIC, passport numbers             │   │
│  │  [✓] Email Addresses          email@example.com                            │   │
│  │  [✓] Phone Numbers            +60-12-345-6789                              │   │
│  │  [✓] Credit Card Numbers      Card numbers with validation                 │   │
│  │                                                                             │   │
│  │  ─────────────────────────────────────────────────────────────────────────  │   │
│  │                                                                             │   │
│  │  CONFIDENCE THRESHOLD                                                       │   │
│  │  ────────────────────                                                       │   │
│  │                                                                             │   │
│  │  Minimum confidence: 70%                                                    │   │
│  │  [──────────●──────────────]                                               │   │
│  │                                                                             │   │
│  │  ℹ️ Lower values detect more potential PII but may                         │   │
│  │     include false positives                                                │   │
│  │                                                                             │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 15.7 Client Implementation Timeline

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         CLIENT IMPLEMENTATION TIMELINE                               │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  PHASE 1: Foundation (Week 8 of main implementation)                                │
│  ═══════════════════════════════════════════════════                                │
│                                                                                      │
│  iOS:                                                                                │
│  [ ] AIServiceClient basic implementation                                           │
│  [ ] ServiceShare creation for PII service                                          │
│  [ ] Session key generation and management                                          │
│  [ ] Query encryption/decryption                                                    │
│                                                                                      │
│  Android:                                                                            │
│  [ ] AIServiceClient basic implementation (parallel with iOS)                       │
│  [ ] ServiceShare creation for PII service                                          │
│  [ ] Session key generation and management                                          │
│  [ ] Query encryption/decryption                                                    │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  PHASE 2: Token Replacement (Week 9 of main implementation)                         │
│  ══════════════════════════════════════════════════════════                         │
│                                                                                      │
│  iOS:                                                                                │
│  [ ] Token map decryption                                                           │
│  [ ] Token replacement engine                                                       │
│  [ ] Response processing pipeline                                                   │
│                                                                                      │
│  Android:                                                                            │
│  [ ] Token map decryption (parallel with iOS)                                       │
│  [ ] Token replacement engine                                                       │
│  [ ] Response processing pipeline                                                   │
│                                                                                      │
│  Desktop:                                                                            │
│  [ ] Rust backend commands for AI queries                                           │
│  [ ] Token replacement in Rust                                                      │
│  [ ] Secure memory handling                                                         │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  PHASE 3: UI Implementation (Week 9-10)                                             │
│  ═══════════════════════════════════════                                            │
│                                                                                      │
│  iOS:                                                                                │
│  [ ] AskAIViewController with chat UI                                               │
│  [ ] ChatMessage cells                                                              │
│  [ ] Input container view                                                           │
│  [ ] Settings screen                                                                │
│  [ ] File viewer integration (FAB)                                                  │
│                                                                                      │
│  Android:                                                                            │
│  [ ] AskAIScreen Compose UI                                                         │
│  [ ] ChatMessage composable                                                         │
│  [ ] ViewModel implementation                                                       │
│  [ ] Settings screen                                                                │
│  [ ] File viewer integration (FAB)                                                  │
│                                                                                      │
│  Desktop:                                                                            │
│  [ ] Ask AI page (Svelte)                                                           │
│  [ ] Chat message component                                                         │
│  [ ] Settings dialog                                                                │
│  [ ] File viewer integration (toolbar)                                              │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  PHASE 4: Polish & Testing (Week 11)                                                │
│  ═══════════════════════════════════                                                │
│                                                                                      │
│  All Platforms:                                                                      │
│  [ ] Error handling and retry logic                                                 │
│  [ ] Loading states and animations                                                  │
│  [ ] Accessibility (VoiceOver, TalkBack)                                           │
│  [ ] Unit tests for service client                                                  │
│  [ ] Integration tests                                                              │
│  [ ] Performance optimization                                                       │
│  [ ] Memory leak testing                                                            │
│                                                                                      │
│  ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                      │
│  DELIVERABLES BY PLATFORM:                                                          │
│                                                                                      │
│  iOS:                                                                                │
│  • AIServiceClient.swift                                                            │
│  • AskAIViewController.swift                                                        │
│  • AISettingsViewController.swift                                                   │
│  • ChatMessage.swift (model)                                                        │
│  • AIInputContainerView.swift                                                       │
│  • ChatMessageCell.swift                                                            │
│                                                                                      │
│  Android:                                                                            │
│  • AIServiceClient.kt                                                               │
│  • AskAIViewModel.kt                                                                │
│  • AskAIScreen.kt                                                                   │
│  • ChatMessageItem.kt                                                               │
│  • AISettingsScreen.kt                                                              │
│                                                                                      │
│  Desktop (Tauri):                                                                   │
│  • src-tauri/src/ai/mod.rs                                                          │
│  • src/lib/ai/AIService.ts                                                          │
│  • src/routes/files/[id]/ask-ai/+page.svelte                                        │
│  • src/lib/components/ChatMessage.svelte                                            │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 15.8 Testing Strategy

#### 15.8.1 Unit Tests

```swift
// iOS Unit Tests

import XCTest
@testable import SecureSharing

final class AIServiceClientTests: XCTestCase {

    var sut: AIServiceClient!
    var mockApiClient: MockAPIClient!
    var mockCryptoService: MockCryptoService!
    var mockKeyManager: MockKeyManager!

    override func setUp() {
        super.setUp()
        mockApiClient = MockAPIClient()
        mockCryptoService = MockCryptoService()
        mockKeyManager = MockKeyManager()
        sut = AIServiceClient(
            apiClient: mockApiClient,
            cryptoService: mockCryptoService,
            keyManager: mockKeyManager
        )
    }

    func testExecuteQuery_createsValidServiceShare() async throws {
        // Given
        let file = SecureFile.mock()
        let query = "What is the diagnosis?"
        mockApiClient.mockResponse = AIQueryResponse.mock()

        // When
        _ = try await sut.executeQuery(
            query,
            forFile: file,
            llmProvider: .openai,
            piiPolicy: PIIPolicy()
        )

        // Then
        let request = mockApiClient.lastRequest as? AIQueryRequest
        XCTAssertNotNil(request?.serviceShare)
        XCTAssertEqual(request?.serviceShare.purpose, "ai_query")
    }

    func testExecuteQuery_encryptsQueryWithSessionKey() async throws {
        // Given
        let query = "Test query"
        mockApiClient.mockResponse = AIQueryResponse.mock()

        // When
        _ = try await sut.executeQuery(
            query,
            forFile: SecureFile.mock(),
            llmProvider: .openai,
            piiPolicy: PIIPolicy()
        )

        // Then
        XCTAssertTrue(mockCryptoService.encryptCalled)
        XCTAssertEqual(mockCryptoService.lastEncryptedData, query.data(using: .utf8))
    }

    func testProcessResponse_replacesTokensCorrectly() async throws {
        // Given
        let tokenizedResponse = "Patient <<PII_NAME_a1b2>> has condition X"
        let tokenMap = ["<<PII_NAME_a1b2>>": "John Doe"]
        mockApiClient.mockResponse = AIQueryResponse(
            sessionId: "test",
            tokenizedResponse: tokenizedResponse,
            encryptedTokenMap: mockEncryptedTokenMap(tokenMap),
            tokenMapNonce: "nonce123",
            entitiesSummary: [:],
            llmMetadata: LLMMetadata.mock()
        )

        // When
        let result = try await sut.executeQuery(
            "query",
            forFile: SecureFile.mock(),
            llmProvider: .openai,
            piiPolicy: PIIPolicy()
        )

        // Then
        XCTAssertEqual(result.response, "Patient John Doe has condition X")
    }
}
```

#### 15.8.2 Integration Tests

```kotlin
// Android Integration Tests

@HiltAndroidTest
class AIServiceIntegrationTest {

    @get:Rule
    val hiltRule = HiltAndroidRule(this)

    @Inject
    lateinit var aiServiceClient: AIServiceClient

    @Before
    fun setup() {
        hiltRule.inject()
    }

    @Test
    fun executeQuery_withRealBackend_returnsValidResponse() = runTest {
        // Given
        val file = createTestFile()
        val query = "What is the main topic of this document?"

        // When
        val result = aiServiceClient.executeQuery(
            query = query,
            file = file,
            llmProvider = LLMProvider.OPENAI,
            piiPolicy = PIIPolicy()
        )

        // Then
        assertThat(result.response).isNotEmpty()
        assertThat(result.response).doesNotContain("<<PII_")
    }

    @Test
    fun executeQuery_withPII_tokensAreReplaced() = runTest {
        // Given
        val file = createTestFileWithPII() // Contains "John Doe"
        val query = "What is John Doe's role?"

        // When
        val result = aiServiceClient.executeQuery(
            query = query,
            file = file,
            llmProvider = LLMProvider.OPENAI,
            piiPolicy = PIIPolicy(detectNames = true)
        )

        // Then
        // Response should contain "John Doe" (replaced by client)
        assertThat(result.response).contains("John Doe")
        // But entities summary should show names were detected
        assertThat(result.entitiesSummary["NAME"]?.count).isGreaterThan(0)
    }
}
```

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **PII** | Personal Identifiable Information - data that can identify an individual |
| **Tokenization** | Replacing sensitive values with non-sensitive placeholders |
| **Token Map** | Mapping between tokens and original values |
| **ServiceShare** | Cryptographic grant allowing a service to access encrypted content |
| **mlock** | System call to lock memory pages, preventing swap to disk |
| **Zeroization** | Securely overwriting memory with zeros to prevent data recovery |
| **NER** | Named Entity Recognition - ML technique to identify entities in text |
| **DEK** | Data Encryption Key - symmetric key used to encrypt file content |
| **KEK** | Key Encryption Key - key used to wrap/protect DEKs |

---

## Appendix B: References

- [SSDID Drive Architecture Overview](./01-architecture-overview.md)
- [Threat Model](./02-threat-model.md)
- [Encryption Protocol](../crypto/03-encryption-protocol.md)
- [Microsoft Presidio Documentation](https://microsoft.github.io/presidio/)
- [Ollama Documentation](https://ollama.ai/docs)
- [Zeroize Crate (Rust)](https://docs.rs/zeroize)

---

**Document Version History**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 2.0.0 | 2026-01-21 | System Architecture Team | Major revision: Standalone database design, Conversation model with chat history, Bidirectional PII redaction (documents + queries), Event-driven sync for file lifecycle, Persistent redacted files, Updated API endpoints for conversations/messages |
| 1.1.0 | 2026-01-21 | System Architecture Team | Added Section 17: Client Integration Design with iOS, Android, Desktop implementations |
| 1.0.0 | 2026-01-21 | System Architecture Team | Initial draft |
