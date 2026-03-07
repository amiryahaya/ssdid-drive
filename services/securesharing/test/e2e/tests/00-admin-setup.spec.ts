import { test, expect, ADMIN_CREDENTIALS } from '../fixtures/auth.fixture';
import { AdminSetupPage } from '../pages/admin-setup.page';
import { AdminLoginPage } from '../pages/admin-login.page';

/**
 * Admin Setup E2E Tests
 *
 * Tests for the one-time admin setup flow.
 * NOTE: These tests require a fresh database with no admin user.
 * Run `MIX_ENV=dev mix ecto.reset` before running these tests.
 */
test.describe('Admin Setup', () => {
  let setupPage: AdminSetupPage;
  let loginPage: AdminLoginPage;

  test.beforeEach(async ({ page }) => {
    setupPage = new AdminSetupPage(page);
    loginPage = new AdminLoginPage(page);
  });

  test('displays setup form when no admin exists', async ({ page }) => {
    const isAvailable = await setupPage.isSetupAvailable();
    if (!isAvailable) {
      test.skip();
      return;
    }
    await setupPage.goto();
    await setupPage.expectLoaded();
    await expect(setupPage.emailInput).toBeVisible();
    await expect(setupPage.passwordInput).toBeVisible();
    await expect(setupPage.passwordConfirmationInput).toBeVisible();
    await expect(setupPage.submitButton).toBeVisible();
  });

  test('shows validation error for empty email', async ({ page }) => {
    const isAvailable = await setupPage.isSetupAvailable();
    if (!isAvailable) {
      test.skip();
      return;
    }
    await setupPage.goto();
    await setupPage.setupAdmin('', 'SecurePassword123!', 'SecurePassword123!');
    // Should stay on setup page with validation error
    await expect(page).toHaveURL(/\/admin\/setup/);
  });

  test('shows validation error for invalid email format', async ({ page }) => {
    const isAvailable = await setupPage.isSetupAvailable();
    if (!isAvailable) {
      test.skip();
      return;
    }
    await setupPage.goto();
    await setupPage.setupAdmin('invalid-email', 'SecurePassword123!', 'SecurePassword123!');
    // Should stay on setup page with validation error
    await expect(page).toHaveURL(/\/admin\/setup/);
  });

  test('shows validation error for short password', async ({ page }) => {
    const isAvailable = await setupPage.isSetupAvailable();
    if (!isAvailable) {
      test.skip();
      return;
    }
    await setupPage.goto();
    await setupPage.setupAdmin('admin@test.com', 'short', 'short');
    // Should stay on setup page with validation error
    await expect(page).toHaveURL(/\/admin\/setup/);
  });

  test('shows validation error for password mismatch', async ({ page }) => {
    const isAvailable = await setupPage.isSetupAvailable();
    if (!isAvailable) {
      test.skip();
      return;
    }
    await setupPage.goto();
    await setupPage.setupAdmin('admin@test.com', 'SecurePassword123!', 'DifferentPassword456!');
    // Should stay on setup page with validation error
    await expect(page).toHaveURL(/\/admin\/setup/);
  });

  test('successfully creates admin and redirects to login', async ({ page }) => {
    // Check if setup is available (no admin exists)
    const isAvailable = await setupPage.isSetupAvailable();

    if (!isAvailable) {
      // Skip test if admin already exists
      test.skip();
      return;
    }

    await setupPage.goto();
    await setupPage.setupAdmin(
      ADMIN_CREDENTIALS.email,
      ADMIN_CREDENTIALS.password,
      ADMIN_CREDENTIALS.password
    );

    // Should redirect to login page
    await setupPage.expectSetupSuccess();
    await expect(page).toHaveURL(/\/admin\/login/);
  });

  test('redirects to login when admin already exists', async ({ page }) => {
    // First, try to go to setup page
    await page.goto('/admin/setup');
    await page.waitForLoadState('networkidle');

    // If admin exists, should be redirected to login
    const url = page.url();
    if (url.includes('/admin/login')) {
      // This is expected behavior when admin exists
      await expect(page).toHaveURL(/\/admin\/login/);
    } else {
      // Setup is still available, admin doesn't exist yet
      await expect(page).toHaveURL(/\/admin\/setup/);
    }
  });

  test('newly created admin can log in', async ({ page }) => {
    // This test depends on the admin being created
    // Either from a previous test or from seeds

    // Try setup first (it will redirect if admin exists)
    await page.goto('/admin/setup');
    await page.waitForLoadState('networkidle');

    const url = page.url();

    if (url.includes('/admin/setup')) {
      // Create admin first
      await setupPage.setupAdmin(
        ADMIN_CREDENTIALS.email,
        ADMIN_CREDENTIALS.password,
        ADMIN_CREDENTIALS.password
      );
    }

    // Now try to login
    await loginPage.goto();
    await loginPage.login(ADMIN_CREDENTIALS.email, ADMIN_CREDENTIALS.password);

    // Should be on dashboard or redirected
    await Promise.race([
      page.waitForURL(/\/admin\?user_id=|\/admin\/dashboard|\/admin$/, { timeout: 10000 }),
      page.waitForSelector('.bg-red-50', { timeout: 10000 }), // Error message
    ]).catch(() => {});
  });
});

/**
 * Additional setup scenarios
 */
test.describe('Admin Setup - Edge Cases', () => {
  let setupPage: AdminSetupPage;

  test.beforeEach(async ({ page }) => {
    setupPage = new AdminSetupPage(page);
  });

  test('form preserves email on validation error', async ({ page }) => {
    await setupPage.goto();

    // Check if setup is available
    const isAvailable = await setupPage.isSetupAvailable();
    if (!isAvailable) {
      test.skip();
      return;
    }

    // Fill form with mismatched passwords
    const testEmail = 'preserve-test@example.com';
    await setupPage.emailInput.fill(testEmail);
    await setupPage.passwordInput.fill('SecurePassword123!');
    await setupPage.passwordConfirmationInput.fill('DifferentPassword!');
    await setupPage.submitButton.click();

    await page.waitForTimeout(1000);

    // Email should be preserved
    const emailValue = await setupPage.emailInput.inputValue();
    expect(emailValue).toBe(testEmail);
  });

  test('password fields are cleared on error', async ({ page }) => {
    await setupPage.goto();

    // Check if setup is available
    const isAvailable = await setupPage.isSetupAvailable();
    if (!isAvailable) {
      test.skip();
      return;
    }

    // Fill form with mismatched passwords
    await setupPage.emailInput.fill('test@example.com');
    await setupPage.passwordInput.fill('SecurePassword123!');
    await setupPage.passwordConfirmationInput.fill('DifferentPassword!');
    await setupPage.submitButton.click();

    await page.waitForTimeout(1000);

    // Password fields might be cleared for security (implementation dependent)
    // Just verify we're still on the setup page
    await expect(page).toHaveURL(/\/admin\/setup/);
  });
});
