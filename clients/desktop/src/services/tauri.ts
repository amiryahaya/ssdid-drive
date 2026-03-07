import { invoke } from '@tauri-apps/api/core';
import type {
  User,
  AuthStatus,
  FileListResponse,
  FileItem,
  FilePreview,
  ShareListResponse,
  Share,
  RecipientSearchResult,
  CreateShareRequest,
  CreateShareResponse,
  AppSettings,
  StorageInfo,
  PiiConversation,
  RegisterKemKeysResponse,
  DecryptedAskResponse,
} from '../types';

// ==================== SSDID Auth Helpers ====================

export interface ServerInfo {
  serverDid: string;
  serverUrl: string;
}

export interface ChallengeResult {
  serverDid: string;
  challengeId: string;
  qrPayload: string;
}

/**
 * Fetch server info from the SSDID auth endpoint.
 * For now, returns mock data until the backend is wired up.
 */
async function fetchServerInfo(): Promise<ServerInfo> {
  try {
    const info = await invoke<ServerInfo>('get_server_info');
    return info;
  } catch {
    // Fallback: derive from environment or use defaults
    return {
      serverDid: 'did:ssdid:server:ssdid-drive',
      serverUrl: 'https://api.ssdid-drive.local',
    };
  }
}

/**
 * Create a challenge for QR-based SSDID wallet authentication.
 * Generates a random challenge ID client-side until backend challenge
 * creation is wired up.
 */
