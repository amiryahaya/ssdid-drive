# drive.ssdid.my Deployment — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy drive.ssdid.my with path-based routing: landing page at `/`, admin portal at `/admin/`, backend API at `/api/`.

**Architecture:** Caddy reverse proxy with path matchers serves three targets from one domain. Landing page is a single static HTML file (Tailwind CDN). Admin portal is a React/TypeScript SPA built with Vite (base path `/admin/`). Backend API runs in Podman container on port 5000.

**Tech Stack:** Caddy, HTML/Tailwind CSS (landing), React/TypeScript/Vite (admin), .NET 10 (API), Podman, PostgreSQL

---

### Task 1: Create the landing page

**Files:**
- Create: `clients/landing/index.html`

**Step 1: Create the landing page directory**

```bash
mkdir -p ~/Workspace/ssdid-drive/clients/landing
```

**Step 2: Write `index.html`**

Create `clients/landing/index.html` — a self-contained single file with Tailwind CSS via CDN. No build step needed.

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SSDID Drive — Post-Quantum Secure File Storage</title>
    <meta name="description" content="Secure file storage and sharing with post-quantum cryptography and self-sovereign identity. Your files, your keys, your identity.">
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        brand: { 50: '#eff6ff', 100: '#dbeafe', 200: '#bfdbfe', 500: '#3b82f6', 600: '#2563eb', 700: '#1d4ed8', 800: '#1e40af', 900: '#1e3a8a' }
                    }
                }
            }
        }
    </script>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
        body { font-family: 'Inter', sans-serif; }
    </style>
