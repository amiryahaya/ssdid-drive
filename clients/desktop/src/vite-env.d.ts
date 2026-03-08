/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SENTRY_DSN: string;
  readonly VITE_APP_VERSION: string;
  readonly VITE_SENTRY_DEBUG: string;
  readonly VITE_ONESIGNAL_APP_ID: string;
  readonly VITE_ONESIGNAL_SAFARI_WEB_ID: string;
  readonly MODE: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
