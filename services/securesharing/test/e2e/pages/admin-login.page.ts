import { type Page, type Locator, expect } from '@playwright/test';

/**
 * Page Object Model for the Admin Login page.
 *
 * Handles authentication flows for admin panel access.
 */
export class AdminLoginPage {
  readonly page: Page;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly loginButton: Locator;
  readonly errorMessage: Locator;

  constructor(page: Page) {
    this.page = page;
    this.emailInput = page.locator('#email, input[name="user[email]"]');
    this.passwordInput = page.locator('#password, input[name="user[password]"]');
    this.loginButton = page.locator('button[type="submit"]');
    // Target only the error container, not nested elements
    this.errorMessage = page.locator('.bg-red-50').first();
  }

  /**
   * Navigate to the admin login page.
   */
  async goto() {
    await this.page.goto('/admin/login');
    await this.page.waitForLoadState('networkidle');
    // Wait for form to be visible - either LiveView or static form
    await this.emailInput.waitFor({ state: 'visible', timeout: 10000 });
  }

  /**
   * Fill in login credentials and submit.
   */
  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.loginButton.click();
    // Wait for LiveView to process the event and either navigate or show error
    await this.page.waitForTimeout(500);
    // Wait for either navigation or error message
    await Promise.race([
      this.page.waitForURL(/\/admin\/dashboard|\/admin\?user_id|\/admin$/, { timeout: 10000 }),
      this.page.waitForSelector('.bg-red-50', { state: 'attached', timeout: 10000 }),
    ]).catch(() => {
      // Timeout - might still be processing or on login page with no error
    });
    await this.page.waitForTimeout(500);
  }

  /**
   * Assert that an error message is displayed.
   */
  async expectError(message?: string) {
    await expect(this.errorMessage).toBeVisible();
    if (message) {
      await expect(this.errorMessage).toContainText(message);
    }
  }

  /**
   * Assert that we've been redirected to the dashboard after login.
   */
  async expectLoginSuccess() {
    // Login redirects to /admin?user_id=... or /admin/dashboard
    await expect(this.page).toHaveURL(/\/admin\?user_id=|\/admin\/dashboard|\/admin$/);
  }
}
