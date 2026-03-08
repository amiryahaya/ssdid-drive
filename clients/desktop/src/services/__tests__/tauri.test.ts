import { describe, it, expect, vi, beforeEach } from 'vitest';
import { invoke } from '@tauri-apps/api/core';
import { tauriService } from '../tauri';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

describe('createChallenge', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.resetModules();
  });

  it('should call backend login/initiate and return subscriberSecret', async () => {
    const mockResponse = {
      challenge_id: 'abc123',
      subscriber_secret: 'secret-xyz',
      qr_payload: {
        action: 'login',
        service_url: 'http://localhost:5147',
        service_name: 'ssdid-drive',
        challenge_id: 'abc123',
        challenge: 'base64challenge',
        server_did: 'did:ssdid:test',
        server_key_id: 'did:ssdid:test#key-1',
        server_signature: 'sig123',
        registry_url: 'https://registry.ssdid.my',
      },
    };

    // Mock invoke to reject (so getApiBaseUrl falls back to env/default)
    mockInvoke.mockRejectedValue(new Error('not available'));

    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const { createChallenge } = await import('../tauri');
    const result = await createChallenge('authenticate');

    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/auth/ssdid/login/initiate'),
      expect.objectContaining({ method: 'POST' })
    );
    expect(result.challengeId).toBe('abc123');
    expect(result.subscriberSecret).toBe('secret-xyz');
    expect(result.serverDid).toBe('did:ssdid:test');
    expect(result.qrPayload).toContain('abc123');
  });

  it('should throw on non-ok response', async () => {
    mockInvoke.mockRejectedValue(new Error('not available'));

    global.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
      statusText: 'Internal Server Error',
    });

    const { createChallenge } = await import('../tauri');
    await expect(createChallenge('authenticate')).rejects.toThrow('Login initiate failed');
  });
});

describe('tauriService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // ==================== Auth Commands ====================

  describe('auth commands', () => {
    describe('login', () => {
      it('should call invoke with correct parameters', async () => {
        const mockUser = { id: 'user-1', email: 'test@example.com', name: 'Test' };
        mockInvoke.mockResolvedValueOnce({ user: mockUser });

        const result = await tauriService.login('test@example.com', 'password123');

        expect(mockInvoke).toHaveBeenCalledWith('login', {
          email: 'test@example.com',
          password: 'password123',
        });
        expect(result).toEqual({ user: mockUser });
      });
    });

    describe('register', () => {
      it('should call invoke with correct parameters', async () => {
        const mockUser = { id: 'user-1', email: 'test@example.com', name: 'Test' };
        mockInvoke.mockResolvedValueOnce({ user: mockUser });

        const result = await tauriService.register(
          'test@example.com',
          'password123',
          'Test User',
          'invite-token'
        );

        expect(mockInvoke).toHaveBeenCalledWith('register', {
          email: 'test@example.com',
          password: 'password123',
          name: 'Test User',
          invitationToken: 'invite-token',
        });
        expect(result).toEqual({ user: mockUser });
      });
    });

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
        const mockFolder = { id: 'folder-1', name: 'New Folder', item_type: 'folder' };
        mockInvoke.mockResolvedValueOnce(mockFolder);

        const result = await tauriService.createFolder('New Folder', 'parent-1');

        expect(mockInvoke).toHaveBeenCalledWith('create_folder', {
          name: 'New Folder',
          parentId: 'parent-1',
        });
        expect(result).toEqual(mockFolder);
      });

      it('should use null for parentId when not provided', async () => {
        const mockFolder = { id: 'folder-1', name: 'New Folder', item_type: 'folder' };
        mockInvoke.mockResolvedValueOnce(mockFolder);

        await tauriService.createFolder('New Folder');

        expect(mockInvoke).toHaveBeenCalledWith('create_folder', {
          name: 'New Folder',
          parentId: null,
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
});
