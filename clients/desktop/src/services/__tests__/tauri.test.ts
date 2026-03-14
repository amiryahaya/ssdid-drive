import { describe, it, expect, vi, beforeEach } from 'vitest';
import { invoke } from '@tauri-apps/api/core';
import { tauriService } from '../tauri';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

describe('createChallenge', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('should invoke create_challenge and return mapped result', async () => {
    const mockResponse = {
      challenge_id: 'abc123',
      subscriber_secret: 'secret-xyz',
      qr_payload: 'ssdid://challenge/abc123',
      server_did: 'did:ssdid:test',
    };
    mockInvoke.mockResolvedValueOnce(mockResponse);

    const { createChallenge } = await import('../tauri');
    const result = await createChallenge('authenticate');

    expect(mockInvoke).toHaveBeenCalledWith('create_challenge');
    expect(result.challengeId).toBe('abc123');
    expect(result.subscriberSecret).toBe('secret-xyz');
    expect(result.qrPayload).toBe('ssdid://challenge/abc123');
    expect(result.serverDid).toBe('did:ssdid:test');
  });

  it('should propagate errors from invoke', async () => {
    mockInvoke.mockRejectedValueOnce(new Error('Backend unavailable'));

    const { createChallenge } = await import('../tauri');
    await expect(createChallenge('register')).rejects.toThrow('Backend unavailable');
  });
});

