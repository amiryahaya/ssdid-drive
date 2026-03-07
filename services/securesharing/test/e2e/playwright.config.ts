import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for SecureSharing E2E tests.
 *
 * Organized into projects by test category for selective execution.
 * Supports multiple reporters for CI/CD integration.
 *
 * See https://playwright.dev/docs/test-configuration
 */

// Environment configuration
const isCI = !!process.env.CI;
const isPiiEnabled = process.env.ENABLE_PII_SERVICE_TESTS === '1';
const baseURL = process.env.BASE_URL || process.env.BACKEND_URL || 'http://localhost:4000';
const piiServiceURL = process.env.PII_SERVICE_URL || 'http://localhost:4001';

export default defineConfig({
  testDir: './tests',

  /* Run tests in files in parallel */
  fullyParallel: true,

  /* Fail the build on CI if you accidentally left test.only in the source code */
  forbidOnly: isCI,

  /* Retry on CI only */
  retries: isCI ? 2 : 0,

  /* Parallel workers - limit on CI for stability */
  workers: isCI ? 2 : undefined,

  /* Global timeout for each test */
  timeout: 60000,

  /* Expect timeout for assertions */
  expect: {
    timeout: 10000,
  },

  /* Reporter configuration for comprehensive reporting */
  reporter: [
    // Always show list output in terminal
    ['list'],

    // HTML report for local viewing
    ['html', {
      outputFolder: 'playwright-report',
      open: isCI ? 'never' : 'on-failure',
    }],

    // JSON report for programmatic access
    ['json', {
      outputFile: 'test-results/results.json',
    }],

    // JUnit report for CI/CD integration (Jenkins, GitLab, etc.)
    ['junit', {
      outputFile: 'test-results/junit.xml',
      embedAnnotationsAsProperties: true,
      embedAttachmentsAsProperty: 'testrun_evidence',
    }],

    // GitHub Actions annotations
    ...(isCI ? [['github'] as const] : []),
  ],

  /* Shared settings for all the projects below */
  use: {
    /* Base URL for the Phoenix server */
    baseURL,

    /* Collect trace when retrying the failed test */
    trace: 'on-first-retry',

    /* Screenshot on failure */
    screenshot: 'only-on-failure',

    /* Video recording on first retry */
    video: 'on-first-retry',

    /* Extra HTTP headers */
    extraHTTPHeaders: {
      'Accept': 'application/json',
    },

    /* Action timeout */
    actionTimeout: 15000,

    /* Navigation timeout */
    navigationTimeout: 30000,
  },

  /* Metadata for test reporting */
  metadata: {
    platform: process.platform,
    ci: isCI,
    piiServiceEnabled: isPiiEnabled,
    baseURL,
    piiServiceURL,
  },

  /* Configure projects by test category */
  projects: [
    // ============================================================================
    // API Contract Tests (P0 - highest priority)
    // ============================================================================
    {
      name: 'api-contracts',
      testDir: './tests/api-contracts',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
      },
      metadata: {
        priority: 'P0',
        category: 'api-contracts',
        description: 'API response structure and schema validation',
      },
    },

    // ============================================================================
    // Authentication Tests (P0)
    // ============================================================================
    {
      name: 'auth',
      testDir: './tests/auth',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
      },
      timeout: 45000, // Auth tests may need less time
      metadata: {
        priority: 'P0',
        category: 'auth',
        description: 'Authentication and authorization flows',
      },
    },

    // ============================================================================
    // File Operations Tests (P0)
    // ============================================================================
    {
      name: 'files',
      testDir: './tests/files',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
      },
      timeout: 90000, // File operations may take longer
      metadata: {
        priority: 'P0',
        category: 'files',
        description: 'File upload, download, and management',
      },
    },

    // ============================================================================
    // Sharing Tests (P0)
    // ============================================================================
    {
      name: 'sharing',
      testDir: './tests/sharing',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
      },
      metadata: {
        priority: 'P0',
        category: 'sharing',
        description: 'File and folder sharing workflows',
      },
    },

    // ============================================================================
    // Recovery Tests (P0)
    // ============================================================================
    {
      name: 'recovery',
      testDir: './tests/recovery',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
      },
      metadata: {
        priority: 'P0',
        category: 'recovery',
        description: 'Shamir Secret Sharing key recovery flows',
      },
    },

    // ============================================================================
    // Invitations Tests (P1)
    // ============================================================================
    {
      name: 'invitations',
      testDir: './tests/invitations',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
      },
      metadata: {
        priority: 'P1',
        category: 'invitations',
        description: 'User invitation workflows',
      },
    },

    // ============================================================================
    // PII Service Tests (P0 - when enabled)
    // ============================================================================
    {
      name: 'pii',
      testDir: './tests/pii',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
        baseURL: piiServiceURL,
      },
      timeout: 120000, // PII detection can be slow
      metadata: {
        priority: 'P0',
        category: 'pii',
        description: 'PII detection and redaction',
        requiresPiiService: true,
      },
    },

    // ============================================================================
    // Admin UI tests (browser-based)
    // ============================================================================
    {
      name: 'admin-chromium',
      testMatch: /admin.*\.spec\.ts$/,
      use: { ...devices['Desktop Chrome'] },
      metadata: {
        priority: 'P1',
        category: 'admin',
        description: 'Admin panel UI tests',
      },
    },
    {
      name: 'admin-firefox',
      testMatch: /admin.*\.spec\.ts$/,
      use: { ...devices['Desktop Firefox'] },
      metadata: {
        priority: 'P2',
        category: 'admin',
        description: 'Admin panel cross-browser (Firefox)',
      },
    },
    {
      name: 'admin-webkit',
      testMatch: /admin.*\.spec\.ts$/,
      use: { ...devices['Desktop Safari'] },
      metadata: {
        priority: 'P2',
        category: 'admin',
        description: 'Admin panel cross-browser (Safari)',
      },
    },

    // ============================================================================
    // Device Management Tests (P1)
    // ============================================================================
    {
      name: 'devices',
      testDir: './tests/devices',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
      },
      metadata: {
        priority: 'P1',
        category: 'devices',
        description: 'Device enrollment and management',
      },
    },

    // ============================================================================
    // WebSocket Tests (P1)
    // ============================================================================
    {
      name: 'websocket',
      testDir: './tests/websocket',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
      },
      metadata: {
        priority: 'P1',
        category: 'websocket',
        description: 'Real-time WebSocket channel tests',
      },
    },

    // ============================================================================
    // Security Tests (P1)
    // ============================================================================
    {
      name: 'security',
      testDir: './tests/security',
      use: {
        ...devices['Desktop Chrome'],
        headless: true,
      },
      timeout: 90000, // Rate limiting tests need time
      metadata: {
        priority: 'P1',
        category: 'security',
        description: 'Access control, rate limiting, crypto validation',
      },
    },

    // ============================================================================
    // Full flow integration tests
    // ============================================================================
    {
      name: 'full-flow',
      testMatch: /full-flow.*\.spec\.ts$/,
      use: { ...devices['Desktop Chrome'] },
      timeout: 180000, // Full flow tests need more time
      metadata: {
        priority: 'P0',
        category: 'integration',
        description: 'End-to-end integration flows',
      },
    },

    // ============================================================================
    // Default: all tests in Chromium
    // ============================================================================
    {
      name: 'chromium',
      testDir: './tests',
      use: { ...devices['Desktop Chrome'] },
      metadata: {
        priority: 'P1',
        category: 'all',
        description: 'All tests in Chromium',
      },
    },
  ],

  /* Output folder for test artifacts */
  outputDir: 'test-results/',

  /* Global setup/teardown */
  globalSetup: undefined, // Can add './global-setup.ts' if needed
  globalTeardown: undefined, // Can add './global-teardown.ts' if needed

  /* Run your local dev server before starting the tests */
  /* When running in Docker/CI, don't start a web server - it's handled externally */
  webServer: isCI ? undefined : {
    command: 'cd ../.. && MIX_ENV=dev mix phx.server',
    url: 'http://localhost:4000',
    reuseExistingServer: true,
    timeout: 120 * 1000,
  },
});
