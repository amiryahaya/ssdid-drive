import { test, expect, ADMIN_CREDENTIALS } from '../fixtures/auth.fixture';
import { AdminLoginPage, AdminDashboardPage, AdminInvitationsPage } from '../pages';

/**
 * Test: Create Invitation Only
 *
 * This test assumes a tenant already exists in the database.
 * It creates an invitation and outputs the invited email.
 */
test.describe('Create Invitation Only', () => {
  test('create invitation for existing tenant', async ({ page }) => {
    // Login as admin
    const loginPage = new AdminLoginPage(page);
    await loginPage.goto();
    await loginPage.login(ADMIN_CREDENTIALS.email, ADMIN_CREDENTIALS.password);

    // Wait for dashboard
    const dashboard = new AdminDashboardPage(page);
    await dashboard.expectLoaded();

    // Navigate to invitations
    await dashboard.goToInvitations();

    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.expectLoaded();

    // Open invitation form
    await invitationsPage.openNewInvitationForm();

    // Get available tenants
    const options = await invitationsPage.tenantSelect.locator('option').allTextContents();
    const availableTenants = options.filter((opt) => opt !== 'Select a tenant');

    if (availableTenants.length === 0) {
      console.log('❌ No tenants available. Please create a tenant first.');
      console.log('   Run: npx playwright test invitation-with-tenant.spec.ts');
      test.skip();
      return;
    }

    // Use first available tenant
    const tenantName = availableTenants[0];
    console.log(`\n📋 Using tenant: ${tenantName}`);

    // Generate unique test email
    const testEmail = `test-user-${Date.now()}@example.com`;
    console.log(`📧 Inviting email: ${testEmail}`);

    // Fill form
    await invitationsPage.tenantSelect.selectOption({ label: tenantName });
    await invitationsPage.emailInput.fill(testEmail);
    await invitationsPage.roleSelect.selectOption({ label: 'Member' });
    await invitationsPage.messageInput.fill('Welcome! This is a test invitation.');

    // Submit
    await invitationsPage.submitButton.click();
    await page.waitForTimeout(1000);

    // Check for success
    const successFlash = page.locator('.bg-green-50, [role="alert"]:has-text("sent")');
    const hasSuccess = await successFlash.isVisible().catch(() => false);

    if (hasSuccess) {
      console.log(`\n✅ Invitation created successfully!`);
      console.log(`   Email: ${testEmail}`);
      console.log(`   Tenant: ${tenantName}`);
      console.log(`   Role: Member`);
    } else {
      // Check if invitation appears in the list
      const inList = await page.locator(`tbody tr:has-text("${testEmail}")`).isVisible().catch(() => false);
      if (inList) {
        console.log(`\n✅ Invitation created and visible in list!`);
        console.log(`   Email: ${testEmail}`);
      } else {
        console.log(`\n⚠️ Could not verify invitation creation`);
      }
    }

    // Verify invitation is in the list
    await invitationsPage.expectLoaded();
    const invitationRow = page.locator(`tbody tr:has-text("${testEmail}")`);
    await expect(invitationRow).toBeVisible({ timeout: 5000 });

    // Output final summary
    console.log(`\n📬 INVITATION SUMMARY:`);
    console.log(`   ├─ Email: ${testEmail}`);
    console.log(`   ├─ Tenant: ${tenantName}`);
    console.log(`   ├─ Role: Member`);
    console.log(`   └─ Status: Pending`);
  });
});