</head>
<body class="bg-white text-gray-900">

    <!-- Nav -->
    <nav class="fixed top-0 w-full bg-white/80 backdrop-blur-md border-b border-gray-100 z-50">
        <div class="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
            <div class="flex items-center gap-2">
                <svg class="w-8 h-8 text-brand-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                <span class="text-xl font-bold">SSDID Drive</span>
            </div>
            <div class="flex items-center gap-4">
                <a href="/admin/" class="text-sm text-gray-600 hover:text-gray-900 transition">Admin</a>
                <a href="https://github.com/nicholasgasior/ssdid-drive" class="text-sm text-gray-600 hover:text-gray-900 transition">GitHub</a>
                <a href="#download" class="text-sm bg-brand-600 text-white px-4 py-2 rounded-lg hover:bg-brand-700 transition">Download</a>
            </div>
        </div>
    </nav>

    <!-- Hero -->
    <section class="pt-32 pb-20 px-6">
        <div class="max-w-4xl mx-auto text-center">
            <div class="inline-flex items-center gap-2 bg-brand-50 text-brand-700 text-sm font-medium px-4 py-1.5 rounded-full mb-6">
                <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                Post-Quantum Secured
            </div>
            <h1 class="text-5xl sm:text-6xl font-bold tracking-tight mb-6">
                Your files.<br>Your keys.<br>
                <span class="text-brand-600">Your identity.</span>
            </h1>
            <p class="text-xl text-gray-600 max-w-2xl mx-auto mb-10">
                Secure file storage and sharing powered by self-sovereign identity and post-quantum cryptography. No one — not even us — can read your files.
            </p>
            <div class="flex flex-wrap justify-center gap-4">
                <a href="#download" class="bg-brand-600 text-white px-8 py-3 rounded-xl text-lg font-medium hover:bg-brand-700 transition shadow-lg shadow-brand-600/25">
                    Get Started
                </a>
                <a href="/api/auth/ssdid/server-info" class="border border-gray-300 text-gray-700 px-8 py-3 rounded-xl text-lg font-medium hover:bg-gray-50 transition">
                    Server Info
                </a>
            </div>
        </div>
    </section>

    <!-- Features -->
    <section class="py-20 px-6 bg-gray-50">
        <div class="max-w-6xl mx-auto">
            <h2 class="text-3xl font-bold text-center mb-4">Why SSDID Drive?</h2>
            <p class="text-gray-600 text-center mb-12 max-w-xl mx-auto">Built for a post-quantum world where you control your own identity and data.</p>
            <div class="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
                <!-- Card 1 -->
                <div class="bg-white rounded-2xl p-6 shadow-sm border border-gray-100">
                    <div class="w-12 h-12 bg-brand-50 rounded-xl flex items-center justify-center mb-4">
                        <svg class="w-6 h-6 text-brand-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
                    </div>
                    <h3 class="font-semibold mb-2">Post-Quantum Security</h3>
                    <p class="text-sm text-gray-600">KAZ-Sign and ML-DSA algorithms protect your data against both classical and quantum computer attacks.</p>
                </div>
                <!-- Card 2 -->
                <div class="bg-white rounded-2xl p-6 shadow-sm border border-gray-100">
                    <div class="w-12 h-12 bg-brand-50 rounded-xl flex items-center justify-center mb-4">
                        <svg class="w-6 h-6 text-brand-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                    </div>
                    <h3 class="font-semibold mb-2">Self-Sovereign Identity</h3>
                    <p class="text-sm text-gray-600">No passwords, no email sign-ups. Authenticate with your SSDID Wallet using decentralized identifiers (DIDs).</p>
                </div>
                <!-- Card 3 -->
                <div class="bg-white rounded-2xl p-6 shadow-sm border border-gray-100">
                    <div class="w-12 h-12 bg-brand-50 rounded-xl flex items-center justify-center mb-4">
                        <svg class="w-6 h-6 text-brand-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
                    </div>
                    <h3 class="font-semibold mb-2">Zero-Knowledge Encryption</h3>
                    <p class="text-sm text-gray-600">Files are encrypted client-side before upload. The server never sees your plaintext data or encryption keys.</p>
                </div>
                <!-- Card 4 -->
                <div class="bg-white rounded-2xl p-6 shadow-sm border border-gray-100">
                    <div class="w-12 h-12 bg-brand-50 rounded-xl flex items-center justify-center mb-4">
                        <svg class="w-6 h-6 text-brand-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
                    </div>
                    <h3 class="font-semibold mb-2">Cross-Platform</h3>
                    <p class="text-sm text-gray-600">Desktop (macOS, Windows, Linux), Android, and iOS. Access your files from any device with the same DID.</p>
                </div>
            </div>
        </div>
    </section>

    <!-- How It Works -->
    <section class="py-20 px-6">
        <div class="max-w-4xl mx-auto">
            <h2 class="text-3xl font-bold text-center mb-12">How It Works</h2>
            <div class="space-y-8">
                <div class="flex gap-6 items-start">
                    <div class="w-10 h-10 bg-brand-600 text-white rounded-full flex items-center justify-center font-bold shrink-0">1</div>
                    <div>
                        <h3 class="font-semibold text-lg mb-1">Create your identity</h3>
                        <p class="text-gray-600">Download the SSDID Wallet app and generate your decentralized identity (DID) with post-quantum key pairs.</p>
                    </div>
                </div>
                <div class="flex gap-6 items-start">
                    <div class="w-10 h-10 bg-brand-600 text-white rounded-full flex items-center justify-center font-bold shrink-0">2</div>
                    <div>
                        <h3 class="font-semibold text-lg mb-1">Scan to connect</h3>
                        <p class="text-gray-600">Open SSDID Drive on your desktop and scan the QR code with your wallet. No passwords needed — ever.</p>
                    </div>
                </div>
                <div class="flex gap-6 items-start">
                    <div class="w-10 h-10 bg-brand-600 text-white rounded-full flex items-center justify-center font-bold shrink-0">3</div>
                    <div>
                        <h3 class="font-semibold text-lg mb-1">Upload and share securely</h3>
                        <p class="text-gray-600">Your files are encrypted on your device before upload. Share with others using their DIDs — only they can decrypt.</p>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <!-- Download -->
    <section id="download" class="py-20 px-6 bg-gray-50">
        <div class="max-w-4xl mx-auto text-center">
            <h2 class="text-3xl font-bold mb-4">Get SSDID Drive</h2>
            <p class="text-gray-600 mb-10">Available on all major platforms.</p>
            <div class="grid sm:grid-cols-3 gap-4 max-w-2xl mx-auto">
                <a href="#" class="bg-white border border-gray-200 rounded-xl p-6 hover:shadow-md transition text-center">
                    <svg class="w-8 h-8 mx-auto mb-3 text-gray-700" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
                    <div class="font-semibold">Desktop</div>
                    <div class="text-xs text-gray-500 mt-1">macOS, Windows, Linux</div>
                </a>
                <a href="#" class="bg-white border border-gray-200 rounded-xl p-6 hover:shadow-md transition text-center">
                    <svg class="w-8 h-8 mx-auto mb-3 text-gray-700" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/></svg>
                    <div class="font-semibold">Android</div>
                    <div class="text-xs text-gray-500 mt-1">Google Play</div>
                </a>
                <a href="#" class="bg-white border border-gray-200 rounded-xl p-6 hover:shadow-md transition text-center">
                    <svg class="w-8 h-8 mx-auto mb-3 text-gray-700" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/></svg>
                    <div class="font-semibold">iOS</div>
                    <div class="text-xs text-gray-500 mt-1">App Store</div>
                </a>
            </div>
        </div>
    </section>

    <!-- Footer -->
    <footer class="py-10 px-6 border-t border-gray-100">
        <div class="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4">
            <div class="flex items-center gap-2 text-sm text-gray-500">
                <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                SSDID Drive
            </div>
            <div class="flex gap-6 text-sm text-gray-500">
                <a href="https://registry.ssdid.my" class="hover:text-gray-900 transition">Registry</a>
                <a href="/admin/" class="hover:text-gray-900 transition">Admin Portal</a>
                <a href="/api/auth/ssdid/server-info" class="hover:text-gray-900 transition">Server Info</a>
            </div>
        </div>
    </footer>

