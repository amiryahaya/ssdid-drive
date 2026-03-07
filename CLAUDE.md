# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SecureSharing (SSDID Edition) — Zero-knowledge encrypted file sharing with pure SSDID authentication.

This is a fork of SecureSharing that replaces all traditional authentication (email/password, JWT, WebAuthn, OIDC) with **pure SSDID (Self-Sovereign Distributed Identity)** based on W3C DID 1.1.

## Architecture

```
Mobile/Desktop Client                SecureSharing Backend            SSDID Registry
┌─────────────────────┐             ┌─────────────────────┐         ┌──────────────┐
│ SSDID Vault (keys)  │◄──mutual──►│ ssdid_server (lib)  │◄──DID──►│ DID Documents│
│ SSDID Client        │   auth     │ Session Store        │  resolve│ Challenge API│
│ File encryption     │            │ VC Verifier          │         └──────────────┘
│ Key encapsulation   │            │ Phoenix API          │
└─────────────────────┘            │ PostgreSQL (metadata)│
                                   │ S3/Garage (blobs)    │
                                   └─────────────────────┘
```

## Key Differences from Original SecureSharing

| Feature | Original | SSDID Edition |
|---------|----------|---------------|
| Identity | Email + Password | DID (Decentralized Identifier) |
| Auth | JWT tokens (Joken) | SSDID session tokens (challenge-response) |
| Login | Bcrypt password verification | Mutual auth via DID signatures |
| WebAuthn | Yes (wax_ library) | Removed (SSDID replaces it) |
| OIDC | Yes (multiple providers) | Removed (SSDID replaces it) |
| PII Service | Yes (separate service) | Removed |
| User table | email required, hashed_password | did required, email optional |
| Session | JWT in Authorization header | SSDID session token in Authorization header |

## Repository Structure

```
ssdid-securesharing/
├── services/
│   └── securesharing/          # Backend (Elixir/Phoenix + ssdid_server)
│       ├── lib/
│       │   ├── secure_sharing/
│       │   │   ├── ssdid.ex              # SSDID identity init + context
│       │   │   ├── accounts.ex           # DID-based user management
│       │   │   └── accounts/user.ex      # User schema (DID primary identity)
│       │   └── secure_sharing_web/
│       │       ├── controllers/api/
│       │       │   └── ssdid_auth_controller.ex  # SSDID auth endpoints
│       │       ├── plugs/authenticate.ex          # SSDID session verification
│       │       └── router.ex                      # Routes
│       └── config/
├── clients/
│   ├── android/                # Android app (Kotlin/Compose)
│   ├── ios/                    # iOS app (Swift/SwiftUI)
│   └── desktop/                # Desktop app (Tauri + React)
└── docs/
```

## Authentication Flow

```
1. Client → POST /api/auth/ssdid/register {did, key_id}
   Server → {challenge, server_did, server_signature}

2. Client verifies server signature (mutual auth)
   Client → POST /api/auth/ssdid/register/verify {did, key_id, signed_challenge}
   Server → {credential (VC)}

3. Client → POST /api/auth/ssdid/authenticate {credential}
   Server → {session_token, server_signature, user, tenants}

4. All subsequent requests: Authorization: Bearer <session_token>
```

## SSDID Dependency

The backend depends on `ssdid_server_sdk` as a path dependency:
```
../../../SSDID/src/ssdid_server_sdk
```

This requires the SSDID repo to be checked out at `../../SSDID/` relative to this project root.

## Development

```bash
# Start infrastructure
docker-compose up -d

# Backend
cd services/securesharing
export SSDID_IDENTITY_PASSWORD=dev_password
mix deps.get && mix ecto.setup && mix phx.server
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SSDID_IDENTITY_PASSWORD` | Yes | Password protecting server's SSDID keypair |
| `SSDID_REGISTRY_URL` | No | Registry URL (default: https://registry.ssdid.my) |
| `DATABASE_URL` | Yes (prod) | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Yes (prod) | Phoenix secret key |
| `S3_BUCKET` | No | S3 bucket for file storage |