export async function createChallenge(
  action: 'authenticate' | 'register'
): Promise<ChallengeResult> {
  const serverInfo = await fetchServerInfo();

  // Generate a random challenge ID (will be replaced by server-issued ID)
  const randomBytes = new Uint8Array(16);
  crypto.getRandomValues(randomBytes);
  const challengeId = Array.from(randomBytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  const qrPayload = JSON.stringify({
    server_url: serverInfo.serverUrl,
    server_did: serverInfo.serverDid,
    action,
    challenge_id: challengeId,
  });

  return {
    serverDid: serverInfo.serverDid,
    challengeId,
    qrPayload,
  };
}

/**
 * Tauri command wrapper service
 * Provides typed access to all backend commands
 */
export const tauriService = {
  // ==================== Auth Commands ====================

  async logout(): Promise<void> {
    return invoke('logout');
  },

  async getCurrentUser(): Promise<User | null> {
    return invoke('get_current_user');
  },

  async checkAuthStatus(): Promise<AuthStatus> {
    return invoke('check_auth_status');
  },

  async unlockWithBiometric(): Promise<boolean> {
    return invoke('unlock_with_biometric');
  },

  async updateProfile(name: string): Promise<User> {
    return invoke('update_profile', { name });
  },

  async listDevices(): Promise<{ id: string; name: string | null; device_type: string; last_active: string; created_at: string; is_current: boolean }[]> {
    return invoke('list_devices');
  },

  async revokeDevice(deviceId: string): Promise<void> {
    return invoke('revoke_device', { deviceId });
  },

  // ==================== SSDID Auth Commands ====================

  async getServerInfo(): Promise<ServerInfo> {
    return fetchServerInfo();
  },

  async createChallenge(action: 'authenticate' | 'register'): Promise<ChallengeResult> {
    return createChallenge(action);
  },

  // ==================== File Commands ====================

  async listFiles(folderId?: string): Promise<FileListResponse> {
    return invoke('list_files', { folderId: folderId ?? null });
  },

  async uploadFile(
    filePath: string,
    folderId?: string,
    fileName?: string
  ): Promise<FileItem> {
    return invoke('upload_file', {
      filePath,
      folderId: folderId ?? null,
      fileName: fileName ?? null,
    });
  },

  async downloadFile(fileId: string, destination: string): Promise<string> {
    return invoke('download_file', { fileId, destination });
  },

  async createFolder(name: string, parentId?: string): Promise<FileItem> {
    return invoke('create_folder', {
      name,
      parentId: parentId ?? null,
    });
  },

  async deleteItem(itemId: string): Promise<void> {
    return invoke('delete_item', { itemId });
  },

  async renameItem(itemId: string, newName: string): Promise<FileItem> {
    return invoke('rename_item', { itemId, newName });
  },

  async moveItem(itemId: string, newFolderId?: string): Promise<FileItem> {
    return invoke('move_item', {
      itemId,
      newFolderId: newFolderId ?? null,
    });
  },

  async getFilePreview(fileId: string): Promise<FilePreview> {
    return invoke('get_file_preview', { fileId });
  },

  // ==================== Sharing Commands ====================

  async searchRecipients(query: string): Promise<RecipientSearchResult[]> {
    return invoke('search_recipients', { query });
  },

  async createShare(request: CreateShareRequest): Promise<CreateShareResponse> {
    return invoke('create_share', { request });
  },

  async revokeShare(shareId: string): Promise<void> {
    return invoke('revoke_share', { shareId });
  },

  async updateShare(
    shareId: string,
    permission: string,
    expiresAt?: string
  ): Promise<Share> {
    return invoke('update_share', {
      shareId,
      permission,
      expiresAt: expiresAt ?? null,
    });
  },

  async listMyShares(): Promise<ShareListResponse> {
    return invoke('list_my_shares');
  },

  async listSharedWithMe(): Promise<ShareListResponse> {
    return invoke('list_shared_with_me');
  },

  async getSharesForItem(itemId: string): Promise<ShareListResponse> {
    return invoke('get_shares_for_item', { itemId });
  },

  async getShareDetails(shareId: string): Promise<Share> {
    return invoke('get_share_details', { shareId });
  },

  async updateSharePermission(shareId: string, permission: string): Promise<Share> {
    return invoke('update_share_permission', { shareId, permission });
  },

  async setShareExpiry(shareId: string, expiresAt: string | null): Promise<Share> {
    return invoke('set_share_expiry', { shareId, expiresAt });
  },

  async acceptShare(shareId: string): Promise<Share> {
    return invoke('accept_share', { shareId });
  },

  async declineShare(shareId: string): Promise<void> {
    return invoke('decline_share', { shareId });
  },

  // ==================== Settings Commands ====================

  async getSettings(): Promise<AppSettings> {
    return invoke('get_settings');
  },

  async updateSettings(settings: Partial<AppSettings>): Promise<AppSettings> {
    return invoke('update_settings', { settings });
  },

  async getStorageInfo(): Promise<StorageInfo> {
    return invoke('get_storage_info');
  },

  async clearCache(): Promise<void> {
    return invoke('clear_cache');
  },

  // ==================== PII Service Commands ====================

  async piiCreateConversation(
    llmProvider: string,
    llmModel: string,
    title?: string
  ): Promise<PiiConversation> {
    return invoke('pii_create_conversation', {
      title: title ?? null,
      llmProvider,
      llmModel,
    });
  },

  async piiGetConversation(conversationId: string): Promise<PiiConversation> {
    return invoke('pii_get_conversation', { conversationId });
  },

  async piiListConversations(): Promise<PiiConversation[]> {
    return invoke('pii_list_conversations');
  },

  async piiRegisterKemKeys(
    conversationId: string,
    includeKazKem: boolean = false
  ): Promise<RegisterKemKeysResponse> {
    return invoke('pii_register_kem_keys', { conversationId, includeKazKem });
  },

  async piiAsk(
    conversationId: string,
    message: string,
    contextFiles?: string[]
  ): Promise<DecryptedAskResponse> {
    return invoke('pii_ask', {
      conversationId,
      message,
      contextFiles: contextFiles ?? null,
    });
  },

  async piiClearKemKeys(): Promise<void> {
    return invoke('pii_clear_kem_keys');
  },
};

export default tauriService;
