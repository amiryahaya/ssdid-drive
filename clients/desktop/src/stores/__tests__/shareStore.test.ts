import { describe, it, expect, beforeEach, vi } from 'vitest';
import { invoke } from '@tauri-apps/api/core';
import { useShareStore } from '../shareStore';
import { mockShares, mockRecipients } from '../../test/mocks/tauri';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

describe('shareStore', () => {
  beforeEach(() => {
    // Reset the store state
    useShareStore.setState({
      myShares: [],
      sharedWithMe: [],
      itemShares: [],
      searchResults: [],
      isLoading: false,
      isSearching: false,
      isCreating: false,
      isUpdating: false,
      error: null,
    });
    vi.clearAllMocks();
  });

  describe('loadMyShares', () => {
    it('should set loading state and fetch shares', async () => {
      mockInvoke.mockResolvedValueOnce({ shares: mockShares });

      const { loadMyShares } = useShareStore.getState();

      const loadPromise = loadMyShares();

      // Check loading state was set
      expect(useShareStore.getState().isLoading).toBe(true);

      await loadPromise;

      expect(mockInvoke).toHaveBeenCalledWith('list_my_shares');
      expect(useShareStore.getState().myShares).toEqual(mockShares);
      expect(useShareStore.getState().isLoading).toBe(false);
      expect(useShareStore.getState().error).toBeNull();
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Network error'));

      const { loadMyShares } = useShareStore.getState();
      await loadMyShares();

      expect(useShareStore.getState().error).toBe('Error: Network error');
      expect(useShareStore.getState().isLoading).toBe(false);
    });
  });

  describe('loadSharedWithMe', () => {
    it('should fetch shares shared with user', async () => {
      mockInvoke.mockResolvedValueOnce({ shares: mockShares });

      const { loadSharedWithMe } = useShareStore.getState();
      await loadSharedWithMe();

      expect(mockInvoke).toHaveBeenCalledWith('list_shared_with_me');
      expect(useShareStore.getState().sharedWithMe).toEqual(mockShares);
    });
  });

  describe('searchRecipients', () => {
    it('should clear results for queries shorter than 2 characters', async () => {
      useShareStore.setState({ searchResults: mockRecipients });

      const { searchRecipients } = useShareStore.getState();
      await searchRecipients('a');

      expect(mockInvoke).not.toHaveBeenCalled();
      expect(useShareStore.getState().searchResults).toEqual([]);
    });

    it('should search and return results', async () => {
      mockInvoke.mockResolvedValueOnce(mockRecipients);

      const { searchRecipients } = useShareStore.getState();
      await searchRecipients('alice');

      expect(mockInvoke).toHaveBeenCalledWith('search_recipients', { query: 'alice' });
      expect(useShareStore.getState().searchResults).toEqual(mockRecipients);
      expect(useShareStore.getState().isSearching).toBe(false);
    });

    it('should set searching state', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(mockRecipients), 100))
      );

      const { searchRecipients } = useShareStore.getState();
      const searchPromise = searchRecipients('alice');

      expect(useShareStore.getState().isSearching).toBe(true);

      await searchPromise;

      expect(useShareStore.getState().isSearching).toBe(false);
    });

    it('should clear results on search error', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Search failed'));

      const { searchRecipients } = useShareStore.getState();
      await searchRecipients('alice');

      expect(useShareStore.getState().searchResults).toEqual([]);
      expect(useShareStore.getState().isSearching).toBe(false);
    });
  });

  describe('createShare', () => {
    it('should create share and reload shares', async () => {
      mockInvoke
        .mockResolvedValueOnce({ share: mockShares[0] }) // createShare
        .mockResolvedValueOnce({ shares: mockShares }); // loadMyShares

      const { createShare } = useShareStore.getState();
      await createShare({
        item_id: 'file-1',
        recipient_email: 'recipient@example.com',
        permission: 'read',
      });

      expect(mockInvoke).toHaveBeenCalledWith('create_share', {
        request: {
          item_id: 'file-1',
          recipient_email: 'recipient@example.com',
          permission: 'read',
        },
      });
      expect(useShareStore.getState().myShares).toEqual(mockShares);
    });

    it('should set error and throw on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Create failed'));

      const { createShare } = useShareStore.getState();

      await expect(
        createShare({
          item_id: 'file-1',
          recipient_email: 'recipient@example.com',
          permission: 'read',
        })
      ).rejects.toThrow();

      expect(useShareStore.getState().error).toBe('Error: Create failed');
    });
  });

  describe('revokeShare', () => {
    it('should remove share from state', async () => {
      useShareStore.setState({ myShares: mockShares });
      mockInvoke.mockResolvedValueOnce(undefined);

      const { revokeShare } = useShareStore.getState();
      await revokeShare('share-1');

      expect(mockInvoke).toHaveBeenCalledWith('revoke_share', { shareId: 'share-1' });
      expect(useShareStore.getState().myShares).toHaveLength(1);
      expect(useShareStore.getState().myShares[0].id).toBe('share-2');
    });
  });

  describe('acceptShare', () => {
    it('should update share status in state', async () => {
      useShareStore.setState({ sharedWithMe: mockShares });
      const acceptedShare = { ...mockShares[0], status: 'accepted' as const };
      mockInvoke.mockResolvedValueOnce(acceptedShare);

      const { acceptShare } = useShareStore.getState();
      await acceptShare('share-1');

      expect(mockInvoke).toHaveBeenCalledWith('accept_share', { shareId: 'share-1' });
      const updatedShare = useShareStore.getState().sharedWithMe.find((s) => s.id === 'share-1');
      expect(updatedShare?.status).toBe('accepted');
    });
  });

  describe('declineShare', () => {
    it('should remove share from sharedWithMe state', async () => {
      useShareStore.setState({ sharedWithMe: mockShares });
      mockInvoke.mockResolvedValueOnce(undefined);

      const { declineShare } = useShareStore.getState();
      await declineShare('share-1');

      expect(mockInvoke).toHaveBeenCalledWith('decline_share', { shareId: 'share-1' });
      expect(useShareStore.getState().sharedWithMe).toHaveLength(1);
      expect(useShareStore.getState().sharedWithMe[0].id).toBe('share-2');
    });
  });

  describe('loadSharesForItem', () => {
    it('should set loading state and fetch shares for an item', async () => {
      mockInvoke.mockResolvedValueOnce({ shares: mockShares });

      const { loadSharesForItem } = useShareStore.getState();

      const loadPromise = loadSharesForItem('file-1');

      // Check loading state was set
      expect(useShareStore.getState().isLoading).toBe(true);

      await loadPromise;

      expect(mockInvoke).toHaveBeenCalledWith('get_shares_for_item', { itemId: 'file-1' });
      expect(useShareStore.getState().itemShares).toEqual(mockShares);
      expect(useShareStore.getState().isLoading).toBe(false);
      expect(useShareStore.getState().error).toBeNull();
    });

    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Network error'));

      const { loadSharesForItem } = useShareStore.getState();
      await loadSharesForItem('file-1');

      expect(useShareStore.getState().error).toBe('Error: Network error');
      expect(useShareStore.getState().isLoading).toBe(false);
      expect(useShareStore.getState().itemShares).toEqual([]);
    });

    it('should clear previous error when loading', async () => {
      useShareStore.setState({ error: 'Previous error' });
      mockInvoke.mockResolvedValueOnce({ shares: mockShares });

      const { loadSharesForItem } = useShareStore.getState();
      await loadSharesForItem('file-1');

      expect(useShareStore.getState().error).toBeNull();
    });
  });

  describe('updatePermission', () => {
    it('should update permission in both myShares and itemShares', async () => {
      useShareStore.setState({ myShares: mockShares, itemShares: mockShares });
      const updatedShare = { ...mockShares[0], permission: 'admin' as const };
      mockInvoke.mockResolvedValueOnce(updatedShare);

      const { updatePermission } = useShareStore.getState();
      await updatePermission('share-1', 'admin');

      expect(mockInvoke).toHaveBeenCalledWith('update_share_permission', {
        shareId: 'share-1',
        permission: 'admin',
      });

      const myShareUpdated = useShareStore.getState().myShares.find((s) => s.id === 'share-1');
      expect(myShareUpdated?.permission).toBe('admin');

      const itemShareUpdated = useShareStore.getState().itemShares.find((s) => s.id === 'share-1');
      expect(itemShareUpdated?.permission).toBe('admin');
    });

    it('should set isUpdating during the operation', async () => {
      useShareStore.setState({ myShares: mockShares, itemShares: mockShares });
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({ ...mockShares[0], permission: 'write' }), 100))
      );

      const { updatePermission } = useShareStore.getState();
      const updatePromise = updatePermission('share-1', 'write');

      expect(useShareStore.getState().isUpdating).toBe(true);

      await updatePromise;

      expect(useShareStore.getState().isUpdating).toBe(false);
    });

    it('should set error, reset isUpdating, and throw on failure', async () => {
      useShareStore.setState({ myShares: mockShares, itemShares: mockShares });
      mockInvoke.mockRejectedValueOnce(new Error('Permission update failed'));

      const { updatePermission } = useShareStore.getState();

      await expect(updatePermission('share-1', 'admin')).rejects.toThrow();

      expect(useShareStore.getState().error).toBe('Error: Permission update failed');
      expect(useShareStore.getState().isUpdating).toBe(false);
    });

    it('should not modify shares that do not match the id', async () => {
      useShareStore.setState({ myShares: mockShares, itemShares: mockShares });
      const updatedShare = { ...mockShares[0], permission: 'write' as const };
      mockInvoke.mockResolvedValueOnce(updatedShare);

      const { updatePermission } = useShareStore.getState();
      await updatePermission('share-1', 'write');

      // share-2 should be unchanged
      const otherShare = useShareStore.getState().myShares.find((s) => s.id === 'share-2');
      expect(otherShare?.permission).toBe('write'); // original value from mockShares[1]
    });
  });

  describe('setExpiry', () => {
    it('should set expiry date in both myShares and itemShares', async () => {
      useShareStore.setState({ myShares: mockShares, itemShares: mockShares });
      const expiryDate = '2025-06-30T23:59:59Z';
      const updatedShare = { ...mockShares[0], expires_at: expiryDate };
      mockInvoke.mockResolvedValueOnce(updatedShare);

      const { setExpiry } = useShareStore.getState();
      await setExpiry('share-1', expiryDate);

      expect(mockInvoke).toHaveBeenCalledWith('set_share_expiry', {
        shareId: 'share-1',
        expiresAt: expiryDate,
      });

      const myShareUpdated = useShareStore.getState().myShares.find((s) => s.id === 'share-1');
      expect(myShareUpdated?.expires_at).toBe(expiryDate);

      const itemShareUpdated = useShareStore.getState().itemShares.find((s) => s.id === 'share-1');
      expect(itemShareUpdated?.expires_at).toBe(expiryDate);
    });

    it('should remove expiry when passing null', async () => {
      const sharesWithExpiry = mockShares.map((s) => ({
        ...s,
        expires_at: '2025-01-01T00:00:00Z',
      }));
      useShareStore.setState({ myShares: sharesWithExpiry, itemShares: sharesWithExpiry });
      const updatedShare = { ...sharesWithExpiry[0], expires_at: null };
      mockInvoke.mockResolvedValueOnce(updatedShare);

      const { setExpiry } = useShareStore.getState();
      await setExpiry('share-1', null);

      expect(mockInvoke).toHaveBeenCalledWith('set_share_expiry', {
        shareId: 'share-1',
        expiresAt: null,
      });

      const myShareUpdated = useShareStore.getState().myShares.find((s) => s.id === 'share-1');
      expect(myShareUpdated?.expires_at).toBeNull();
    });

    it('should set isUpdating during the operation', async () => {
      useShareStore.setState({ myShares: mockShares, itemShares: mockShares });
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({ ...mockShares[0], expires_at: '2025-06-30T00:00:00Z' }), 100))
      );

      const { setExpiry } = useShareStore.getState();
      const expiryPromise = setExpiry('share-1', '2025-06-30T00:00:00Z');

      expect(useShareStore.getState().isUpdating).toBe(true);

      await expiryPromise;

      expect(useShareStore.getState().isUpdating).toBe(false);
    });

    it('should set error, reset isUpdating, and throw on failure', async () => {
      useShareStore.setState({ myShares: mockShares, itemShares: mockShares });
      mockInvoke.mockRejectedValueOnce(new Error('Expiry update failed'));

      const { setExpiry } = useShareStore.getState();

      await expect(setExpiry('share-1', '2025-06-30T00:00:00Z')).rejects.toThrow();

      expect(useShareStore.getState().error).toBe('Error: Expiry update failed');
      expect(useShareStore.getState().isUpdating).toBe(false);
    });

    it('should not modify shares that do not match the id', async () => {
      useShareStore.setState({ myShares: mockShares, itemShares: mockShares });
      const updatedShare = { ...mockShares[0], expires_at: '2025-12-31T00:00:00Z' };
      mockInvoke.mockResolvedValueOnce(updatedShare);

      const { setExpiry } = useShareStore.getState();
      await setExpiry('share-1', '2025-12-31T00:00:00Z');

      // share-2 should keep its original expiry
      const otherShare = useShareStore.getState().myShares.find((s) => s.id === 'share-2');
      expect(otherShare?.expires_at).toBe('2024-12-31T23:59:59Z'); // original from mockShares[1]
    });
  });

  describe('revokeShare itemShares', () => {
    it('should remove share from both myShares and itemShares', async () => {
      useShareStore.setState({ myShares: mockShares, itemShares: mockShares });
      mockInvoke.mockResolvedValueOnce(undefined);

      const { revokeShare } = useShareStore.getState();
      await revokeShare('share-1');

      expect(useShareStore.getState().myShares).toHaveLength(1);
      expect(useShareStore.getState().myShares[0].id).toBe('share-2');
      expect(useShareStore.getState().itemShares).toHaveLength(1);
      expect(useShareStore.getState().itemShares[0].id).toBe('share-2');
    });
  });

  describe('clearSearch', () => {
    it('should clear search results', () => {
      useShareStore.setState({ searchResults: mockRecipients });

      const { clearSearch } = useShareStore.getState();
      clearSearch();

      expect(useShareStore.getState().searchResults).toEqual([]);
    });
  });

  describe('clearError', () => {
    it('should clear error state', () => {
      useShareStore.setState({ error: 'Some error' });

      const { clearError } = useShareStore.getState();
      clearError();

      expect(useShareStore.getState().error).toBeNull();
    });
  });

  describe('loadSharedWithMe', () => {
    it('should set error on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Network error'));

      const { loadSharedWithMe } = useShareStore.getState();
      await loadSharedWithMe();

      expect(useShareStore.getState().error).toBe('Error: Network error');
      expect(useShareStore.getState().isLoading).toBe(false);
    });

    it('should set loading state', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve({ shares: mockShares }), 100))
      );

      const { loadSharedWithMe } = useShareStore.getState();
      const loadPromise = loadSharedWithMe();

      expect(useShareStore.getState().isLoading).toBe(true);

      await loadPromise;

      expect(useShareStore.getState().isLoading).toBe(false);
    });
  });

  describe('updateShare', () => {
    it('should update share in state', async () => {
      useShareStore.setState({ myShares: mockShares });
      const updatedShare = { ...mockShares[0], permission: 'write' as const };
      mockInvoke.mockResolvedValueOnce(updatedShare);

      const { updateShare } = useShareStore.getState();
      await updateShare('share-1', 'write');

      expect(mockInvoke).toHaveBeenCalledWith('update_share', {
        shareId: 'share-1',
        permission: 'write',
        expiresAt: null,
      });

      const updated = useShareStore.getState().myShares.find((s) => s.id === 'share-1');
      expect(updated?.permission).toBe('write');
    });

    it('should update share with expiration date', async () => {
      useShareStore.setState({ myShares: mockShares });
      const updatedShare = { ...mockShares[0], expires_at: '2024-12-31' };
      mockInvoke.mockResolvedValueOnce(updatedShare);

      const { updateShare } = useShareStore.getState();
      await updateShare('share-1', 'read', '2024-12-31');

      expect(mockInvoke).toHaveBeenCalledWith('update_share', {
        shareId: 'share-1',
        permission: 'read',
        expiresAt: '2024-12-31',
      });
    });

    it('should set error and throw on failure', async () => {
      useShareStore.setState({ myShares: mockShares });
      mockInvoke.mockRejectedValueOnce(new Error('Update failed'));

      const { updateShare } = useShareStore.getState();

      await expect(updateShare('share-1', 'write')).rejects.toThrow();

      expect(useShareStore.getState().error).toBe('Error: Update failed');
    });
  });

  describe('revokeShare error handling', () => {
    it('should set error and throw on failure', async () => {
      useShareStore.setState({ myShares: mockShares });
      mockInvoke.mockRejectedValueOnce(new Error('Revoke failed'));

      const { revokeShare } = useShareStore.getState();

      await expect(revokeShare('share-1')).rejects.toThrow();

      expect(useShareStore.getState().error).toBe('Error: Revoke failed');
      // Shares should not be removed on failure
      expect(useShareStore.getState().myShares).toHaveLength(2);
    });
  });

  describe('acceptShare error handling', () => {
    it('should set error and throw on failure', async () => {
      useShareStore.setState({ sharedWithMe: mockShares });
      mockInvoke.mockRejectedValueOnce(new Error('Accept failed'));

      const { acceptShare } = useShareStore.getState();

      await expect(acceptShare('share-1')).rejects.toThrow();

      expect(useShareStore.getState().error).toBe('Error: Accept failed');
    });
  });

  describe('declineShare error handling', () => {
    it('should set error and throw on failure', async () => {
      useShareStore.setState({ sharedWithMe: mockShares });
      mockInvoke.mockRejectedValueOnce(new Error('Decline failed'));

      const { declineShare } = useShareStore.getState();

      await expect(declineShare('share-1')).rejects.toThrow();

      expect(useShareStore.getState().error).toBe('Error: Decline failed');
      // Shares should not be removed on failure
      expect(useShareStore.getState().sharedWithMe).toHaveLength(2);
    });
  });
});