describe('tauriService', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  // ==================== Auth Commands ====================

  describe('auth commands', () => {
    describe('logout', () => {
      it('should call invoke with correct command', async () => {
        mockInvoke.mockResolvedValueOnce(undefined);

        await tauriService.logout();

        expect(mockInvoke).toHaveBeenCalledWith('logout');
      });
    });

    describe('getCurrentUser', () => {
      it('should return user when logged in', async () => {
        const mockUser = { id: 'user-1', email: 'test@example.com', name: 'Test' };
        mockInvoke.mockResolvedValueOnce(mockUser);

        const result = await tauriService.getCurrentUser();

        expect(mockInvoke).toHaveBeenCalledWith('get_current_user');
        expect(result).toEqual(mockUser);
      });

      it('should return null when not logged in', async () => {
        mockInvoke.mockResolvedValueOnce(null);

        const result = await tauriService.getCurrentUser();

        expect(result).toBeNull();
      });
    });

    describe('checkAuthStatus', () => {
      it('should return auth status', async () => {
        const mockStatus = { isAuthenticated: true, isLocked: false };
        mockInvoke.mockResolvedValueOnce(mockStatus);

        const result = await tauriService.checkAuthStatus();

        expect(mockInvoke).toHaveBeenCalledWith('check_auth_status');
        expect(result).toEqual(mockStatus);
      });
    });

    describe('unlockWithBiometric', () => {
      it('should return true on successful unlock', async () => {
        mockInvoke.mockResolvedValueOnce(true);

        const result = await tauriService.unlockWithBiometric();

        expect(mockInvoke).toHaveBeenCalledWith('unlock_with_biometric');
        expect(result).toBe(true);
      });

      it('should return false on failed unlock', async () => {
        mockInvoke.mockResolvedValueOnce(false);

        const result = await tauriService.unlockWithBiometric();

        expect(result).toBe(false);
      });
    });
  });

  // ==================== File Commands ====================

  describe('file commands', () => {
    describe('listFiles', () => {
      it('should call invoke with null folderId when not provided', async () => {
        const mockResponse = { items: [], currentFolder: null, breadcrumbs: [] };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listFiles();

        expect(mockInvoke).toHaveBeenCalledWith('list_files', { folderId: null });
        expect(result).toEqual(mockResponse);
      });

      it('should call invoke with folderId when provided', async () => {
        const mockResponse = { items: [], currentFolder: { id: 'folder-1' }, breadcrumbs: [] };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listFiles('folder-1');

        expect(mockInvoke).toHaveBeenCalledWith('list_files', { folderId: 'folder-1' });
        expect(result).toEqual(mockResponse);
      });
    });

    describe('uploadFile', () => {
      it('should call invoke with correct parameters', async () => {
        const mockFile = { id: 'file-1', name: 'test.txt', item_type: 'file' };
        mockInvoke.mockResolvedValueOnce(mockFile);

        const result = await tauriService.uploadFile('/path/to/file.txt', 'folder-1', 'custom.txt');

        expect(mockInvoke).toHaveBeenCalledWith('upload_file', {
          filePath: '/path/to/file.txt',
          folderId: 'folder-1',
          fileName: 'custom.txt',
          fileId: null,
          encryptedFileKey: null,
          nonce: null,
          algorithm: null,
        });
        expect(result).toEqual(mockFile);
      });

      it('should use null for optional parameters when not provided', async () => {
        const mockFile = { id: 'file-1', name: 'file.txt', item_type: 'file' };
        mockInvoke.mockResolvedValueOnce(mockFile);

        await tauriService.uploadFile('/path/to/file.txt');

        expect(mockInvoke).toHaveBeenCalledWith('upload_file', {
          filePath: '/path/to/file.txt',
          folderId: null,
          fileName: null,
          fileId: null,
          encryptedFileKey: null,
          nonce: null,
          algorithm: null,
        });
      });
    });

    describe('downloadFile', () => {
      it('should call invoke with correct parameters', async () => {
        mockInvoke.mockResolvedValueOnce('/downloads/file.txt');

        const result = await tauriService.downloadFile('file-1', '/downloads/file.txt');

        expect(mockInvoke).toHaveBeenCalledWith('download_file', {
          fileId: 'file-1',
          destination: '/downloads/file.txt',
        });
        expect(result).toBe('/downloads/file.txt');
      });
    });

    describe('createFolder', () => {
      it('should call invoke with correct parameters', async () => {
        const mockKeys = { ml_kem_pk: 'ml-pk', kaz_kem_pk: 'kaz-pk' };
        const mockFolder = { id: 'folder-1', name: 'New Folder', item_type: 'folder' };
        mockInvoke
          .mockResolvedValueOnce(mockKeys) // get_user_kem_public_keys
          .mockResolvedValueOnce(mockFolder); // create_folder

        const result = await tauriService.createFolder('New Folder', 'parent-1');

        expect(mockInvoke).toHaveBeenCalledWith('get_user_kem_public_keys');
        expect(mockInvoke).toHaveBeenCalledWith('create_folder', {
          name: 'New Folder',
          parentId: 'parent-1',
          mlKemPk: 'ml-pk',
          kazKemPk: 'kaz-pk',
        });
        expect(result).toEqual(mockFolder);
      });

      it('should use null for parentId when not provided', async () => {
        const mockKeys = { ml_kem_pk: 'ml-pk', kaz_kem_pk: 'kaz-pk' };
        const mockFolder = { id: 'folder-1', name: 'New Folder', item_type: 'folder' };
        mockInvoke
          .mockResolvedValueOnce(mockKeys) // get_user_kem_public_keys
          .mockResolvedValueOnce(mockFolder); // create_folder

        await tauriService.createFolder('New Folder');

        expect(mockInvoke).toHaveBeenCalledWith('create_folder', {
          name: 'New Folder',
          parentId: null,
          mlKemPk: 'ml-pk',
          kazKemPk: 'kaz-pk',
        });
      });
    });

    describe('deleteItem', () => {
      it('should call invoke with correct parameters', async () => {
        mockInvoke.mockResolvedValueOnce(undefined);

        await tauriService.deleteItem('item-1');

        expect(mockInvoke).toHaveBeenCalledWith('delete_item', { itemId: 'item-1' });
      });
    });

    describe('renameItem', () => {
      it('should call invoke with correct parameters', async () => {
        const mockItem = { id: 'item-1', name: 'renamed.txt', item_type: 'file' };
        mockInvoke.mockResolvedValueOnce(mockItem);

        const result = await tauriService.renameItem('item-1', 'renamed.txt');

        expect(mockInvoke).toHaveBeenCalledWith('rename_item', {
          itemId: 'item-1',
          newName: 'renamed.txt',
        });
        expect(result).toEqual(mockItem);
      });
    });

    describe('moveItem', () => {
      it('should call invoke with correct parameters', async () => {
        const mockItem = { id: 'item-1', name: 'file.txt', item_type: 'file' };
        mockInvoke.mockResolvedValueOnce(mockItem);

        const result = await tauriService.moveItem('item-1', 'folder-2');

        expect(mockInvoke).toHaveBeenCalledWith('move_item', {
          itemId: 'item-1',
          newFolderId: 'folder-2',
        });
        expect(result).toEqual(mockItem);
      });

      it('should use null for newFolderId when moving to root', async () => {
        const mockItem = { id: 'item-1', name: 'file.txt', item_type: 'file' };
        mockInvoke.mockResolvedValueOnce(mockItem);

        await tauriService.moveItem('item-1');

        expect(mockInvoke).toHaveBeenCalledWith('move_item', {
          itemId: 'item-1',
          newFolderId: null,
        });
      });
    });

    describe('getFilePreview', () => {
      it('should call invoke with correct parameters', async () => {
        const mockPreview = { fileId: 'file-1', data: 'base64...', mimeType: 'image/png' };
        mockInvoke.mockResolvedValueOnce(mockPreview);

        const result = await tauriService.getFilePreview('file-1');

        expect(mockInvoke).toHaveBeenCalledWith('get_file_preview', { fileId: 'file-1' });
        expect(result).toEqual(mockPreview);
      });
    });
  });

  // ==================== Sharing Commands ====================

  describe('sharing commands', () => {
    describe('searchRecipients', () => {
      it('should call invoke with correct parameters', async () => {
        const mockResults = [{ id: 'user-1', email: 'john@example.com', name: 'John' }];
        mockInvoke.mockResolvedValueOnce(mockResults);

        const result = await tauriService.searchRecipients('john');

        expect(mockInvoke).toHaveBeenCalledWith('search_recipients', { query: 'john' });
        expect(result).toEqual(mockResults);
      });
    });

    describe('createShare', () => {
      it('should call invoke with correct parameters', async () => {
        const request = { item_id: 'file-1', recipient_email: 'john@example.com', permission: 'read' };
        const mockResponse = { share: { id: 'share-1' } };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.createShare(request);

        expect(mockInvoke).toHaveBeenCalledWith('create_share', { request });
        expect(result).toEqual(mockResponse);
      });
    });

    describe('revokeShare', () => {
      it('should call invoke with correct parameters', async () => {
        mockInvoke.mockResolvedValueOnce(undefined);

        await tauriService.revokeShare('share-1');

        expect(mockInvoke).toHaveBeenCalledWith('revoke_share', { shareId: 'share-1' });
      });
    });

    describe('updateShare', () => {
      it('should call invoke with correct parameters', async () => {
        const mockShare = { id: 'share-1', permission: 'write' };
        mockInvoke.mockResolvedValueOnce(mockShare);

        const result = await tauriService.updateShare('share-1', 'write', '2024-12-31');

        expect(mockInvoke).toHaveBeenCalledWith('update_share', {
          shareId: 'share-1',
          permission: 'write',
          expiresAt: '2024-12-31',
        });
        expect(result).toEqual(mockShare);
      });

      it('should use null for expiresAt when not provided', async () => {
        const mockShare = { id: 'share-1', permission: 'write' };
        mockInvoke.mockResolvedValueOnce(mockShare);

        await tauriService.updateShare('share-1', 'write');

        expect(mockInvoke).toHaveBeenCalledWith('update_share', {
          shareId: 'share-1',
          permission: 'write',
          expiresAt: null,
        });
      });
    });

    describe('listMyShares', () => {
      it('should call invoke with correct command', async () => {
        const mockResponse = { shares: [{ id: 'share-1' }] };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listMyShares();

        expect(mockInvoke).toHaveBeenCalledWith('list_my_shares');
        expect(result).toEqual(mockResponse);
      });
    });

    describe('listSharedWithMe', () => {
      it('should call invoke with correct command', async () => {
        const mockResponse = { shares: [{ id: 'share-1' }] };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listSharedWithMe();

        expect(mockInvoke).toHaveBeenCalledWith('list_shared_with_me');
        expect(result).toEqual(mockResponse);
      });
    });

    describe('getShareDetails', () => {
      it('should call invoke with correct parameters', async () => {
        const mockShare = { id: 'share-1', permission: 'read' };
        mockInvoke.mockResolvedValueOnce(mockShare);

        const result = await tauriService.getShareDetails('share-1');

        expect(mockInvoke).toHaveBeenCalledWith('get_share_details', { shareId: 'share-1' });
        expect(result).toEqual(mockShare);
      });
    });

    describe('acceptShare', () => {
      it('should call invoke with correct parameters', async () => {
        const mockShare = { id: 'share-1', status: 'accepted' };
        mockInvoke.mockResolvedValueOnce(mockShare);

        const result = await tauriService.acceptShare('share-1');

        expect(mockInvoke).toHaveBeenCalledWith('accept_share', { shareId: 'share-1' });
        expect(result).toEqual(mockShare);
      });
    });

    describe('declineShare', () => {
      it('should call invoke with correct parameters', async () => {
        mockInvoke.mockResolvedValueOnce(undefined);

        await tauriService.declineShare('share-1');

        expect(mockInvoke).toHaveBeenCalledWith('decline_share', { shareId: 'share-1' });
      });
    });
  });

  // ==================== Settings Commands ====================

  describe('settings commands', () => {
    describe('getSettings', () => {
      it('should call invoke with correct command', async () => {
        const mockSettings = { theme: 'dark', autoLockTimeout: 300 };
        mockInvoke.mockResolvedValueOnce(mockSettings);

        const result = await tauriService.getSettings();

        expect(mockInvoke).toHaveBeenCalledWith('get_settings');
        expect(result).toEqual(mockSettings);
      });
    });

    describe('updateSettings', () => {
      it('should call invoke with correct parameters', async () => {
        const settings = { theme: 'light' };
        const mockResponse = { theme: 'light', autoLockTimeout: 300 };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.updateSettings(settings);

        expect(mockInvoke).toHaveBeenCalledWith('update_settings', { settings });
        expect(result).toEqual(mockResponse);
      });
    });

    describe('getStorageInfo', () => {
      it('should call invoke with correct command', async () => {
        const mockInfo = { cacheSize: 1024, totalUsed: 2048, quota: 10000 };
        mockInvoke.mockResolvedValueOnce(mockInfo);

        const result = await tauriService.getStorageInfo();

        expect(mockInvoke).toHaveBeenCalledWith('get_storage_info');
        expect(result).toEqual(mockInfo);
      });
    });

    describe('clearCache', () => {
      it('should call invoke with correct command', async () => {
        mockInvoke.mockResolvedValueOnce(undefined);

        await tauriService.clearCache();

        expect(mockInvoke).toHaveBeenCalledWith('clear_cache');
      });
    });
  });

  // ==================== Email Auth Commands ====================

  describe('email auth commands', () => {
    describe('sendOtp', () => {
      it('should call invoke with email and no invitation token', async () => {
        const mockResponse = { message: 'OTP sent' };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.sendOtp('user@example.com');

        expect(mockInvoke).toHaveBeenCalledWith('send_otp', {
          email: 'user@example.com',
          invitationToken: null,
        });
        expect(result).toEqual(mockResponse);
      });

      it('should call invoke with email and invitation token', async () => {
        const mockResponse = { message: 'OTP sent' };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.sendOtp('user@example.com', 'inv-token-123');

        expect(mockInvoke).toHaveBeenCalledWith('send_otp', {
          email: 'user@example.com',
          invitationToken: 'inv-token-123',
        });
        expect(result).toEqual(mockResponse);
      });
    });

    describe('verifyOtp', () => {
      it('should call invoke with email, code, and no invitation token', async () => {
        const mockResponse = { token: 'auth-token-xyz' };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.verifyOtp('user@example.com', '123456');

        expect(mockInvoke).toHaveBeenCalledWith('verify_otp', {
          email: 'user@example.com',
          code: '123456',
          invitationToken: null,
        });
        expect(result).toEqual(mockResponse);
      });

      it('should call invoke with invitation token when provided', async () => {
        const mockResponse = { token: 'auth-token-xyz', totp_setup_required: true };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.verifyOtp('user@example.com', '123456', 'inv-token');

        expect(mockInvoke).toHaveBeenCalledWith('verify_otp', {
          email: 'user@example.com',
          code: '123456',
          invitationToken: 'inv-token',
        });
        expect(result).toEqual(mockResponse);
      });
    });

    describe('emailLogin', () => {
      it('should call invoke with email', async () => {
        const mockResponse = { requires_totp: true };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.emailLogin('user@example.com');

        expect(mockInvoke).toHaveBeenCalledWith('email_login', { email: 'user@example.com' });
        expect(result).toEqual(mockResponse);
      });
    });
  });

  // ==================== OIDC Auth Commands ====================

  describe('oidc auth commands', () => {
    describe('oidcLogin', () => {
      it('should call invoke with provider', async () => {
        mockInvoke.mockResolvedValueOnce(undefined);

        await tauriService.oidcLogin('google');

        expect(mockInvoke).toHaveBeenCalledWith('oidc_login', { provider: 'google' });
      });
    });

    describe('verifyOidcToken', () => {
      it('should call invoke with provider and idToken only', async () => {
        const mockResponse = { token: 'oidc-token' };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.verifyOidcToken('google', 'id-token-abc');

        expect(mockInvoke).toHaveBeenCalledWith('verify_oidc_token', {
          provider: 'google',
          idToken: 'id-token-abc',
          nonce: null,
          invitationToken: null,
        });
        expect(result).toEqual(mockResponse);
      });

      it('should call invoke with all parameters', async () => {
        const mockResponse = { token: 'oidc-token', mfa_required: true, totp_setup_required: false };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.verifyOidcToken('apple', 'id-token', 'nonce-xyz', 'inv-token');

        expect(mockInvoke).toHaveBeenCalledWith('verify_oidc_token', {
          provider: 'apple',
          idToken: 'id-token',
          nonce: 'nonce-xyz',
          invitationToken: 'inv-token',
        });
        expect(result).toEqual(mockResponse);
      });
    });
  });

  // ==================== TOTP Commands ====================

  describe('totp commands', () => {
    describe('totpSetup', () => {
      it('should call invoke with correct command', async () => {
        const mockResponse = { secret: 'JBSWY3DPEHPK3PXP', otpauth_uri: 'otpauth://totp/SsdidDrive?secret=JBSWY3DPEHPK3PXP' };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.totpSetup();

        expect(mockInvoke).toHaveBeenCalledWith('totp_setup');
        expect(result).toEqual(mockResponse);
      });
    });

    describe('totpSetupConfirm', () => {
      it('should call invoke with code', async () => {
        const mockResponse = { backup_codes: ['code1', 'code2', 'code3'] };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.totpSetupConfirm('123456');

        expect(mockInvoke).toHaveBeenCalledWith('totp_setup_confirm', { code: '123456' });
        expect(result).toEqual(mockResponse);
      });
    });

    describe('totpVerify', () => {
      it('should call invoke with email and code', async () => {
        const mockResponse = { token: 'verified-token' };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.totpVerify('user@example.com', '654321');

        expect(mockInvoke).toHaveBeenCalledWith('totp_verify', {
          email: 'user@example.com',
          code: '654321',
        });
        expect(result).toEqual(mockResponse);
      });
    });
  });

  // ==================== Account Commands ====================

  describe('account commands', () => {
    describe('listLogins', () => {
      it('should call invoke with correct command', async () => {
        const mockLogins = [
          { id: 'login-1', provider: 'email', provider_subject: 'user@example.com', email: 'user@example.com', linked_at: '2025-01-01T00:00:00Z' },
          { id: 'login-2', provider: 'google', provider_subject: '12345', email: null, linked_at: '2025-02-01T00:00:00Z' },
        ];
        mockInvoke.mockResolvedValueOnce(mockLogins);

        const result = await tauriService.listLogins();

        expect(mockInvoke).toHaveBeenCalledWith('list_logins');
        expect(result).toEqual(mockLogins);
      });
    });

    describe('linkEmailLogin', () => {
      it('should call invoke with email', async () => {
        const mockResponse = { message: 'Verification email sent' };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.linkEmailLogin('new@example.com');

        expect(mockInvoke).toHaveBeenCalledWith('link_email_login', { email: 'new@example.com' });
        expect(result).toEqual(mockResponse);
      });
    });

    describe('linkOidcLogin', () => {
      it('should call invoke with provider and idToken', async () => {
        mockInvoke.mockResolvedValueOnce(undefined);

        await tauriService.linkOidcLogin('google', 'id-token-abc');

        expect(mockInvoke).toHaveBeenCalledWith('link_oidc_login', {
          provider: 'google',
          idToken: 'id-token-abc',
        });
      });
    });

    describe('unlinkLogin', () => {
      it('should call invoke with loginId', async () => {
        mockInvoke.mockResolvedValueOnce(undefined);

        await tauriService.unlinkLogin('login-1');

        expect(mockInvoke).toHaveBeenCalledWith('unlink_login', { loginId: 'login-1' });
      });
    });
  });

  // ==================== Activity Commands ====================

  describe('activity commands', () => {
    describe('listActivity', () => {
      it('should call invoke with null params when none provided', async () => {
        const mockResponse = { items: [], total: 0, page: 1, page_size: 20 };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listActivity();

        expect(mockInvoke).toHaveBeenCalledWith('list_activity', {
          page: null,
          page_size: null,
          event_type: null,
          resource_type: null,
          from: null,
          to: null,
        });
        expect(result).toEqual(mockResponse);
      });

      it('should call invoke with mapped params', async () => {
        const mockResponse = { items: [{ id: 'act-1' }], total: 1, page: 2, page_size: 10 };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listActivity({
          page: 2,
          pageSize: 10,
          eventType: 'file.upload',
          resourceType: 'file',
          from: '2025-01-01',
          to: '2025-12-31',
        });

        expect(mockInvoke).toHaveBeenCalledWith('list_activity', {
          page: 2,
          page_size: 10,
          event_type: 'file.upload',
          resource_type: 'file',
          from: '2025-01-01',
          to: '2025-12-31',
        });
        expect(result).toEqual(mockResponse);
      });
    });

    describe('listResourceActivity', () => {
      it('should call invoke with resourceId and null optional params', async () => {
        const mockResponse = { items: [], total: 0, page: 1, page_size: 20 };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listResourceActivity('resource-1');

        expect(mockInvoke).toHaveBeenCalledWith('list_resource_activity', {
          resource_id: 'resource-1',
          page: null,
          page_size: null,
        });
        expect(result).toEqual(mockResponse);
      });

      it('should call invoke with all params', async () => {
        const mockResponse = { items: [{ id: 'act-1' }], total: 1, page: 3, page_size: 5 };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listResourceActivity('resource-1', 3, 5);

        expect(mockInvoke).toHaveBeenCalledWith('list_resource_activity', {
          resource_id: 'resource-1',
          page: 3,
          page_size: 5,
        });
        expect(result).toEqual(mockResponse);
      });
    });

    describe('listAdminActivity', () => {
      it('should call invoke with null params when none provided', async () => {
        const mockResponse = { items: [], total: 0, page: 1, page_size: 20 };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listAdminActivity();

        expect(mockInvoke).toHaveBeenCalledWith('list_admin_activity', {
          page: null,
          page_size: null,
          actor_id: null,
          event_type: null,
          resource_type: null,
          from: null,
          to: null,
          search: null,
        });
        expect(result).toEqual(mockResponse);
      });

      it('should call invoke with all mapped params', async () => {
        const mockResponse = { items: [{ id: 'act-1' }], total: 1, page: 1, page_size: 50 };
        mockInvoke.mockResolvedValueOnce(mockResponse);

        const result = await tauriService.listAdminActivity({
          page: 1,
          pageSize: 50,
          actorId: 'user-1',
          eventType: 'share.create',
          resourceType: 'folder',
          from: '2025-06-01',
          to: '2025-06-30',
          search: 'quarterly',
        });

        expect(mockInvoke).toHaveBeenCalledWith('list_admin_activity', {
          page: 1,
          page_size: 50,
          actor_id: 'user-1',
          event_type: 'share.create',
          resource_type: 'folder',
          from: '2025-06-01',
          to: '2025-06-30',
          search: 'quarterly',
        });
        expect(result).toEqual(mockResponse);
      });
    });
  });

  // ==================== Crypto Commands ====================

  describe('crypto operations', () => {
    it('should encrypt file', async () => {
      mockInvoke.mockResolvedValueOnce({
        ciphertext_path: '/tmp/encrypted.bin',
        file_key: 'enc-key',
        nonce: 'nonce-123',
      });

      const result = await tauriService.encryptFile('/path/file.pdf', 'folder-key', 'file-id');

      expect(mockInvoke).toHaveBeenCalledWith('encrypt_file', {
        filePath: '/path/file.pdf',
        folderKey: 'folder-key',
        fileId: 'file-id',
      });
      expect(result.ciphertext_path).toBe('/tmp/encrypted.bin');
      expect(result.file_key).toBe('enc-key');
      expect(result.nonce).toBe('nonce-123');
    });

    it('should decrypt file', async () => {
      mockInvoke.mockResolvedValueOnce({ plaintext_path: '/path/decrypted.pdf' });

      const result = await tauriService.decryptFile('/tmp/encrypted.bin', 'folder-key', 'file-id');

      expect(mockInvoke).toHaveBeenCalledWith('decrypt_file', {
        ciphertextPath: '/tmp/encrypted.bin',
        folderKey: 'folder-key',
        fileId: 'file-id',
      });
      expect(result.plaintext_path).toBe('/path/decrypted.pdf');
    });

    it('should decapsulate folder key', async () => {
      mockInvoke.mockResolvedValueOnce({ folder_key: 'decapsulated-key' });

      const result = await tauriService.decapsulateFolderKey(
        'kem-ciphertext',
        'wrapped-key',
        'ml-kem-sk',
        'kaz-kem-sk'
      );

      expect(mockInvoke).toHaveBeenCalledWith('decapsulate_folder_key', {
        kemCiphertext: 'kem-ciphertext',
        wrappedFolderKey: 'wrapped-key',
        encryptedMlKemSk: 'ml-kem-sk',
        encryptedKazKemSk: 'kaz-kem-sk',
      });
      expect(result.folder_key).toBe('decapsulated-key');
    });

    it('should get folder encryption metadata', async () => {
      const mockMeta = {
        kem_ciphertext: 'kem-ct',
        wrapped_folder_key: 'wrapped-key',
        encrypted_ml_kem_sk: 'ml-sk',
        encrypted_kaz_kem_sk: 'kaz-sk',
      };
      mockInvoke.mockResolvedValueOnce(mockMeta);

      const result = await tauriService.getFolderEncryptionMetadata('folder-1');

      expect(mockInvoke).toHaveBeenCalledWith('get_folder_encryption_metadata', {
        folderId: 'folder-1',
      });
      expect(result).toEqual(mockMeta);
    });

    it('should get file metadata', async () => {
      const mockMeta = {
        id: 'file-1',
        name: 'Document.pdf',
        folder_id: 'folder-1',
        encrypted_file_key: 'enc-key',
        nonce: 'nonce-123',
        algorithm: 'AES-256-GCM',
      };
      mockInvoke.mockResolvedValueOnce(mockMeta);

      const result = await tauriService.getFileMetadata('file-1');

      expect(mockInvoke).toHaveBeenCalledWith('get_file_metadata', { fileId: 'file-1' });
      expect(result).toEqual(mockMeta);
    });
  });
});
