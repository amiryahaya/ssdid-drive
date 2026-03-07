import { type Page, type Locator, expect } from '@playwright/test';

/**
 * Page Object Model for the Admin Tenants management page.
 *
 * Handles tenant listing, creation, and management operations.
 */
export class AdminTenantsPage {
  readonly page: Page;
  readonly heading: Locator;
  readonly tenantsTable: Locator;
  readonly tenantRows: Locator;
  readonly createButton: Locator;
  readonly searchInput: Locator;
  readonly pagination: Locator;

  constructor(page: Page) {
    this.page = page;
    // Target main content heading to avoid matching nav h1
    this.heading = page.locator('main h1, [role="main"] h1').first();
    this.tenantsTable = page.locator('table, [data-role="tenants-table"]');
    this.tenantRows = page.locator('tbody tr, [data-role="tenant-row"]');
    this.createButton = page.locator('a:has-text("New Tenant"), button:has-text("New Tenant"), a:has-text("Create"), button:has-text("Create")');
    this.searchInput = page.locator('input[name="search"], input[placeholder*="Search"]');
    this.pagination = page.locator('[data-role="pagination"], nav[aria-label="Pagination"]');
  }

  /**
   * Navigate to the tenants page.
   */
  async goto() {
    await this.page.goto('/admin/tenants');
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Assert that we're on the tenants page.
   */
  async expectLoaded() {
    await expect(this.page).toHaveURL(/\/admin\/tenants/);
    await expect(this.heading).toBeVisible();
  }

  /**
   * Get the number of tenant rows displayed.
   */
  async getTenantCount(): Promise<number> {
    return this.tenantRows.count();
  }

  /**
   * Search for a tenant.
   */
  async search(query: string) {
    await this.searchInput.fill(query);
    // Wait for LiveView to update
    await this.page.waitForTimeout(500);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Click on a tenant row to view details.
   */
  async viewTenant(tenantName: string) {
    const row = this.page.locator(`tr:has-text("${tenantName}"), [data-role="tenant-row"]:has-text("${tenantName}")`);
    await row.locator('a:has-text("View"), a:has-text("Show")').click();
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Click the create tenant button.
   */
  async clickCreate() {
    await this.createButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Assert that a tenant is in the list.
   */
  async expectTenantInList(tenantName: string) {
    const row = this.page.locator(`tr:has-text("${tenantName}"), [data-role="tenant-row"]:has-text("${tenantName}")`);
    await expect(row).toBeVisible();
  }
}
