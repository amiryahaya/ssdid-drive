import { invoke } from '@tauri-apps/api/core';
import type {
  User,
  AuthStatus,
  AuthProvider,
  OidcCallbackResponse,
  WebAuthnBeginResponse,
  WebAuthnLoginResponse,
  UserCredential,
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

/**
 * Tauri command wrapper service
 * Provides typed access to all backend commands
 */
export const tauriService = {
  // ==================== Auth Commands ====================

  async login(email: string, password: string): Promise<{ user: User }> {
    return invoke('login', { email, password });
  },

  async register(
    email: string,
    password: string,
    name: string,
    invitationToken: string
  ): Promise<{ user: User }> {
    return invoke('register', {
      email,
      password,
      name,
      invitationToken,
    });
  },

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

  // ==================== OIDC Commands ====================

  async oidcGetProviders(tenantSlug: string): Promise<AuthProvider[]> {
    return invoke('oidc_get_providers', { tenantSlug });
  },

  async oidcBeginLogin(providerId: string): Promise<string> {
    return invoke('oidc_begin_login', { providerId });
  },

  async oidcHandleCallback(
    code: string,
    oidcState: string
  ): Promise<OidcCallbackResponse> {
    return invoke('oidc_handle_callback', { code, oidcState });
  },

  async oidcCompleteRegistration(
    providerId: string,
    oidcSub: string,
    email: string,
    name: string,
    keyMaterial: string,
    keySalt: string
  ): Promise<{ user: User }> {
    return invoke('oidc_complete_registration', {
      providerId,
      oidcSub,
      email,
      name,
      keyMaterial,
      keySalt,
    });
  },

  // ==================== WebAuthn Commands ====================

  async webauthnLoginBegin(email?: string): Promise<WebAuthnBeginResponse> {
    return invoke('webauthn_login_begin', { email: email ?? null });
  },

  async webauthnLoginComplete(
    challengeId: string,
    assertion: Record<string, unknown>,
    prfOutput?: string
  ): Promise<WebAuthnLoginResponse> {
    return invoke('webauthn_login_complete', {
      challengeId,
      assertion,
      prfOutput: prfOutput ?? null,
    });
  },

  async webauthnRegisterBegin(
    email: string,
    tenantSlug?: string
  ): Promise<WebAuthnBeginResponse> {
    return invoke('webauthn_register_begin', {
      email,
      tenantSlug: tenantSlug ?? null,
    });
  },

  async webauthnRegisterComplete(
    request: Record<string, unknown>
  ): Promise<WebAuthnLoginResponse> {
    return invoke('webauthn_register_complete', { request });
  },

  async webauthnAddCredentialBegin(): Promise<WebAuthnBeginResponse> {
    return invoke('webauthn_add_credential_begin');
  },

  async webauthnAddCredentialComplete(
    request: Record<string, unknown>
  ): Promise<unknown> {
    return invoke('webauthn_add_credential_complete', { request });
  },

  // ==================== Credential Commands ====================

  async listCredentials(): Promise<UserCredential[]> {
    return invoke('list_credentials');
  },

  async renameCredential(credentialId: string, name: string): Promise<UserCredential> {
    return invoke('rename_credential', { credentialId, name });
  },

  async deleteCredential(credentialId: string): Promise<void> {
    return invoke('delete_credential', { credentialId });
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

  /**
   * Create a new PII service conversation
   */
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

  /**
   * Get a PII service conversation by ID
   */
  async piiGetConversation(conversationId: string): Promise<PiiConversation> {
    return invoke('pii_get_conversation', { conversationId });
  },

  /**
   * List all PII service conversations
   */
  async piiListConversations(): Promise<PiiConversation[]> {
    return invoke('pii_list_conversations');
  },

  /**
   * Register KEM keys for a conversation
   *
   * This generates new ML-KEM (and optionally KAZ-KEM) keypairs,
   * registers the public keys with the PII service, and stores
   * the secret keys locally for DEK unwrapping.
   *
   * @param conversationId - The conversation to register keys for
   * @param includeKazKem - Whether to also generate KAZ-KEM keys for hybrid security
   */
  async piiRegisterKemKeys(
    conversationId: string,
    includeKazKem: boolean = false
  ): Promise<RegisterKemKeysResponse> {
    return invoke('pii_register_kem_keys', { conversationId, includeKazKem });
  },

  /**
   * Send a message to the PII service and get a response
   *
   * This automatically handles:
   * - Sending the message to the LLM via the PII service
   * - Unwrapping the KEM-encrypted DEK (if KEM keys were registered)
   * - Decrypting the token map
   * - Restoring original PII values in the response
   *
   * @param conversationId - The conversation to send the message to
   * @param message - The user's message
   * @param contextFiles - Optional file IDs to include as context
   */
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

  /**
   * Clear KEM secret keys from memory
   *
   * Call this when switching conversations or logging out
   */
  async piiClearKemKeys(): Promise<void> {
    return invoke('pii_clear_kem_keys');
  },
};

export default tauriService;
