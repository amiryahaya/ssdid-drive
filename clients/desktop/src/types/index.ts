// User types
export interface User {
  id: string;
  email: string;
  name: string;
  tenant_id: string;
  created_at: string;
  updated_at: string;
}

// Auth types
export interface AuthStatus {
  is_authenticated: boolean;
  is_locked: boolean;
  user: User | null;
}

// File types
export interface FileItem {
  id: string;
  name: string;
  type: 'file' | 'folder';
  size: number;
  mime_type: string | null;
  folder_id: string | null;
  is_shared: boolean;
  created_at: string;
  updated_at: string;
}

export interface FolderInfo {
  id: string;
  name: string;
}

export interface FileListResponse {
  items: FileItem[];
  current_folder: FolderInfo | null;
  breadcrumbs: FolderInfo[];
}

export interface FilePreview {
  file_id: string;
  file_name: string;
  mime_type: string;
  preview_data: string | null;
  can_preview: boolean;
}

// Share types
export type SharePermission = 'read' | 'write' | 'admin';
export type ShareStatus = 'pending' | 'accepted' | 'declined';

export interface Share {
  id: string;
  item_id: string;
  item_name: string;
  item_type: 'file' | 'folder';
  owner_id: string;
  owner_email: string;
  owner_name: string;
  recipient_id: string;
  recipient_email: string;
  recipient_name: string;
  permission: SharePermission;
  status: ShareStatus;
  message: string | null;
  expires_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface ShareListResponse {
  shares: Share[];
}

export interface RecipientSearchResult {
  id: string;
  email: string;
  name: string;
}

export interface CreateShareRequest {
  item_id: string;
  recipient_email: string;
  permission: SharePermission;
  expires_at?: string;
  message?: string;
}

export interface CreateShareResponse {
  share: Share;
}

// Upload/Download progress
export type UploadPhase = 'preparing' | 'encrypting' | 'uploading' | 'complete';
export type DownloadPhase = 'preparing' | 'downloading' | 'decrypting' | 'complete';

export interface UploadProgress {
  file_id: string;
  file_name: string;
  phase: UploadPhase;
  bytes_uploaded: number;
  total_bytes: number;
  progress_percent: number;
}

export interface DownloadProgress {
  file_id: string;
  file_name: string;
  phase: DownloadPhase;
  bytes_downloaded: number;
  total_bytes: number;
  progress_percent: number;
}

// Settings types
export type Theme = 'light' | 'dark' | 'system';

export interface AppSettings {
  theme: Theme;
  auto_lock_minutes: number;
  biometric_enabled: boolean;
  notifications_enabled: boolean;
  download_location: string;
}

export interface StorageInfo {
  used_bytes: number;
  total_bytes: number;
  file_count: number;
}

// Toast types
export type ToastType = 'success' | 'error' | 'info' | 'warning';

export interface Toast {
  id: string;
  type: ToastType;
  title: string;
  description?: string;
  duration?: number;
}

// Auth provider types
export interface AuthProvider {
  id: string;
  name: string;
  provider_type: string;
  tenant_id: string;
  client_id: string | null;
  issuer: string | null;
  enabled: boolean;
}

export interface OidcCallbackResponse {
  status: 'authenticated' | 'new_user';
  user: User | null;
  access_token: string | null;
  refresh_token: string | null;
  device_id: string | null;
  key_material: string | null;
  key_salt: string | null;
}

export interface WebAuthnBeginResponse {
  options: Record<string, unknown>;
  challenge_id: string;
}

export interface WebAuthnLoginResponse {
  user: User;
  access_token: string;
  refresh_token: string;
  device_id: string;
}

export interface UserCredential {
  id: string;
  credential_type: string;
  name: string | null;
  provider_name: string | null;
  created_at: string;
  last_used_at: string | null;
}

// PII Service types
export interface PiiConversation {
  id: string;
  title: string | null;
  status: string;
  llm_provider: string;
  llm_model: string;
  created_at: string;
}

export interface CreatePiiConversationRequest {
  title?: string;
  llm_provider: string;
  llm_model: string;
}

export interface RegisterKemKeysResponse {
  success: boolean;
  kem_keys_registered_at: string;
}

export interface DecryptedAskResponse {
  user_message_id: string;
  assistant_message_id: string;
  /** Original content with PII restored */
  content: string;
  /** Tokenized content (with PII replaced by tokens) */
  tokenized_content: string;
  role: string;
  tokens_detected: number;
  created_at: string;
}