</body>
</html>
```

**Step 3: Test locally**

```bash
cd ~/Workspace/ssdid-drive/clients/landing && python3 -m http.server 8080
```

Open `http://localhost:8080` in browser. Verify all sections render correctly.

**Step 4: Commit**

```bash
git add clients/landing/index.html
git commit -m "feat: add landing page for drive.ssdid.my"
```

---

### Task 2: Update deployment guide — Caddyfile for path-based routing

**Files:**
- Modify: `docs/deployment-guide.md`

**Step 1: Replace the Caddyfile section (section 7.1)**

Replace the existing Caddyfile in section 7.1 with:

```bash
sudo tee /etc/caddy/Caddyfile << 'EOF'
drive.ssdid.my {
    # SSE — disable buffering (must come before generic /api/* handler)
    @sse path /api/auth/ssdid/events
    handle @sse {
        reverse_proxy localhost:5000 {
            flush_interval -1
        }
    }

    # Backend API
    handle /api/* {
        reverse_proxy localhost:5000
    }

    # Health check
    handle /health {
        reverse_proxy localhost:5000
    }

    # Admin portal (React SPA) — strip /admin prefix
    handle_path /admin/* {
        root * /var/www/admin
        file_server
        try_files {path} /index.html
    }

    # Landing page (catch-all)
    handle {
        root * /var/www/landing
        file_server
        try_files {path} /index.html
    }

    # Security headers
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
    }

    # File upload limit (100 MB)
    request_body {
        max_size 100MB
    }

    log {
        output file /var/log/caddy/drive.log {
            roll_size 10mb
            roll_keep 5
        }
    }
}
EOF
```

**Step 2: Remove the `admin.ssdid.my` server block**

Delete the entire `admin.ssdid.my { ... }` block from the Caddyfile section — it's no longer needed.

**Step 3: Update section 7.2 — directory creation**

Replace with:

```bash
sudo mkdir -p /var/www/landing /var/www/admin

# Deploy landing page
sudo cp -r ~/ssdid-drive/repo/clients/landing/* /var/www/landing/

# Deploy admin SPA build artifacts here later
# sudo cp -r ~/ssdid-drive/repo/clients/admin/dist/* /var/www/admin/
```

**Step 4: Update CORS origins in section 5.1**

In the `appsettings.Production.json` template, replace:

```json
"Cors": {
    "Origins": [
        "https://drive.ssdid.my",
        "https://admin.ssdid.my"
    ]
}
```

With:

```json
"Cors": {
    "Origins": [
        "https://drive.ssdid.my"
    ]
}
```

**Step 5: Update the architecture diagram**

