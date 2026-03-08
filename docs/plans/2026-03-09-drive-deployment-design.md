# drive.ssdid.my Deployment Design — Path-Based Routing + Landing Page

## Overview

Single domain `drive.ssdid.my` with Caddy path-based routing serving a static landing page, React admin portal SPA, and .NET backend API. Replaces the previous subdomain-based design (`admin.ssdid.my`).

## URL Structure

| Path | Serves | Source |
|------|--------|--------|
| `drive.ssdid.my/` | Landing page (static HTML) | `/var/www/landing/` |
| `drive.ssdid.my/admin/` | Admin portal (React SPA) | `/var/www/admin/` |
| `drive.ssdid.my/api/` | Backend API (proxy) | `localhost:5000` |
| `drive.ssdid.my/health` | Health check (proxy) | `localhost:5000` |

## Caddyfile

```
drive.ssdid.my {
    # SSE — must come before generic /api/* handler
    @sse path /api/auth/ssdid/events
    handle @sse {
        reverse_proxy localhost:5000 {
            flush_interval -1
        }
    }

    # API
    handle /api/* {
        reverse_proxy localhost:5000
    }
    handle /health {
        reverse_proxy localhost:5000
    }

    # Admin portal SPA (strip /admin prefix)
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

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
    }

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
```

## Landing Page

Single self-contained `index.html` with Tailwind CSS via CDN. No build tools.

Content sections:
- Hero: "SSDID Drive" + tagline (PQC-secured file storage)
- Feature cards: post-quantum security, self-sovereign identity, zero-knowledge encryption, cross-platform
- Download/CTA section: desktop app, mobile apps, admin portal link
- Footer: links to registry, docs

## CORS Update

Admin portal is now same-origin, simplify to:

```json
{
  "Cors": {
    "Origins": ["https://drive.ssdid.my"]
  }
}
```

## Admin Portal Build Config

Vite config must set `base: '/admin/'` so asset paths resolve under the path prefix.

## Directory Structure (VPS)

```
/var/www/
├── landing/
│   └── index.html
└── admin/
    ├── index.html
    └── assets/
```
