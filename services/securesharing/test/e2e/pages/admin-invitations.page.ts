import { type Page, type Locator, expect } from '@playwright/test';

/**
 * Page Object Model for the Admin Invitations management page.
 *
 * Handles invitation listing, creation, and management operations.
 */
export class AdminInvitationsPage {
  readonly page: Page;
  readonly heading: Locator;
  readonly invitationsTable: Locator;
  readonly invitationRows: Locator;
  readonly newInvitationButton: Locator;
  readonly statusFilter: Locator;

  // Modal form elements
  readonly modal: Locator;
  readonly tenantSelect: Locator;
  readonly emailInput: Locator;
  readonly roleSelect: Locator;
  readonly messageInput: Locator;
  readonly submitButton: Locator;
  readonly cancelButton: Locator;
  readonly formError: Locator;

  constructor(page: Page) {
    this.page = page;
    // Target main content heading to avoid matching nav h1
    this.heading = page.locator('main h1, [role="main"] h1').first();
    this.invitationsTable = page.locator('table');
    this.invitationRows = page.locator('tbody tr');
    this.newInvitationButton = page.locator('button:has-text("New Invitation")');
    this.statusFilter = page.locator('select[name="status"]');

    // Modal elements - field names use as: :invitation wrapper
    this.modal = page.locator('#invitation-modal');
    this.tenantSelect = page.locator('#invitation-modal select[name="invitation[tenant_id]"]');
    this.emailInput = page.locator('#invitation-modal input[name="invitation[email]"]');
    this.roleSelect = page.locator('#invitation-modal select[name="invitation[role]"]');
    this.messageInput = page.locator('#invitation-modal textarea[name="invitation[message]"]');
    this.submitButton = page.locator('#invitation-modal button:has-text("Send Invitation")');
    this.cancelButton = page.locator('#invitation-modal button:has-text("Cancel")');
    this.formError = page.locator('#invitation-modal div.bg-red-50 p');
  }

  /**
   * Navigate to the invitations page.
   */
  async goto() {
    await this.page.goto('/admin/invitations');
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Assert that we're on the invitations page.
   */
  async expectLoaded() {
    await expect(this.page).toHaveURL(/\/admin\/invitations/);
    await expect(this.heading).toBeVisible();
  }

  /**
   * Get the number of invitation rows displayed.
   */
  async getInvitationCount(): Promise<number> {
    return this.invitationRows.count();
  }

  /**
   * Filter invitations by status.
   */
  async filterByStatus(status: 'all' | 'pending' | 'accepted' | 'expired' | 'revoked') {
    const value = status === 'all' ? '' : status;
    await this.statusFilter.selectOption(value);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Open the new invitation modal.
   */
  async openNewInvitationForm() {
    await this.newInvitationButton.click();
    // Wait for LiveView to process and render the modal
    await this.page.waitForTimeout(1000);
    // Wait for modal to be rendered (even if hidden initially)
    await this.page.waitForSelector('#invitation-modal', { state: 'attached', timeout: 5000 });
    // Wait for form elements to be visible
    await expect(this.emailInput).toBeVisible({ timeout: 10000 });
  }

  /**
   * Close the invitation modal.
   */
  async closeModal() {
    await this.cancelButton.click();
    await this.page.waitForTimeout(300); // Wait for animation
    await expect(this.tenantSelect).not.toBeVisible({ timeout: 5000 });
  }

  /**
   * Create a new invitation.
   */
  async createInvitation(options: {
    tenantName: string;
    email: string;
    role?: 'member' | 'admin' | 'manager';
    message?: string;
  }) {
    await this.openNewInvitationForm();

    // Select tenant by label
    await this.tenantSelect.selectOption({ label: options.tenantName });

    // Fill email
    await this.emailInput.fill(options.email);

    // Select role if provided
    if (options.role) {
      const roleLabel = options.role.charAt(0).toUpperCase() + options.role.slice(1);
      await this.roleSelect.selectOption({ label: roleLabel });
    }

    // Fill message if provided
    if (options.message) {
      await this.messageInput.fill(options.message);
    }

    // Submit the form
    await this.submitButton.click();

    // Wait for response
    await this.page.waitForTimeout(500);
  }

  /**
   * Check if form error is displayed.
   */
  async expectFormError(message?: string) {
    await expect(this.formError).toBeVisible();
    if (message) {
      await expect(this.formError).toContainText(message);
    }
  }

  /**
   * Check if invitation appears in the list.
   */
  async expectInvitationInList(email: string) {
    const row = this.page.locator(`tbody tr:has-text("${email}")`);
    await expect(row).toBeVisible();
  }

  /**
   * Revoke an invitation by email.
   */
  async revokeInvitation(email: string) {
    const row = this.page.locator(`tbody tr:has-text("${email}")`);
    const revokeLink = row.locator('a:has-text("Revoke")');

    // Handle confirmation dialog
    this.page.once('dialog', (dialog) => dialog.accept());

    await revokeLink.click();
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Resend an invitation by email.
   */
  async resendInvitation(email: string) {
    const row = this.page.locator(`tbody tr:has-text("${email}")`);
    const resendLink = row.locator('a:has-text("Resend")');
    await resendLink.click();
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Get the status badge text for an invitation.
   */
  async getInvitationStatus(email: string): Promise<string | null> {
    const row = this.page.locator(`tbody tr:has-text("${email}")`);
    // The status badge is typically in a span with specific colors
    const statusBadge = row.locator('span[class*="rounded-full"]').first();
    return statusBadge.textContent();
  }

  /**
   * Check if revoke button is visible for an invitation.
   */
  async isRevokeVisible(email: string): Promise<boolean> {
    const row = this.page.locator(`tbody tr:has-text("${email}")`);
    const revokeLink = row.locator('a:has-text("Revoke")');
    return revokeLink.isVisible().catch(() => false);
  }

  /**
   * Check if resend button is visible for an invitation.
   */
  async isResendVisible(email: string): Promise<boolean> {
    const row = this.page.locator(`tbody tr:has-text("${email}")`);
    const resendLink = row.locator('a:has-text("Resend")');
    return resendLink.isVisible().catch(() => false);
  }
}
