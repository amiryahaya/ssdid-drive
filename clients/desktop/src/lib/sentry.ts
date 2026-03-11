/**
 * Sentry configuration for SSDID Drive Desktop
 *
 * IMPORTANT: Replace SENTRY_DSN with your actual Sentry DSN from
 * https://sentry.io/settings/[org]/projects/[project]/keys/
 *
 * This module provides a safe wrapper around Sentry that gracefully handles
 * the case when the @sentry/react package is not installed.
 */

const SENTRY_DSN = import.meta.env.VITE_SENTRY_DSN || '';
const APP_VERSION = import.meta.env.VITE_APP_VERSION || '1.0.0';
const ENVIRONMENT = import.meta.env.MODE || 'development';

export type SeverityLevel = 'fatal' | 'error' | 'warning' | 'log' | 'info' | 'debug';

/**
 * Regex patterns for sensitive field names.
 * Matches both snake_case and camelCase variants.
 */
const SENSITIVE_FIELD_PATTERNS: RegExp[] = [
  /password/i,
  /token/i,
  /key/i,
  /secret/i,
  /credential/i,
  /folder_key/i,
  /folderKey/i,
  /file_key/i,
  /fileKey/i,
  /subscriber_secret/i,
  /subscriberSecret/i,
  /kem/i,
  /kemCiphertext/i,
  /wrapped_folder_key/i,
  /wrappedFolderKey/i,
  /bearer/i,
  /authorization/i,
  /did/i,
  /challenge/i,
  /nonce/i,
  /seed/i,
  /mnemonic/i,
  /private/i,
  /encrypted/i,
];

/**
 * Check if a field name matches any sensitive pattern
 */
function isSensitiveField(fieldName: string): boolean {
  return SENSITIVE_FIELD_PATTERNS.some((pattern) => pattern.test(fieldName));
}

/**
 * Recursively scrub sensitive fields from an object
 */
function scrubObject(obj: unknown): unknown {
  if (obj === null || obj === undefined) return obj;
  if (typeof obj !== 'object') return obj;

  if (Array.isArray(obj)) {
    return obj.map(scrubObject);
  }

  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
    if (isSensitiveField(key)) {
      result[key] = '[REDACTED]';
    } else if (typeof value === 'object' && value !== null) {
      result[key] = scrubObject(value);
    } else {
      result[key] = value;
    }
  }
  return result;
}

/**
 * Strip query parameters from a URL string
 */
function stripQueryParams(url: string): string {
  try {
    const parsed = new URL(url);
    parsed.search = '';
    return parsed.toString();
  } catch {
    // If URL parsing fails, strip anything after '?'
    const idx = url.indexOf('?');
    return idx >= 0 ? url.substring(0, idx) : url;
  }
}

// Sentry instance - lazily loaded
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let Sentry: any = null;
let initialized = false;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let loadPromise: Promise<any> | null = null;

/**
 * Load Sentry dynamically.
 * Uses a shared promise to prevent concurrent imports.
 */
async function loadSentry() {
  if (Sentry !== null) return Sentry;
  if (loadPromise) return loadPromise;

  try {
    loadPromise = import('@sentry/react');
    Sentry = await loadPromise;
    return Sentry;
  } catch {
    Sentry = false; // Mark as attempted but failed
    return null;
  }
}

/**
 * Initialize Sentry error tracking
 */
