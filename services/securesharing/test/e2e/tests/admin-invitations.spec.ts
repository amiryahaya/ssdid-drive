import { test, expect, ADMIN_CREDENTIALS } from '../fixtures/auth.fixture';
import { AdminLoginPage, AdminDashboardPage, AdminInvitationsPage } from '../pages';

test.describe('Admin Invitations Management', () => {
  test.beforeEach(async ({ page }) => {
    // Login before each test and navigate to invitations via dashboard
    const loginPage = new AdminLoginPage(page);
    await loginPage.goto();
    await loginPage.login(ADMIN_CREDENTIALS.email, ADMIN_CREDENTIALS.password);

    // Wait for dashboard to load, then navigate to invitations
    const dashboard = new AdminDashboardPage(page);
    await dashboard.expectLoaded();

    // Navigate to invitations page via nav link
    await page.locator('nav a[href="/admin/invitations"]').click();
    await page.waitForLoadState('networkidle');
  });

  test('displays invitations list', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.expectLoaded();
  });

  test('shows invitation table', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);

    // Table should exist (may be empty in fresh test db)
    await expect(invitationsPage.invitationsTable.or(page.locator('[data-role="empty-state"]'))).toBeVisible();
  });

  test('displays new invitation button', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await expect(invitationsPage.newInvitationButton).toBeVisible();
  });

  test('opens invitation form modal', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.openNewInvitationForm();

    // Form elements should be visible
    await expect(invitationsPage.tenantSelect).toBeVisible();
    await expect(invitationsPage.emailInput).toBeVisible();
    await expect(invitationsPage.roleSelect).toBeVisible();
    await expect(invitationsPage.submitButton).toBeVisible();
  });

  test('can close invitation form modal', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.openNewInvitationForm();
    await invitationsPage.closeModal();

    // Form elements should no longer be visible
    await expect(invitationsPage.tenantSelect).not.toBeVisible();
  });

  test('tenant field is required for submission', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.openNewInvitationForm();

    // Fill email but not tenant
    await invitationsPage.emailInput.fill('test@example.com');
    await invitationsPage.submitButton.click();

    // HTML5 validation should prevent submission - form should still be visible
    await expect(invitationsPage.emailInput).toBeVisible();

    // Check that the tenant select has required attribute
    const isRequired = await invitationsPage.tenantSelect.getAttribute('required');
    expect(isRequired).not.toBeNull();
  });

  test('shows error for invalid email format', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.openNewInvitationForm();

    // Try to get the first tenant option
    const options = await invitationsPage.tenantSelect.locator('option').allTextContents();
    const firstTenant = options.find((opt) => opt !== 'Select a tenant');

    if (firstTenant) {
      await invitationsPage.tenantSelect.selectOption({ label: firstTenant });
      await invitationsPage.emailInput.fill('invalid-email');
      await invitationsPage.submitButton.click();

      // HTML5 validation should prevent submission - form should still be visible
      await page.waitForTimeout(500);
      await expect(invitationsPage.emailInput).toBeVisible();

      // Check that HTML5 validation marks the email as invalid
      const isValid = await invitationsPage.emailInput.evaluate((el: HTMLInputElement) => el.validity.valid);
      expect(isValid).toBe(false);
    }
  });

  test('can filter invitations by status', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);

    // Filter by pending
    await invitationsPage.filterByStatus('pending');
    await expect(page).toHaveURL(/status=pending/);

    // Filter by accepted
    await invitationsPage.filterByStatus('accepted');
    await expect(page).toHaveURL(/status=accepted/);

    // Filter by all
    await invitationsPage.filterByStatus('all');
    await expect(page).not.toHaveURL(/status=/);
  });

  test('prevents XSS in email input', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.openNewInvitationForm();

    // Get first tenant
    const options = await invitationsPage.tenantSelect.locator('option').allTextContents();
    const firstTenant = options.find((opt) => opt !== 'Select a tenant');

    if (firstTenant) {
      await invitationsPage.tenantSelect.selectOption({ label: firstTenant });

      // Try XSS in email field
      await invitationsPage.emailInput.fill('<script>alert("xss")</script>@example.com');
      await invitationsPage.submitButton.click();

      await page.waitForTimeout(500);

      // Check that script is not executed in page content
      const pageContent = await page.content();
      expect(pageContent).not.toContain('<script>alert("xss")</script>');
    }
  });

  test('prevents SQL injection in email input', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.openNewInvitationForm();

    // Get first tenant
    const options = await invitationsPage.tenantSelect.locator('option').allTextContents();
    const firstTenant = options.find((opt) => opt !== 'Select a tenant');

    if (firstTenant) {
      await invitationsPage.tenantSelect.selectOption({ label: firstTenant });

      // Try SQL injection in email field
      await invitationsPage.emailInput.fill("'; DROP TABLE invitations; --@example.com");
      await invitationsPage.submitButton.click();

      await page.waitForTimeout(500);

      // Page should still function normally
      await invitationsPage.expectLoaded();
    }
  });

  test('message field is optional', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.openNewInvitationForm();

    // Message field should not be required
    const messageInput = invitationsPage.messageInput;
    const isRequired = await messageInput.getAttribute('required');
    expect(isRequired).toBeNull();
  });

  test('role defaults to member', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.openNewInvitationForm();

    // Check default role value
    const selectedRole = await invitationsPage.roleSelect.inputValue();
    expect(selectedRole).toBe('member');
  });

  test('navigation link is visible in navbar', async ({ page }) => {
    // Check that invitations link is in the navbar
    const invitationsNavLink = page.locator('nav a[href="/admin/invitations"]');
    await expect(invitationsNavLink).toBeVisible();
    await expect(invitationsNavLink).toContainText('Invitations');
  });
});

