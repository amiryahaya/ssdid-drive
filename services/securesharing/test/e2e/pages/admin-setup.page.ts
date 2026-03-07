import { type Page, type Locator, expect } from '@playwright/test';

/**
 * Page Object Model for the Admin Setup page.
 *
 * One-time setup page for creating the first admin user.
 * Only accessible when no admin exists in the system.
 */
export class AdminSetupPage {
  readonly page: Page;
  readonly heading: Locator;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly passwordConfirmationInput: Locator;
  readonly setupTokenInput: Locator;
  readonly submitButton: Locator;
  readonly errorMessage: Locator;
  readonly fieldErrors: Locator;

  constructor(page: Page) {
    this.page = page;
    this.heading = page.locator('h1, [data-role="page-title"]');
    this.emailInput = page.locator('#admin_email, input[name="admin[email]"]');
    this.passwordInput = page.locator('#admin_password, input[name="admin[password]"]');
    this.passwordConfirmationInput = page.locator('#admin_password_confirmation, input[name="admin[password_confirmation]"]');
    this.setupTokenInput = page.locator('#admin_setup_token, input[name="admin[setup_token]"]');
    this.submitButton = page.locator('button[type="submit"]');
    this.errorMessage = page.locator('.bg-red-50, .text-red-800, [data-role="error-message"]');
    this.fieldErrors = page.locator('.text-red-600, .invalid-feedback, [data-role="field-error"]');
  }

  /**
   * Navigate to the admin setup page.
   */
  async goto() {
    await this.page.goto('/admin/setup');
    await this.page.waitForLoadState('domcontentloaded');
    // Wait for LiveView to connect
    await this.page.waitForSelector('form[phx-submit="create"]', { timeout: 10000 }).catch(() => {
      // Form might not use phx-submit, try waiting for any form
      return this.page.waitForSelector('form', { timeout: 5000 });
    });
    await this.page.waitForTimeout(500);
  }

  /**
   * Check if setup page is available (no admin exists).
   */
  async isSetupAvailable(): Promise<boolean> {
    try {
      await this.page.goto('/admin/setup');
      await this.page.waitForLoadState('domcontentloaded');
      // If redirected to login, setup is not available
      const url = this.page.url();
      return url.includes('/admin/setup');
    } catch {
      return false;
    }
  }

  /**
   * Fill in the setup form and submit.
   */
  async setupAdmin(email: string, password: string, passwordConfirmation?: string, setupToken?: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.passwordConfirmationInput.fill(passwordConfirmation ?? password);

    if (setupToken) {
      const tokenInputVisible = await this.setupTokenInput.isVisible().catch(() => false);
      if (tokenInputVisible) {
        await this.setupTokenInput.fill(setupToken);
      }
    }

    await this.submitButton.click();

    // Wait for either navigation to login or error message
    await Promise.race([
      this.page.waitForURL(/\/admin\/login/, { timeout: 15000 }),
      this.page.waitForSelector('.bg-red-50, .text-red-800, .text-red-600', { timeout: 15000 }),
    ]).catch(() => {
      // Timeout - might still be processing
    });
    await this.page.waitForTimeout(500);
  }

  /**
   * Assert that setup was successful (redirected to login).
   */
  async expectSetupSuccess() {
    await expect(this.page).toHaveURL(/\/admin\/login/);
  }

  /**
   * Assert that an error message is displayed.
   */
  async expectError(message?: string) {
    const hasError = await this.errorMessage.isVisible().catch(() => false) ||
                     await this.fieldErrors.first().isVisible().catch(() => false);
    expect(hasError).toBe(true);

    if (message) {
      const errorText = await this.page.locator('.bg-red-50, .text-red-800, .text-red-600').allTextContents();
      expect(errorText.join(' ')).toContain(message);
    }
  }

  /**
   * Assert that we're on the setup page.
   */
  async expectLoaded() {
    await expect(this.page).toHaveURL(/\/admin\/setup/);
    await expect(this.emailInput).toBeVisible({ timeout: 10000 });
  }
}