export async function initSentry() {
  if (initialized) return;
  initialized = true;

  const sentry = await loadSentry();

  if (!sentry || sentry === false) {
    return;
  }

  if (!SENTRY_DSN) {
    return;
  }

  sentry.init({
    dsn: SENTRY_DSN,
    environment: ENVIRONMENT,
    release: `ssdid-drive-desktop@${APP_VERSION}`,

    // Performance monitoring - reduced sample rate for non-production
    tracesSampleRate: ENVIRONMENT === 'production' ? 0.1 : 0.1,

    // Filtering - using any type since Sentry types aren't available at compile time
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    beforeSend(event: any) {
      // Don't send events in development unless explicitly enabled
      if (ENVIRONMENT === 'development' && !import.meta.env.VITE_SENTRY_DEBUG) {
        return null;
      }

      // Scrub event.request.data
      if (event.request?.data) {
        event.request.data = scrubObject(event.request.data);
      }

      // Scrub event.extra
      if (event.extra) {
        event.extra = scrubObject(event.extra);
      }

      // Scrub custom contexts (preserve standard ones like browser, os, device)
      if (event.contexts) {
        const standardContexts = new Set([
          'browser', 'os', 'device', 'runtime', 'app', 'trace', 'otel',
        ]);
        for (const key of Object.keys(event.contexts)) {
          if (!standardContexts.has(key)) {
            event.contexts[key] = scrubObject(event.contexts[key]);
          }
        }
      }

      // Strip PII from user — only keep opaque id
      if (event.user) {
        event.user = { id: event.user.id };
      }

      return event;
    },

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    beforeBreadcrumb(breadcrumb: any) {
      // Drop console breadcrumbs entirely — they may contain crypto data
      if (breadcrumb.category === 'console') {
        return null;
      }

      // Strip query params from navigation/fetch/xhr URLs
      if (breadcrumb.data?.url && typeof breadcrumb.data.url === 'string') {
        breadcrumb.data.url = stripQueryParams(breadcrumb.data.url);
      }
      if (breadcrumb.data?.from && typeof breadcrumb.data.from === 'string') {
        breadcrumb.data.from = stripQueryParams(breadcrumb.data.from);
      }
      if (breadcrumb.data?.to && typeof breadcrumb.data.to === 'string') {
        breadcrumb.data.to = stripQueryParams(breadcrumb.data.to);
      }

      // Scrub fetch/XHR request/response body data
      if (breadcrumb.category === 'fetch' || breadcrumb.category === 'xhr') {
        if (breadcrumb.data?.body) {
          breadcrumb.data.body = '[REDACTED]';
        }
        if (breadcrumb.data?.request_body) {
          breadcrumb.data.request_body = '[REDACTED]';
        }
        if (breadcrumb.data?.response_body) {
          breadcrumb.data.response_body = '[REDACTED]';
        }
      }

      return breadcrumb;
    },

    // Ignore certain errors
    ignoreErrors: [
      'Network request failed',
      'Failed to fetch',
      'Load failed',
      'AbortError',
      /^chrome-extension:\/\//,
      /^moz-extension:\/\//,
    ],

    // Additional integrations — no replay integration for privacy
    integrations: [
      sentry.browserTracingIntegration(),
    ],
  });
}

/**
 * Capture a custom error with additional context
 */
export function captureError(error: Error, context?: Record<string, unknown>) {
  if (!Sentry || Sentry === false) {
    if (import.meta.env.DEV) {
      console.error('Error:', error, context);
    }
    return;
  }
  Sentry.captureException(error, {
    extra: context,
  });
}

/**
 * Capture a custom message
 */
export function captureMessage(message: string, level: SeverityLevel = 'info') {
  if (!Sentry || Sentry === false) {
    if (import.meta.env.DEV) {
      console.log(`[${level}] ${message}`);
    }
    return;
  }
  Sentry.captureMessage(message, level);
}

/**
 * Set user information for error tracking.
 * Only sends opaque user ID — no PII (email, name).
 */
export function setUser(user: { id: string; email?: string; name?: string } | null) {
  if (!Sentry || Sentry === false) return;

  if (user) {
    Sentry.setUser({
      id: user.id,
    });
  } else {
    Sentry.setUser(null);
  }
}

/**
 * Add a breadcrumb for debugging
 */
export function addBreadcrumb(
  category: string,
  message: string,
  level: SeverityLevel = 'info',
  data?: Record<string, unknown>
) {
  if (!Sentry || Sentry === false) {
    return;
  }
  Sentry.addBreadcrumb({
    category,
    message,
    level,
    data,
  });
}

/**
 * Set additional context tags
 */
export function setTag(key: string, value: string) {
  if (!Sentry || Sentry === false) return;
  Sentry.setTag(key, value);
}

/**
 * Set extra context data
 */
export function setExtra(key: string, value: unknown) {
  if (!Sentry || Sentry === false) return;
  Sentry.setExtra(key, value);
}

/**
 * Get Sentry's ErrorBoundary component (if available)
 */
export function getSentryErrorBoundary() {
  if (!Sentry || Sentry === false) return null;
  return Sentry.ErrorBoundary;
}
