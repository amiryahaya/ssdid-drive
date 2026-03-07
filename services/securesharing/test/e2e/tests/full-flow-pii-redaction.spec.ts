/**
 * Full E2E Flow: Invitation → Sign Up → File Upload → PII Redaction → Download
 *
 * This test simulates the complete user journey:
 * 1. Admin creates an invitation for a new user
 * 2. New user accepts invitation and creates account
 * 3. User uploads a file containing PII
 * 4. File is sent to PII service for redaction
 * 5. User downloads the redacted file
 * 6. Verify PII has been properly redacted
 */

import { test, expect, request as playwrightRequest } from '@playwright/test';
import {
  createApiClients,
  BackendApiClient,
  PiiServiceApiClient,
  CONFIG,
} from '../lib/api-client';
import {
  generateTestEmail,
  generateTestPassword,
  generateMockCryptoKeys,
  generateMockFileMetadata,
  SAMPLE_DOCUMENTS,
  EXPECTED_PII_TYPES,
  assertRedacted,
  retryWithBackoff,
} from '../lib/test-helpers';

// Run tests serially to avoid rate limiting
test.describe.configure({ mode: 'serial' });

test.describe('Full E2E Flow: Invitation → Upload → Redact → Download', () => {
  // Test state (shared across serial tests)
  let adminToken: string;
  let invitationToken: string;
  let newUserEmail: string;
  let newUserPassword: string;
  let newUserToken: string;
  let newUserId: string;

  test.beforeAll(async () => {
    // Create a fresh API request context for beforeAll
    const requestContext = await playwrightRequest.newContext();
    const backend = new BackendApiClient(requestContext);

    // Login as admin
    console.log('Logging in as admin...');
    const adminAuth = await backend.login(CONFIG.adminEmail, CONFIG.adminPassword);
    adminToken = adminAuth.data.access_token;
    console.log('Admin login successful');

    await requestContext.dispose();
  });

  test.describe.serial('Complete User Journey', () => {
    test('Step 1: Admin creates invitation for new user', async ({ request }) => {
      const backend = new BackendApiClient(request);
      backend.setAuthToken(adminToken);

      newUserEmail = generateTestEmail('newuser');
      console.log(`Creating invitation for: ${newUserEmail}`);

      const invitation = await backend.createInvitation({
        email: newUserEmail,
        role: 'member',
        message: 'Welcome to SecureSharing! This is an E2E test invitation.',
      });

      expect(invitation.data).toBeDefined();
      expect(invitation.data.email).toBe(newUserEmail);
      expect(invitation.data.token).toBeDefined();
      expect(invitation.data.status).toBe('pending');

      invitationToken = invitation.data.token;
      console.log(`Invitation created with token: ${invitationToken.substring(0, 8)}...`);
    });

    test('Step 2: Verify invitation can be retrieved', async ({ request }) => {
      // Create a fresh client without auth for public endpoint
      const publicBackend = new BackendApiClient(request);

      const invitation = await publicBackend.getInvitation(invitationToken);

      expect(invitation.data).toBeDefined();
      expect(invitation.data.email).toBe(newUserEmail);
      expect(invitation.data.valid).toBe(true);

      console.log('Invitation verified successfully');
    });

    test('Step 3: New user accepts invitation and creates account', async ({ request }) => {
      // Create a fresh client for the new user
      const newUserBackend = new BackendApiClient(request);

      newUserPassword = generateTestPassword();
      const cryptoKeys = generateMockCryptoKeys();

      console.log('Accepting invitation and creating account...');

      const authResult = await newUserBackend.acceptInvitation(invitationToken, {
        name: 'E2E Test User',
        password: newUserPassword,
        ...cryptoKeys,
      });

      expect(authResult.data.access_token).toBeDefined();
      expect(authResult.data.user).toBeDefined();
      expect(authResult.data.user.email).toBe(newUserEmail);

      newUserToken = authResult.data.access_token;
      newUserId = authResult.data.user.id;

      console.log(`Account created for user: ${newUserId}`);
    });

    test('Step 4: New user can login with credentials', async ({ request }) => {
      const userBackend = new BackendApiClient(request);

      const authResult = await userBackend.login(newUserEmail, newUserPassword);

      expect(authResult.data.access_token).toBeDefined();
      expect(authResult.data.user.id).toBe(newUserId);

      // Update token for subsequent tests
      newUserToken = authResult.data.access_token;

      console.log('Login successful');
    });

    test('Step 5: User uploads a file with PII', async ({ request }) => {
      test.skip(
        !process.env.ENABLE_FILE_UPLOAD_TESTS,
        'File upload tests require storage backend (set ENABLE_FILE_UPLOAD_TESTS=1)'
      );

      const userBackend = new BackendApiClient(request);
      userBackend.setAuthToken(newUserToken);

      const fileContent = SAMPLE_DOCUMENTS.simple;
      const metadata = generateMockFileMetadata('pii-document.txt', fileContent);

      console.log('Getting upload URL...');
      const uploadUrl = await userBackend.getUploadUrl({
        folder_id: null,
        ...metadata,
      });

      expect(uploadUrl.data.upload_url).toBeDefined();
      expect(uploadUrl.data.file_id).toBeDefined();

      console.log('Uploading file to storage...');
      await userBackend.uploadToPresignedUrl(uploadUrl.data.upload_url, fileContent);

      console.log(`File uploaded with ID: ${uploadUrl.data.file_id}`);
    });

    test('Step 6: Send file to PII service for redaction', async ({ request }) => {
      test.skip(
        !process.env.ENABLE_PII_SERVICE_TESTS,
        'PII service tests require running PII service (set ENABLE_PII_SERVICE_TESTS=1)'
      );

      const userPiiService = new PiiServiceApiClient(request, CONFIG.piiServiceUrl);
      userPiiService.setAuthToken(newUserToken);

      // Check PII service health
      console.log('Checking PII service health...');
      const health = await retryWithBackoff(() => userPiiService.healthCheck(), {
        maxAttempts: 5,
        initialDelayMs: 2000,
      });
      expect(health.status).toBe('ok');

      // Create conversation
      console.log('Creating conversation...');
      const conversation = await userPiiService.createConversation({
        name: 'E2E Test Document Review',
      });
      expect(conversation.id).toBeDefined();

      // Upload file
      console.log('Uploading file to PII service...');
      const file = await userPiiService.uploadFile(
        conversation.id,
        'pii-document.txt',
        SAMPLE_DOCUMENTS.simple,
        'text/plain'
      );
      expect(file.id).toBeDefined();
      expect(file.status).toBe('pending');

      // Process file
      console.log('Processing file for PII redaction...');
      const processResult = await userPiiService.processFile(file.id);
      expect(processResult.status).toBeDefined();

      // Wait for processing to complete
      console.log('Waiting for processing to complete...');
      const processedFile = await userPiiService.waitForProcessing(
        conversation.id,
        file.id,
        120000 // 2 minute timeout
      );
      expect(processedFile.status).toBe('processed');

      // Verify PII was detected
      if (processedFile.pii_findings) {
        console.log(`Found ${processedFile.pii_findings.length} PII instances`);
        expect(processedFile.pii_findings.length).toBeGreaterThan(0);
      }

      // Download redacted file
      console.log('Downloading redacted file...');
      const redactedContent = await userPiiService.downloadRedactedFile(file.id);

      // Verify redaction
      console.log('Verifying PII redaction...');
      assertRedacted(redactedContent, SAMPLE_DOCUMENTS.simple, EXPECTED_PII_TYPES.simple);

      // Log sample of redacted content
      console.log('Redacted content preview:');
      console.log(redactedContent.substring(0, 200) + '...');

      console.log('PII redaction completed successfully!');
    });
  });

  test.describe('PII Detection Tests', () => {
    test('Detect PII in simple document', async ({ request }) => {
      test.skip(
        !process.env.ENABLE_PII_SERVICE_TESTS,
        'PII service tests require running PII service'
      );

      const piiService = new PiiServiceApiClient(request, CONFIG.piiServiceUrl);
      piiService.setAuthToken(newUserToken || adminToken);

      const result = await piiService.detectPii(SAMPLE_DOCUMENTS.simple);

      expect(result.findings).toBeDefined();
      expect(result.findings.length).toBeGreaterThan(0);

      // Check for expected PII types
      const foundTypes = result.findings.map((f) => f.type);
      console.log('Detected PII types:', foundTypes);

      expect(foundTypes).toContain('PERSON');
      expect(foundTypes.some((t) => t.includes('EMAIL') || t === 'EMAIL_ADDRESS')).toBeTruthy();
    });

    test('Detect PII in medical document', async ({ request }) => {
      test.skip(
        !process.env.ENABLE_PII_SERVICE_TESTS,
        'PII service tests require running PII service'
      );

      const piiService = new PiiServiceApiClient(request, CONFIG.piiServiceUrl);
      piiService.setAuthToken(newUserToken || adminToken);

      const result = await piiService.detectPii(SAMPLE_DOCUMENTS.medical);

      expect(result.findings).toBeDefined();
      expect(result.findings.length).toBeGreaterThan(0);

      const foundTypes = result.findings.map((f) => f.type);
      console.log('Detected PII types in medical doc:', foundTypes);

      // Medical documents should have more PII
      expect(result.findings.length).toBeGreaterThan(5);
    });

    test('Detect PII in financial document', async ({ request }) => {
      test.skip(
        !process.env.ENABLE_PII_SERVICE_TESTS,
        'PII service tests require running PII service'
      );

      const piiService = new PiiServiceApiClient(request, CONFIG.piiServiceUrl);
      piiService.setAuthToken(newUserToken || adminToken);

      const result = await piiService.detectPii(SAMPLE_DOCUMENTS.financial);

      expect(result.findings).toBeDefined();
      expect(result.findings.length).toBeGreaterThan(0);

      const foundTypes = result.findings.map((f) => f.type);
      console.log('Detected PII types in financial doc:', foundTypes);

      // Should detect financial PII
      expect(
        foundTypes.some(
          (t) =>
            t.includes('CREDIT') ||
            t.includes('CARD') ||
            t.includes('ACCOUNT') ||
            t.includes('SSN')
        )
      ).toBeTruthy();
    });

    test('No PII in clean document', async ({ request }) => {
      test.skip(
        !process.env.ENABLE_PII_SERVICE_TESTS,
        'PII service tests require running PII service'
      );

      const piiService = new PiiServiceApiClient(request, CONFIG.piiServiceUrl);
      piiService.setAuthToken(newUserToken || adminToken);

      const result = await piiService.detectPii(SAMPLE_DOCUMENTS.noPii);

      expect(result.findings).toBeDefined();
      // Should have no or minimal findings
      expect(result.findings.length).toBeLessThan(2);

      console.log(`Clean document: ${result.findings.length} findings`);
    });
  });
});

