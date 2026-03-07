# E2E Test Metrics and Coverage

This document tracks end-to-end test coverage, quality metrics, and execution guidelines for the SecureSharing platform.

## Test Distribution Summary

### By Platform

| Platform | Test Count | Priority Breakdown | Status |
|----------|------------|-------------------|--------|
| Backend API (Playwright) | 20 | P0: 13, P1: 5, P2: 2 | Active |
| iOS XCUITest | 15 | P0: 8, P1: 4, P2: 3 | Active |
| Android Compose | 15 | P0: 8, P1: 4, P2: 3 | Active |
| API Contract Tests | 50 | P0: 35, P1: 10, P2: 5 | Active |
| PII Service | 30 | P0: 15, P1: 10, P2: 5 | Active |
| **Total** | **130** | **P0: 79, P1: 33, P2: 18** | - |

### By Category

| Category | Backend | iOS | Android | API | PII | Total |
|----------|---------|-----|---------|-----|-----|-------|
| Authentication | 5 | 5 | 4 | 10 | - | 24 |
| File Operations | 6 | 6 | 4 | 15 | - | 31 |
| Sharing | 4 | 4 | 4 | 10 | - | 22 |
| Invitations | 3 | - | - | 10 | - | 13 |
| PII Detection | - | - | - | - | 15 | 15 |
| Tokenization | - | - | - | - | 8 | 8 |
| Settings/Profile | - | 2 | 2 | 3 | - | 7 |
| Offline/Error | 2 | 3 | 3 | 2 | - | 10 |
| **Total** | **20** | **20** | **17** | **50** | **23** | **130** |

---

## Quality Targets

### Pass Rate

| Metric | Target | Critical Threshold |
|--------|--------|-------------------|
| Overall Pass Rate | >= 95% | >= 90% |
| P0 Tests Pass Rate | >= 99% | >= 95% |
| P1 Tests Pass Rate | >= 95% | >= 90% |
| P2 Tests Pass Rate | >= 90% | >= 85% |

### Flaky Test Threshold

| Metric | Target | Action Required |
|--------|--------|-----------------|
| Flaky Test Rate | < 5% | Investigate if > 3% |
| Max Consecutive Failures | 2 | Mark as flaky after 3 |
| Quarantine Duration | 7 days max | Fix or remove |

### Execution Time Limits

| Test Category | Timeout | Max Suite Duration |
|---------------|---------|-------------------|
| API Contract Tests | 10s | 5 min |
| Auth Tests | 45s | 3 min |
| File Operations | 90s | 10 min |
| Sharing Tests | 60s | 5 min |
| PII Service Tests | 120s | 15 min |
| Full Flow Integration | 180s | 20 min |
| iOS UI Tests | 60s | 15 min |
| Android UI Tests | 60s | 15 min |

---

## Test Priority Definitions

### P0 - Critical Path
- **Definition**: Core functionality that must work for the product to be usable
- **Examples**: Login, file upload/download, sharing files
- **SLA**: Must pass on every PR merge
- **Retry Policy**: Auto-retry 2x before failure

### P1 - Important
- **Definition**: Important features that impact user experience
- **Examples**: Search, notifications, settings persistence
- **SLA**: Must pass on release branches
- **Retry Policy**: Auto-retry 1x before failure

### P2 - Nice-to-Have
- **Definition**: Edge cases and enhanced functionality
- **Examples**: Offline mode, cross-browser tests, accessibility
- **SLA**: Tracked but non-blocking
- **Retry Policy**: No auto-retry

---

## Run Instructions

### Prerequisites

```bash
# Install Podman (macOS)
brew install podman podman-compose

# Initialize Podman machine
podman machine init --cpus 4 --memory 8192
podman machine start

# Verify installation
podman info
```

### Backend & API Tests

```bash
# Start services
./scripts/e2e/podman-setup.sh
podman-compose -f podman-compose.e2e.yml up -d
./scripts/e2e/wait-for-services.sh

# Run all tests
cd services/securesharing/test/e2e
npm ci
npx playwright test

# Run by category
npx playwright test --project=auth
npx playwright test --project=files
npx playwright test --project=sharing
npx playwright test --project=api-contracts
npx playwright test --project=pii

# Run P0 tests only
npx playwright test --grep "@P0"

# Generate HTML report
npx playwright show-report
```

