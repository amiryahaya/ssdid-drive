/**
 * Pagination API Contract Tests
 *
 * Validates that paginated endpoints follow consistent structure.
 * Note: API uses "pagination" key with "total" (not "meta" with "total_count")
 */

import { test, expect } from '@playwright/test';
import { BackendApiClient, CONFIG } from '../../lib/api-client';

test.describe('Pagination Contract', () => {
  test('Pagination has required fields', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Test with invitations endpoint (which has pagination)
    const response = await api.listInvitations();

    expect(response.pagination).toHaveProperty('page');
    expect(response.pagination).toHaveProperty('per_page');
    expect(response.pagination).toHaveProperty('total');
    expect(response.pagination).toHaveProperty('total_pages');

    console.log('✓ Pagination has all required fields');
  });

  test('Pagination fields are correct types', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const response = await api.listInvitations();

    expect(typeof response.pagination.page).toBe('number');
    expect(typeof response.pagination.per_page).toBe('number');
    expect(typeof response.pagination.total).toBe('number');
    expect(typeof response.pagination.total_pages).toBe('number');

    // All should be integers
    expect(Number.isInteger(response.pagination.page)).toBe(true);
    expect(Number.isInteger(response.pagination.per_page)).toBe(true);
    expect(Number.isInteger(response.pagination.total)).toBe(true);
    expect(Number.isInteger(response.pagination.total_pages)).toBe(true);

    console.log('✓ Pagination fields are correct types');
  });

  test('Page parameter is respected', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const page1 = await api.listInvitations({ page: 1, per_page: 5 });
    expect(page1.pagination.page).toBe(1);

    const page2 = await api.listInvitations({ page: 2, per_page: 5 });
    expect(page2.pagination.page).toBe(2);

    console.log('✓ Page parameter is respected');
  });

  test('Per_page parameter is respected', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const response5 = await api.listInvitations({ per_page: 5 });
    expect(response5.pagination.per_page).toBe(5);
    expect(response5.data.length).toBeLessThanOrEqual(5);

    const response10 = await api.listInvitations({ per_page: 10 });
    expect(response10.pagination.per_page).toBe(10);
    expect(response10.data.length).toBeLessThanOrEqual(10);

    console.log('✓ Per_page parameter is respected');
  });

  test('Total_pages is calculated correctly', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const response = await api.listInvitations({ per_page: 5 });

    const expectedTotalPages = response.pagination.total === 0
      ? 0
      : Math.ceil(response.pagination.total / response.pagination.per_page);
    expect(response.pagination.total_pages).toBe(expectedTotalPages);

    console.log(`✓ Total pages (${response.pagination.total_pages}) calculated correctly`);
  });
});

test.describe('Shares Endpoints', () => {
  // Note: Shares endpoints return simple lists without pagination
  test('Created shares returns data array', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const response = await api.listCreatedShares();

    expect(response).toHaveProperty('data');
    expect(Array.isArray(response.data)).toBe(true);

    console.log(`✓ Created shares returns data array (${response.data.length} items)`);
  });

  test('Received shares returns data array', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const response = await api.listReceivedShares();

    expect(response).toHaveProperty('data');
    expect(Array.isArray(response.data)).toBe(true);

    console.log(`✓ Received shares returns data array (${response.data.length} items)`);
  });
});

test.describe('Pagination Edge Cases', () => {
  test('Empty result set has valid pagination', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Request a page that likely doesn't exist
    const response = await api.listInvitations({ page: 9999, per_page: 10 });

    expect(response.data).toEqual([]);
    expect(response.pagination.page).toBe(9999);
    expect(response.pagination.total).toBeGreaterThanOrEqual(0);

    console.log('✓ Empty result set has valid pagination');
  });

  test('First page when total is less than per_page', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    // Request with large per_page
    const response = await api.listInvitations({ page: 1, per_page: 1000 });

    expect(response.pagination.page).toBe(1);
    expect(response.data.length).toBeLessThanOrEqual(response.pagination.total);

    if (response.pagination.total <= 1000 && response.pagination.total > 0) {
      expect(response.pagination.total_pages).toBe(1);
    }

    console.log('✓ First page with large per_page works correctly');
  });

  test('Default pagination when no params provided', async ({ request }) => {
    const api = new BackendApiClient(request);
    await api.login(CONFIG.adminEmail, CONFIG.adminPassword);

    const response = await api.listInvitations();

    // Should have sensible defaults
    expect(response.pagination.page).toBe(1);
    expect(response.pagination.per_page).toBeGreaterThan(0);
    expect(response.pagination.per_page).toBeLessThanOrEqual(100); // Reasonable max

    console.log(`✓ Default pagination: page=${response.pagination.page}, per_page=${response.pagination.per_page}`);
  });
});
