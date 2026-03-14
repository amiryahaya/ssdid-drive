# Desktop Client Auth Migration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SSDID Wallet QR-based authentication in the desktop client with email+OTP login, OIDC (Google/Microsoft) via system browser deep link, and TOTP verification/setup screens.

**Architecture:** The desktop client is Tauri v2 (React/TypeScript frontend + Rust backend). Auth flows call backend API endpoints via Rust Tauri commands (bypassing CORS). Session tokens are stored in OS keychain via `KeyringStore`. The existing `loginWithSession(token)` flow remains — new auth methods produce the same session token. OIDC opens the system browser, and the redirect `ssdid-drive://auth/callback` is captured by Tauri's deep-link plugin and routed to `useDeepLink`.

**Tech Stack:** React 18, TypeScript, Zustand, Tailwind CSS, Radix UI, Lucide icons, qrcode.react, Tauri v2 (Rust), vitest

---

## File Structure

### New Files — React (Frontend)

| File | Responsibility |
|------|---------------|
| `clients/desktop/src/pages/EmailLoginPage.tsx` | Email input + OTP verification + TOTP verification flow |
| `clients/desktop/src/pages/TotpSetupPage.tsx` | TOTP QR display + confirm code + backup codes |
| `clients/desktop/src/components/auth/OtpInput.tsx` | Reusable 6-digit OTP/TOTP code input component |
| `clients/desktop/src/components/auth/OidcButtons.tsx` | "Sign in with Google" / "Sign in with Microsoft" buttons |
| `clients/desktop/src/components/settings/LinkedLoginsSection.tsx` | Settings > Linked Logins list + add/remove |

### New Files — Rust (Backend)

| File | Responsibility |
|------|---------------|
| `clients/desktop/src-tauri/src/commands/email_auth.rs` | Tauri commands: `send_otp`, `verify_otp`, `email_login` |
| `clients/desktop/src-tauri/src/commands/oidc_auth.rs` | Tauri commands: `oidc_login`, `verify_oidc_token` |
| `clients/desktop/src-tauri/src/commands/totp.rs` | Tauri commands: `totp_setup`, `totp_setup_confirm`, `totp_verify` |
| `clients/desktop/src-tauri/src/commands/account.rs` | Tauri commands: `list_logins`, `link_email_login`, `link_oidc_login`, `unlink_login` |

### New Files — Tests

| File | Responsibility |
|------|---------------|
| `clients/desktop/src/components/auth/OtpInput.test.tsx` | OtpInput unit tests |
| `clients/desktop/src/components/auth/OidcButtons.test.tsx` | OidcButtons unit tests |
| `clients/desktop/src/pages/EmailLoginPage.test.tsx` | EmailLoginPage unit tests |
| `clients/desktop/src/pages/TotpSetupPage.test.tsx` | TotpSetupPage unit tests |

### Modified Files

| File | Changes |
|------|---------|
| `clients/desktop/src/pages/LoginPage.tsx` | Replace QR-only with multi-method: email, OIDC, QR (kept) |
| `clients/desktop/src/App.tsx` | Add routes: `/login/email`, `/login/totp-setup`, `/auth/callback` |
| `clients/desktop/src/stores/authStore.ts` | Add `sendOtp`, `verifyOtp`, `loginWithOidc`, `totpSetup`, `totpVerify` actions |
| `clients/desktop/src/services/tauri.ts` | Add Tauri command wrappers for new auth commands |
| `clients/desktop/src/hooks/useDeepLink.ts` | Add `auth/callback` handler for OIDC redirect |
| `clients/desktop/src/pages/RegisterPage.tsx` | Replace QR-only with email registration flow |
| `clients/desktop/src/pages/SettingsPage.tsx` | Add "Linked Logins" section |
| `clients/desktop/src-tauri/src/commands/mod.rs` | Add `pub mod email_auth; pub mod oidc_auth; pub mod totp; pub mod account;` |
| `clients/desktop/src-tauri/src/lib.rs` | Register new Tauri commands |
| `clients/desktop/src-tauri/src/services/auth_service.rs` | Add `login_with_email`, `login_with_oidc` methods |

---

## Chunk 1: Foundation — OTP Input Component + Tauri Commands

### Task 1: OtpInput Component

**Files:**
- Create: `clients/desktop/src/components/auth/OtpInput.tsx`
- Create: `clients/desktop/src/components/auth/OtpInput.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// clients/desktop/src/components/auth/OtpInput.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi } from 'vitest';
import { OtpInput } from './OtpInput';

describe('OtpInput', () => {
  it('renders 6 input fields', () => {
    render(<OtpInput onComplete={vi.fn()} />);
    const inputs = screen.getAllByRole('textbox');
    expect(inputs).toHaveLength(6);
  });

  it('calls onComplete when all digits entered', async () => {
    const onComplete = vi.fn();
    render(<OtpInput onComplete={onComplete} />);
    const inputs = screen.getAllByRole('textbox');
    const user = userEvent.setup();
    for (let i = 0; i < 6; i++) {
      await user.type(inputs[i], String(i));
    }
    expect(onComplete).toHaveBeenCalledWith('012345');
  });

  it('displays error message when provided', () => {
    render(<OtpInput onComplete={vi.fn()} error="Invalid code" />);
    expect(screen.getByText('Invalid code')).toBeInTheDocument();
  });

  it('disables inputs when disabled prop is true', () => {
    render(<OtpInput onComplete={vi.fn()} disabled />);
    const inputs = screen.getAllByRole('textbox');
    inputs.forEach(input => expect(input).toBeDisabled());
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx vitest run src/components/auth/OtpInput.test.tsx`
Expected: FAIL — module not found

- [ ] **Step 3: Write minimal implementation**