Replace the existing diagram with:

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────┐
│  Caddy :443 (auto-TLS)                          │
│                                                  │
│  drive.ssdid.my/          → /var/www/landing/    │
│  drive.ssdid.my/admin/*   → /var/www/admin/      │
│  drive.ssdid.my/api/*     → localhost:5000       │
│  drive.ssdid.my/health    → localhost:5000       │
└──────────────────────────────────────────────────┘
         │                         │
         ▼                         ▼
┌─────────────────┐     ┌──────────────────┐
│ ssdid-drive API │     │  PostgreSQL 17   │
│ :5000 (Podman)  │────▶│  :5432 (Podman)  │
└─────────────────┘     └──────────────────┘
         │
         ▼
┌───────────────────────┐
│  SSDID Registry       │
│  registry.ssdid.my    │
└───────────────────────┘
```

**Step 6: Update verification section (section 8)**

Add landing page and admin portal checks:

```bash
# Landing page
curl -s https://drive.ssdid.my/ | head -5
# Expected: <!DOCTYPE html> ...

# Admin portal (returns SPA index.html for any path)
curl -s -o /dev/null -w "%{http_code}" https://drive.ssdid.my/admin/
# Expected: 200

# API health check
curl -s https://drive.ssdid.my/health
# Expected: {"status":"ok"}

# Server info
curl -s https://drive.ssdid.my/api/auth/ssdid/server-info | python3 -m json.tool
```

**Step 7: Commit**

```bash
git add docs/deployment-guide.md
git commit -m "docs: update deployment guide for path-based routing"
```

---

### Task 3: Update CORS config in appsettings

**Files:**
- Modify: `src/SsdidDrive.Api/appsettings.json`

**Step 1: Update CORS origins**

In `src/SsdidDrive.Api/appsettings.json`, the `Cors.Origins` array currently has:

```json
"Cors": {
    "Origins": [
        "http://localhost:3000",
        "http://localhost:5173"
    ]
}
```

Add the Vite dev port for the admin portal (`http://localhost:5174` — second Vite instance):

```json
"Cors": {
    "Origins": [
        "http://localhost:3000",
        "http://localhost:5173",
        "http://localhost:5174"
    ]
}
```

**Step 2: Commit**

```bash
git add src/SsdidDrive.Api/appsettings.json
git commit -m "chore: add admin portal dev origin to CORS config"
```

---

### Task 4: Scaffold admin portal (React/TypeScript/Vite)

**Files:**
- Create: `clients/admin/` (Vite React project)

**Step 1: Scaffold with Vite**

```bash
cd ~/Workspace/ssdid-drive/clients
npm create vite@latest admin -- --template react-ts
cd admin
npm install
```

**Step 2: Set Vite base path to `/admin/`**

Edit `clients/admin/vite.config.ts`:

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  base: '/admin/',
  server: {
    port: 5174,
    proxy: {
      '/api': {
        target: 'http://localhost:5147',
        changeOrigin: true,
      },
    },
  },
})
```

**Step 3: Update `clients/admin/src/App.tsx` with a placeholder**

```tsx
function App() {
  return (
    <div style={{ padding: '2rem', fontFamily: 'system-ui' }}>
      <h1>SSDID Drive — Admin Portal</h1>
      <p>Coming soon.</p>
      <p><a href="/">Back to landing page</a></p>
    </div>
  )
}

export default App
```

**Step 4: Verify build produces correct asset paths**

```bash
cd ~/Workspace/ssdid-drive/clients/admin
npm run build
grep -o 'src="/admin/[^"]*"' dist/index.html
```

Expected: All asset paths start with `/admin/` (e.g., `src="/admin/assets/index-xxx.js"`).

**Step 5: Verify dev server runs**

```bash
npm run dev
```

Open `http://localhost:5174/admin/` — should show the placeholder page.

**Step 6: Commit**

```bash
cd ~/Workspace/ssdid-drive
git add clients/admin/
git commit -m "feat: scaffold admin portal with Vite React TypeScript"
```

---

### Task 5: Add deploy script for landing page + admin portal

**Files:**
- Create: `scripts/deploy-static.sh`

**Step 1: Create deploy script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Deploy landing page and admin portal static files to the VPS.
# Usage: ./scripts/deploy-static.sh <user@host>

REMOTE="${1:?Usage: $0 <user@host>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Building admin portal ==="
cd "$REPO_ROOT/clients/admin"
npm ci
npm run build

echo "=== Deploying landing page ==="
rsync -avz --delete "$REPO_ROOT/clients/landing/" "$REMOTE:/var/www/landing/"

echo "=== Deploying admin portal ==="
rsync -avz --delete "$REPO_ROOT/clients/admin/dist/" "$REMOTE:/var/www/admin/"

echo "=== Done ==="
echo "Landing: https://drive.ssdid.my/"
echo "Admin:   https://drive.ssdid.my/admin/"
```

**Step 2: Make executable**

```bash
chmod +x scripts/deploy-static.sh
```

**Step 3: Commit**

```bash
git add scripts/deploy-static.sh
git commit -m "feat: add static deploy script for landing + admin portal"
```
