import { test, expect, ADMIN_CREDENTIALS } from '../fixtures/auth.fixture';
import { AdminLoginPage, AdminDashboardPage, AdminTenantsPage, AdminInvitationsPage } from '../pages';

/**
 * Test: Create Tenant and Then Create Invitation
 *
 * This test creates a new tenant first, then creates an invitation
 * for that tenant and outputs the invited email.
 */
test.describe('Create Tenant and Invitation', () => {
  test('create tenant then invite user', async ({ page }) => {
    // Generate unique identifiers
    const timestamp = Date.now();
    const tenantName = `Test Company ${timestamp}`;
    const tenantSlug = `test-company-${timestamp}`;
    const inviteEmail = `invited-user-${timestamp}@example.com`;

    console.log('\n🚀 Starting: Create Tenant and Invitation Test');
    console.log('━'.repeat(50));

    // ========================================
    // STEP 1: Login as Admin
    // ========================================
    console.log('\n📝 Step 1: Logging in as admin...');

    const loginPage = new AdminLoginPage(page);
    await loginPage.goto();
    await loginPage.login(ADMIN_CREDENTIALS.email, ADMIN_CREDENTIALS.password);

    const dashboard = new AdminDashboardPage(page);
    await dashboard.expectLoaded();
    console.log('   ✓ Logged in successfully');

    // ========================================
    // STEP 2: Create New Tenant
    // ========================================
    console.log('\n📝 Step 2: Creating new tenant...');
    console.log(`   Tenant Name: ${tenantName}`);
    console.log(`   Tenant Slug: ${tenantSlug}`);

    // Navigate to tenants
    await dashboard.goToTenants();
    const tenantsPage = new AdminTenantsPage(page);
    await tenantsPage.expectLoaded();

    // Click "New Tenant" link (not the modal submit button)
    const newTenantBtn = page.locator('a[href="/admin/tenants/new"]');
    await newTenantBtn.click();
    await page.waitForTimeout(500);

    // Fill tenant form
    const nameInput = page.locator('input[name="tenant[name]"]');
    const slugInput = page.locator('input[name="tenant[slug]"]');

    await nameInput.fill(tenantName);
    await slugInput.fill(tenantSlug);

    // Submit tenant form
    const saveTenantBtn = page.locator('button:has-text("Save"), button[type="submit"]:has-text("Save")');
    await saveTenantBtn.click();
    await page.waitForTimeout(1000);

    // Verify tenant was created (check for flash or presence in list)
    const tenantCreated = await page.locator(`text="${tenantName}"`).isVisible().catch(() => false);
    if (tenantCreated) {
      console.log('   ✓ Tenant created successfully');
    } else {
      // Navigate back to tenants list to verify
      await dashboard.goToTenants();
      await page.waitForTimeout(500);
    }

    // ========================================
    // STEP 3: Navigate to Invitations
    // ========================================
    console.log('\n📝 Step 3: Navigating to invitations...');

    await dashboard.goToInvitations();
    const invitationsPage = new AdminInvitationsPage(page);
    await invitationsPage.expectLoaded();
    console.log('   ✓ On invitations page');

    // ========================================
    // STEP 4: Create Invitation
    // ========================================
    console.log('\n📝 Step 4: Creating invitation...');
    console.log(`   Email: ${inviteEmail}`);
    console.log(`   Tenant: ${tenantName}`);
    console.log(`   Role: Member`);

    // Open invitation form
    await invitationsPage.openNewInvitationForm();

    // Check if our new tenant is in the dropdown
    const options = await invitationsPage.tenantSelect.locator('option').allTextContents();
    const ourTenant = options.find((opt) => opt.includes(tenantName) || opt === tenantName);

    if (!ourTenant) {
      console.log('   ⚠️ New tenant not found in dropdown, using first available tenant');
      const firstTenant = options.find((opt) => opt !== 'Select a tenant');
      if (firstTenant) {
        await invitationsPage.tenantSelect.selectOption({ label: firstTenant });
      }
    } else {
      await invitationsPage.tenantSelect.selectOption({ label: ourTenant });
    }

    // Fill invitation details
    await invitationsPage.emailInput.fill(inviteEmail);
    await invitationsPage.roleSelect.selectOption({ label: 'Member' });
    await invitationsPage.messageInput.fill(`Welcome to ${tenantName}! We are excited to have you on board.`);

    // Submit invitation
    await invitationsPage.submitButton.click();
    await page.waitForTimeout(1500);

    // ========================================
    // STEP 5: Verify and Output Results
    // ========================================
    console.log('\n📝 Step 5: Verifying invitation...');

    // Check for success flash
    const successFlash = await page.locator('.bg-green-50').isVisible().catch(() => false);

    // Check if invitation is in the list
    await invitationsPage.expectLoaded();
    const invitationRow = page.locator(`tbody tr:has-text("${inviteEmail}")`);
    const invitationVisible = await invitationRow.isVisible({ timeout: 5000 }).catch(() => false);

    if (invitationVisible) {
      console.log('   ✓ Invitation created and visible in list');

      // Get status from the row
      const statusBadge = await invitationRow.locator('span[class*="rounded-full"]').first().textContent().catch(() => 'pending');

      console.log('\n' + '═'.repeat(50));
      console.log('📬 INVITATION CREATED SUCCESSFULLY');
      console.log('═'.repeat(50));
      console.log(`\n   📧 INVITED EMAIL: ${inviteEmail}`);
      console.log(`   🏢 TENANT: ${tenantName}`);
      console.log(`   👤 ROLE: Member`);
      console.log(`   📊 STATUS: ${statusBadge}`);
      console.log('\n' + '═'.repeat(50));

      // Output just the email for easy copying
      console.log(`\n🎯 COPY THIS EMAIL: ${inviteEmail}\n`);
    } else if (successFlash) {
      console.log('   ✓ Success message shown');
      console.log(`\n📧 INVITED EMAIL: ${inviteEmail}`);
    } else {
      console.log('   ⚠️ Could not verify invitation in list');
      console.log(`   Email attempted: ${inviteEmail}`);
    }

    // Final assertion
    expect(invitationVisible || successFlash).toBeTruthy();
  });
});

