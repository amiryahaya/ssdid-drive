# SecureSharing Contabo Hosting Sizing Guide

**Document Version**: 1.1.0
**Date**: February 2026
**Classification**: Internal / Planning

---

> **Note**: This guide maps SecureSharing's hardware requirements (from `hardware-sizing-guide.md`) to Contabo's product lineup. **Pricing researched from [contabo.com](https://contabo.com) on February 2026** (EUR base prices, excluding VAT). Singapore region pricing is approximately 2.1x EU base. Conduct load testing before finalizing production specifications.

---

## Table of Contents

1. [Contabo Product Overview](#1-contabo-product-overview)
2. [Deployment Options](#2-deployment-options)
3. [Recommended Configurations](#3-recommended-configurations)
4. [Single-Server with Qwen2.5-14B](#4-single-server-with-qwen25-14b)
5. [Comparison with Other Providers](#5-comparison-with-other-providers)
6. [Object Storage](#6-object-storage)
7. [Network and Regions](#7-network-and-regions)
8. [Cost Summary](#8-cost-summary)

---

## 1. Contabo Product Overview

### Cloud VPS (Shared vCPU)

| Plan | vCPU | RAM | NVMe Storage | Bandwidth | EU Price/month | SG Price/month (est.) |
|------|------|-----|--------------|-----------|----------------|----------------------|
| Cloud VPS 10 | 4 | 8 GB | 75 GB | 200 Mbit/s | €4.50 | ~$10 |
| Cloud VPS 20 | 6 | 12 GB | 100 GB | 300 Mbit/s | €7.00 | ~$15 |
| Cloud VPS 30 | 8 | 24 GB | 200 GB | 600 Mbit/s | €14.00 | ~$30 |
| Cloud VPS 40 | 12 | 48 GB | 250 GB | 800 Mbit/s | €25.00 | ~$53 |
| Cloud VPS 50 | 16 | 64 GB | 300 GB | 1 Gbit/s | €37.00 | **~$78** |
| Cloud VPS 60 | 18 | 96 GB | 350 GB | 1 Gbit/s | €49.00 | **~$103** |

*Singapore pricing estimated from confirmed VPS 50 = $78 USD data point (approximately 2.1x EU base).*

### Storage VPS (Optimized for Data)

| Plan | vCPU | RAM | SSD Storage | Bandwidth | Price/month |
|------|------|-----|-------------|-----------|-------------|
| Storage VPS 30 | 6 | 18 GB | 1 TB | 600 Mbit/s | €14.00 |
| Storage VPS 40 | 8 | 30 GB | 1.2 TB | 800 Mbit/s | €25.00 |
| Storage VPS 50 | 14 | 50 GB | 1.4 TB | 1 Gbit/s | €37.00 |

### Virtual Dedicated Servers (VDS — Guaranteed Physical Cores)

| Plan | Physical Cores | RAM | NVMe Storage | Bandwidth | Price/month |
|------|----------------|-----|--------------|-----------|-------------|
| Cloud VDS S | 3 | 24 GB | 180 GB | 250 Mbit/s | €34.40 |
| Cloud VDS M | 4 | 32 GB | 240 GB | 500 Mbit/s | €44.80 |
| Cloud VDS L | 6 | 48 GB | 360 GB | 750 Mbit/s | €64.00 |
| Cloud VDS XL | 8 | 64 GB | 480 GB | 1 Gbit/s | €82.40 |
| Cloud VDS XXL | 12 | 96 GB | 720 GB | 1 Gbit/s | €119.00 |

*VDS use AMD EPYC 7282 (2.8 GHz) with dedicated physical cores.*

### Dedicated Bare Metal Servers

| Model | CPU | RAM | Storage | Bandwidth | Price/month |
|-------|-----|-----|---------|-----------|-------------|
| AMD Ryzen 12 | 12-core Ryzen 9 7900 (3.70 GHz) | 64 GB | 1 TB NVMe | 1 Gbit/s | €96.00 |
| AMD Genoa 24 | 24-core EPYC 9224 (2.50 GHz) | 128 GB ECC | 2x 1 TB SSD | 1 Gbit/s | €169.00 |

---

## 2. Deployment Options

### Option A: Single VPS — MVP / Pilot (< 50 users)

A single Cloud VPS running all components. No LLM/PII service, or use a cloud LLM API instead.

### Option B: Two VPS — Small Production (< 100 users)

Separate compute and data servers for better isolation and performance.

### Option C: Two-Server (VDS or Bare Metal) — Full Production (50-500 users)

Dedicated cores with full PII/LLM stack, mirroring the Hetzner two-server architecture.

---

## 3. Recommended Configurations

### Option A: Single VPS — MVP / Pilot

**Use case**: Development, demos, pilot with < 50 users, no local LLM

```
┌─────────────────────────────────────────────┐
│        Cloud VPS 40 (€25/month)             │
│                                             │
│  ┌─────────────────────────────────┐        │
│  │  Nginx (Reverse Proxy + SSL)    │        │
│  └─────────────────────────────────┘        │
│  ┌─────────────────────────────────┐        │
│  │  SecureSharing Backend (:4000)  │  8 GB  │
│  └─────────────────────────────────┘        │
│  ┌─────────────────────────────────┐        │
│  │  PostgreSQL 18                  │  8 GB  │
│  └─────────────────────────────────┘        │
│  ┌─────────────────────────────────┐        │
│  │  Garage S3                      │  2 GB  │
│  └─────────────────────────────────┘        │
│                                             │
│  12 vCPU │ 48 GB RAM │ 250 GB NVMe         │
└─────────────────────────────────────────────┘
```

| Component | RAM Allocation |
|-----------|---------------|
| OS & System | 2 GB |
| SecureSharing Backend | 8 GB |
| PostgreSQL 18 | 8 GB |
| Garage S3 | 2 GB |
| Nginx | 512 MB |
| Argon2 headroom (25 concurrent) | 1.6 GB |
| **Remaining buffer** | **~26 GB** |

**Plan**: Cloud VPS 40 — €25/month

> With 48 GB RAM and no LLM, there's substantial headroom. If budget is tight, Cloud VPS 30 (8 vCPU, 24 GB, €14/month) is viable for < 25 users.

---

### Option B: Two VPS — Small Production

**Use case**: Production with < 100 users, PII detection via Presidio (no local LLM)

```
┌─────────────────────────────┐    ┌─────────────────────────────┐
│   COMPUTE: Cloud VPS 30     │    │   DATA: Storage VPS 30      │
│   €14/month                 │    │   €14/month                 │
│                             │    │                             │
│  Nginx + SSL                │    │  PostgreSQL 18      8 GB   │
│  SecureSharing Backend 4 GB │    │  Garage S3          4 GB   │
│  PII Service           2 GB │    │                             │
│  Presidio NER          2 GB │    │  6 vCPU │ 18 GB │ 1 TB SSD │
│                             │    └─────────────────────────────┘
│  8 vCPU │ 24 GB │ 200 GB   │               │
└─────────────────────────────┘               │
              │                    Private Network
              └───────────────────────┘
```

| Server | Plan | RAM | Storage | Price |
|--------|------|-----|---------|-------|
| Compute | Cloud VPS 30 | 24 GB | 200 GB NVMe | €14.00 |
| Data | Storage VPS 30 | 18 GB | 1 TB SSD | €14.00 |
| **Total** | | | | **€28.00/month** |

---

### Option C: Two-Server Full Production (Recommended)

**Use case**: Production with 50-500 users, full PII + local LLM stack

This mirrors the Hetzner two-server architecture. Two options depending on budget:

#### Option C1: VDS (Budget-Friendly Production)

```
┌─────────────────────────────┐    ┌─────────────────────────────┐
│  COMPUTE: Cloud VDS XL      │    │  DATA: Cloud VDS L          │
│  €82.40/month               │    │  €64.00/month               │
│                             │    │                             │
│  Nginx + SSL                │    │  PostgreSQL 18     16 GB   │
│  SecureSharing Backend 8 GB │    │  Garage S3          8 GB   │
│  PII Service           4 GB │    │  Backups                    │
│  Presidio NER          2 GB │    │                             │
│  Qwen2.5-14B (CPU)   36 GB │    │  6 cores │ 48 GB │ 360 GB  │
│                             │    └─────────────────────────────┘
│  8 cores │ 64 GB │ 480 GB  │               │
└─────────────────────────────┘               │
              │                    Private Network
              └───────────────────────┘
```

| Server | Plan | Cores | RAM | Storage | Price |
|--------|------|-------|-----|---------|-------|
| Compute | Cloud VDS XL | 8 physical | 64 GB | 480 GB NVMe | €82.40 |
| Data | Cloud VDS L | 6 physical | 48 GB | 360 GB NVMe | €64.00 |
| **Total** | | | | | **€146.40/month** |

**Compute Memory Allocation:**

| Component | RAM | Notes |
|-----------|-----|-------|
| OS & System | 2 GB | |
| SecureSharing Backend | 8 GB | Elixir/Phoenix |
| PII Service | 4 GB | Elixir/Phoenix |
| Presidio + spaCy | 2 GB | Python NER |
| Qwen2.5-14B (CPU) | 36 GB | llama.cpp, Q4_K_M quantization |
| Argon2 headroom | 6.4 GB | 100 concurrent logins |
| Buffer | ~5.6 GB | |
| **Total** | **64 GB** | |

**Data Memory Allocation:**

| Component | RAM | Notes |
|-----------|-----|-------|
| OS & System | 2 GB | |
| PostgreSQL 18 | 16 GB | shared_buffers=4GB, effective_cache=12GB |
| Garage S3 | 8 GB | Object storage |
| Buffer | 22 GB | Backups, maintenance |
| **Total** | **48 GB** | |

> **Note**: LLM inference on CPU (no GPU) means slower response times (1-2s per validation vs 200-500ms with GPU). Contabo does not currently offer GPU instances.

#### Option C2: Bare Metal (Maximum Performance)

For workloads needing maximum CPU performance for LLM inference:

| Server | Plan | CPU | RAM | Storage | Price |
|--------|------|-----|-----|---------|-------|
| Compute | AMD Ryzen 12 | 12-core Ryzen 9 7900 | 64 GB | 1 TB NVMe | €96.00 |
| Data | Cloud VDS L | 6 physical cores | 48 GB | 360 GB NVMe | €64.00 |
| **Total** | | | | | **€160.00/month** |

The Ryzen 9 7900's single-threaded performance (3.70 GHz base, 5.4 GHz boost) significantly outperforms VDS EPYC cores for LLM inference.

---

## 4. Single-Server with Qwen2.5-14B

The Qwen2.5-14B model (Q4_K_M quantization) requires ~36 GB RAM. Only the **Cloud VPS 60 (96 GB RAM)** can accommodate the full stack with the 14B model on a single server.

### Cloud VPS 60 — Full Stack with LLM (Recommended for Qwen2.5-14B)

```
┌──────────────────────────────────────────────────┐
│          Cloud VPS 60 (~$103/month SG)           │
│          18 vCPU │ 96 GB RAM │ 350 GB NVMe       │
│                                                  │
│  ┌──────────────────────────────────────┐        │
│  │  Nginx (Reverse Proxy + SSL)         │        │
│  └──────────────────────────────────────┘        │
│  ┌──────────────────────────────────────┐        │
│  │  SecureSharing Backend (:4000)  8 GB │        │
│  └──────────────────────────────────────┘        │
│  ┌──────────────────────────────────────┐        │
│  │  PII Service (:4001)            4 GB │        │
│  └──────────────────────────────────────┘        │
│  ┌──────────────────────────────────────┐        │
│  │  Presidio NER                   2 GB │        │
│  └──────────────────────────────────────┘        │
│  ┌──────────────────────────────────────┐        │
│  │  Qwen2.5-14B (llama.cpp)      36 GB │        │
│  └──────────────────────────────────────┘        │
│  ┌──────────────────────────────────────┐        │
│  │  PostgreSQL 18                 16 GB │        │
│  └──────────────────────────────────────┘        │
│  ┌──────────────────────────────────────┐        │
│  │  Garage S3                      4 GB │        │
│  └──────────────────────────────────────┘        │
└──────────────────────────────────────────────────┘
```

| Component | RAM | Notes |
|-----------|-----|-------|
| OS & System | 2 GB | |
| Nginx | 512 MB | |
| SecureSharing Backend | 8 GB | Elixir/Phoenix |
| PII Service | 4 GB | Elixir/Phoenix |
| Presidio NER | 2 GB | spaCy + custom recognizers |
| Qwen2.5-14B (Q4_K_M) | 36 GB | llama.cpp, CPU inference |
| PostgreSQL 18 | 16 GB | shared_buffers=4GB, effective_cache=12GB |
| Garage S3 | 4 GB | Object storage |
| Argon2 headroom (50 concurrent) | 3.2 GB | |
| **Used** | **~76 GB** | |
| **Buffer** | **~20 GB** | Healthy margin |

**Cloud VPS 50 (64 GB) is NOT recommended** for Qwen2.5-14B — only ~2 GB buffer remains, creating OOM risk under load.

### Alternative: Smaller LLM on Cloud VPS 50

If budget requires VPS 50 (~$78/month SG), use phi3:mini (4 GB RAM) instead of Qwen2.5-14B:

| Component | VPS 60 + Qwen2.5-14B | VPS 50 + phi3:mini |
|-----------|----------------------|---------------------|
| LLM RAM | 36 GB | 4 GB |
| Total used | ~76 GB | ~44 GB |
| Buffer | ~20 GB | ~20 GB |
| LLM accuracy | Higher | Lower |
| LLM speed (CPU) | ~1-2s | ~800ms |
| **Monthly (SG)** | **~$103** | **~$78** |

---

## 5. Comparison with Other Providers

### Contabo vs Hetzner vs IPServerOne (February 2026)

| Aspect | Hetzner (AX52+AX42) | Contabo VPS 60 (SG) | Contabo VDS XL+L | IPServerOne C16+C4 (MY) | IPServerOne RAMOpt-C8 (MY) |
|--------|---------------------|---------------------|-------------------|--------------------------|----------------------------|
| Type | Bare metal (2 servers) | Single cloud VPS | 2x dedicated VDS | 2x cloud VPS | Single cloud VPS |
| Compute CPU | 16c/32t Ryzen 9 5950X | 18 shared vCPU | 8 physical EPYC | 16+4 shared vCPU | 8 shared vCPU |
| Total RAM | 128 GB (64+64) ECC | 96 GB | 112 GB (64+48) | 75 GB (60+15) | 120 GB |
| Storage | 2x1TB + 2x2TB | 350 GB NVMe | 840 GB NVMe | 10 GB base (+paid) | 10 GB base (+paid) |
| Bandwidth | 1 Gbit/s | 1 Gbit/s | 1 Gbit/s | 450 Mbit/s | 350 Mbit/s |
| Private Network | vSwitch (free) | N/A (single) | WireGuard | WireGuard | N/A (single) |
| Qwen2.5-14B fits? | Yes | Yes (20 GB buffer) | Yes (5.6 GB buffer) | Barely (7 GB buffer) | Yes (21 GB buffer) |
| Data location | EU (Germany) | APAC (Singapore) | EU/APAC | **Malaysia (Cyberjaya)** | **Malaysia (Cyberjaya)** |
| GPU option | No | No | No | **Yes (NovaGPU)** | **Yes (NovaGPU)** |
| **Monthly cost** | **~€104 (~$115)** | **~$103** | **~€146 (~$162)** | **~MYR 1,105 (~$251)** | **~MYR 1,134 (~$258)** |

**Key takeaways:**
- **Best value**: Contabo VPS 60 in Singapore (~$103/month) — best RAM/dollar with 96 GB on a single server
- **Best performance**: Hetzner bare metal (~€104) — dedicated cores, ECC RAM, more storage; note new accounts may be limited to cloud instances (max CPX62: 32 GB RAM)
- **Data sovereignty (Malaysia)**: IPServerOne — only option with servers in Cyberjaya; 2-3x more expensive but required if PDPA mandates in-country data
- **GPU-accelerated LLM**: IPServerOne NovaGPU — RTX 4090/5090 available in Malaysia (MYR 1,734-2,234/month)

---

## 6. Object Storage

For deployments needing more file storage than the VPS disk provides, use Contabo's S3-compatible Object Storage:

| Storage Tier | Price/month | Use Case |
|--------------|-------------|----------|
| 250 GB | €2.49 | Pilot / MVP |
| 500 GB | €4.98 | Small production |
| 1 TB | €9.96 | Medium production |
| 2 TB | €19.92 | Large production |
| 5 TB | €49.80 | Enterprise |

**Features**: S3-compatible API, unlimited transfer, triple replication, no egress fees.

This can **replace self-hosted Garage** for simpler operations at the cost of data leaving your server. For zero-knowledge architecture, encrypted blobs stored in Contabo Object Storage remain secure since the server never holds decryption keys.

---

## 7. Network and Regions

### Available Regions

Contabo operates in 9 regions across 11 locations:
- **EU**: Germany (Nuremberg, Munich), UK
- **US**: New York City, St. Louis, Seattle
- **APAC**: Singapore, Japan, Australia, India

### Private Networking

Unlike Hetzner's vSwitch, Contabo does not offer a managed private network product. For two-server setups, use:

1. **WireGuard VPN** (recommended) — lightweight, fast, encrypted tunnel between servers
2. **Tailscale** — zero-config WireGuard mesh

Example WireGuard setup between compute and data servers:

```
# Compute server (10.0.0.1) ◄──WireGuard──► Data server (10.0.0.2)
# PostgreSQL and Garage listen only on 10.0.0.2 (WireGuard interface)
```

### DDoS Protection

All Contabo plans include automatic DDoS protection at no extra cost.

---

## 8. Cost Summary

### All Contabo Options at a Glance

| Option | Target | Config | EU Price | SG Price (est.) |
|--------|--------|--------|----------|-----------------|
| **A: Budget MVP** | < 25 users | Cloud VPS 30 (no LLM) | €14/month | ~$30/month |
| **A: Single VPS MVP** | < 50 users | Cloud VPS 40 (no LLM) | €25/month | ~$53/month |
| **B: Two VPS** | < 100 users | VPS 30 + Storage VPS 30 (no LLM) | €28/month | ~$59/month |
| **D: Single VPS + small LLM** | < 100 users | Cloud VPS 50 + phi3:mini | €37/month | **~$78/month** |
| **E: Single VPS + Qwen2.5-14B** | < 100 users | **Cloud VPS 60** | €49/month | **~$103/month** |
| **C1: VDS Production** | 50-500 users | VDS XL + VDS L + Qwen2.5-14B | €146/month | ~$306/month |
| **C2: Bare Metal Prod** | 50-500 users | Ryzen 12 + VDS L + Qwen2.5-14B | €160/month | N/A (EU only) |

### Cross-Provider Comparison (Production with Qwen2.5-14B)

| Provider | Config | RAM | Monthly Cost | Data Location |
|----------|--------|-----|-------------|---------------|
| **Contabo VPS 60 (SG)** | Single server | 96 GB | **~$103** | Singapore |
| **Hetzner AX52+AX42** | 2x bare metal | 64+64 GB | **~$115** | Germany |
| **Contabo VDS XL+L** | 2x VDS | 64+48 GB | **~$162** | EU/SG |
| **IPServerOne C16+C4** | 2x cloud VPS | 60+15 GB | **~$251** | Malaysia |
| **IPServerOne RAMOpt-C8** | Single server | 120 GB | **~$258** | Malaysia |
| **AWS g4dn.4xlarge** | Single + GPU | 64 GB | **~$905** | Any region |

*See also: `ipserverone-hosting-sizing.md` for Malaysia-local options, `hetzner-two-server-deployment.md` for Hetzner deployment guide.*

### Recommendation

| Scenario | Recommended Option | Est. Cost |
|----------|--------------------|-----------|
| Demo / pilot / development | **Option A**: Cloud VPS 30 or 40 | €14-25 / $30-53 |
| Small production, no LLM | **Option B**: Two VPS | €28 / ~$59 |
| Production with Qwen2.5-14B (best value) | **Option E**: Cloud VPS 60 single server (SG) | **~$103** |
| Production with smaller LLM (budget) | **Option D**: Cloud VPS 50 + phi3:mini (SG) | **~$78** |
| Production with LLM (dedicated cores) | **Option C1**: VDS XL + VDS L | €146 / ~$306 (SG) |
| Data must stay in Malaysia | IPServerOne (see `ipserverone-hosting-sizing.md`) | MYR 1,105+ |

> **GPU limitation**: Contabo does not offer GPU instances. All LLM inference runs on CPU (1-2s per validation). For GPU-accelerated PII processing, consider IPServerOne NovaGPU (Malaysia), Hetzner GPU servers, or cloud providers (AWS/GCP).

---

**Document Control**

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | Feb 2026 | Initial Contabo sizing guide |
| 1.1.0 | Feb 2026 | Added Singapore pricing, single-server Qwen2.5-14B option, IPServerOne cross-comparison |

---

*Pricing sourced from [contabo.com](https://contabo.com) as of February 2026. EU prices in EUR excluding VAT. Singapore estimates based on confirmed VPS 50 = $78 USD. Actual requirements should be validated through load testing.*
