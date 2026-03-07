# SecureSharing Hardware Sizing Guide

**Document Version**: 1.0.0
**Date**: February 2026
**Classification**: Internal / Planning

---

> **DISCLAIMER: ESTIMATION GUIDE**
>
> This document provides **estimated** hardware requirements based on component specifications, testing, and industry benchmarks. Actual requirements may vary based on:
> - Usage patterns and concurrent user load
> - Document sizes and processing complexity
> - Network conditions and latency requirements
> - Specific deployment configurations
>
> **Recommendation**: Conduct load testing with representative workloads before finalizing production hardware specifications. Start with recommended specifications and scale based on observed metrics.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Component Requirements](#2-component-requirements)
3. [Deployment Scenarios](#3-deployment-scenarios)
4. [Cloud Instance Recommendations](#4-cloud-instance-recommendations)
5. [Performance Expectations](#5-performance-expectations)
6. [Cost Considerations](#6-cost-considerations)
7. [Scaling Guidelines](#7-scaling-guidelines)

---

## 1. Overview

SecureSharing is a multi-component platform consisting of:

- **SecureSharing API**: Core file sharing and encryption services
- **PII Service**: Document redaction and AI-assisted queries
- **Ollama (SLM)**: Local Small Language Model for PII validation
- **Presidio NER**: Machine learning-based named entity recognition (optional)
- **PostgreSQL**: Primary relational database
- **Object Storage**: S3-compatible storage (Garage/MinIO/AWS S3)

The PII Service with local SLM inference is the most resource-intensive component, particularly regarding RAM and optional GPU requirements.

---

## 2. Component Requirements

### 2.1 Individual Component Specifications

| Component | CPU | RAM | Storage | Notes |
|-----------|-----|-----|---------|-------|
| **SecureSharing API** | 2-4 vCPU | 4-8 GiB | - | Elixir/Phoenix, stateless, horizontally scalable |
| **PII Service** | 2 vCPU | 2 GiB | - | Elixir/Phoenix application |
| **Ollama (SLM)** | 4 vCPU | 8-16 GiB | 10 GiB | Model storage; GPU recommended |
| **Presidio NER** | 1 vCPU | 2 GiB | 2 GiB | Optional; includes spaCy models |
| **PostgreSQL** | 2-4 vCPU | 4-8 GiB | 100+ GiB SSD | Primary database |
| **Garage/MinIO** | 1-2 vCPU | 1-2 GiB | Variable | Object storage for encrypted files |
| **Nginx** | 1 vCPU | 512 MiB | - | Reverse proxy and TLS termination |
| **OS & System** | - | 1-2 GiB | 20 GiB | Ubuntu 22.04 LTS recommended |

### 2.2 SLM Model Requirements

The PII Service uses local language models via Ollama for intelligent PII validation:

| Model | Disk Size | RAM (Loaded) | VRAM (GPU) | Purpose |
|-------|-----------|--------------|------------|---------|
| phi3:mini | ~2 GiB | ~4 GiB | ~4 GiB | Fast classification |
| mistral:7b | ~4 GiB | ~8 GiB | ~8 GiB | Accurate validation |
| **Total** | **~6 GiB** | **~12 GiB** | **~12 GiB** | Both models loaded |

> **Note**: Ollama loads models into memory on demand. With `OLLAMA_MAX_LOADED_MODELS=2`, both models remain in memory for faster inference.

### 2.3 Client-Side KDF Overhead

SecureSharing uses a tiered KDF for client-side key derivation (see `crypto/01-algorithm-suite.md` §6.2). The memory overhead listed below is **per concurrent client operation**, not server-side.

| KDF Profile | Memory/op | Iterations | Use Case |
|-------------|-----------|------------|----------|
| `argon2id-standard` (default) | 64 MiB | 3 | Desktop, modern mobile |
| `argon2id-low` | 19 MiB | 4 | Low-RAM mobile (2-4 GB) |
| `bcrypt-hkdf` | ~4 KB | cost=13 | Extremely constrained (< 2 GB) |

**Concurrent Login Capacity (worst case: all clients using `argon2id-standard`):**

| Concurrent Logins | Additional RAM Required |
|-------------------|-------------------------|
| 10 | 640 MiB |
| 25 | 1.6 GiB |
| 50 | 3.2 GiB |
| 100 | 6.4 GiB |

> **Note**: This is client-side memory. The server does not perform Argon2id hashing — it uses Bcrypt for authentication. The table above is relevant for sizing client devices, not servers.

---

## 3. Deployment Scenarios

### 3.1 Scenario A: Single Server MVP (Small)

**Target Use Case**: Development, pilot deployments, small teams (< 50 users)

#### Hardware Specifications

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **CPU** | 4 vCPU | 8 vCPU |
| **RAM** | 16 GiB | 32 GiB |
| **Storage** | 100 GiB SSD | 200 GiB NVMe SSD |
| **Network** | 100 Mbps | 1 Gbps |
| **GPU** | None | None (CPU inference) |

#### Resource Allocation (32 GiB Configuration)

```
┌─────────────────────────────────────────────────────────┐
│              Single Server MVP (32 GiB RAM)             │
├─────────────────────────────────────────────────────────┤
│  Component                │  RAM Allocation             │
├───────────────────────────┼─────────────────────────────┤
│  OS & System              │  2 GiB                      │
│  SecureSharing API        │  4 GiB                      │
│  PII Service              │  2 GiB                      │
│  Ollama (SLM)             │  16 GiB  ← largest          │
│  PostgreSQL               │  4 GiB                      │
│  Garage (S3)              │  1 GiB                      │
│  Nginx                    │  512 MiB                    │
│  Argon2 headroom (25)     │  1.6 GiB                    │
│  Safety margin            │  ~1 GiB                     │
├───────────────────────────┼─────────────────────────────┤
│  TOTAL                    │  ~32 GiB                    │
└─────────────────────────────────────────────────────────┘
```

#### Limitations

- SLM inference on CPU is slower (1-2 seconds per validation)
- Limited concurrent user capacity
- No high availability

---

### 3.2 Scenario B: Single Server Production (Medium)

**Target Use Case**: Production deployments, medium organizations (50-500 users)

#### Hardware Specifications

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **CPU** | 8 vCPU | 16 vCPU |
| **RAM** | 32 GiB | 64 GiB |
| **Storage** | 250 GiB NVMe | 500 GiB NVMe SSD |
| **Network** | 1 Gbps | 1 Gbps |
| **GPU** | NVIDIA T4 (16 GiB) | NVIDIA T4/A10 |

#### Resource Allocation (64 GiB + GPU Configuration)

```
┌─────────────────────────────────────────────────────────┐
│         Production Server (64 GiB RAM + GPU)            │
├─────────────────────────────────────────────────────────┤
│  Component                │  RAM Allocation             │
├───────────────────────────┼─────────────────────────────┤
│  OS & System              │  2 GiB                      │
│  SecureSharing API        │  8 GiB                      │
│  PII Service              │  4 GiB                      │
│  Ollama (SLM)             │  8 GiB (models on GPU)      │
│  Presidio NER             │  2 GiB                      │
│  PostgreSQL               │  16 GiB                     │
│  Garage (S3)              │  2 GiB                      │
│  Nginx                    │  1 GiB                      │
│  Argon2 headroom (100)    │  6.4 GiB                    │
│  Safety margin            │  ~14 GiB                    │
├───────────────────────────┼─────────────────────────────┤
│  TOTAL RAM                │  ~64 GiB                    │
├───────────────────────────┼─────────────────────────────┤
│  GPU VRAM                 │                             │
│  ├─ phi3:mini             │  ~4 GiB                     │
│  └─ mistral:7b            │  ~8 GiB                     │
│  TOTAL VRAM               │  ~12 GiB                    │
└─────────────────────────────────────────────────────────┘
```

#### Benefits

- Fast SLM inference (200-500ms with GPU)
- Higher concurrent user capacity
- Room for growth

---

### 3.3 Scenario C: Distributed Production (Large)

**Target Use Case**: Enterprise deployments, high availability requirements (500+ users)

#### Architecture Overview

```
                    ┌─────────────────┐
                    │  Load Balancer  │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  API Server   │    │  API Server   │    │  API Server   │
│  (Node 1)     │    │  (Node 2)     │    │  (Node 3)     │
└───────────────┘    └───────────────┘    └───────────────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  PII Service  │    │  PostgreSQL   │    │    Object     │
│  + GPU        │    │  (Primary +   │    │    Storage    │
│               │    │   Replica)    │    │   (Cluster)   │
└───────────────┘    └───────────────┘    └───────────────┘
```

#### API/App Servers (2-3 nodes)

| Resource | Per Node |
|----------|----------|
| **CPU** | 4-8 vCPU |
| **RAM** | 8-16 GiB |
| **Storage** | 50 GiB SSD |
| **Network** | 1 Gbps |

#### PII Service + SLM Server (1-2 nodes)

| Resource | Per Node |
|----------|----------|
| **CPU** | 8 vCPU |
| **RAM** | 32 GiB |
| **GPU** | NVIDIA T4/A10 (16+ GiB VRAM) |
| **Storage** | 100 GiB SSD |

#### Database Server (Primary + Replica)

| Resource | Per Node |
|----------|----------|
| **CPU** | 8-16 vCPU |
| **RAM** | 32-64 GiB |
| **Storage** | 500 GiB - 1 TiB NVMe SSD |
| **IOPS** | 10,000+ |

#### Object Storage Cluster

| Resource | Specification |
|----------|---------------|
| **Type** | S3-compatible (AWS S3/MinIO/Garage) |
| **Capacity** | Scalable (start with 1 TiB) |
| **Redundancy** | 3x replication or erasure coding |

---

## 4. Cloud Instance Recommendations

### 4.1 Amazon Web Services (AWS)

| Scenario | Instance Type | vCPU | RAM | GPU | Est. Monthly Cost |
|----------|---------------|------|-----|-----|-------------------|
| MVP | t3.2xlarge | 8 | 32 GiB | - | ~$245 |
| MVP + spot | t3.2xlarge (spot) | 8 | 32 GiB | - | ~$75-100 |
| Production | g4dn.2xlarge | 8 | 32 GiB | T4 | ~$565 |
| Production (large) | g4dn.4xlarge | 16 | 64 GiB | T4 | ~$905 |

**Additional AWS Services:**
- RDS PostgreSQL: db.r6g.large (~$150/month)
- S3 Storage: ~$23/TiB/month

### 4.2 Google Cloud Platform (GCP)

| Scenario | Instance Type | vCPU | RAM | GPU | Est. Monthly Cost |
|----------|---------------|------|-----|-----|-------------------|
| MVP | n2-standard-8 | 8 | 32 GiB | - | ~$260 |
| Production | n1-standard-8 + T4 | 8 | 30 GiB | T4 | ~$530 |
| Production (large) | n1-standard-16 + T4 | 16 | 60 GiB | T4 | ~$750 |

### 4.3 Microsoft Azure

| Scenario | Instance Type | vCPU | RAM | GPU | Est. Monthly Cost |
|----------|---------------|------|-----|-----|-------------------|
| MVP | Standard_D8s_v5 | 8 | 32 GiB | - | ~$280 |
| Production | Standard_NC4as_T4_v3 | 4 | 28 GiB | T4 | ~$525 |
| Production (large) | Standard_NC8as_T4_v3 | 8 | 56 GiB | T4 | ~$750 |

### 4.4 Contabo (EU / Singapore)

*Pricing researched February 2026 from [contabo.com](https://contabo.com). See `contabo-hosting-sizing.md` for full deployment guide.*

Contabo offers strong price-to-RAM ratios. No GPU instances available — all LLM inference is CPU-only.

| Scenario | Plan | vCPU | RAM | Storage | Est. Monthly Cost |
|----------|------|------|-----|---------|-------------------|
| MVP (no LLM) | Cloud VPS 40 | 12 | 48 GiB | 250 GB NVMe | ~€25 / ~$53 (SG) |
| Production (with LLM) | Cloud VPS 60 | 18 | 96 GiB | 350 GB NVMe | ~€49 / ~$103 (SG) |
| Production (2-server) | VDS XL + VDS L | 8+6 cores | 64+48 GiB | 480+360 GB | ~€146 |
| Production (bare metal) | Ryzen 12 + VDS L | 12c+6c | 64+48 GiB | 1TB+360 GB | ~€160 |

**Additional Services:**
- S3-compatible Object Storage: €2.49/250 GB (no egress fees)
- No managed private network — requires WireGuard/VPN between servers
- Regions: EU (Germany, UK), US (NYC, St. Louis, Seattle), APAC (Singapore, Japan, Australia, India)

### 4.5 IPServerOne (Malaysia — Cyberjaya)

*Pricing researched February 2026 from [ipserverone.com](https://www.ipserverone.com). See `ipserverone-hosting-sizing.md` for full deployment guide.*

Malaysian provider with Tier III data center in Cyberjaya. Best option when data sovereignty (PDPA compliance) requires data to remain in Malaysia. Also offers GPU-as-a-Service (NovaGPU).

**NovaCloud (Cloud VPS):**

| Scenario | Plan | vCPU | RAM | Est. Monthly Cost |
|----------|------|------|-----|-------------------|
| MVP (no LLM) | C8 | 8 | 30 GiB | MYR 322 (~$73) |
| Production (with LLM) | C16 | 16 | 60 GiB | MYR 644 (~$146) + storage |
| Production (high RAM) | RAMOpt-C8 | 8 | 120 GiB | MYR 834 (~$190) + storage |

**Bare Metal:**

| Scenario | Plan | CPU | RAM | Est. Monthly Cost |
|----------|------|-----|-----|-------------------|
| MVP | Basic | 4-core Xeon E3 | 32 GiB | MYR 549 (~$125) |
| Production | Pro | 6-core Xeon E | 64 GiB | MYR 779 (~$177) |
| Production (large) | Business | 8-core EPYC | 128 GiB | MYR 1,299 (~$295) |

**NovaGPU (GPU-as-a-Service):**

| GPU | VRAM | RAM | Est. Monthly Cost |
|-----|------|-----|-------------------|
| RTX 4090 | 24 GiB | 120 GiB | MYR 1,734 (~$394) |
| RTX 5090 | 32 GiB | 120 GiB | MYR 2,234 (~$508) |

**Notes:**
- Base cloud storage is only 10 GiB — additional storage at MYR 0.60/GiB (~$0.14/GiB)
- Bandwidth: 100-550 Mbit/s (lower than Contabo/Hetzner)
- NovaGPU enables GPU-accelerated LLM inference locally in Malaysia

### 4.6 On-Premises / Bare Metal

| Scenario | Specifications | Est. Hardware Cost |
|----------|----------------|-------------------|
| MVP | Dell PowerEdge R450, Xeon 8-core, 32GB | ~$3,000-4,000 |
| Production | Dell PowerEdge R750, Xeon 16-core, 64GB, NVIDIA T4 | ~$8,000-12,000 |

> **Note**: Cloud cost estimates are approximate and based on on-demand pricing as of February 2026. Actual costs may vary by region and commitment discounts.

---

## 5. Performance Expectations

### 5.1 Response Time Targets

| Operation | Target (p95) | MVP (CPU) | Production (GPU) |
|-----------|--------------|-----------|------------------|
| API Response | < 200ms | < 200ms | < 100ms |
| File Upload (10MB) | < 2s | < 2s | < 1s |
| PII Detection | < 100ms | ~50ms | ~35ms |
| SLM Validation | < 500ms | 1-2s | 200-500ms |
| Full Redaction | < 3s | 2-3s | < 1s |

### 5.2 Throughput Estimates

| Scenario | Concurrent Users | Requests/sec | PII Operations/min |
|----------|------------------|--------------|-------------------|
| MVP | 10-25 | 50-100 | 20-30 |
| Production | 50-100 | 200-500 | 100-200 |
| Distributed | 200+ | 1000+ | 500+ |

### 5.3 SLM Inference Performance

| Configuration | phi3:mini | mistral:7b |
|---------------|-----------|------------|
| CPU (8 cores) | ~800ms | ~2,000ms |
| GPU (T4) | ~150ms | ~400ms |
| GPU (A10) | ~100ms | ~250ms |

---

## 6. Cost Considerations

### 6.1 Cost Drivers (Ranked by Impact)

| Rank | Component | Impact | Notes |
|------|-----------|--------|-------|
| 1 | **GPU** | High | ~$300-500/month for T4 instance |
| 2 | **Database** | Medium | Managed RDS adds ~$150-300/month |
| 3 | **Storage** | Variable | Depends on file volume |
| 4 | **Bandwidth** | Variable | Outbound transfer costs |

### 6.2 Cost Optimization Strategies

| Strategy | Savings | Trade-off |
|----------|---------|-----------|
| **CPU-only MVP** | ~$300/month | Slower SLM (1-2s vs 200-500ms) |
| **Cloud LLM API** | GPU cost eliminated | Per-request API costs, data leaves infrastructure |
| **Spot/Preemptible** | 60-70% | Instance may be terminated |
| **Reserved Instances** | 30-50% | 1-3 year commitment |
| **Disable Presidio** | ~2 GiB RAM | Reduced NER accuracy |
| **Single SLM Model** | ~4 GiB RAM/VRAM | Less flexible validation |

### 6.3 Alternative Architecture: Cloud LLM

For deployments where GPU cost is prohibitive:

```
┌─────────────────────────────────────────────────────────┐
│            Alternative: Cloud LLM Architecture          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  SecureSharing ──► PII Service ──► OpenAI/Claude API   │
│                                                         │
│  Benefits:                                              │
│  • No GPU required                                      │
│  • Smaller server (16-32 GiB RAM sufficient)           │
│  • Better model capabilities                            │
│                                                         │
│  Trade-offs:                                            │
│  • Per-request API costs (~$0.01-0.03 per query)       │
│  • Data sent to external provider                       │
│  • Network latency dependency                           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Scaling Guidelines

### 7.1 Vertical Scaling Indicators

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU utilization | > 70% sustained | Add vCPUs |
| Memory utilization | > 80% | Add RAM |
| Disk I/O wait | > 20% | Upgrade to faster storage |
| SLM queue depth | > 10 requests | Add GPU or scale out |

### 7.2 Horizontal Scaling Indicators

| Metric | Threshold | Action |
|--------|-----------|--------|
| API response time | > 500ms p95 | Add API nodes |
| Database connections | > 80% pool | Add read replicas |
| Concurrent PII requests | > capacity | Add PII Service nodes |

### 7.3 Scaling Path

```
Stage 1 (MVP)           Stage 2 (Growth)        Stage 3 (Scale)
─────────────────       ─────────────────       ─────────────────
Single Server           Single + GPU            Distributed
32 GiB / 8 vCPU        64 GiB / 16 vCPU        Multiple nodes
< 50 users             50-500 users            500+ users
CPU inference          GPU inference           Load balanced
```

---

## Summary Quick Reference

### By Deployment Size

| Deployment | Users | RAM | CPU | GPU | Storage | Est. Monthly Cost |
|------------|-------|-----|-----|-----|---------|-------------------|
| **MVP** | < 50 | 32 GiB | 8 vCPU | None | 200 GiB | $100-250 |
| **Production** | 50-500 | 64 GiB | 16 vCPU | T4 | 500 GiB | $500-900 |
| **Enterprise** | 500+ | 128+ GiB | 32+ vCPU | T4/A10 | 1+ TiB | $1,500+ |

### By Provider (Production with Qwen2.5-14B, as of February 2026)

| Provider | Config | RAM | CPU | GPU | Monthly Cost | Notes |
|----------|--------|-----|-----|-----|-------------|-------|
| **Hetzner** | AX52 + AX42 (bare metal) | 64+64 GiB | 16c+8c | None | ~€104 | Best value; ECC RAM; new account limits apply |
| **Contabo** | VPS 60 single server (SG) | 96 GiB | 18 vCPU | None | ~$103 | Best RAM/dollar; no GPU |
| **Contabo** | VDS XL + VDS L | 64+48 GiB | 8c+6c | None | ~€146 | Dedicated cores |
| **IPServerOne** | C16 + C4 (Malaysia) | 60+15 GiB | 16+4 vCPU | None | ~MYR 1,105 ($251) | Data sovereignty (PDPA) |
| **IPServerOne** | NovaGPU RTX 4090 | 120 GiB | 8-32 vCPU | RTX 4090 | ~MYR 1,734 ($394) | GPU LLM in Malaysia |
| **AWS** | g4dn.4xlarge | 64 GiB | 16 vCPU | T4 | ~$905 | Managed services |

---

**Document Control**

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | Feb 2026 | Initial estimation guide |
| 1.1.0 | Feb 2026 | Added Contabo and IPServerOne (Malaysia) provider recommendations; provider comparison table |

---

*This document provides estimates for planning purposes. Actual requirements should be validated through load testing with representative workloads.*