```tsx
// clients/desktop/src/components/auth/OtpInput.tsx
import { useRef, useCallback, KeyboardEvent, ClipboardEvent } from 'react';
import { cn } from '@/lib/utils';

interface OtpInputProps {
  length?: number;
  onComplete: (code: string) => void;
  error?: string;
  disabled?: boolean;
}

export function OtpInput({ length = 6, onComplete, error, disabled }: OtpInputProps) {
  const inputsRef = useRef<(HTMLInputElement | null)[]>([]);

  const handleChange = useCallback(
    (index: number, value: string) => {
      if (!/^\d?$/.test(value)) return;

      const input = inputsRef.current[index];
      if (input) input.value = value;

      if (value && index < length - 1) {
        inputsRef.current[index + 1]?.focus();
      }

      const code = inputsRef.current.map((i) => i?.value || '').join('');
      if (code.length === length) {
        onComplete(code);
      }
    },
    [length, onComplete]
  );

  const handleKeyDown = useCallback(
    (index: number, e: KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Backspace' && !inputsRef.current[index]?.value && index > 0) {
        inputsRef.current[index - 1]?.focus();
      }
    },
    []
  );

  const handlePaste = useCallback(
    (e: ClipboardEvent<HTMLInputElement>) => {
      e.preventDefault();
      const text = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, length);
      text.split('').forEach((char, i) => {
        if (inputsRef.current[i]) {
          inputsRef.current[i]!.value = char;
        }
      });
      if (text.length === length) {
        onComplete(text);
      } else if (text.length > 0) {
        inputsRef.current[Math.min(text.length, length - 1)]?.focus();
      }
    },
    [length, onComplete]
  );

  return (
    <div>
      <div className="flex gap-2 justify-center">
        {Array.from({ length }).map((_, i) => (
          <input
            key={i}
            ref={(el) => { inputsRef.current[i] = el; }}
            role="textbox"
            type="text"
            inputMode="numeric"
            maxLength={1}
            disabled={disabled}
            className={cn(
              'w-12 h-14 text-center text-xl font-mono rounded-lg border bg-background',
              'focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2',
              'disabled:opacity-50 disabled:cursor-not-allowed',
              error ? 'border-destructive' : 'border-input'
            )}
            onChange={(e) => handleChange(i, e.target.value)}
            onKeyDown={(e) => handleKeyDown(i, e)}
            onPaste={i === 0 ? handlePaste : undefined}
          />
        ))}
      </div>
      {error && (
        <p className="text-sm text-destructive text-center mt-2">{error}</p>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx vitest run src/components/auth/OtpInput.test.tsx`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/components/auth/OtpInput.tsx clients/desktop/src/components/auth/OtpInput.test.tsx && git commit -m "feat(desktop): add OtpInput component with 6-digit code entry"
```

### Task 2: OIDC Buttons Component

**Files:**
- Create: `clients/desktop/src/components/auth/OidcButtons.tsx`
- Create: `clients/desktop/src/components/auth/OidcButtons.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// clients/desktop/src/components/auth/OidcButtons.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi } from 'vitest';
import { OidcButtons } from './OidcButtons';