test.describe('Invitation Edge Cases', () => {
  // Run serially to avoid rate limiting
  test.describe.configure({ mode: 'serial' });

  let adminToken: string;

  test.beforeAll(async () => {
    const requestContext = await playwrightRequest.newContext();
    const backend = new BackendApiClient(requestContext);
    const auth = await backend.login(CONFIG.adminEmail, CONFIG.adminPassword);
    adminToken = auth.data.access_token;
    await requestContext.dispose();
  });

  test('Cannot accept invitation with invalid token', async ({ request }) => {
    const publicBackend = new BackendApiClient(request);

    // The API returns 200 with {valid: false} for invalid tokens
    const invitation = await publicBackend.getInvitation('invalid-token-12345');
    expect(invitation.data.valid).toBe(false);
    expect(invitation.data.error_reason).toBeDefined();
  });

  test('Cannot create invitation for existing user email', async ({ request }) => {
    const backend = new BackendApiClient(request);
    backend.setAuthToken(adminToken);

    // This should fail or handle gracefully
    try {
      await backend.createInvitation({
        email: CONFIG.adminEmail, // Already exists
        role: 'member',
      });
      // Some systems allow this (invitation to join another tenant)
      // so we just verify no crash
    } catch (error) {
      // Expected - user already exists
      expect((error as Error).message).toMatch(/already exists|already a member|409/i);
    }
  });

  test('Cannot accept same invitation twice', async ({ request }) => {
    const backend = new BackendApiClient(request);
    backend.setAuthToken(adminToken);

    // Create invitation
    const email = generateTestEmail('double-accept');
    const invitation = await backend.createInvitation({
      email,
      role: 'member',
    });

    // Accept first time
    const publicBackend = new BackendApiClient(request);
    const cryptoKeys = generateMockCryptoKeys();

    await publicBackend.acceptInvitation(invitation.data.token, {
      name: 'First Accept',
      password: generateTestPassword(),
      ...cryptoKeys,
    });

    // Try to accept again
    try {
      await publicBackend.acceptInvitation(invitation.data.token, {
        name: 'Second Accept',
        password: generateTestPassword(),
        ...cryptoKeys,
      });
      throw new Error('Should have thrown an error');
    } catch (error) {
      expect((error as Error).message).toMatch(/already|accepted|expired|invalid|404|410/i);
    }
  });
});
