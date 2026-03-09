import { vi } from 'vitest';
import type { Share, RecipientSearchResult } from '../../types';
import type { Notification } from '../../stores/notificationStore';

export const mockShares: Share[] = [
  {
    id: 'share-1',
    item_id: 'file-1',
    item_name: 'Document.pdf',
    item_type: 'file',
    owner_id: 'user-1',
    owner_email: 'owner@example.com',
    owner_name: 'Owner User',
    recipient_id: 'user-2',
    recipient_email: 'recipient@example.com',
    recipient_name: 'Recipient User',
    permission: 'read',
    status: 'pending',
    message: null,
    expires_at: null,
    created_at: '2024-01-15T10:00:00Z',
    updated_at: '2024-01-15T10:00:00Z',
  },
  {
    id: 'share-2',
    item_id: 'folder-1',
    item_name: 'Project Files',
    item_type: 'folder',
    owner_id: 'user-1',
    owner_email: 'owner@example.com',
    owner_name: 'Owner User',
    recipient_id: 'user-3',
    recipient_email: 'alice@example.com',
    recipient_name: 'Alice Smith',
    permission: 'write',
    status: 'accepted',
    message: 'Please review these files',
    expires_at: '2024-12-31T23:59:59Z',
    created_at: '2024-01-10T08:00:00Z',
    updated_at: '2024-01-11T09:00:00Z',
  },
];

export const mockRecipients: RecipientSearchResult[] = [
  { id: 'user-3', email: 'alice@example.com', name: 'Alice Smith' },
  { id: 'user-4', email: 'bob@example.com', name: 'Bob Jones' },
  { id: 'user-5', email: 'charlie@example.com', name: 'Charlie Brown' },
];

export const mockFileItem = {
  id: 'file-1',
  name: 'Document.pdf',
  type: 'file' as const,
  size: 1024 * 1024,
  mime_type: 'application/pdf',
  folder_id: null,
  is_shared: false,
  created_at: '2024-01-15T10:00:00Z',
  updated_at: '2024-01-15T10:00:00Z',
};

export const mockFolderItem = {
  id: 'folder-1',
  name: 'Project Files',
  type: 'folder' as const,
  size: 0,
  mime_type: null,
  folder_id: null,
  is_shared: true,
  created_at: '2024-01-10T08:00:00Z',
  updated_at: '2024-01-10T08:00:00Z',
};

export const mockImagePreview = {
  file_id: 'file-1',
  file_name: 'photo.png',
  mime_type: 'image/png',
  preview_data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  can_preview: true,
};

export const mockTextPreview = {
  file_id: 'file-2',
  file_name: 'readme.txt',
  mime_type: 'text/plain',
  preview_data: btoa('Hello, World!\nThis is a sample text file.'),
  can_preview: true,
};

export const mockUnsupportedPreview = {
  file_id: 'file-3',
  file_name: 'archive.zip',
  mime_type: 'application/zip',
  preview_data: null,
  can_preview: false,
};

// Auth mock data
export const mockUser = {
  id: 'user-1',
  email: 'test@example.com',
  name: 'Test User',
  tenantId: 'tenant-1',
};

export const mockAuthStatus = {
  is_authenticated: true,
  is_locked: false,
  user: mockUser,
};

export const mockAuthStatusLocked = {
  is_authenticated: true,
  is_locked: true,
  user: mockUser,
};

export const mockAuthStatusUnauthenticated = {
  is_authenticated: false,
  is_locked: true,
  user: null,
};

export const mockNotifications: Notification[] = [
  {
    id: 'notif-1',
    type: 'share_received',
    title: 'New share received',
    message: 'Alice Smith shared "Document.pdf" with you',
    read: false,
    created_at: new Date(Date.now() - 1000 * 60 * 5).toISOString(),
    metadata: { share_id: 'share-1', item_name: 'Document.pdf' },
  },
  {
    id: 'notif-2',
    type: 'share_accepted',
    title: 'Share accepted',
    message: 'Bob Jones accepted your share of "Project Files"',
    read: false,
    created_at: new Date(Date.now() - 1000 * 60 * 60 * 2).toISOString(),
  },
  {
    id: 'notif-3',
    type: 'system',
    title: 'System update',
    message: 'Your encryption keys have been rotated successfully',
    read: true,
    created_at: new Date(Date.now() - 1000 * 60 * 60 * 24).toISOString(),
  },
  {
    id: 'notif-4',
    type: 'recovery_request',
    title: 'Recovery request',
    message: 'Charlie Brown has requested key recovery assistance',
    read: false,
    created_at: new Date(Date.now() - 1000 * 60 * 30).toISOString(),
    metadata: { requester_name: 'Charlie Brown' },
  },
];