describe('OidcButtons', () => {
  it('renders Google and Microsoft buttons', () => {
    render(<OidcButtons onProviderClick={vi.fn()} />);
    expect(screen.getByText(/Google/)).toBeInTheDocument();
    expect(screen.getByText(/Microsoft/)).toBeInTheDocument();
  });

  it('calls onProviderClick with provider name', async () => {
    const onClick = vi.fn();
    render(<OidcButtons onProviderClick={onClick} />);
    const user = userEvent.setup();
    await user.click(screen.getByText(/Google/));
    expect(onClick).toHaveBeenCalledWith('google');
  });

  it('disables buttons when disabled', () => {
    render(<OidcButtons onProviderClick={vi.fn()} disabled />);
    expect(screen.getByText(/Google/).closest('button')).toBeDisabled();
    expect(screen.getByText(/Microsoft/).closest('button')).toBeDisabled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx vitest run src/components/auth/OidcButtons.test.tsx`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```tsx
// clients/desktop/src/components/auth/OidcButtons.tsx
import { Button } from '@/components/ui/Button';
import { Loader2 } from 'lucide-react';

interface OidcButtonsProps {
  onProviderClick: (provider: 'google' | 'microsoft') => void;
  disabled?: boolean;
  loading?: 'google' | 'microsoft' | null;
}

export function OidcButtons({ onProviderClick, disabled, loading }: OidcButtonsProps) {
  return (
    <div className="space-y-3">
      <Button
        variant="outline"
        className="w-full h-11 relative"
        onClick={() => onProviderClick('google')}
        disabled={disabled || loading !== null}
      >
        {loading === 'google' ? (
          <Loader2 className="h-5 w-5 animate-spin mr-2" />
        ) : (
          <svg className="h-5 w-5 mr-2" viewBox="0 0 24 24">
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" />
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
          </svg>
        )}
        Sign in with Google
      </Button>
      <Button
        variant="outline"
        className="w-full h-11 relative"
        onClick={() => onProviderClick('microsoft')}
        disabled={disabled || loading !== null}
      >
        {loading === 'microsoft' ? (
          <Loader2 className="h-5 w-5 animate-spin mr-2" />
        ) : (
          <svg className="h-5 w-5 mr-2" viewBox="0 0 23 23">
            <path fill="#f35325" d="M1 1h10v10H1z" />
            <path fill="#81bc06" d="M12 1h10v10H12z" />
            <path fill="#05a6f0" d="M1 12h10v10H1z" />
            <path fill="#ffba08" d="M12 12h10v10H12z" />
          </svg>
        )}
        Sign in with Microsoft
      </Button>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx vitest run src/components/auth/OidcButtons.test.tsx`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/components/auth/OidcButtons.tsx clients/desktop/src/components/auth/OidcButtons.test.tsx && git commit -m "feat(desktop): add OidcButtons component for Google/Microsoft sign-in"
```

### Task 3: Tauri Service Wrappers for New Auth API

**Files:**
- Modify: `clients/desktop/src/services/tauri.ts`

- [ ] **Step 1: Add new auth command types and wrappers to tauri.ts**

Add after the existing `// ==================== SSDID Auth Commands ====================` section in `tauriService`:

```typescript
// In tauri.ts, add these types at the top level:

export interface OtpSendResponse {
  message: string;
}

export interface OtpVerifyResponse {
  token: string;
  totp_setup_required?: boolean;
}

export interface EmailLoginResponse {
  requires_totp: boolean;
}

export interface TotpSetupResponse {
  secret: string;
  otpauth_uri: string;
}

export interface TotpSetupConfirmResponse {
  backup_codes: string[];
}

export interface TotpVerifyResponse {
  token: string;
}

export interface OidcLoginResponse {
  token: string;
  mfa_required?: boolean;
  totp_setup_required?: boolean;
}

export interface LinkedLogin {
  id: string;
  provider: string;
  provider_subject: string;
  email: string | null;
  linked_at: string;
}

// Add to tauriService object:

  // ==================== Email Auth Commands ====================

  async sendOtp(email: string, invitationToken?: string): Promise<OtpSendResponse> {
    return invoke('send_otp', { email, invitationToken: invitationToken ?? null });
  },

  async verifyOtp(email: string, code: string, invitationToken?: string): Promise<OtpVerifyResponse> {
    return invoke('verify_otp', { email, code, invitationToken: invitationToken ?? null });
  },

  async emailLogin(email: string): Promise<EmailLoginResponse> {
    return invoke('email_login', { email });
  },

  // ==================== OIDC Auth Commands ====================

  async oidcLogin(provider: string): Promise<void> {
    return invoke('oidc_login', { provider });
  },

  async verifyOidcToken(provider: string, idToken: string, invitationToken?: string): Promise<OidcLoginResponse> {
    return invoke('verify_oidc_token', { provider, idToken, invitationToken: invitationToken ?? null });
  },

  // ==================== TOTP Commands ====================

  async totpSetup(): Promise<TotpSetupResponse> {
    return invoke('totp_setup');
  },

  async totpSetupConfirm(code: string): Promise<TotpSetupConfirmResponse> {
    return invoke('totp_setup_confirm', { code });
  },

  async totpVerify(email: string, code: string): Promise<TotpVerifyResponse> {
    return invoke('totp_verify', { email, code });
  },

  // ==================== Account Commands ====================

  async listLogins(): Promise<LinkedLogin[]> {
    return invoke('list_logins');
  },

  async linkEmailLogin(email: string): Promise<OtpSendResponse> {
    return invoke('link_email_login', { email });
  },

  async linkOidcLogin(provider: string, idToken: string): Promise<void> {
    return invoke('link_oidc_login', { provider, idToken });
  },

  async unlinkLogin(loginId: string): Promise<void> {
    return invoke('unlink_login', { loginId });
  },
```

- [ ] **Step 2: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/services/tauri.ts && git commit -m "feat(desktop): add Tauri service wrappers for email, OIDC, TOTP, and account commands"
```

### Task 4: Rust Tauri Commands — Email Auth

**Files:**
- Create: `clients/desktop/src-tauri/src/commands/email_auth.rs`
- Modify: `clients/desktop/src-tauri/src/commands/mod.rs`
- Modify: `clients/desktop/src-tauri/src/lib.rs`

- [ ] **Step 1: Create email_auth.rs with Tauri commands**

```rust
// clients/desktop/src-tauri/src/commands/email_auth.rs
//! Email + OTP authentication commands

use crate::error::AppResult;
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Serialize, Deserialize)]
pub struct OtpSendResponse {
    pub message: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OtpVerifyResponse {
    pub token: String,
    pub totp_setup_required: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EmailLoginResponse {
    pub requires_totp: bool,
}

/// Send OTP to email for registration
#[tauri::command]
pub async fn send_otp(
    email: String,
    invitation_token: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<OtpSendResponse> {
    #[derive(Serialize)]
    struct Body {
        email: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        invitation_token: Option<String>,
    }

    state
        .api_client()
        .post_unauth::<Body, OtpSendResponse>(
            "/auth/email/register",
            &Body { email, invitation_token },
        )
        .await
}

/// Verify OTP code for registration
#[tauri::command]
pub async fn verify_otp(
    email: String,
    code: String,
    invitation_token: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<OtpVerifyResponse> {
    #[derive(Serialize)]
    struct Body {
        email: String,
        code: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        invitation_token: Option<String>,
    }

    let response: OtpVerifyResponse = state
        .api_client()
        .post_unauth(
            "/auth/email/register/verify",
            &Body { email, code, invitation_token },
        )
        .await?;

    // Save session token
    state.auth_service().save_session(&response.token)?;
    state.unlock();

    // Fetch and cache user
    if let Ok(user) = state.auth_service().get_current_user().await {
        state.set_current_user(Some(user));
    }

    Ok(response)
}

/// Initiate email login (check if TOTP required)
#[tauri::command]
pub async fn email_login(
    email: String,
    state: State<'_, AppState>,
) -> AppResult<EmailLoginResponse> {
    #[derive(Serialize)]
    struct Body {
        email: String,
    }

    state
        .api_client()
        .post_unauth::<Body, EmailLoginResponse>(
            "/auth/email/login",
            &Body { email },
        )
        .await
}
```

- [ ] **Step 2: Add module to mod.rs**

Add `pub mod email_auth;` to `clients/desktop/src-tauri/src/commands/mod.rs`.

- [ ] **Step 3: Register commands in lib.rs**

Add to the `invoke_handler` in `lib.rs`:
```rust
// Email auth commands
commands::email_auth::send_otp,
commands::email_auth::verify_otp,
commands::email_auth::email_login,
```

- [ ] **Step 4: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src-tauri/src/commands/email_auth.rs clients/desktop/src-tauri/src/commands/mod.rs clients/desktop/src-tauri/src/lib.rs && git commit -m "feat(desktop): add Rust Tauri commands for email OTP auth"
```

### Task 5: Rust Tauri Commands — OIDC Auth

**Files:**
- Create: `clients/desktop/src-tauri/src/commands/oidc_auth.rs`
- Modify: `clients/desktop/src-tauri/src/commands/mod.rs`
- Modify: `clients/desktop/src-tauri/src/lib.rs`

- [ ] **Step 1: Create oidc_auth.rs**

```rust
// clients/desktop/src-tauri/src/commands/oidc_auth.rs
//! OIDC authentication commands
//!
//! Desktop OIDC flow:
//! 1. Client calls `oidc_login` → opens system browser to provider auth URL
//! 2. Provider redirects to `ssdid-drive://auth/callback?provider=X&id_token=Y`
//! 3. Deep link handler captures the redirect, calls `verify_oidc_token`
//! 4. Backend verifies the ID token, returns session token

use crate::error::{AppError, AppResult};
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Serialize, Deserialize)]
pub struct OidcLoginResponse {
    pub token: String,
    pub mfa_required: Option<bool>,
    pub totp_setup_required: Option<bool>,
}

/// Open system browser for OIDC provider authentication
#[tauri::command]
pub async fn oidc_login(
    provider: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    let base_url = state.api_client().base_url().to_string();
    let server_url = base_url.trim_end_matches("/api").trim_end_matches("/api/");

    // Build the server-side authorize URL that redirects to the provider
    // The server generates PKCE state and redirects the browser to Google/Microsoft
    let authorize_url = format!(
        "{}/api/auth/oidc/{}/authorize?redirect_uri={}",
        server_url,
        provider,
        urlencoding::encode("ssdid-drive://auth/callback")
    );

    tracing::info!("Opening OIDC authorize URL for provider: {}", provider);

    // Open in system browser
    open::that(&authorize_url).map_err(|e| {
        AppError::Auth(format!("Failed to open browser: {}", e))
    })?;

    Ok(())
}

/// Verify an OIDC ID token received from the provider callback
#[tauri::command]
pub async fn verify_oidc_token(
    provider: String,
    id_token: String,
    invitation_token: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<OidcLoginResponse> {
    #[derive(Serialize)]
    struct Body {
        provider: String,
        id_token: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        invitation_token: Option<String>,
    }

    let response: OidcLoginResponse = state
        .api_client()
        .post_unauth(
            "/auth/oidc/verify",
            &Body { provider, id_token, invitation_token },
        )
        .await?;

    // Save session token
    state.auth_service().save_session(&response.token)?;
    state.unlock();

    // Fetch and cache user
    if let Ok(user) = state.auth_service().get_current_user().await {
        state.set_current_user(Some(user));
    }

    Ok(response)
}
```

- [ ] **Step 2: Add module to mod.rs and register commands in lib.rs**

Add `pub mod oidc_auth;` to `mod.rs`.

Add to `invoke_handler` in `lib.rs`:
```rust
// OIDC auth commands
commands::oidc_auth::oidc_login,
commands::oidc_auth::verify_oidc_token,
```

- [ ] **Step 3: Add `open` and `urlencoding` crates to Cargo.toml**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop/src-tauri && cargo add open urlencoding
```

- [ ] **Step 4: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src-tauri/src/commands/oidc_auth.rs clients/desktop/src-tauri/src/commands/mod.rs clients/desktop/src-tauri/src/lib.rs clients/desktop/src-tauri/Cargo.toml clients/desktop/src-tauri/Cargo.lock && git commit -m "feat(desktop): add Rust Tauri commands for OIDC auth via system browser"
```

### Task 6: Rust Tauri Commands — TOTP

**Files:**
- Create: `clients/desktop/src-tauri/src/commands/totp.rs`
- Modify: `clients/desktop/src-tauri/src/commands/mod.rs`
- Modify: `clients/desktop/src-tauri/src/lib.rs`

- [ ] **Step 1: Create totp.rs**

```rust
// clients/desktop/src-tauri/src/commands/totp.rs
//! TOTP setup and verification commands

use crate::error::AppResult;
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Serialize, Deserialize)]
pub struct TotpSetupResponse {
    pub secret: String,
    pub otpauth_uri: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TotpSetupConfirmResponse {
    pub backup_codes: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TotpVerifyResponse {
    pub token: String,
}

/// Request TOTP setup (requires auth)
#[tauri::command]
pub async fn totp_setup(
    state: State<'_, AppState>,
) -> AppResult<TotpSetupResponse> {
    state
        .api_client()
        .post::<(), TotpSetupResponse>("/auth/totp/setup", &())
        .await
}

/// Confirm TOTP setup with first code (requires auth)
#[tauri::command]
pub async fn totp_setup_confirm(
    code: String,
    state: State<'_, AppState>,
) -> AppResult<TotpSetupConfirmResponse> {
    #[derive(Serialize)]
    struct Body {
        code: String,
    }

    state
        .api_client()
        .post::<Body, TotpSetupConfirmResponse>(
            "/auth/totp/setup/confirm",
            &Body { code },
        )
        .await
}

/// Verify TOTP code for login (public endpoint)
#[tauri::command]
pub async fn totp_verify(
    email: String,
    code: String,
    state: State<'_, AppState>,
) -> AppResult<TotpVerifyResponse> {
    #[derive(Serialize)]
    struct Body {
        email: String,
        code: String,
    }

    let response: TotpVerifyResponse = state
        .api_client()
        .post_unauth(
            "/auth/totp/verify",
            &Body { email, code },
        )
        .await?;

    // Save session token
    state.auth_service().save_session(&response.token)?;
    state.unlock();

    // Fetch and cache user
    if let Ok(user) = state.auth_service().get_current_user().await {
        state.set_current_user(Some(user));
    }

    Ok(response)
}
```

- [ ] **Step 2: Add module and register commands**

Add `pub mod totp;` to `mod.rs`.

Add to `invoke_handler` in `lib.rs`:
```rust
// TOTP commands
commands::totp::totp_setup,
commands::totp::totp_setup_confirm,
commands::totp::totp_verify,
```

- [ ] **Step 3: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src-tauri/src/commands/totp.rs clients/desktop/src-tauri/src/commands/mod.rs clients/desktop/src-tauri/src/lib.rs && git commit -m "feat(desktop): add Rust Tauri commands for TOTP setup and verification"
```

### Task 7: Rust Tauri Commands — Account (Linked Logins)

**Files:**
- Create: `clients/desktop/src-tauri/src/commands/account.rs`
- Modify: `clients/desktop/src-tauri/src/commands/mod.rs`
- Modify: `clients/desktop/src-tauri/src/lib.rs`

- [ ] **Step 1: Create account.rs**

```rust
// clients/desktop/src-tauri/src/commands/account.rs
//! Account management commands (linked logins)

use crate::error::AppResult;
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LinkedLogin {
    pub id: String,
    pub provider: String,
    pub provider_subject: String,
    pub email: Option<String>,
    pub linked_at: String,
}

/// List all linked logins for the current account
#[tauri::command]
pub async fn list_logins(
    state: State<'_, AppState>,
) -> AppResult<Vec<LinkedLogin>> {
    state
        .api_client()
        .get::<Vec<LinkedLogin>>("/account/logins")
        .await
}

/// Initiate linking a new email login (sends OTP)
#[tauri::command]
pub async fn link_email_login(
    email: String,
    state: State<'_, AppState>,
) -> AppResult<serde_json::Value> {
    #[derive(Serialize)]
    struct Body {
        email: String,
    }

    state
        .api_client()
        .post::<Body, serde_json::Value>(
            "/account/logins/email",
            &Body { email },
        )
        .await
}

/// Link an OIDC login to the current account
#[tauri::command]
pub async fn link_oidc_login(
    provider: String,
    id_token: String,
    state: State<'_, AppState>,
) -> AppResult<serde_json::Value> {
    #[derive(Serialize)]
    struct Body {
        provider: String,
        id_token: String,
    }

    state
        .api_client()
        .post::<Body, serde_json::Value>(
            "/account/logins/oidc",
            &Body { provider, id_token },
        )
        .await
}

/// Unlink a login from the current account
#[tauri::command]
pub async fn unlink_login(
    login_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state
        .api_client()
        .delete_no_content(&format!("/account/logins/{}", login_id))
        .await
}
```

- [ ] **Step 2: Add module and register commands**

Add `pub mod account;` to `mod.rs`.

Add to `invoke_handler` in `lib.rs`:
```rust
// Account commands
commands::account::list_logins,
commands::account::link_email_login,
commands::account::link_oidc_login,
commands::account::unlink_login,
```

- [ ] **Step 3: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src-tauri/src/commands/account.rs clients/desktop/src-tauri/src/commands/mod.rs clients/desktop/src-tauri/src/lib.rs && git commit -m "feat(desktop): add Rust Tauri commands for linked login management"
```

---

## Chunk 2: Auth Store + Email Login Page

### Task 8: Auth Store — New Auth Actions

**Files:**
- Modify: `clients/desktop/src/stores/authStore.ts`

- [ ] **Step 1: Add new auth state and actions to authStore.ts**

Add to `AuthState` interface:
```typescript
  // Email auth
  sendOtp: (email: string, invitationToken?: string) => Promise<void>;
  verifyOtp: (email: string, code: string, invitationToken?: string) => Promise<{ totpSetupRequired?: boolean }>;
  emailLogin: (email: string) => Promise<{ requiresTotp: boolean }>;

  // OIDC
  loginWithOidc: (provider: 'google' | 'microsoft') => Promise<void>;

  // TOTP
  totpVerify: (email: string, code: string) => Promise<void>;
```

Add implementations in the `create` store:
```typescript
      sendOtp: async (email, invitationToken) => {
        set({ isLoading: true, error: null });
        try {
          const { tauriService } = await import('@/services/tauri');
          await tauriService.sendOtp(email, invitationToken);
          set({ isLoading: false });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      verifyOtp: async (email, code, invitationToken) => {
        set({ isLoading: true, error: null });
        try {
          const { tauriService } = await import('@/services/tauri');
          const response = await tauriService.verifyOtp(email, code, invitationToken);
          await get().loginWithSession(response.token);
          set({ isLoading: false });
          return { totpSetupRequired: response.totp_setup_required };
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      emailLogin: async (email) => {
        set({ isLoading: true, error: null });
        try {
          const { tauriService } = await import('@/services/tauri');
          const response = await tauriService.emailLogin(email);
          set({ isLoading: false });
          return { requiresTotp: response.requires_totp };
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      loginWithOidc: async (provider) => {
        set({ isLoading: true, error: null });
        try {
          const { tauriService } = await import('@/services/tauri');
          await tauriService.oidcLogin(provider);
          // Browser opens — auth continues via deep link callback
          set({ isLoading: false });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      totpVerify: async (email, code) => {
        set({ isLoading: true, error: null });
        try {
          const { tauriService } = await import('@/services/tauri');
          const response = await tauriService.totpVerify(email, code);
          await get().loginWithSession(response.token);
          set({ isLoading: false });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },
```

- [ ] **Step 2: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/stores/authStore.ts && git commit -m "feat(desktop): add email, OIDC, and TOTP auth actions to authStore"
```

### Task 9: Email Login Page

**Files:**
- Create: `clients/desktop/src/pages/EmailLoginPage.tsx`
- Create: `clients/desktop/src/pages/EmailLoginPage.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// clients/desktop/src/pages/EmailLoginPage.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { EmailLoginPage } from './EmailLoginPage';

// Mock authStore
vi.mock('@/stores/authStore', () => ({
  useAuthStore: vi.fn((selector) => {
    const state = {
      emailLogin: vi.fn().mockResolvedValue({ requiresTotp: true }),
      totpVerify: vi.fn(),
      isLoading: false,
      error: null,
      clearError: vi.fn(),
    };
    return selector(state);
  }),
}));

describe('EmailLoginPage', () => {
  it('renders email input step initially', () => {
    render(
      <MemoryRouter>
        <EmailLoginPage />
      </MemoryRouter>
    );
    expect(screen.getByPlaceholderText(/email/i)).toBeInTheDocument();
    expect(screen.getByText(/continue/i)).toBeInTheDocument();
  });

  it('shows TOTP input after email submit when TOTP required', async () => {
    render(
      <MemoryRouter>
        <EmailLoginPage />
      </MemoryRouter>
    );
    const user = userEvent.setup();
    await user.type(screen.getByPlaceholderText(/email/i), 'test@test.com');
    await user.click(screen.getByText(/continue/i));
    // Should transition to TOTP step
    expect(await screen.findByText(/authenticator/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx vitest run src/pages/EmailLoginPage.test.tsx`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```tsx
// clients/desktop/src/pages/EmailLoginPage.tsx
import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { OtpInput } from '@/components/auth/OtpInput';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/input';
import { ArrowLeft, Loader2, Mail, Shield } from 'lucide-react';

type Step = 'email' | 'totp';

export function EmailLoginPage() {
  const navigate = useNavigate();
  const emailLogin = useAuthStore((s) => s.emailLogin);
  const totpVerify = useAuthStore((s) => s.totpVerify);
  const isLoading = useAuthStore((s) => s.isLoading);
  const error = useAuthStore((s) => s.error);
  const clearError = useAuthStore((s) => s.clearError);

  const [step, setStep] = useState<Step>('email');
  const [email, setEmail] = useState('');

  const handleEmailSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) return;
    try {
      const result = await emailLogin(email.trim());
      if (result.requiresTotp) {
        setStep('totp');
      }
    } catch {
      // Error handled by store
    }
  };

  const handleTotpComplete = async (code: string) => {
    try {
      await totpVerify(email, code);
      navigate('/files');
    } catch {
      // Error handled by store
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Header */}
        <div className="flex flex-col items-center mb-8">
          <div className="h-16 w-16 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
            {step === 'email' ? (
              <Mail className="h-8 w-8 text-primary" />
            ) : (
              <Shield className="h-8 w-8 text-primary" />
            )}
          </div>
          <h1 className="text-2xl font-bold">
            {step === 'email' ? 'Sign in with Email' : 'Enter Authenticator Code'}
          </h1>
          <p className="text-muted-foreground text-sm mt-1 text-center">
            {step === 'email'
              ? 'Enter your email to continue'
              : 'Open your authenticator app and enter the 6-digit code'}
          </p>
        </div>

        {/* Error */}
        {error && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {error}
            <button onClick={clearError} className="ml-2 underline hover:no-underline">
              Dismiss
            </button>
          </div>
        )}

        {/* Email Step */}
        {step === 'email' && (
          <form onSubmit={handleEmailSubmit} className="space-y-4">
            <Input
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              disabled={isLoading}
              autoFocus
            />
            <Button type="submit" className="w-full" disabled={isLoading || !email.trim()}>
              {isLoading ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Checking...
                </>
              ) : (
                'Continue'
              )}
            </Button>
          </form>
        )}

        {/* TOTP Step */}
        {step === 'totp' && (
          <div className="space-y-6">
            <OtpInput onComplete={handleTotpComplete} disabled={isLoading} error={error ?? undefined} />
            {isLoading && (
              <div className="flex justify-center">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            )}
            <button
              onClick={() => { setStep('email'); clearError(); }}
              className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground mx-auto"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to email
            </button>
          </div>
        )}

        {/* Back to login */}
        <div className="mt-6 text-center text-sm">
          <Link to="/login" className="text-muted-foreground hover:text-foreground">
            <ArrowLeft className="h-4 w-4 inline mr-1" />
            Back to all sign-in options
          </Link>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx vitest run src/pages/EmailLoginPage.test.tsx`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/pages/EmailLoginPage.tsx clients/desktop/src/pages/EmailLoginPage.test.tsx && git commit -m "feat(desktop): add EmailLoginPage with email input and TOTP verification"
```

---

## Chunk 3: TOTP Setup + Login Page Redesign

### Task 10: TOTP Setup Page

**Files:**
- Create: `clients/desktop/src/pages/TotpSetupPage.tsx`
- Create: `clients/desktop/src/pages/TotpSetupPage.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// clients/desktop/src/pages/TotpSetupPage.test.tsx
import { render, screen } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { TotpSetupPage } from './TotpSetupPage';

vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn(),
}));

vi.mock('@/services/tauri', () => ({
  tauriService: {
    totpSetup: vi.fn().mockResolvedValue({
      secret: 'JBSWY3DPEHPK3PXP',
      otpauth_uri: 'otpauth://totp/SsdidDrive:test@test.com?secret=JBSWY3DPEHPK3PXP&issuer=SsdidDrive',
    }),
    totpSetupConfirm: vi.fn().mockResolvedValue({
      backup_codes: ['111111', '222222', '333333'],
    }),
  },
}));

describe('TotpSetupPage', () => {
  it('renders QR code step initially', async () => {
    render(
      <MemoryRouter>
        <TotpSetupPage />
      </MemoryRouter>
    );
    expect(await screen.findByText(/scan.*qr/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx vitest run src/pages/TotpSetupPage.test.tsx`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```tsx
// clients/desktop/src/pages/TotpSetupPage.tsx
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { Button } from '@/components/ui/Button';
import { OtpInput } from '@/components/auth/OtpInput';
import { tauriService } from '@/services/tauri';
import { Loader2, Shield, Copy, Check, AlertTriangle } from 'lucide-react';

type Step = 'loading' | 'qr' | 'confirm' | 'backup-codes' | 'error';

export function TotpSetupPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState<Step>('loading');
  const [otpauthUri, setOtpauthUri] = useState('');
  const [secret, setSecret] = useState('');
  const [backupCodes, setBackupCodes] = useState<string[]>([]);
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    (async () => {
      try {
        const result = await tauriService.totpSetup();
        setOtpauthUri(result.otpauth_uri);
        setSecret(result.secret);
        setStep('qr');
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
        setStep('error');
      }
    })();
  }, []);

  const handleConfirm = async (code: string) => {
    setIsLoading(true);
    setError('');
    try {
      const result = await tauriService.totpSetupConfirm(code);
      setBackupCodes(result.backup_codes);
      setStep('backup-codes');
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setIsLoading(false);
    }
  };

  const handleCopySecret = async () => {
    await navigator.clipboard.writeText(secret);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDone = () => {
    navigate('/files');
  };

  if (step === 'loading') {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (step === 'error') {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <AlertTriangle className="h-8 w-8 text-destructive mx-auto mb-4" />
          <p className="text-destructive mb-4">{error}</p>
          <Button onClick={() => navigate('/files')}>Go back</Button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Header */}
        <div className="flex flex-col items-center mb-6">
          <div className="h-16 w-16 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
            <Shield className="h-8 w-8 text-primary" />
          </div>
          <h1 className="text-2xl font-bold">
            {step === 'qr' && 'Set Up Authenticator'}
            {step === 'confirm' && 'Verify Setup'}
            {step === 'backup-codes' && 'Save Backup Codes'}
          </h1>
        </div>

        {/* QR Step */}
        {step === 'qr' && (
          <div className="space-y-6">
            <p className="text-sm text-muted-foreground text-center">
              Scan this QR code with your authenticator app (Google Authenticator, Authy, etc.)
            </p>
            <div className="bg-white p-4 rounded-xl shadow-inner flex justify-center">
              <QRCodeSVG value={otpauthUri} size={200} level="M" />
            </div>
            <div className="text-center">
              <p className="text-xs text-muted-foreground mb-1">Or enter this key manually:</p>
              <button
                onClick={handleCopySecret}
                className="inline-flex items-center gap-1 text-sm font-mono bg-muted px-3 py-1.5 rounded-lg hover:bg-muted/80"
              >
                {secret}
                {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
              </button>
            </div>
            <Button className="w-full" onClick={() => setStep('confirm')}>
              I've scanned the QR code
            </Button>
          </div>
        )}

        {/* Confirm Step */}
        {step === 'confirm' && (
          <div className="space-y-6">
            <p className="text-sm text-muted-foreground text-center">
              Enter the 6-digit code from your authenticator app to confirm setup
            </p>
            <OtpInput
              onComplete={handleConfirm}
              disabled={isLoading}
              error={error || undefined}
            />
            {isLoading && (
              <div className="flex justify-center">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            )}
            <button
              onClick={() => { setStep('qr'); setError(''); }}
              className="text-sm text-muted-foreground hover:text-foreground mx-auto block"
            >
              Back to QR code
            </button>
          </div>
        )}

        {/* Backup Codes Step */}
        {step === 'backup-codes' && (
          <div className="space-y-6">
            <div className="p-4 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg">
              <div className="flex items-start gap-2">
                <AlertTriangle className="h-5 w-5 text-amber-600 dark:text-amber-400 flex-shrink-0 mt-0.5" />
                <p className="text-sm text-amber-800 dark:text-amber-200">
                  Save these backup codes in a safe place. You can use each code once if you lose access to your authenticator app.
                </p>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              {backupCodes.map((code, i) => (
                <div key={i} className="font-mono text-sm bg-muted px-3 py-2 rounded-lg text-center">
                  {code}
                </div>
              ))}
            </div>
            <Button
              variant="outline"
              className="w-full"
              onClick={async () => {
                await navigator.clipboard.writeText(backupCodes.join('\n'));
                setCopied(true);
                setTimeout(() => setCopied(false), 2000);
              }}
            >
              {copied ? <Check className="h-4 w-4 mr-2" /> : <Copy className="h-4 w-4 mr-2" />}
              {copied ? 'Copied!' : 'Copy all codes'}
            </Button>
            <Button className="w-full" onClick={handleDone}>
              I've saved my backup codes
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx vitest run src/pages/TotpSetupPage.test.tsx`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/pages/TotpSetupPage.tsx clients/desktop/src/pages/TotpSetupPage.test.tsx && git commit -m "feat(desktop): add TotpSetupPage with QR display, confirmation, and backup codes"
```

### Task 11: Redesign LoginPage with Multiple Auth Methods

**Files:**
- Modify: `clients/desktop/src/pages/LoginPage.tsx`

- [ ] **Step 1: Replace LoginPage content**

The new LoginPage offers three auth methods: Email+TOTP, Google OIDC, Microsoft OIDC. The existing QR code flow is preserved under a collapsed "Sign in with SSDID Wallet" option (to be removed in Phase 10).

```tsx
// clients/desktop/src/pages/LoginPage.tsx
import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { OidcButtons } from '@/components/auth/OidcButtons';
import { QrChallenge } from '@/components/auth/QrChallenge';
import { Button } from '@/components/ui/Button';
import { Mail, ChevronDown, ChevronUp } from 'lucide-react';

export function LoginPage() {
  const navigate = useNavigate();
  const { loginWithSession, loginWithOidc, error, clearError, isLoading } = useAuthStore();
  const [showQr, setShowQr] = useState(false);
  const [oidcLoading, setOidcLoading] = useState<'google' | 'microsoft' | null>(null);

  const handleAuthenticated = async (sessionToken: string) => {
    try {
      await loginWithSession(sessionToken);
      navigate('/files');
    } catch {
      // Error handled by store
    }
  };

  const handleOidcLogin = async (provider: 'google' | 'microsoft') => {
    setOidcLoading(provider);
    try {
      await loginWithOidc(provider);
      // Browser opens — continue via deep link callback
    } catch {
      // Error handled by store
    } finally {
      setOidcLoading(null);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Logo */}
        <div className="flex flex-col items-center mb-8">
          <img
            src="/app-icon.png"
            alt="SSDID Drive"
            className="h-24 w-24 rounded-2xl mb-4"
          />
          <h1 className="text-2xl font-bold">SSDID Drive</h1>
          <p className="text-muted-foreground text-sm mt-1">
            Sign in to your account
          </p>
        </div>

        {/* Error message */}
        {error && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {error}
            <button onClick={clearError} className="ml-2 underline hover:no-underline">
              Dismiss
            </button>
          </div>
        )}

        {/* Email login */}
        <Button
          variant="default"
          className="w-full h-11 mb-3"
          onClick={() => navigate('/login/email')}
          disabled={isLoading}
        >
          <Mail className="h-5 w-5 mr-2" />
          Sign in with Email
        </Button>

        {/* Divider */}
        <div className="relative my-4">
          <div className="absolute inset-0 flex items-center">
            <span className="w-full border-t" />
          </div>
          <div className="relative flex justify-center text-xs uppercase">
            <span className="bg-card px-2 text-muted-foreground">or</span>
          </div>
        </div>

        {/* OIDC buttons */}
        <OidcButtons
          onProviderClick={handleOidcLogin}
          disabled={isLoading}
          loading={oidcLoading}
        />

        {/* SSDID Wallet (legacy, collapsible) */}
        <div className="mt-4">
          <button
            onClick={() => setShowQr(!showQr)}
            className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground mx-auto"
          >
            {showQr ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
            Sign in with SSDID Wallet
          </button>
          {showQr && (
            <div className="mt-4">
              <QrChallenge action="authenticate" onAuthenticated={handleAuthenticated} />
            </div>
          )}
        </div>

        {/* Register link */}
        <div className="mt-6 text-center text-sm">
          <p className="text-muted-foreground">
            New to SSDID Drive?{' '}
            <Link to="/register" className="text-primary hover:underline font-medium">
              Register
            </Link>
          </p>
        </div>

        {/* Invite code link */}
        <div className="mt-2 text-center text-sm">
          <p className="text-muted-foreground">
            <Link to="/join" className="text-primary hover:underline font-medium">
              Have an invite code?
            </Link>
          </p>
        </div>

        {/* Recovery link */}
        <div className="mt-2 text-center text-sm">
          <Link to="/recover" className="text-muted-foreground hover:text-foreground text-sm">
            Lost your device? Recover your account
          </Link>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/pages/LoginPage.tsx && git commit -m "feat(desktop): redesign LoginPage with email, OIDC, and collapsible QR options"
```

---

## Chunk 4: Deep Link Callback + Routing + Linked Logins

### Task 12: Deep Link Handler for OIDC Callback

**Files:**
- Modify: `clients/desktop/src/hooks/useDeepLink.ts`

- [ ] **Step 1: Add `auth` action to ParsedDeepLink and handleDeepLink**

In `parseDeepLink`, add `'auth'` to the action type and switch case.

In `handleDeepLink`, add the `auth/callback` handler:
```typescript
      case 'auth':
        // OIDC callback: ssdid-drive://auth/callback?provider=google&id_token=xxx
        if (parsed.id === 'callback' && parsed.params?.provider && parsed.params?.id_token) {
          info({
            title: 'Completing sign-in',
            description: 'Verifying your identity...',
          });
          try {
            const { tauriService } = await import('@/services/tauri');
            const response = await tauriService.verifyOidcToken(
              parsed.params.provider,
              parsed.params.id_token
            );
            // loginWithSession is handled inside verifyOidcToken Rust command
            const authStore = (await import('@/stores/authStore')).useAuthStore.getState();
            await authStore.checkAuth();
            if (response.totp_setup_required) {
              navigate('/login/totp-setup');
            } else if (response.mfa_required) {
              navigate('/login/email', { state: { step: 'totp' } });
            } else {
              navigate('/files');
            }
          } catch (err) {
            showError({
              title: 'Sign-in failed',
              description: err instanceof Error ? err.message : 'Authentication failed',
            });
            navigate('/login');
          }
        }
        break;
```

Update the `ParsedDeepLink` type:
```typescript
  action: 'invite' | 'share' | 'recovery' | 'file' | 'folder' | 'auth' | 'unknown';
```

- [ ] **Step 2: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/hooks/useDeepLink.ts && git commit -m "feat(desktop): add OIDC callback deep link handler for ssdid-drive://auth/callback"
```

### Task 13: App Routes for New Pages

**Files:**
- Modify: `clients/desktop/src/App.tsx`

- [ ] **Step 1: Add imports and routes**

Add imports:
```tsx
import { EmailLoginPage } from '@/pages/EmailLoginPage';
import { TotpSetupPage } from '@/pages/TotpSetupPage';
```

Add routes inside the `<Routes>` block, after the login route:
```tsx
        <Route
          path="/login/email"
          element={
            <PublicRoute>
              <EmailLoginPage />
            </PublicRoute>
          }
        />
        <Route
          path="/login/totp-setup"
          element={<TotpSetupPage />}
        />
```

Note: `/login/totp-setup` is NOT wrapped in `PublicRoute` because the user is already authenticated (with a `totp_setup_required` flag) — they need access to setup TOTP.

- [ ] **Step 2: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/App.tsx && git commit -m "feat(desktop): add routes for EmailLoginPage and TotpSetupPage"
```

### Task 14: Linked Logins Settings Section

**Files:**
- Create: `clients/desktop/src/components/settings/LinkedLoginsSection.tsx`
- Modify: `clients/desktop/src/pages/SettingsPage.tsx`

- [ ] **Step 1: Create LinkedLoginsSection**

```tsx
// clients/desktop/src/components/settings/LinkedLoginsSection.tsx
import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/Button';
import { tauriService, LinkedLogin } from '@/services/tauri';
import { Loader2, Trash2, Plus, Mail, Globe } from 'lucide-react';
import { useToast } from '@/hooks/useToast';

export function LinkedLoginsSection() {
  const [logins, setLogins] = useState<LinkedLogin[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { success, error: showError } = useToast();

  useEffect(() => {
    loadLogins();
  }, []);

  const loadLogins = async () => {
    setIsLoading(true);
    try {
      const result = await tauriService.listLogins();
      setLogins(result);
    } catch {
      // May not be implemented yet
    } finally {
      setIsLoading(false);
    }
  };

  const handleUnlink = async (login: LinkedLogin) => {
    if (logins.length <= 1) {
      showError({ title: 'Cannot remove', description: 'You must have at least one login method' });
      return;
    }
    try {
      await tauriService.unlinkLogin(login.id);
      success({ title: 'Login removed', description: `${login.provider} login has been removed` });
      await loadLogins();
    } catch (e) {
      showError({ title: 'Failed to remove login', description: String(e) });
    }
  };

  const handleAddOidc = async (provider: 'google' | 'microsoft') => {
    try {
      await tauriService.oidcLogin(provider);
      // Browser opens — linking continues via deep link callback
    } catch (e) {
      showError({ title: 'Failed to open browser', description: String(e) });
    }
  };

  const providerIcon = (provider: string) => {
    switch (provider.toLowerCase()) {
      case 'email':
        return <Mail className="h-5 w-5 text-muted-foreground" />;
      default:
        return <Globe className="h-5 w-5 text-muted-foreground" />;
    }
  };

  if (isLoading) {
    return (
      <div className="flex justify-center py-8">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {logins.map((login) => (
        <div key={login.id} className="flex items-center justify-between p-4 rounded-lg border">
          <div className="flex items-center gap-3">
            {providerIcon(login.provider)}
            <div>
              <p className="font-medium capitalize">{login.provider}</p>
              <p className="text-sm text-muted-foreground">
                {login.email || login.provider_subject}
              </p>
            </div>
          </div>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => handleUnlink(login)}
            disabled={logins.length <= 1}
            title={logins.length <= 1 ? 'Cannot remove last login method' : 'Remove login'}
          >
            <Trash2 className="h-4 w-4 text-muted-foreground" />
          </Button>
        </div>
      ))}

      <div className="flex gap-2 pt-2">
        <Button variant="outline" size="sm" onClick={() => handleAddOidc('google')}>
          <Plus className="h-4 w-4 mr-1" />
          Link Google
        </Button>
        <Button variant="outline" size="sm" onClick={() => handleAddOidc('microsoft')}>
          <Plus className="h-4 w-4 mr-1" />
          Link Microsoft
        </Button>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Add LinkedLoginsSection to SettingsPage**

Import and add after the Account section in `SettingsPage.tsx`:

```tsx
import { LinkedLoginsSection } from '@/components/settings/LinkedLoginsSection';
import { Link2 } from 'lucide-react';

// Add after the Account section (after <ProfileSection />):
      {/* Linked Logins */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold flex items-center gap-2">
          <Link2 className="h-5 w-5" />
          Linked Logins
        </h2>
        <LinkedLoginsSection />
      </div>
```

- [ ] **Step 3: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/components/settings/LinkedLoginsSection.tsx clients/desktop/src/pages/SettingsPage.tsx && git commit -m "feat(desktop): add Linked Logins settings section for managing login methods"
```

### Task 15: Update RegisterPage with Email Registration

**Files:**
- Modify: `clients/desktop/src/pages/RegisterPage.tsx`

- [ ] **Step 1: Replace RegisterPage with email-based registration**

The new RegisterPage has three steps: email+invitation code input, OTP verification, and redirect to onboarding. QR registration is collapsed under an advanced option.

```tsx
// clients/desktop/src/pages/RegisterPage.tsx
import { useState } from 'react';
import { useNavigate, Link, useSearchParams } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { OtpInput } from '@/components/auth/OtpInput';
import { OidcButtons } from '@/components/auth/OidcButtons';
import { QrChallenge } from '@/components/auth/QrChallenge';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/input';
import { Loader2, UserPlus, ChevronDown, ChevronUp } from 'lucide-react';

type Step = 'email' | 'otp';

export function RegisterPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const inviteToken = searchParams.get('invite') || '';

  const { sendOtp, verifyOtp, loginWithSession, loginWithOidc, isLoading, error, clearError } = useAuthStore();

  const [step, setStep] = useState<Step>('email');
  const [email, setEmail] = useState('');
  const [showQr, setShowQr] = useState(false);

  const handleEmailSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) return;
    try {
      await sendOtp(email.trim(), inviteToken || undefined);
      setStep('otp');
    } catch {
      // Error handled by store
    }
  };

  const handleOtpComplete = async (code: string) => {
    try {
      const result = await verifyOtp(email, code, inviteToken || undefined);
      if (result.totpSetupRequired) {
        navigate('/login/totp-setup');
      } else {
        navigate('/onboarding');
      }
    } catch {
      // Error handled by store
    }
  };

  const handleOidcRegister = async (provider: 'google' | 'microsoft') => {
    try {
      await loginWithOidc(provider);
      // Browser opens — registration continues via deep link callback
    } catch {
      // Error handled by store
    }
  };

  const handleQrAuthenticated = async (sessionToken: string) => {
    try {
      await loginWithSession(sessionToken);
      navigate('/onboarding');
    } catch {
      // Error handled by store
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        <div className="flex flex-col items-center mb-8">
          <div className="h-16 w-16 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
            <UserPlus className="h-8 w-8 text-primary" />
          </div>
          <h1 className="text-2xl font-bold">Create Account</h1>
          <p className="text-muted-foreground text-sm mt-1">
            {step === 'email' ? 'Register for SSDID Drive' : 'Enter the verification code sent to your email'}
          </p>
        </div>

        {error && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {error}
            <button onClick={clearError} className="ml-2 underline hover:no-underline">Dismiss</button>
          </div>
        )}

        {step === 'email' && (
          <>
            <form onSubmit={handleEmailSubmit} className="space-y-4">
              <Input
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={isLoading}
                autoFocus
              />
              {inviteToken && (
                <div className="text-sm text-muted-foreground bg-muted rounded-lg p-3">
                  Registering with invitation code
                </div>
              )}
              <Button type="submit" className="w-full" disabled={isLoading || !email.trim()}>
                {isLoading ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Sending code...</> : 'Send verification code'}
              </Button>
            </form>

            <div className="relative my-4">
              <div className="absolute inset-0 flex items-center"><span className="w-full border-t" /></div>
              <div className="relative flex justify-center text-xs uppercase">
                <span className="bg-card px-2 text-muted-foreground">or register with</span>
              </div>
            </div>

            <OidcButtons onProviderClick={handleOidcRegister} disabled={isLoading} />

            <div className="mt-4">
              <button
                onClick={() => setShowQr(!showQr)}
                className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground mx-auto"
              >
                {showQr ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                Register with SSDID Wallet
              </button>
              {showQr && (
                <div className="mt-4">
                  <QrChallenge action="register" onAuthenticated={handleQrAuthenticated} />
                </div>
              )}
            </div>
          </>
        )}

        {step === 'otp' && (
          <div className="space-y-6">
            <p className="text-sm text-muted-foreground text-center">
              Code sent to <strong>{email}</strong>
            </p>
            <OtpInput onComplete={handleOtpComplete} disabled={isLoading} error={error ?? undefined} />
            {isLoading && (
              <div className="flex justify-center">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            )}
            <button
              onClick={() => { setStep('email'); clearError(); }}
              className="text-sm text-muted-foreground hover:text-foreground mx-auto block"
            >
              Use a different email
            </button>
          </div>
        )}

        <div className="mt-6 text-center text-sm">
          <p className="text-muted-foreground">
            Already registered?{' '}
            <Link to="/login" className="text-primary hover:underline font-medium">Sign in</Link>
          </p>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add clients/desktop/src/pages/RegisterPage.tsx && git commit -m "feat(desktop): redesign RegisterPage with email OTP and OIDC registration"
```

### Task 16: Verify Rust Build

- [ ] **Step 1: Verify Rust builds**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && cargo check --manifest-path src-tauri/Cargo.toml
```

- [ ] **Step 2: Verify TypeScript builds**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx tsc --noEmit
```

- [ ] **Step 3: Run vitest**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth/clients/desktop && npx vitest run
```

- [ ] **Step 4: Fix any issues and commit**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/desktop-auth && git add -A && git commit -m "fix(desktop): resolve build issues from auth migration"
```