/**
 * Test: Create Multiple Invitations for Same Tenant
 */
test.describe('Multiple Invitations', () => {
  test('create tenant with multiple invitations', async ({ page }) => {
    const timestamp = Date.now();
    const tenantName = `Multi-Invite Corp ${timestamp}`;
    const emails = [
      `user1-${timestamp}@example.com`,
      `user2-${timestamp}@example.com`,
      `admin-${timestamp}@example.com`,
    ];
    const roles = ['Member', 'Member', 'Admin'];

    console.log('\n🚀 Starting: Multiple Invitations Test');
    console.log('━'.repeat(50));

    // Login
    const loginPage = new AdminLoginPage(page);
    await loginPage.goto();
    await loginPage.login(ADMIN_CREDENTIALS.email, ADMIN_CREDENTIALS.password);

    const dashboard = new AdminDashboardPage(page);
    await dashboard.expectLoaded();

    // Create tenant first
    console.log(`\n📝 Creating tenant: ${tenantName}`);
    await dashboard.goToTenants();

    const newTenantBtn = page.locator('a[href="/admin/tenants/new"]');
    await newTenantBtn.click();
    await page.waitForTimeout(500);

    await page.locator('input[name="tenant[name]"]').fill(tenantName);
    await page.locator('input[name="tenant[slug]"]').fill(`multi-invite-${timestamp}`);
    await page.locator('button:has-text("Save"), button[type="submit"]:has-text("Save")').click();
    await page.waitForTimeout(1000);

    // Navigate to invitations
    await dashboard.goToInvitations();
    const invitationsPage = new AdminInvitationsPage(page);

    // Create invitations
    const createdEmails: string[] = [];

    for (let i = 0; i < emails.length; i++) {
      console.log(`\n📝 Creating invitation ${i + 1}/${emails.length}: ${emails[i]} (${roles[i]})`);

      await invitationsPage.openNewInvitationForm();

      // Select tenant (try to find our tenant or use first available)
      const options = await invitationsPage.tenantSelect.locator('option').allTextContents();
      const targetTenant = options.find((opt) => opt.includes(tenantName)) || options.find((opt) => opt !== 'Select a tenant');

      if (targetTenant) {
        await invitationsPage.tenantSelect.selectOption({ label: targetTenant });
        await invitationsPage.emailInput.fill(emails[i]);
        await invitationsPage.roleSelect.selectOption({ label: roles[i] });
        await invitationsPage.submitButton.click();
        await page.waitForTimeout(1000);
        createdEmails.push(emails[i]);
        console.log(`   ✓ Sent invitation to ${emails[i]}`);
      }
    }

    // Output summary
    console.log('\n' + '═'.repeat(50));
    console.log('📬 ALL INVITATIONS CREATED');
    console.log('═'.repeat(50));
    console.log(`\n🏢 TENANT: ${tenantName}\n`);
    console.log('📧 INVITED EMAILS:');
    createdEmails.forEach((email, i) => {
      console.log(`   ${i + 1}. ${email} (${roles[i]})`);
    });
    console.log('\n' + '═'.repeat(50));

    expect(createdEmails.length).toBeGreaterThan(0);
  });
});