export function createTauriMocks() {
  return {
    // Auth mocks
    login: vi.fn().mockResolvedValue({ user: mockUser }),
    register: vi.fn().mockResolvedValue({ user: mockUser }),
    logout: vi.fn().mockResolvedValue(undefined),
    checkAuthStatus: vi.fn().mockResolvedValue(mockAuthStatus),
    unlockWithBiometric: vi.fn().mockResolvedValue(true),
    // Share mocks
    listMyShares: vi.fn().mockResolvedValue({ shares: mockShares }),
    listSharedWithMe: vi.fn().mockResolvedValue({ shares: mockShares }),
    getSharesForItem: vi.fn().mockResolvedValue({ shares: mockShares }),
    searchRecipients: vi.fn().mockResolvedValue(mockRecipients),
    createShare: vi.fn().mockResolvedValue({ share: mockShares[0] }),
    revokeShare: vi.fn().mockResolvedValue(undefined),
    updateShare: vi.fn().mockResolvedValue(mockShares[0]),
    updateSharePermission: vi.fn().mockResolvedValue(mockShares[0]),
    setShareExpiry: vi.fn().mockResolvedValue(mockShares[0]),
    acceptShare: vi.fn().mockResolvedValue({ ...mockShares[0], status: 'accepted' }),
    declineShare: vi.fn().mockResolvedValue(undefined),
    // File mocks
    listFiles: vi.fn().mockResolvedValue({
      items: [mockFileItem, mockFolderItem],
      current_folder: null,
      breadcrumbs: [],
    }),
    createFolder: vi.fn().mockResolvedValue(mockFolderItem),
    renameItem: vi.fn().mockResolvedValue({ ...mockFileItem, name: 'Renamed.pdf' }),
    deleteItem: vi.fn().mockResolvedValue(undefined),
    getFilePreview: vi.fn().mockResolvedValue(mockImagePreview),
    // Notification mocks
    getNotifications: vi.fn().mockResolvedValue(mockNotifications),
    markNotificationRead: vi.fn().mockResolvedValue(undefined),
    markAllNotificationsRead: vi.fn().mockResolvedValue(undefined),
  };
}

export async function setupTauriMocks(mocks = createTauriMocks()) {
  const { invoke } = vi.mocked(await import('@tauri-apps/api/core'));

  invoke.mockImplementation(async (cmd: string, args?: unknown) => {
    const typedArgs = args as Record<string, unknown> | undefined;
    switch (cmd) {
      // Auth commands
      case 'login':
        return mocks.login(typedArgs?.email as string, typedArgs?.password as string);
      case 'register':
        return mocks.register(
          typedArgs?.email as string,
          typedArgs?.password as string,
          typedArgs?.name as string,
          typedArgs?.invitationToken as string
        );
      case 'logout':
        return mocks.logout();
      case 'check_auth_status':
        return mocks.checkAuthStatus();
      case 'unlock_with_biometric':
        return mocks.unlockWithBiometric();
      // Share commands
      case 'list_my_shares':
        return mocks.listMyShares();
      case 'list_shared_with_me':
        return mocks.listSharedWithMe();
      case 'search_recipients':
        return mocks.searchRecipients(typedArgs?.query as string);
      case 'create_share':
        return mocks.createShare(typedArgs?.request);
      case 'revoke_share':
        return mocks.revokeShare(typedArgs?.shareId as string);
      case 'update_share':
        return mocks.updateShare(typedArgs?.shareId as string, typedArgs?.permission as string);
      case 'get_shares_for_item':
        return mocks.getSharesForItem(typedArgs?.itemId as string);
      case 'update_share_permission':
        return mocks.updateSharePermission(typedArgs?.shareId as string, typedArgs?.permission as string);
      case 'set_share_expiry':
        return mocks.setShareExpiry(typedArgs?.shareId as string, typedArgs?.expiresAt as string | null);
      case 'accept_share':
        return mocks.acceptShare(typedArgs?.shareId as string);
      case 'decline_share':
        return mocks.declineShare(typedArgs?.shareId as string);
      case 'list_files':
        return mocks.listFiles(typedArgs?.folderId as string | undefined);
      case 'create_folder':
        return mocks.createFolder(typedArgs?.name as string, typedArgs?.parentId as string | undefined);
      case 'rename_item':
        return mocks.renameItem(typedArgs?.itemId as string, typedArgs?.newName as string);
      case 'delete_item':
        return mocks.deleteItem(typedArgs?.itemId as string);
      case 'get_file_preview':
        return mocks.getFilePreview(typedArgs?.fileId as string);
      // Notification commands
      case 'get_notifications':
        return mocks.getNotifications();
      case 'mark_notification_read':
        return mocks.markNotificationRead(typedArgs?.notificationId as string);
      case 'mark_all_notifications_read':
        return mocks.markAllNotificationsRead();
      default:
        console.warn(`Unhandled mock command: ${cmd}`);
        return undefined;
    }
  });

  return { invoke, mocks };
}
