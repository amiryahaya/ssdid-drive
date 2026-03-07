import { type Page, type Locator, expect } from '@playwright/test';

/**
 * Page Object Model for the Admin Users management page.
 *
 * Handles user listing, search, and management operations.
 */
export class AdminUsersPage {
  readonly page: Page;
  readonly heading: Locator;
  readonly usersTable: Locator;
  readonly userRows: Locator;
  readonly searchInput: Locator;
  readonly tenantFilter: Locator;
  readonly statusFilter: Locator;
  readonly pagination: Locator;

  constructor(page: Page) {
    this.page = page;
    // Target main content heading to avoid matching nav h1
    this.heading = page.locator('main h1, [role="main"] h1').first();
    this.usersTable = page.locator('table, [data-role="users-table"]');
    this.userRows = page.locator('tbody tr, [data-role="user-row"]');
    this.searchInput = page.locator('input[name="search"], input[placeholder*="Search"]');
    this.tenantFilter = page.locator('select[name="tenant"], [data-role="tenant-filter"]');
    this.statusFilter = page.locator('select[name="status"], [data-role="status-filter"]');
    this.pagination = page.locator('[data-role="pagination"], nav[aria-label="Pagination"]');
  }

  /**
   * Navigate to the users page.
   */
  async goto() {
    await this.page.goto('/admin/users');
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Assert that we're on the users page.
   */
  async expectLoaded() {
    await expect(this.page).toHaveURL(/\/admin\/users/);
    await expect(this.heading).toBeVisible();
  }

  /**
   * Get the number of user rows displayed.
   */
  async getUserCount(): Promise<number> {
    return this.userRows.count();
  }

  /**
   * Search for a user.
   */
  async search(query: string) {
    await this.searchInput.fill(query);
    // Wait for LiveView to update
    await this.page.waitForTimeout(500);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Filter by tenant.
   */
  async filterByTenant(tenantName: string) {
    await this.tenantFilter.selectOption({ label: tenantName });
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Click on a user row to view details.
   */
  async viewUser(email: string) {
    const row = this.page.locator(`tr:has-text("${email}"), [data-role="user-row"]:has-text("${email}")`);
    await row.locator('a:has-text("View"), a:has-text("Show")').click();
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Assert that a user is in the list.
   */
  async expectUserInList(email: string) {
    const row = this.page.locator(`tr:has-text("${email}"), [data-role="user-row"]:has-text("${email}")`);
    await expect(row).toBeVisible();
  }

  /**
   * Assert that the list is empty.
   */
  async expectEmptyList() {
    const emptyState = this.page.locator('[data-role="empty-state"], .empty-state, :text("No users found")');
    await expect(emptyState).toBeVisible();
  }
}