test.describe('Admin Invitations - Create and Manage', () => {
  const testEmail = `test-invite-${Date.now()}@example.com`;

  test.beforeEach(async ({ page }) => {
    const loginPage = new AdminLoginPage(page);
    await loginPage.goto();
    await loginPage.login(ADMIN_CREDENTIALS.email, ADMIN_CREDENTIALS.password);

    const dashboard = new AdminDashboardPage(page);
    await dashboard.expectLoaded();

    await page.locator('nav a[href="/admin/invitations"]').click();
    await page.waitForLoadState('networkidle');
  });

  test('can create a new invitation', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);

    // Get first available tenant
    await invitationsPage.openNewInvitationForm();
    const options = await invitationsPage.tenantSelect.locator('option').allTextContents();
    const firstTenant = options.find((opt) => opt !== 'Select a tenant');

    if (!firstTenant) {
      test.skip(true, 'No tenants available in dropdown — check seed data');
      return;
    }

    // Close and reopen to reset form
    await invitationsPage.closeModal();

    // Create invitation
    await invitationsPage.createInvitation({
      tenantName: firstTenant,
      email: testEmail,
      role: 'member',
      message: 'Welcome to the team!',
    });

    // Should see success flash or invitation in list
    const hasFlash = await page.locator('.bg-green-50, [role="alert"]').isVisible().catch(() => false);
    const inList = await invitationsPage.invitationRows.locator(`text=${testEmail}`).isVisible().catch(() => false);

    expect(hasFlash || inList).toBeTruthy();
  });

  test('shows error for duplicate pending invitation', async ({ page }) => {
    const invitationsPage = new AdminInvitationsPage(page);

    // Get first available tenant
    await invitationsPage.openNewInvitationForm();
    const options = await invitationsPage.tenantSelect.locator('option').allTextContents();
    const firstTenant = options.find((opt) => opt !== 'Select a tenant');

    if (!firstTenant) {
      test.skip(true, 'No tenants available in dropdown — check seed data');
      return;
    }

    await invitationsPage.closeModal();

    const duplicateEmail = `duplicate-${Date.now()}@example.com`;

    // Create first invitation
    await invitationsPage.createInvitation({
      tenantName: firstTenant,
      email: duplicateEmail,
    });

    await page.waitForTimeout(1000);

    // Try to create duplicate
    await invitationsPage.createInvitation({
      tenantName: firstTenant,
      email: duplicateEmail,
    });

    // Should show error about pending invitation
    await invitationsPage.expectFormError('pending invitation');
  });
});
