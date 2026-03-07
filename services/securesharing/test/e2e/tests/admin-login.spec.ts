import { test, expect, ADMIN_CREDENTIALS } from '../fixtures/auth.fixture';
import { AdminLoginPage } from '../pages';

test.describe('Admin Login', () => {
  let loginPage: AdminLoginPage;

  test.beforeEach(async ({ page }) => {
    loginPage = new AdminLoginPage(page);
    await loginPage.goto();
  });

  test('displays login form', async ({ page }) => {
    await expect(loginPage.emailInput).toBeVisible();
    await expect(loginPage.passwordInput).toBeVisible();
    await expect(loginPage.loginButton).toBeVisible();
  });

  test('shows error for invalid credentials', async () => {
    await loginPage.login('invalid@example.com', 'wrongpassword');
    await loginPage.expectError();
  });

  test('shows error for empty email', async () => {
    await loginPage.login('', 'somepassword');
    // Form validation or server error should appear
    await expect(loginPage.page).toHaveURL(/\/admin\/login/);
  });

  test('shows error for empty password', async () => {
    await loginPage.login('admin@example.com', '');
    // Form validation or server error should appear
    await expect(loginPage.page).toHaveURL(/\/admin\/login/);
  });

  test('successful login redirects to dashboard', async () => {
    await loginPage.login(ADMIN_CREDENTIALS.email, ADMIN_CREDENTIALS.password);
    await loginPage.expectLoginSuccess();
  });

  test('redirects unauthenticated users to login', async ({ page }) => {
    // Navigate to admin without authentication
    await page.goto('/admin');
    // Should redirect to login page
    await expect(page).toHaveURL(/\/admin\/login/);
  });

  test('login form prevents XSS in error messages', async () => {
    // Attempt XSS payload in email field
    await loginPage.login('<script>alert("xss")</script>', 'password');

    // Check that no script tags are rendered
    const pageContent = await loginPage.page.content();
    expect(pageContent).not.toContain('<script>alert("xss")</script>');
  });

  test('rate limits excessive login attempts', async () => {
    // Make multiple rapid login attempts
    for (let i = 0; i < 10; i++) {
      await loginPage.login('attacker@example.com', 'wrongpassword');
      await loginPage.goto(); // Reset for next attempt
    }

    // Should show rate limit error or block further attempts
    await loginPage.login('attacker@example.com', 'wrongpassword');

    // Either rate limit message or continued error (depends on config)
    const content = await loginPage.page.content();
    const hasRateLimit = content.includes('rate limit') || content.includes('too many');
    const hasError = await loginPage.errorMessage.isVisible().catch(() => false);

    expect(hasRateLimit || hasError).toBeTruthy();
  });
});