### iOS UI Tests

```bash
cd clients/ios/SecureSharing

# Generate Xcode project (if using XcodeGen)
xcodegen generate

# Run all UI tests
xcodebuild test \
  -scheme SecureSharingUITests \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -resultBundlePath ./test-results

# Run specific test class
xcodebuild test \
  -scheme SecureSharingUITests \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:SecureSharingUITests/AuthUITests
```

### Android UI Tests

```bash
cd clients/android

# Run all E2E tests
./gradlew connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.e2e=true

# Run specific test class
./gradlew connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.securesharing.e2e.FullFlowUiE2eTest

# Generate test report
./gradlew jacocoTestReport
```

### PII Service Tests

```bash
# Ensure PII service is running
curl http://localhost:4001/health

# Run PII-specific tests
cd services/securesharing/test/e2e
ENABLE_PII_SERVICE_TESTS=1 npx playwright test --project=pii

# Run Elixir integration tests
cd services/pii_service
MIX_ENV=test mix test test/integration/
```

---

## CI/CD Integration

### GitHub Actions Workflow

Tests are automatically run via `.github/workflows/e2e-tests.yml`:

| Job | Trigger | Timeout |
|-----|---------|---------|
| backend-e2e | Every PR | 30 min |
| ios-e2e | Every PR | 45 min |
| android-e2e | Every PR | 45 min |
| api-integration | Every PR | 20 min |
| pii-service-e2e | Every PR | 30 min |

### Test Reports

| Report Type | Location | Purpose |
|-------------|----------|---------|
| HTML Report | `playwright-report/` | Visual test results |
| JSON Report | `test-results/results.json` | Programmatic access |
| JUnit XML | `test-results/junit.xml` | CI/CD integration |
| Screenshots | `test-results/` | Failure debugging |

### Artifacts Retention

| Artifact | Retention |
|----------|-----------|
| Test Reports | 30 days |
| Screenshots | 14 days |
| Videos | 7 days |
| Coverage Reports | 30 days |

---

## Test Data Management

### Seed Data

| Entity | Count | Purpose |
|--------|-------|---------|
| Test Tenant | 1 | "E2E Test Organization" (slug: e2e-test) |
| Admin User | 1 | admin@securesharing.test |
| Test Users | 5 | user1@e2e-test.local - user5@e2e-test.local |
| Test Folders | 3 | Documents, Images, Shared |

### Test Isolation

- Each test run creates unique email addresses using timestamps
- Tests clean up created resources after completion
- Database is reset between full test suite runs
- PII tokens are ephemeral and expire after 1 hour

---

## Monitoring and Alerts

### Metrics to Track

| Metric | Collection | Alert Threshold |
|--------|------------|-----------------|
| Test Pass Rate | Per run | < 90% |
| Test Duration | Per run | > 150% baseline |
| Flaky Test Count | Weekly | > 5% of total |
| New Test Failures | Per PR | Any P0 failure |

### Dashboard

Test metrics are visualized in:
- GitHub Actions Summary
- Playwright HTML Report
- CI/CD Pipeline Dashboard

---

## Troubleshooting

### Common Issues

**Services not starting:**
```bash
# Check Podman status
podman ps -a
podman logs <container_id>

# Restart services
podman-compose -f podman-compose.e2e.yml down
podman-compose -f podman-compose.e2e.yml up -d
```

**iOS tests failing to find elements:**
- Ensure accessibility identifiers are set in view controllers
- Check if app state matches expected (logged in/out)
- Increase wait timeouts for slower simulators

**Android tests timing out:**
- Check emulator health: `adb devices`
- Ensure backend URL is accessible from emulator
- Use `10.0.2.2` instead of `localhost` for emulator

**PII tests failing:**
- Verify GLiNER service is running
- Check LLM_PROVIDER environment variable
- Ensure test documents are in expected format

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-06 | Initial test metrics documentation |
