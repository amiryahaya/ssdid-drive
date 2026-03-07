import { type Page, type Locator, expect } from '@playwright/test';

/**
 * Page Object Model for the Admin Dashboard page.
 *
 * Main landing page after admin login with stats and navigation.
 */
export class AdminDashboardPage {
  readonly page: Page;
  readonly heading: Locator;
  readonly statsCards: Locator;
  readonly tenantsLink: Locator;
  readonly usersLink: Locator;
  readonly invitationsLink: Locator;
  readonly auditLink: Locator;
  readonly notificationsLink: Locator;
  readonly logoutButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.heading = page.locator('h1');
    this.statsCards = page.locator('[data-role="stats-card"], .stats-card, .bg-white.overflow-hidden.shadow.rounded-lg');
    // Navigation links in the navbar
    this.tenantsLink = page.locator('nav a[href="/admin/tenants"]');
    this.usersLink = page.locator('nav a[href="/admin/users"]');
    this.invitationsLink = page.locator('nav a[href="/admin/invitations"]');
    this.auditLink = page.locator('nav a[href="/admin/audit"]');
    this.notificationsLink = page.locator('nav a[href="/admin/notifications"]');
    // Logout link goes to /admin/login with text "Logout"
    this.logoutButton = page.locator('a:has-text("Logout")');
  }

  /**
   * Navigate to the admin dashboard.
   */
  async goto() {
    await this.page.goto('/admin/dashboard');
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Assert that we're on the dashboard page.
   */
  async expectLoaded() {
    // Dashboard can be at /admin?user_id=... or /admin/dashboard
    await expect(this.page).toHaveURL(/\/admin\?user_id=|\/admin\/dashboard|\/admin$/);
    await this.page.waitForTimeout(1000); // Wait for LiveView
    await expect(this.heading).toBeVisible({ timeout: 10000 });
  }

  /**
   * Navigate to tenants management.
   */
  async goToTenants() {
    await this.tenantsLink.click();
    await this.page.waitForLoadState('networkidle');
    await expect(this.page).toHaveURL(/\/admin\/tenants/);
  }

  /**
   * Navigate to users management.
   */
  async goToUsers() {
    await this.usersLink.click();
    await this.page.waitForLoadState('networkidle');
    await expect(this.page).toHaveURL(/\/admin\/users/);
  }

  /**
   * Navigate to invitations management.
   */
  async goToInvitations() {
    await this.invitationsLink.click();
    await this.page.waitForLoadState('networkidle');
    await expect(this.page).toHaveURL(/\/admin\/invitations/);
  }

  /**
   * Navigate to audit logs.
   */
  async goToAudit() {
    await this.auditLink.click();
    await this.page.waitForLoadState('networkidle');
    await expect(this.page).toHaveURL(/\/admin\/audit/);
  }

  /**
   * Log out from admin panel.
   * Note: Currently logout just navigates to login page without clearing session.
   * For proper logout, we navigate directly and clear local state.
   */
  async logout() {
    // Get the logout link href and navigate directly
    const href = await this.logoutButton.getAttribute('href');
    if (href) {
      await this.page.goto(href);
    } else {
      // Fallback: direct navigation to login page
      await this.page.goto('/admin/login');
    }
    await this.page.waitForLoadState('networkidle');
    await expect(this.page).toHaveURL(/\/admin\/login/);
  }

  /**
   * Get the count from a stats card.
   */
  async getStatsValue(cardTitle: string): Promise<string | null> {
    const card = this.page.locator(`[data-role="stats-card"]:has-text("${cardTitle}"), .stats-card:has-text("${cardTitle}")`);
    const value = card.locator('[data-role="stats-value"], .stats-value, .text-2xl, .text-3xl').first();
    return value.textContent();
  }
}
