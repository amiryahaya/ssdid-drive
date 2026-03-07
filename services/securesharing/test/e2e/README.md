# SecureSharing E2E Tests

End-to-end tests for SecureSharing using Playwright.

## Test Suites

| Suite | Description | Command |
|-------|-------------|---------|
| Admin UI | Tests for admin panel (login, tenants, users) | `npm run test:admin` |
| Invitations | Invitation creation and acceptance flows | `npm run test:invitations` |
| Full Flow | Complete user journey with PII redaction | `npm run test:full-flow` |
| Full Stack | All services in Docker (backend + PII service) | `npm run test:full-stack` |

## Prerequisites

- Node.js 18+
- PostgreSQL with test database
- Elixir/Phoenix server

## Setup

1. Install dependencies:

```bash
cd test/e2e
npm install
npx playwright install
```

2. Seed the test database:

```bash
cd ../..
MIX_ENV=test mix ecto.reset
MIX_ENV=test mix run priv/repo/seeds/e2e_admin_seed.exs
```

## Running Tests

### Run all tests

```bash
npm test
```

### Run with UI

```bash
npm run test:ui
```

### Run in headed mode (see browser)

```bash
npm run test:headed
```

### Run in debug mode

```bash
npm run test:debug
```

### Generate test code

```bash
npm run codegen
```

## Test Structure

```
test/e2e/
├── fixtures/          # Test fixtures and helpers
│   └── auth.fixture.ts
├── pages/             # Page Object Models
│   ├── admin-login.page.ts
│   ├── admin-dashboard.page.ts
│   ├── admin-tenants.page.ts
│   ├── admin-users.page.ts
│   └── index.ts
├── tests/             # Test specifications
│   ├── admin-login.spec.ts
│   ├── admin-dashboard.spec.ts
│   ├── admin-tenants.spec.ts
│   └── admin-users.spec.ts
├── package.json
├── playwright.config.ts
└── tsconfig.json
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `http://localhost:4000` | Phoenix server URL |
| `E2E_ADMIN_EMAIL` | `admin@securesharing.test` | Admin login email |
| `E2E_ADMIN_PASSWORD` | `AdminTestPassword123!` | Admin login password |

### CI Configuration

Set `CI=true` to enable CI-specific behavior:
- Sequential test execution
- Retry failed tests twice
- Start server automatically

## Writing Tests

### Page Object Pattern

Tests use the Page Object Model pattern. Create a new page object in `pages/`:

```typescript
import { type Page, type Locator, expect } from '@playwright/test';

export class MyPage {
  readonly page: Page;
  readonly heading: Locator;

  constructor(page: Page) {
    this.page = page;
    this.heading = page.locator('h1');
  }

  async goto() {
    await this.page.goto('/my-page');
  }
}
```

### Using Fixtures

```typescript
import { test, expect, ADMIN_CREDENTIALS } from '../fixtures/auth.fixture';
import { AdminLoginPage } from '../pages';

test.describe('My Feature', () => {
  test('does something', async ({ page }) => {
    const loginPage = new AdminLoginPage(page);
    await loginPage.goto();
    await loginPage.login(ADMIN_CREDENTIALS.email, ADMIN_CREDENTIALS.password);
    // ...
  });
});
```

## Full Stack E2E Tests

The full stack tests run all services in Docker containers:

```
┌─────────────────────────────────────────────────────────────────┐
│                     E2E Test Environment                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  PostgreSQL  │  │    Garage    │  │  Playwright  │          │
│  │    :5432     │  │ (S3) :3900   │  │   Runner     │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                   │
│         └─────────────────┼─────────────────┘                   │
│                           │                                     │
│  ┌──────────────┐  ┌──────┴───────┐                             │
│  │   Backend    │  │ PII Service  │                             │
│  │    :4000     │  │    :4001     │                             │
│  └──────────────┘  └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

### Running Full Stack Tests

```bash
# Run all tests in Docker
npm run test:full-stack

# View logs during test run
npm run test:full-stack:logs

# Clean up after tests
npm run test:full-stack:down
```

### Test Flow: Invitation → Upload → Redact → Download

The `full-flow-pii-redaction.spec.ts` test simulates:

1. **Admin creates invitation** - POST `/api/tenant/invitations`
2. **User accepts invitation** - POST `/api/invite/:token/accept`
3. **User logs in** - POST `/api/auth/login`
4. **User uploads file** - POST `/api/files/upload-url` + PUT to S3
5. **PII detection** - POST `/api/v1/detect` (PII service)
6. **File redaction** - POST `/api/v1/files/:id/process`
7. **Download redacted** - GET `/api/v1/files/:id/download`

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_URL` | `http://localhost:4000` | SecureSharing backend URL |
| `PII_SERVICE_URL` | `http://localhost:4001` | PII service URL |
| `ENABLE_FILE_UPLOAD_TESTS` | `false` | Enable file upload tests |
| `ENABLE_PII_SERVICE_TESTS` | `false` | Enable PII service tests |

## Debugging

### View test report

```bash
npm run test:report
```

### Debug specific test

```bash
npx playwright test -g "test name" --debug
```

### Trace viewer

Failed tests generate traces automatically. View them:

```bash
npx playwright show-trace trace.zip
```
