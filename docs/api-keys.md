# API Keys & Secrets Configuration

This document describes where each platform reads its API keys and secrets.

## Backend (.NET API)

| Key | File | Config Path |
|-----|------|-------------|
| PostgreSQL connection | `appsettings.Production.json` | `ConnectionStrings:Default` |
| SSDID Registry URL | `appsettings.Production.json` | `Ssdid:RegistryUrl` |
| Server identity path | `appsettings.Production.json` | `Ssdid:IdentityPath` |
| Server algorithm | `appsettings.Production.json` | `Ssdid:Algorithm` |
| Service URL | `appsettings.Production.json` | `Ssdid:ServiceUrl` |
| CORS origins | `appsettings.Production.json` | `Cors:Origins` |

All backend config can be overridden via environment variables using the `__` separator:
```bash
ConnectionStrings__Default="Host=db;Port=5432;..."
Ssdid__RegistryUrl="https://registry.ssdid.my"
```

The server identity private key is auto-generated at `data/server-identity.json` on first run. **Back this up** — losing it invalidates all issued Verifiable Credentials.

## Desktop (Tauri + React)

| Key | Env Variable | File |
|-----|-------------|------|
| OneSignal App ID | `VITE_ONESIGNAL_APP_ID` | `clients/desktop/.env` |
| OneSignal Safari Web ID | `VITE_ONESIGNAL_SAFARI_WEB_ID` | `clients/desktop/.env` |
| Sentry DSN | `VITE_SENTRY_DSN` | `clients/desktop/.env` |
| Sentry (Rust backend) | `SENTRY_DSN` | `clients/desktop/.env` |

Template: `clients/desktop/.env.example`

Create the `.env` file:
```bash
cp clients/desktop/.env.example clients/desktop/.env
# Edit and fill in values
```

## Android

| Key | Property | File |
|-----|----------|------|
| OneSignal App ID | `onesignal.app.id` | `clients/android/local.properties` |
| Sentry DSN | `sentry.dsn` | `clients/android/local.properties` |

Template: `clients/android/local.properties.example`

Create the `local.properties` file:
```bash
cp clients/android/local.properties.example clients/android/local.properties
# Edit and fill in values
```

Note: `local.properties` is gitignored. Android Studio also writes `sdk.dir` to this file.

## iOS

| Key | Info.plist Key | Set Via |
|-----|---------------|---------|
| OneSignal App ID | `ONESIGNAL_APP_ID` | xcconfig or CI build settings |
| Sentry DSN | `SENTRY_DSN` | xcconfig or CI build settings |

Add to your `.xcconfig` file or Xcode build settings:
```
ONESIGNAL_APP_ID = your-app-id-here
SENTRY_DSN = https://your-dsn@sentry.io/project-id
```

Then reference in `Info.plist`:
```xml
<key>ONESIGNAL_APP_ID</key>
<string>$(ONESIGNAL_APP_ID)</string>
<key>SENTRY_DSN</key>
<string>$(SENTRY_DSN)</string>
```

## Key Sources

| Service | Dashboard |
|---------|-----------|
| OneSignal | https://onesignal.com → App Settings → Keys & IDs |
| Sentry | https://sentry.io → Project Settings → Client Keys (DSN) |
| SSDID Registry | Self-hosted at `registry.ssdid.my` |

## Files That Must Never Be Committed

| File | Contains |
|------|----------|
| `clients/desktop/.env` | OneSignal, Sentry keys |
| `clients/android/local.properties` | OneSignal, Sentry keys, SDK path |
| `data/server-identity.json` | Server private key |
| `clients/android/keystore.properties` | Signing keystore password |
| `*.p12`, `*.pem`, `*.key`, `*.pfx` | Certificates and private keys |

All of these are covered by `.gitignore`.
