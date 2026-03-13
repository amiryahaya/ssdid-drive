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

// ==================== Activity Types ====================

export interface ActivityItem {
  id: string;
  actor_id: string;
  actor_name: string | null;
  event_type: string;
  resource_type: string;
  resource_id: string;
  resource_name: string;
  details: Record<string, unknown> | null;
  created_at: string;
}

export interface ActivityResponse {
  items: ActivityItem[];
  total: number;
  page: number;
  page_size: number;
}

// ==================== Recovery Types ====================

export interface RecoveryStatus {
  is_active: boolean;
  created_at: string | null;
}

export interface SplitResult {
  file1: string;
  file2: string;
  server_share: string;
  key_proof: string;
}

export interface RecoverResult {
  master_key_b64: string;
  user_did: string;
}

// ==================== SSDID Auth Helpers ====================

export interface ChallengeResult {
  serverDid: string;
  challengeId: string;
  subscriberSecret: string;
  qrPayload: string;
}

/**
 * Create a challenge by calling the backend via Tauri command (bypasses CORS).
 */
export async function createChallenge(
  _action: 'authenticate' | 'register'
): Promise<ChallengeResult> {
  const data = await invoke<{
    challenge_id: string;
    subscriber_secret: string;
    qr_payload: string;
    server_did: string;
  }>('create_challenge');

  return {
    serverDid: data.server_did,
    challengeId: data.challenge_id,
    subscriberSecret: data.subscriber_secret,
    qrPayload: data.qr_payload,
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

  // ==================== Activity Commands ====================

  async listActivity(params?: {
    page?: number;
    pageSize?: number;
    eventType?: string;
    resourceType?: string;
    from?: string;
    to?: string;
  }): Promise<ActivityResponse> {
    return invoke('list_activity', {
      page: params?.page ?? null,
      page_size: params?.pageSize ?? null,
      event_type: params?.eventType ?? null,
      resource_type: params?.resourceType ?? null,
      from: params?.from ?? null,
      to: params?.to ?? null,
    });
  },

  async listResourceActivity(
    resourceId: string,
    page?: number,
    pageSize?: number,
  ): Promise<ActivityResponse> {
    return invoke('list_resource_activity', {
      resource_id: resourceId,
      page: page ?? null,
      page_size: pageSize ?? null,
    });
  },

  async listAdminActivity(params?: {
    page?: number;
    pageSize?: number;
    actorId?: string;
    eventType?: string;
    resourceType?: string;
    from?: string;
    to?: string;
    search?: string;
  }): Promise<ActivityResponse> {
    return invoke('list_admin_activity', {
      page: params?.page ?? null,
      page_size: params?.pageSize ?? null,
      actor_id: params?.actorId ?? null,
      event_type: params?.eventType ?? null,
      resource_type: params?.resourceType ?? null,
      from: params?.from ?? null,
      to: params?.to ?? null,
      search: params?.search ?? null,
    });
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

  // ==================== Recovery Commands ====================

  async getRecoveryStatus(): Promise<RecoveryStatus> {
    return invoke('get_recovery_status');
  },

  async splitMasterKey(): Promise<SplitResult> {
    return invoke('split_master_key');
  },

  async setupRecovery(serverShare: string, keyProof: string): Promise<void> {
    return invoke('setup_recovery', { server_share: serverShare, key_proof: keyProof });
  },

  async recoverWithFiles(file1Contents: string, file2Contents: string): Promise<RecoverResult> {
    return invoke('recover_with_files', { file1_contents: file1Contents, file2_contents: file2Contents });
  },

  async recoverWithFileAndServer(fileContents: string): Promise<RecoverResult> {
    return invoke('recover_with_file_and_server', { file_contents: fileContents });
  },

  async deleteRecoverySetup(): Promise<void> {
    return invoke('delete_recovery_setup');
  },
};

export default tauriService;
