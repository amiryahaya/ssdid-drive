# SecureSharing IPServerOne Hosting Sizing Guide (Malaysia)

**Document Version**: 1.0.0
**Date**: February 2026
**Classification**: Internal / Planning

---

> **Note**: This guide maps SecureSharing's hardware requirements (from `hardware-sizing-guide.md`) to IPServerOne's product lineup. **Pricing researched from [ipserverone.com](https://www.ipserverone.com) on February 2026**. All MYR prices subject to 8% SST. USD estimates use MYR 1 = USD 0.227 (as referenced by IPServerOne: USD 1 = MYR 4.4). Conduct load testing before finalizing production specifications.

---

## Table of Contents

1. [Why IPServerOne](#1-why-ipserverone)
2. [Product Overview](#2-product-overview)
3. [Recommended Configurations](#3-recommended-configurations)
4. [GPU-Accelerated Option (NovaGPU)](#4-gpu-accelerated-option-novagpu)
5. [Storage Considerations](#5-storage-considerations)
6. [Network and Data Center](#6-network-and-data-center)
7. [Comparison with Contabo and Hetzner](#7-comparison-with-contabo-and-hetzner)
8. [Cost Summary](#8-cost-summary)

---

## 1. Why IPServerOne

IPServerOne is a Malaysian hosting provider with a **Tier III-certified data center in Cyberjaya**. Key reasons to choose IPServerOne:

- **Data sovereignty**: Servers physically located in Malaysia — critical for PDPA (Personal Data Protection Act 2010) compliance or government tender requirements mandating in-country data residency
- **Local support**: Malaysian business hours, MYR billing, local SLA
- **GPU availability**: NovaGPU service offers RTX 3090/4090/5090 and H200 NVL for AI workloads — the only provider in this comparison with GPU options in Malaysia
- **Managed services**: Optional managed infrastructure, backup (Veeam), DRaaS

**Trade-offs vs international providers:**
- 2-3x more expensive than Contabo/Hetzner for equivalent specs
- Lower bandwidth (100-550 Mbit/s vs 1 Gbit/s)
- Low base storage on cloud instances (10 GiB — additional storage at MYR 0.60/GiB)
- Older CPUs on bare metal plans (Xeon E3 generation)

---

## 2. Product Overview

### NovaCloud — General CPU (Cloud VPS)

| Plan | vCPU | RAM | Network | MYR/month | USD/month |
|------|------|-----|---------|-----------|-----------|
| C1 | 1 | 3.75 GB | 100 Mbit/s | MYR 44 | $10 |
| C2 | 2 | 7.5 GB | 150 Mbit/s | MYR 81 | $18 |
| C4 | 4 | 15 GB | 250 Mbit/s | MYR 161 | $37 |
| C8 | 8 | 30 GB | 350 Mbit/s | MYR 322 | $73 |
| **C16** | **16** | **60 GB** | **450 Mbit/s** | **MYR 644** | **$146** |
| C32 | 32 | 120 GB | 550 Mbit/s | MYR 1,288 | $293 |

*All plans include 10 GiB storage, 1 TiB data transfer, 1x IPv4/IPv6. Hourly billing available.*

### NovaCloud — RAM Optimized

| Plan | vCPU | RAM | Network | MYR/month | USD/month |
|------|------|-----|---------|-----------|-----------|
| RAMOpt-C2 | 2 | 30 GB | 150 Mbit/s | MYR 212 | $48 |
| **RAMOpt-C4** | **4** | **60 GB** | **250 Mbit/s** | **MYR 417** | **$95** |
| **RAMOpt-C8** | **8** | **120 GB** | **350 Mbit/s** | **MYR 834** | **$190** |
| RAMOpt-C12 | 12 | 240 GB | 450 Mbit/s | MYR 1,596 | $363 |

*Best for LLM workloads requiring high RAM-to-CPU ratio.*

### Bare Metal (Malaysia — Cyberjaya)

| Plan | CPU | RAM | Storage | Bandwidth | MYR/month | USD/month |
|------|-----|-----|---------|-----------|-----------|-----------|
| Basic | 4-core Xeon E3 | 32 GB | 2x 1TB HDD | 100 Mbit/s | MYR 549 | $125 |
| Lite | 4-core Xeon E3 | 64 GB | 2x 2TB NL SAS | 100 Mbit/s | MYR 599 | $136 |
| Pro | 6-core Xeon E | 64 GB | 2x 2TB NL SAS | 100 Mbit/s | MYR 779 | $177 |
| Business | 8-core EPYC | 128 GB | 2x 960GB SSD | 100 Mbit/s | MYR 1,299 | $295 |
| Business Plus | 8-core EPYC | 256 GB | 2x 960GB SSD | 300 Mbit/s | MYR 1,919 | $436 |

*Setup fee: MYR 380 (one-time). All prices + 8% SST.*

### NovaGPU (GPU-as-a-Service)

| GPU | VRAM | CPU | RAM | MYR/hour | MYR/month | USD/month |
|-----|------|-----|-----|----------|-----------|-----------|
| RTX 3090 | 24 GB GDDR6X | 8-core EPYC | 120 GB | MYR 1.82 | MYR 1,334 | $303 |
| **RTX 4090** | **24 GB GDDR6X** | **8-core EPYC** | **120 GB** | **MYR 2.37** | **MYR 1,734** | **$394** |
| RTX 5090 | 32 GB GDDR7 | 8-core EPYC | 120 GB | MYR 3.05 | MYR 2,234 | $508 |
| RTX 6000 Ada | 48 GB GDDR6 | 8-core EPYC | 120 GB | MYR 4.84 | MYR 3,535 | $804 |

*All NovaGPU instances include 1 Gbit/s bandwidth. Storage: MYR 0.60/GiB. Multi-GPU options available.*

---

## 3. Recommended Configurations

### Option A: Single Cloud VPS — MVP / Pilot (No LLM)

**Use case**: Development, demos, pilot with < 50 users, Presidio NER only

| Plan | vCPU | RAM | Storage Add-on | MYR/month | USD/month |
|------|------|-----|----------------|-----------|-----------|
| C8 | 8 | 30 GB | +200 GiB (MYR 120) | MYR 442 | $100 |

| Component | RAM |
|-----------|-----|
| OS & System | 2 GB |
| SecureSharing Backend | 8 GB |
| PII Service | 2 GB |
| Presidio NER | 2 GB |
| PostgreSQL 18 | 8 GB |
| Garage S3 | 2 GB |
| Nginx | 512 MB |
| Argon2 headroom (25) | 1.6 GB |
| **Used / Buffer** | **~26 GB / 4 GB** |

---

### Option B: Two Cloud VPS — Production with Qwen2.5-14B

**Use case**: Production with < 100 users, full PII + LLM stack, data in Malaysia

```
┌───────────────────────────────┐    ┌──────────────────────────┐
│   COMPUTE: C16                │    │   DATA: C4               │
│   MYR 644/month              │    │   MYR 161/month          │
│                               │    │                          │
│  Nginx + SSL                  │    │  PostgreSQL 18    8 GB   │
│  SecureSharing Backend  8 GB  │    │  Garage S3        4 GB   │
│  PII Service            2 GB  │    │                          │
│  Presidio NER           2 GB  │    │  4 vCPU │ 15 GB         │
│  Qwen2.5-14B           36 GB  │    │  +200 GiB storage       │
│                               │    └──────────────────────────┘
│  16 vCPU │ 60 GB             │               │
│  +300 GiB storage            │        WireGuard VPN
└───────────────────────────────┘───────────────┘
```

| Server | Plan | Storage Add-on | MYR/month |
|--------|------|----------------|-----------|
| Compute | C16 (16 vCPU, 60 GB) | +300 GiB (MYR 180) | MYR 824 |
| Data | C4 (4 vCPU, 15 GB) | +200 GiB (MYR 120) | MYR 281 |
| **Total** | | | **MYR 1,105 (~$251)** |

**Compute Memory Allocation:**

| Component | RAM | Notes |
|-----------|-----|-------|
| OS & System | 2 GB | |
| SecureSharing Backend | 8 GB | Elixir/Phoenix |
| PII Service | 2 GB | Elixir/Phoenix |
| Presidio NER | 2 GB | spaCy + custom recognizers |
| Qwen2.5-14B (Q4_K_M) | 36 GB | llama.cpp, CPU inference |
| Argon2 headroom (25) | 1.6 GB | |
| **Used / Buffer** | **~52 GB / 8 GB** | Adequate |

> **Warning**: Only 8 GB buffer. Under heavy simultaneous LLM + login load, consider upgrading compute to C32 (120 GB, MYR 1,288) or RAMOpt-C8 (120 GB, MYR 834).

---

### Option C: Single RAMOpt-C8 — Comfortable Single-Server

**Use case**: Production with < 100 users, generous buffer, simplest deployment

| Plan | vCPU | RAM | Storage Add-on | MYR/month | USD/month |
|------|------|-----|----------------|-----------|-----------|
| RAMOpt-C8 | 8 | 120 GB | +500 GiB (MYR 300) | MYR 1,134 | $258 |

| Component | RAM | Notes |
|-----------|-----|-------|
| OS & System | 2 GB | |
| Nginx | 512 MB | |
| SecureSharing Backend | 8 GB | |
| PII Service | 4 GB | |
| Presidio NER | 2 GB | |
| Qwen2.5-14B (Q4_K_M) | 36 GB | |
| PostgreSQL 18 | 32 GB | Generous cache |
| Garage S3 | 8 GB | |
| Argon2 headroom (100) | 6.4 GB | |
| **Used / Buffer** | **~99 GB / 21 GB** | Excellent |

> **Trade-off**: Only 8 vCPU — LLM inference will be slower (~2-3s per query). But 120 GB RAM means PostgreSQL gets a full 32 GB and there's no memory pressure.

---

### Option D: Bare Metal Business — Maximum On-Prem Performance

**Use case**: Production with 100-500 users, best performance within IPServerOne

| Plan | CPU | RAM | Storage | MYR/month | USD/month |
|------|-----|-----|---------|-----------|-----------|
| Business | 8-core EPYC | 128 GB | 2x 960GB SSD | MYR 1,299 | $295 |

| Component | RAM |
|-----------|-----|
| OS & System | 2 GB |
| Nginx | 512 MB |
| SecureSharing Backend | 8 GB |
| PII Service | 4 GB |
| Presidio NER | 2 GB |
| Qwen2.5-14B (Q4_K_M) | 36 GB |
| PostgreSQL 18 | 32 GB |
| Garage S3 | 16 GB |
| Argon2 headroom (100) | 6.4 GB |
| **Used / Buffer** | **~107 GB / 21 GB** |

**Advantages**: Dedicated physical 8-core EPYC, 2x 960GB SSD for storage, 128 GB RAM with healthy buffer.

**Disadvantage**: 100 Mbit/s bandwidth — may bottleneck for concurrent large file transfers.

---

## 4. GPU-Accelerated Option (NovaGPU)

For deployments requiring fast LLM inference (200-500ms instead of 1-2s on CPU), NovaGPU provides dedicated GPU cards in Malaysia.

### NovaGPU RTX 4090 — Full Stack with GPU LLM

| Spec | Value |
|------|-------|
| GPU | NVIDIA RTX 4090 (24 GB VRAM) |
| CPU | 8-core AMD EPYC 9124 |
| RAM | 120 GB |
| Storage | +500 GiB (MYR 300) |
| Bandwidth | 1 Gbit/s |
| **Monthly** | **MYR 2,034 (~$462)** |

| Component | RAM | GPU VRAM |
|-----------|-----|----------|
| OS & System | 2 GB | — |
| SecureSharing Backend | 8 GB | — |
| PII Service | 4 GB | — |
| Presidio NER | 2 GB | — |
| Qwen2.5-14B | 4 GB (loader) | **~12 GB** |
| PostgreSQL 18 | 32 GB | — |
| Garage S3 | 8 GB | — |
| Argon2 headroom (100) | 6.4 GB | — |
| **Used / Buffer** | **~67 GB / 53 GB** | **~12 / 12 GB free** |

**LLM Performance Comparison:**

| Metric | CPU (C16, 16 vCPU) | GPU (RTX 4090) |
|--------|---------------------|----------------|
| Qwen2.5-14B inference | ~1-2s | ~200-400ms |
| phi3:mini inference | ~800ms | ~100-150ms |
| Concurrent PII ops/min | 20-30 | 100-200 |

> The RTX 4090 option is only justified if PII processing volume and latency requirements demand GPU acceleration. For most deployments under 100 users, CPU inference is sufficient.

---

## 5. Storage Considerations

IPServerOne NovaCloud instances start with only **10 GiB base storage**. Budget for additional storage:

| Use Case | Recommended Add-on | MYR/month |
|----------|-------------------|-----------|
| MVP / Pilot | 100 GiB | MYR 60 |
| Small Production | 200 GiB | MYR 120 |
| Medium Production | 500 GiB | MYR 300 |
| Large Production | 1 TiB | MYR 614 |

**Bare metal plans** include built-in storage (960GB-2TB per drive, RAID configurations).

**Alternative**: Use Contabo S3 Object Storage (€2.49/250 GB, no egress fees) for encrypted file blobs, keeping only the database local. Since SecureSharing uses zero-knowledge encryption, file blobs stored externally remain secure.

---

## 6. Network and Data Center

### Data Center Location

- **Primary**: Cyberjaya, Selangor, Malaysia (Tier III certified)
- **Also available**: Singapore, Hong Kong

### Bandwidth

| Product | Bandwidth |
|---------|-----------|
| NovaCloud C1-C4 | 100-250 Mbit/s |
| NovaCloud C8-C32 | 350-550 Mbit/s |
| Bare Metal (Easy/Medium) | 100 Mbit/s |
| Bare Metal (Large) | 300 Mbit/s - 1 Gbit/s |
| NovaGPU | 1 Gbit/s |

> **Note**: Bandwidth is lower than Contabo/Hetzner (1 Gbit/s). For workloads with many concurrent large file transfers, this may be a bottleneck. Consider bare metal Large plans or NovaGPU for 1 Gbit/s.

### Private Networking

For multi-server setups, use WireGuard VPN between instances (same approach as Contabo). IPServerOne does not advertise a managed private network product for cloud VPS.

### Additional Services

- **Cloud Backup**: Veeam-based backup-as-a-service
- **DRaaS**: Disaster recovery to secondary site
- **Cloud Connect**: Direct connectivity to AWS/Azure/GCP
- **DDoS Protection**: Available as add-on
- **Managed Services**: Full infrastructure management plans available

---

## 7. Comparison with Contabo and Hetzner

### Single-Server Production with Qwen2.5-14B (February 2026)

| Aspect | Contabo VPS 60 (SG) | IPServerOne C16 (MY) | IPServerOne RAMOpt-C8 (MY) |
|--------|---------------------|----------------------|----------------------------|
| vCPU | 18 | 16 | 8 |
| RAM | 96 GB | 60 GB | 120 GB |
| Base Storage | 350 GB NVMe | 10 GiB (+paid) | 10 GiB (+paid) |
| Bandwidth | 1 Gbit/s | 450 Mbit/s | 350 Mbit/s |
| Qwen2.5-14B buffer | 20 GB | 8 GB (tight) | 21 GB |
| Data location | Singapore | **Malaysia** | **Malaysia** |
| GPU option | No | **Yes (NovaGPU)** | **Yes (NovaGPU)** |
| **Monthly cost** | **~$103** | **~$146 + storage** | **~$190 + storage** |

### Two-Server Production with Qwen2.5-14B

| Aspect | Hetzner (AX52+AX42) | Contabo (VDS XL+L) | IPServerOne (C16+C4) |
|--------|---------------------|---------------------|----------------------|
| Compute CPU | 16c/32t dedicated | 8 physical cores | 16 shared vCPU |
| Total RAM | 128 GB ECC | 112 GB | 75 GB |
| Total Storage | 2TB + 2TB | 840 GB NVMe | 10+10 GiB (+paid) |
| Bandwidth | 1 Gbit/s | 1 Gbit/s | 450 Mbit/s |
| Private Network | vSwitch (free) | WireGuard | WireGuard |
| Data location | Germany | EU/Singapore | **Malaysia** |
| **Monthly cost** | **~$115** | **~$162** | **~$251 + storage** |

### Decision Matrix

| Requirement | Best Provider |
|-------------|---------------|
| Lowest cost | **Contabo VPS 60 (Singapore)** — ~$103/month |
| Best performance | **Hetzner bare metal** — ~$115/month (dedicated cores, ECC RAM) |
| Data must stay in Malaysia | **IPServerOne** — from MYR 1,105/month |
| GPU-accelerated LLM in Malaysia | **IPServerOne NovaGPU** — from MYR 1,734/month |
| Hourly billing / burst usage | **IPServerOne NovaCloud** — from MYR 0.06/hour |

---

## 8. Cost Summary

### All IPServerOne Options

| Option | Target | Config | MYR/month | USD/month |
|--------|--------|--------|-----------|-----------|
| **A: MVP (no LLM)** | < 50 users | C8 + 200 GiB storage | MYR 442 | ~$100 |
| **B: Two VPS + Qwen2.5-14B** | < 100 users | C16 + C4 + storage | MYR 1,105 | ~$251 |
| **C: Single RAMOpt-C8** | < 100 users | RAMOpt-C8 + 500 GiB | MYR 1,134 | ~$258 |
| **D: Bare Metal Business** | 100-500 users | 8-core EPYC, 128 GB | MYR 1,299 | ~$295 |
| **E: NovaGPU RTX 4090** | GPU-accelerated | RTX 4090 + 500 GiB | MYR 2,034 | ~$462 |

### Recommendation

| Scenario | Recommended |
|----------|-------------|
| Pilot / demo (data in Malaysia) | **Option A**: C8 (MYR 442/month) |
| Production with LLM (budget) | **Option B**: C16 + C4 (MYR 1,105/month) |
| Production with LLM (comfortable) | **Option C**: RAMOpt-C8 (MYR 1,134/month) |
| Production (max performance, no GPU) | **Option D**: Bare Metal Business (MYR 1,299/month) |
| GPU-accelerated PII processing | **Option E**: NovaGPU RTX 4090 (MYR 2,034/month) |

> **If data sovereignty is not required**, Contabo VPS 60 in Singapore (~$103/month) provides 96 GB RAM at less than half the cost of the cheapest IPServerOne option that fits Qwen2.5-14B.

---

**Document Control**

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | Feb 2026 | Initial IPServerOne sizing guide |

---

*Pricing sourced from [ipserverone.com](https://www.ipserverone.com) as of February 2026. MYR prices subject to 8% SST. USD estimates at USD 1 = MYR 4.4. Actual requirements should be validated through load testing.*
