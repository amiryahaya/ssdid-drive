# SecureSharing Development Guide

## Prerequisites

| Requirement | Version | Check |
|-------------|---------|-------|
| Elixir | 1.16+ | `elixir --version` |
| Erlang/OTP | 26+ | `erl -version` |
| Rust | 1.75+ | `rustc --version` |
| Docker | 24+ | `docker --version` |
| Docker Compose | 2.0+ | `docker-compose --version` |

### Installing Prerequisites

**macOS (Homebrew):**
```bash
brew install elixir rust
brew install --cask docker
```

**Ubuntu/Debian:**
```bash
# Elixir
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt update
sudo apt install elixir erlang-dev

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

## Quick Start

```bash
# 1. Clone the repository
git clone <repo-url>
cd SecureSharing

# 2. Copy environment file
cp .env.example .env

# 3. Start Docker services (PostgreSQL + Garage)
make dev.docker

# 4. Initialize Garage (first time only - outputs access keys)
make garage.init
# Copy the access keys to your .env file

# 5. Install deps and setup database
make deps
make db.setup

# 6. Start development server
make dev.server

# App running at http://localhost:4000
```

## Development Commands

### Daily Workflow

```bash
# Start everything
make dev

# Or start separately:
make dev.docker    # Start PostgreSQL + MinIO
make dev.server    # Start Phoenix server

# Stop services
make stop
```

### Testing

```bash
# Run all tests
make test

# Run tests in watch mode (re-runs on file change)
make test.watch

# Run with coverage
make test.cover

# Run only failed tests
make test.failed
```

### Code Quality

```bash
# Format code
make format

# Run linter
make lint

# Run type checker
make dialyzer

# Run all checks (format, lint, test)
make check
```

### Database

```bash
# Setup database (create + migrate)
make db.setup

# Reset database (drop + create + migrate)
make db.reset

# Run pending migrations
make db.migrate

# Rollback last migration
make db.rollback
```

## Project Structure

```
SecureSharing/
├── lib/
│   ├── secure_sharing/           # Business logic (Contexts)
│   │   ├── accounts/             # Users, tenants, credentials
│   │   ├── storage/              # Files, folders, blobs
│   │   ├── sharing/              # Share grants, share links
│   │   ├── recovery/             # Shamir recovery
│   │   ├── identity/             # IdP adapters
│   │   └── crypto/               # Rust NIF wrappers
│   │
│   ├── secure_sharing_web/       # Web layer
│   │   ├── controllers/          # REST API
│   │   ├── channels/             # WebSocket
│   │   └── live/                 # LiveView (admin)
│   │
│   └── secure_sharing_crypto/    # Rust NIF package
│       └── native/               # Rust source
│
├── test/                         # Tests mirror lib/ structure
├── priv/repo/migrations/         # Database migrations
├── config/                       # Environment configs
│
├── docs/                         # Documentation
│   ├── api/                      # API specifications
│   ├── crypto/                   # Cryptographic protocols
│   ├── flows/                    # Operation flows
│   └── development/              # Development guides
│
├── docker-compose.yml            # Development services
├── Makefile                      # Development commands
└── mix.exs                       # Project configuration
```

## Services

### PostgreSQL 18 (Port 5432)

Primary database with UUIDv7 support.

**Why PostgreSQL 18?**
- Built-in `uuidv7()` function
- Time-ordered UUIDs = better index performance
- No need for `uuid-ossp` extension

**Connect:**
```bash
psql -h localhost -U securesharing -d securesharing_dev
# Password: securesharing_dev
```

### Garage (Port 3900) - S3-Compatible Storage

Lightweight, Rust-based object storage.

**First-time setup:**
```bash
# Start services
make dev.docker

# Initialize Garage (creates bucket + access key)
make garage.init
```

The init script will output your access keys. Add them to `.env`:
```env
S3_ENDPOINT=http://localhost:3900
S3_ACCESS_KEY_ID=<from-init-output>
S3_SECRET_ACCESS_KEY=<from-init-output>
S3_BUCKET=securesharing-dev
S3_REGION=garage
```

**Ports:**
- **S3 API**: http://localhost:3900
- **Admin API**: http://localhost:3901

**Production Options:**
- Cloudflare R2 (recommended - no egress fees)
- Backblaze B2 (budget-friendly)
- AWS S3

### MailHog (Ports 1025, 8025) - Optional

Email testing. Start with:
```bash
make dev.email
```

- **SMTP**: localhost:1025
- **Web UI**: http://localhost:8025

### Redis (Port 6379) - Optional

For distributed setups. Start with:
```bash
make dev.redis
```

## Testing Strategy

### Test Types

| Type | Command | Purpose |
|------|---------|---------|
| Unit | `mix test test/secure_sharing/` | Context logic |
| Controller | `mix test test/secure_sharing_web/controllers/` | HTTP endpoints |
| Channel | `mix test test/secure_sharing_web/channels/` | WebSocket |
| Integration | `mix test test/integration/` | Full flows |

### TDD Workflow

1. Write failing test
2. Run `mix test path/to/test.exs` - confirm failure
3. Implement minimal code
4. Run test - confirm pass
5. Refactor
6. Run `make check` - ensure quality

### Property-Based Testing

For crypto operations, use StreamData:
```elixir
property "sign then verify" do
  check all message <- binary() do
    # Generate, sign, verify
  end
end
```

## Debugging

### IEx Session

```bash
# Start IEx with app loaded
make iex

# In IEx:
iex> alias SecureSharing.{Accounts, Storage}
iex> Accounts.get_user!("uuid")
```

### Debugging Tests

```elixir
# Add to test
IO.inspect(variable, label: "DEBUG")

# Or use debugger
require IEx; IEx.pry()
```

### Logging

```elixir
# In code
require Logger
Logger.debug("Debug message")
Logger.info("Info message")
Logger.warning("Warning message")
Logger.error("Error message")
```

## Common Issues

### NIF Compilation Fails

Ensure Rust is installed:
```bash
rustc --version
# If missing: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Database Connection Refused

Ensure Docker is running:
```bash
docker-compose ps
# If not running: make dev.docker
```

### MinIO Bucket Not Found

Reinitialize buckets:
```bash
docker-compose up minio-init
```

### Port Already in Use

Check what's using the port:
```bash
lsof -i :4000  # Phoenix
lsof -i :5432  # PostgreSQL
lsof -i :9000  # MinIO
```

## Documentation

- [Architecture Overview](docs/specs/01-architecture-overview.md)
- [API Specifications](docs/api/)
- [Cryptographic Protocols](docs/crypto/)
- [Development Plan](docs/development/01-elixir-development-plan.md)
