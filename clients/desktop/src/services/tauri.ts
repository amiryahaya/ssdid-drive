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

export interface ChallengeResult {
  serverDid: string;
  challengeId: string;
  subscriberSecret: string;
  qrPayload: string;
}

async function getApiBaseUrl(): Promise<string> {
  try {
    const info = await invoke<{ api_base_url: string }>('get_api_base_url');
    return info.api_base_url;
  } catch {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return (import.meta as any).env?.VITE_API_BASE_URL ?? 'http://localhost:5147';
  }
}

/**
 * Create a challenge by calling the backend login/initiate endpoint.
 */
export async function createChallenge(
  _action: 'authenticate' | 'register'
): Promise<ChallengeResult> {
  const baseUrl = await getApiBaseUrl();
  const resp = await fetch(`${baseUrl}/api/auth/ssdid/login/initiate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });

  if (!resp.ok) {
    throw new Error(`Login initiate failed: ${resp.status} ${resp.statusText}`);
  }

  const data = await resp.json();

  if (!data?.challenge_id || !data?.subscriber_secret || !data?.qr_payload?.server_did) {
    throw new Error('Unexpected response from login/initiate');
  }

  return {
    serverDid: data.qr_payload.server_did,
    challengeId: data.challenge_id,
    subscriberSecret: data.subscriber_secret,
    qrPayload: JSON.stringify(data.qr_payload),
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
    fileName?: string,
    fileId?: string,
    encryptedFileKey?: string,
    nonce?: string,
    algorithm?: string
  ): Promise<FileItem> {
    return invoke('upload_file', {
      filePath,
      folderId: folderId ?? null,
      fileName: fileName ?? null,
      fileId: fileId ?? null,
      encryptedFileKey: encryptedFileKey ?? null,
      nonce: nonce ?? null,
      algorithm: algorithm ?? null,
    });
  },

  async downloadFile(fileId: string, destination: string): Promise<string> {
    return invoke('download_file', { fileId, destination });
  },

  async createFolder(name: string, parentId?: string): Promise<FileItem> {
    // Fetch user's KEM public keys for folder key encapsulation
    const keys = await invoke<{ ml_kem_pk: string; kaz_kem_pk: string }>('get_user_kem_public_keys');

    return invoke('create_folder', {
      name,
      parentId: parentId ?? null,
      mlKemPk: keys.ml_kem_pk,
      kazKemPk: keys.kaz_kem_pk,
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

  async getFileMetadata(fileId: string): Promise<{
    id: string;
    name: string;
    folder_id: string | null;
    encrypted_file_key: string | null;
    nonce: string | null;
    algorithm: string | null;
  }> {
    return invoke('get_file_metadata', { fileId });
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

  // ==================== Crypto Commands ====================

  async encryptFile(
    filePath: string,
    folderKey: string,
    fileId: string
  ): Promise<{ ciphertext_path: string; file_key: string; nonce: string }> {
    return invoke('encrypt_file', { filePath, folderKey, fileId });
  },

  async decryptFile(
    ciphertextPath: string,
    folderKey: string,
    fileId: string
  ): Promise<{ plaintext_path: string }> {
    return invoke('decrypt_file', { ciphertextPath, folderKey, fileId });
  },

  async decapsulateFolderKey(
    kemCiphertext: string,
    wrappedFolderKey: string,
    encryptedMlKemSk: string,
    encryptedKazKemSk: string
  ): Promise<{ folder_key: string }> {
    return invoke('decapsulate_folder_key', {
      kemCiphertext,
      wrappedFolderKey,
      encryptedMlKemSk,
      encryptedKazKemSk,
    });
  },

  async getFolderEncryptionMetadata(
    folderId: string
  ): Promise<{
    kem_ciphertext: string;
    wrapped_folder_key: string;
    encrypted_ml_kem_sk: string;
    encrypted_kaz_kem_sk: string;
  }> {
    return invoke('get_folder_encryption_metadata', { folderId });
  },
};

export default tauriService;
