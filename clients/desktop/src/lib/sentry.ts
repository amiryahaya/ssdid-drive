/**
 * Sentry configuration for SecureSharing Desktop
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

// Sentry instance - lazily loaded
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let Sentry: any = null;
let initialized = false;

/**
 * Load Sentry dynamically
 */
async function loadSentry() {
  if (Sentry !== null) return Sentry;

  try {
    Sentry = await import('@sentry/react');
    return Sentry;
  } catch {
    console.log('Sentry package not available, error tracking will be disabled');
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
    console.log('Sentry not available, error tracking disabled');
    return;
  }

  if (!SENTRY_DSN) {
    console.log('Sentry DSN not configured, error tracking disabled');
    return;
  }

  sentry.init({
    dsn: SENTRY_DSN,
    environment: ENVIRONMENT,
    release: `securesharing-desktop@${APP_VERSION}`,

    // Performance monitoring
    tracesSampleRate: ENVIRONMENT === 'production' ? 0.1 : 1.0,

    // Session replay (disabled for privacy)
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,

    // Filtering - using any type since Sentry types aren't available at compile time
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    beforeSend(event: any) {
      // Don't send events in development unless explicitly enabled
      if (ENVIRONMENT === 'development' && !import.meta.env.VITE_SENTRY_DEBUG) {
        console.log('Sentry event (dev mode, not sent):', event);
        return null;
      }

      // Filter out sensitive data
      if (event.request?.data) {
        const sensitiveFields = ['password', 'token', 'key', 'secret', 'credential'];
        const data = event.request.data as Record<string, unknown>;
        for (const field of sensitiveFields) {
          if (field in data) {
            data[field] = '[REDACTED]';
          }
        }
      }

      return event;
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

    // Additional integrations
    integrations: [
      sentry.browserTracingIntegration(),
      sentry.replayIntegration({
        maskAllText: true,
        blockAllMedia: true,
      }),
    ],
  });

  console.log(`Sentry initialized for ${ENVIRONMENT} environment`);
}

/**
 * Capture a custom error with additional context
 */
export function captureError(error: Error, context?: Record<string, unknown>) {
  if (!Sentry || Sentry === false) {
    console.error('Error:', error, context);
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
    console.log(`[${level}] ${message}`);
    return;
  }
  Sentry.captureMessage(message, level);
}

/**
 * Set user information for error tracking
 */
export function setUser(user: { id: string; email?: string; name?: string } | null) {
  if (!Sentry || Sentry === false) return;

  if (user) {
    Sentry.setUser({
      id: user.id,
      email: user.email,
      username: user.name,
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
    console.log(`[Breadcrumb:${category}] ${message}`, data);
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

