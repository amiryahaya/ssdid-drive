/**
 * API Client for E2E Testing
 *
 * Provides typed helpers for interacting with SecureSharing and PII Service APIs
 */

import { APIRequestContext } from '@playwright/test';

// Configuration
export const CONFIG = {
  backendUrl: process.env.BACKEND_URL || process.env.BASE_URL || 'http://localhost:4000',
  piiServiceUrl: process.env.PII_SERVICE_URL || 'http://localhost:4001',
  adminEmail: process.env.E2E_ADMIN_EMAIL || 'admin@securesharing.test',
  adminPassword: process.env.E2E_ADMIN_PASSWORD || 'AdminTestPassword123!',
};

// Types
export interface AuthResponse {
  data: {
    access_token: string;
    refresh_token: string;
    expires_in: number;
    token_type: string;
    user: {
      id: string;
      email: string;
      display_name?: string;
      status: string;
      tenants?: Array<{
        id: string;
        name: string;
        slug: string;
        role: string;
      }>;
      current_tenant_id?: string;
    };
  };
}

export interface InvitationResponse {
  data: {
    id: string;
    email: string;
    token: string;
    status: string;
    role: string;
    expires_at: string;
  };
}

export interface FileUploadUrlResponse {
  data: {
    upload_url: string;
    file_id: string;
    storage_path: string;
    expires_in: number;
  };
}

export interface ConversationResponse {
  id: string;
  name: string;
  status: string;
  created_at: string;
}

export interface PiiFileResponse {
  id: string;
  filename: string;
  status: 'pending' | 'processing' | 'processed' | 'failed';
  redacted_content_url?: string;
  pii_findings?: PiiFinding[];
}

export interface PiiFinding {
  type: string;
  value: string;
  start: number;
  end: number;
  confidence: number;
}

export interface KeyBundleResponse {
  data: {
    encrypted_master_key: string | null;
    encrypted_private_keys: string | null;
    key_derivation_salt: string | null;
    public_keys: Record<string, string> | null;
  };
}

// Additional Types for Extended API
export interface Tenant {
  id: string;
  name: string;
  slug: string;
  status: string;
  role?: string;
}

export interface Folder {
  id: string;
  name: string;
  parent_id: string | null;
  created_at: string;
  updated_at: string;
  file_count?: number;
  folder_count?: number;
}

export interface File {
  id: string;
  name: string;
  folder_id: string | null;
  size: number;
  content_type: string;
  status: string;
  created_at: string;
  updated_at: string;
}

export interface Share {
  id: string;
  resource_type: 'file' | 'folder';
  resource_id: string;
  grantor_id: string;
  grantee_id: string;
  permission: 'read' | 'write' | 'admin';
  recursive?: boolean;
  revoked_at?: string;
  expires_at?: string;
  created_at: string;
}

export interface Invitation {
  id: string;
  email: string;
  token?: string;
  role: string;
  status: 'pending' | 'accepted' | 'expired' | 'revoked';
  expires_at: string;
  created_at: string;
  tenant_id: string;
  tenant_name?: string;
}

export interface PaginationMeta {
  page: number;
  per_page: number;
  total_count: number;
  total_pages: number;
}

export interface PaginatedResponse<T> {
  data: T[];
  meta: PaginationMeta;
}

/**
 * SecureSharing Backend API Client
 */
export class BackendApiClient {
  constructor(
    private request: APIRequestContext,
    private baseUrl: string = CONFIG.backendUrl
  ) {}

  private authToken?: string;

  setAuthToken(token: string) {
    this.authToken = token;
  }

  private getHeaders() {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (this.authToken) {
      headers['Authorization'] = `Bearer ${this.authToken}`;
    }
    return headers;
  }

  // Authentication
  async login(email: string, password: string): Promise<AuthResponse> {
    const response = await this.request.post(`${this.baseUrl}/api/auth/login`, {
      headers: { 'Content-Type': 'application/json' },
      data: {
        email,
        password,
        device_info: {
          platform: 'e2e-test',
          name: 'Playwright E2E',
          os_version: 'test',
        },
      },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Login failed: ${response.status()} - ${error}`);
    }

    const result: AuthResponse = await response.json();
    this.authToken = result.data.access_token;
    return result;
  }

  async register(data: {
    email: string;
    password: string;
    name: string;
    tenant_slug: string;
    public_keys: { kem: string; sign: string };
    encrypted_master_key: string;
    master_key_nonce: string;
    key_derivation_salt?: string;
    encrypted_private_keys?: string;
  }): Promise<AuthResponse> {
    const response = await this.request.post(`${this.baseUrl}/api/auth/register`, {
      headers: { 'Content-Type': 'application/json' },
      data: {
        ...data,
        device_info: {
          platform: 'e2e-test',
          name: 'Playwright E2E',
          os_version: 'test',
        },
      },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Registration failed: ${response.status()} - ${error}`);
    }

    const result: AuthResponse = await response.json();
    this.authToken = result.data.access_token;
    return result;
  }

  // Invitations
  async createInvitation(data: {
    email: string;
    role?: string;
    message?: string;
  }): Promise<InvitationResponse> {
    const response = await this.request.post(
      `${this.baseUrl}/api/tenant/invitations`,
      {
        headers: this.getHeaders(),
        data: {
          email: data.email,
          role: data.role || 'member',
          message: data.message,
        },
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Create invitation failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getInvitation(token: string): Promise<{ data: InvitationResponse['data'] }> {
    const response = await this.request.get(`${this.baseUrl}/api/invite/${token}`);

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get invitation failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async acceptInvitation(
    token: string,
    data: {
      name: string;
      password: string;
      public_keys: { kem: string; sign: string };
      encrypted_master_key: string;
      master_key_nonce: string;
    }
  ): Promise<AuthResponse> {
    const response = await this.request.post(
      `${this.baseUrl}/api/invite/${token}/accept`,
      {
        headers: { 'Content-Type': 'application/json' },
        data: {
          ...data,
          device_info: {
            platform: 'e2e-test',
            name: 'Playwright E2E',
            os_version: 'test',
          },
        },
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Accept invitation failed: ${response.status()} - ${error}`);
    }

    const result: AuthResponse = await response.json();
    this.authToken = result.data.access_token;
    return result;
  }

  // Files
  async getUploadUrl(data: {
    folder_id?: string | null;
    filename: string;
    content_type: string;
    size: number;
    blob_size?: number;
    encrypted_metadata: string;
    metadata_nonce: string;
    wrapped_dek: string;
    kem_ciphertext: string;
    blob_hash: string;
    signature: string;
  }): Promise<FileUploadUrlResponse> {
    // Ensure folder_id is always present (backend pattern matches on it)
    const payload = {
      ...data,
      folder_id: data.folder_id ?? null,
    };

    const response = await this.request.post(
      `${this.baseUrl}/api/files/upload-url`,
      {
        headers: this.getHeaders(),
        data: payload,
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get upload URL failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async uploadToPresignedUrl(url: string, content: Buffer | string): Promise<void> {
    const response = await this.request.put(url, {
      data: content,
      headers: {
        'Content-Type': 'application/octet-stream',
      },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Upload to presigned URL failed: ${response.status()} - ${error}`);
    }
  }

  async getDownloadUrl(fileId: string): Promise<{ download_url: string }> {
    const response = await this.request.get(
      `${this.baseUrl}/api/files/${fileId}/download-url`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get download URL failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // Tenant & User info
  async getCurrentUser(): Promise<{ data: AuthResponse['data']['user'] }> {
    const response = await this.request.get(`${this.baseUrl}/api/me`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get current user failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // Key Material
  async getKeyBundle(): Promise<KeyBundleResponse> {
    const response = await this.request.get(`${this.baseUrl}/api/me/keys`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get key bundle failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async updateKeyMaterial(data: {
    encrypted_master_key?: string;
    key_derivation_salt?: string;
    encrypted_private_keys?: string;
    public_keys?: { kem: string; sign: string };
  }): Promise<{ data: any }> {
    const response = await this.request.put(`${this.baseUrl}/api/me/keys`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Update key material failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getTenants(): Promise<{ data: Array<{ id: string; name: string }> }> {
    const response = await this.request.get(`${this.baseUrl}/api/tenants`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get tenants failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Extended Authentication
  // ============================================================================

  async logout(): Promise<void> {
    const response = await this.request.post(`${this.baseUrl}/api/auth/logout`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Logout failed: ${response.status()} - ${error}`);
    }

    this.authToken = undefined;
  }

  async refreshToken(refreshToken: string): Promise<AuthResponse> {
    const response = await this.request.post(`${this.baseUrl}/api/auth/refresh`, {
      headers: { 'Content-Type': 'application/json' },
      data: { refresh_token: refreshToken },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Token refresh failed: ${response.status()} - ${error}`);
    }

    const result: AuthResponse = await response.json();
    this.authToken = result.data.access_token;
    return result;
  }

  // ============================================================================
  // Tenant Operations
  // ============================================================================

  async listTenants(): Promise<{ data: Tenant[] }> {
    const response = await this.request.get(`${this.baseUrl}/api/tenants`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List tenants failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async switchTenant(tenantId: string): Promise<{ data: { tenant: Tenant } }> {
    const response = await this.request.post(`${this.baseUrl}/api/tenants/${tenantId}/switch`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Switch tenant failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async leaveTenant(tenantId: string): Promise<void> {
    const response = await this.request.delete(`${this.baseUrl}/api/tenants/${tenantId}/leave`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Leave tenant failed: ${response.status()} - ${error}`);
    }
  }

  // ============================================================================
  // Folder Operations
  // ============================================================================

  async getRootFolder(): Promise<{ data: Folder }> {
    const response = await this.request.get(`${this.baseUrl}/api/folders/root`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get root folder failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async listFolders(parentId?: string): Promise<{ data: Folder[] }> {
    const url = parentId
      ? `${this.baseUrl}/api/folders?parent_id=${parentId}`
      : `${this.baseUrl}/api/folders`;

    const response = await this.request.get(url, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List folders failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getFolder(folderId: string): Promise<{ data: Folder }> {
    const response = await this.request.get(`${this.baseUrl}/api/folders/${folderId}`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get folder failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async createFolder(data: { name: string; parent_id?: string | null }): Promise<{ data: Folder }> {
    const response = await this.request.post(`${this.baseUrl}/api/folders`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Create folder failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async updateFolder(folderId: string, data: { name?: string }): Promise<{ data: Folder }> {
    const response = await this.request.patch(`${this.baseUrl}/api/folders/${folderId}`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Update folder failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async deleteFolder(folderId: string): Promise<void> {
    const response = await this.request.delete(`${this.baseUrl}/api/folders/${folderId}`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Delete folder failed: ${response.status()} - ${error}`);
    }
  }

  // ============================================================================
  // File Operations
  // ============================================================================

  async listFiles(folderId?: string): Promise<{ data: File[] }> {
    const url = folderId
      ? `${this.baseUrl}/api/files?folder_id=${folderId}`
      : `${this.baseUrl}/api/files`;

    const response = await this.request.get(url, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List files failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getFile(fileId: string): Promise<{ data: File }> {
    const response = await this.request.get(`${this.baseUrl}/api/files/${fileId}`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get file failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async moveFile(fileId: string, data: { folder_id: string | null }): Promise<{ data: File }> {
    const response = await this.request.patch(`${this.baseUrl}/api/files/${fileId}/move`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Move file failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async updateFile(
    fileId: string,
    data: {
      status?: string;
      blob_hash?: string;
      blob_size?: number;
      chunk_count?: number;
    }
  ): Promise<{ data: File }> {
    const response = await this.request.put(`${this.baseUrl}/api/files/${fileId}`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Update file failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async deleteFile(fileId: string): Promise<void> {
    const response = await this.request.delete(`${this.baseUrl}/api/files/${fileId}`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Delete file failed: ${response.status()} - ${error}`);
    }
  }

  // ============================================================================
  // Share Operations
  // ============================================================================

  async shareFile(data: {
    file_id: string;
    grantee_id: string;
    wrapped_key: string;
    kem_ciphertext: string;
    signature: string;
    permission: 'read' | 'write' | 'admin';
    expires_at?: string;
  }): Promise<{ data: Share }> {
    const response = await this.request.post(`${this.baseUrl}/api/shares/file`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Share file failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async shareFolder(data: {
    folder_id: string;
    grantee_id: string;
    wrapped_key: string;
    kem_ciphertext: string;
    signature: string;
    permission: 'read' | 'write' | 'admin';
    recursive?: boolean;
    expires_at?: string;
  }): Promise<{ data: Share }> {
    const response = await this.request.post(`${this.baseUrl}/api/shares/folder`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Share folder failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async listCreatedShares(params?: {
    page?: number;
    per_page?: number;
  }): Promise<PaginatedResponse<Share>> {
    const searchParams = new URLSearchParams();
    if (params?.page) searchParams.set('page', params.page.toString());
    if (params?.per_page) searchParams.set('per_page', params.per_page.toString());

    const url = `${this.baseUrl}/api/shares/created?${searchParams.toString()}`;
    const response = await this.request.get(url, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List created shares failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async listReceivedShares(params?: {
    page?: number;
    per_page?: number;
  }): Promise<PaginatedResponse<Share>> {
    const searchParams = new URLSearchParams();
    if (params?.page) searchParams.set('page', params.page.toString());
    if (params?.per_page) searchParams.set('per_page', params.per_page.toString());

    const url = `${this.baseUrl}/api/shares/received?${searchParams.toString()}`;
    const response = await this.request.get(url, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List received shares failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getShare(shareId: string): Promise<{ data: Share }> {
    const response = await this.request.get(`${this.baseUrl}/api/shares/${shareId}`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get share failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async updateSharePermission(
    shareId: string,
    data: {
      permission: 'read' | 'write' | 'admin';
      signature?: string;
    }
  ): Promise<{ data: Share }> {
    const response = await this.request.put(`${this.baseUrl}/api/shares/${shareId}/permission`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Update share permission failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async revokeShare(shareId: string): Promise<void> {
    const response = await this.request.delete(`${this.baseUrl}/api/shares/${shareId}`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Revoke share failed: ${response.status()} - ${error}`);
    }
  }

  async acceptShare(shareId: string): Promise<{ data: Share }> {
    const response = await this.request.post(`${this.baseUrl}/api/shares/${shareId}/accept`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Accept share failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Invitation Operations (Extended)
  // ============================================================================

  async listInvitations(params?: {
    status?: string;
    page?: number;
    per_page?: number;
  }): Promise<PaginatedResponse<Invitation>> {
    const searchParams = new URLSearchParams();
    if (params?.status) searchParams.set('status', params.status);
    if (params?.page) searchParams.set('page', params.page.toString());
    if (params?.per_page) searchParams.set('per_page', params.per_page.toString());

    const url = `${this.baseUrl}/api/tenant/invitations?${searchParams.toString()}`;
    const response = await this.request.get(url, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List invitations failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async revokeInvitation(invitationId: string): Promise<void> {
    const response = await this.request.delete(
      `${this.baseUrl}/api/tenant/invitations/${invitationId}`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Revoke invitation failed: ${response.status()} - ${error}`);
    }
  }

  async resendInvitation(invitationId: string): Promise<{ data: Invitation }> {
    const response = await this.request.post(
      `${this.baseUrl}/api/tenant/invitations/${invitationId}/resend`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Resend invitation failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Device Management
  // ============================================================================

  async enrollDevice(params: {
    device_fingerprint: string;
    platform: string;
    device_info: { model: string; os_version: string; app_version: string };
    device_public_key: string;
    key_algorithm: string;
    device_name: string;
  }): Promise<any> {
    const response = await this.request.post(`${this.baseUrl}/api/devices/enroll`, {
      headers: this.getHeaders(),
      data: params,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Enroll device failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async listDevices(): Promise<any> {
    const response = await this.request.get(`${this.baseUrl}/api/devices`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List devices failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getDevice(deviceId: string): Promise<any> {
    const response = await this.request.get(`${this.baseUrl}/api/devices/${deviceId}`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get device failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async updateDevice(deviceId: string, params: { device_name: string }): Promise<any> {
    const response = await this.request.put(`${this.baseUrl}/api/devices/${deviceId}`, {
      headers: this.getHeaders(),
      data: params,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Update device failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async revokeDevice(deviceId: string, reason?: string): Promise<any> {
    const query = reason ? `?reason=${encodeURIComponent(reason)}` : '';
    const response = await this.request.delete(
      `${this.baseUrl}/api/devices/${deviceId}${query}`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Revoke device failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async registerPush(deviceId: string, params: { player_id: string }): Promise<any> {
    const response = await this.request.post(
      `${this.baseUrl}/api/devices/${deviceId}/push`,
      {
        headers: this.getHeaders(),
        data: params,
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Register push failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async unregisterPush(deviceId: string): Promise<any> {
    const response = await this.request.delete(
      `${this.baseUrl}/api/devices/${deviceId}/push`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Unregister push failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Folder Content Operations
  // ============================================================================

  async listFolderFiles(folderId: string): Promise<{ data: File[]; meta?: any }> {
    const response = await this.request.get(
      `${this.baseUrl}/api/folders/${folderId}/files`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List folder files failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async listFolderChildren(folderId: string): Promise<{ data: Folder[]; meta?: any }> {
    const response = await this.request.get(
      `${this.baseUrl}/api/folders/${folderId}/children`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List folder children failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Notification Operations
  // ============================================================================

  async getNotifications(params?: {
    limit?: number;
    offset?: number;
    unread_only?: boolean;
  }): Promise<{
    data: Array<{
      id: string;
      type: string;
      title: string;
      body: string;
      data: Record<string, unknown>;
      read_at: string | null;
      created_at: string;
    }>;
    meta: { unread_count: number };
  }> {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', String(params.limit));
    if (params?.offset) query.set('offset', String(params.offset));
    if (params?.unread_only) query.set('unread_only', 'true');
    const qs = query.toString();

    const response = await this.request.get(
      `${this.baseUrl}/api/notifications${qs ? `?${qs}` : ''}`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get notifications failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getUnreadNotificationCount(): Promise<{ data: { unread_count: number } }> {
    const response = await this.request.get(
      `${this.baseUrl}/api/notifications/unread_count`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get unread count failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async markNotificationRead(notificationId: string): Promise<{
    data: { notification_id: string; unread_count: number };
  }> {
    const response = await this.request.post(
      `${this.baseUrl}/api/notifications/${notificationId}/read`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Mark notification read failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async markAllNotificationsRead(): Promise<{
    data: { marked_count: number; unread_count: number };
  }> {
    const response = await this.request.post(
      `${this.baseUrl}/api/notifications/read_all`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Mark all notifications read failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async deleteNotification(notificationId: string): Promise<void> {
    const response = await this.request.delete(
      `${this.baseUrl}/api/notifications/${notificationId}`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Delete notification failed: ${response.status()} - ${error}`);
    }
  }

  // ============================================================================
  // Health Check
  // ============================================================================

  async healthCheck(): Promise<{ status: string }> {
    const response = await this.request.get(`${this.baseUrl}/health`);

    if (!response.ok()) {
      throw new Error(`Health check failed: ${response.status()}`);
    }

    return response.json();
  }

  // ============================================================================
  // Recovery Configuration
  // ============================================================================

  async getRecoveryConfig(): Promise<any> {
    const response = await this.request.get(`${this.baseUrl}/api/recovery/config`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get recovery config failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async setupRecovery(params: { threshold: number; total_shares: number }): Promise<any> {
    const response = await this.request.post(`${this.baseUrl}/api/recovery/setup`, {
      headers: this.getHeaders(),
      data: params,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Setup recovery failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async disableRecovery(): Promise<void> {
    const response = await this.request.delete(`${this.baseUrl}/api/recovery/config`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Disable recovery failed: ${response.status()} - ${error}`);
    }
  }

  // ============================================================================
  // Recovery Shares
  // ============================================================================

  async createRecoveryShare(params: {
    trustee_id: string;
    share_index: number;
    encrypted_share: string;
    kem_ciphertext: string;
    signature: string;
  }): Promise<any> {
    const response = await this.request.post(`${this.baseUrl}/api/recovery/shares`, {
      headers: this.getHeaders(),
      data: params,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Create recovery share failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async listTrusteeShares(): Promise<any> {
    const response = await this.request.get(`${this.baseUrl}/api/recovery/shares/trustee`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List trustee shares failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async listCreatedRecoveryShares(): Promise<any> {
    const response = await this.request.get(`${this.baseUrl}/api/recovery/shares/created`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List created recovery shares failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async acceptRecoveryShare(shareId: string): Promise<any> {
    const response = await this.request.post(
      `${this.baseUrl}/api/recovery/shares/${shareId}/accept`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Accept recovery share failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async rejectRecoveryShare(shareId: string): Promise<void> {
    const response = await this.request.post(
      `${this.baseUrl}/api/recovery/shares/${shareId}/reject`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Reject recovery share failed: ${response.status()} - ${error}`);
    }
  }

  async revokeRecoveryShare(shareId: string): Promise<void> {
    const response = await this.request.delete(
      `${this.baseUrl}/api/recovery/shares/${shareId}`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Revoke recovery share failed: ${response.status()} - ${error}`);
    }
  }

  // ============================================================================
  // Recovery Requests
  // ============================================================================

  async createRecoveryRequest(params: {
    new_public_key: string;
    reason?: string;
  }): Promise<any> {
    const response = await this.request.post(`${this.baseUrl}/api/recovery/request`, {
      headers: this.getHeaders(),
      data: params,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Create recovery request failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async listRecoveryRequests(): Promise<any> {
    const response = await this.request.get(`${this.baseUrl}/api/recovery/requests`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List recovery requests failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async listPendingRecoveryRequests(): Promise<any> {
    const response = await this.request.get(`${this.baseUrl}/api/recovery/requests/pending`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`List pending recovery requests failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getRecoveryRequest(requestId: string): Promise<any> {
    const response = await this.request.get(
      `${this.baseUrl}/api/recovery/requests/${requestId}`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get recovery request failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async approveRecoveryRequest(
    requestId: string,
    params: {
      share_id: string;
      reencrypted_share: string;
      kem_ciphertext: string;
      signature: string;
    }
  ): Promise<any> {
    const response = await this.request.post(
      `${this.baseUrl}/api/recovery/requests/${requestId}/approve`,
      {
        headers: this.getHeaders(),
        data: params,
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Approve recovery request failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async completeRecovery(
    requestId: string,
    params: {
      encrypted_master_key: string;
      encrypted_private_keys: string;
      key_derivation_salt: string;
      public_keys: { kem: string; sign: string };
    }
  ): Promise<any> {
    const response = await this.request.post(
      `${this.baseUrl}/api/recovery/requests/${requestId}/complete`,
      {
        headers: this.getHeaders(),
        data: params,
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Complete recovery failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async cancelRecoveryRequest(requestId: string): Promise<void> {
    const response = await this.request.delete(
      `${this.baseUrl}/api/recovery/requests/${requestId}`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Cancel recovery request failed: ${response.status()} - ${error}`);
    }
  }
}

/**
 * PII Service API Client
 */
export class PiiServiceApiClient {
  constructor(
    private request: APIRequestContext,
    private baseUrl: string = CONFIG.piiServiceUrl
  ) {}

  private authToken?: string;

  setAuthToken(token: string) {
    this.authToken = token;
  }

  private getHeaders() {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (this.authToken) {
      headers['Authorization'] = `Bearer ${this.authToken}`;
    }
    return headers;
  }

  // Health check
  async healthCheck(): Promise<{ status: string }> {
    const response = await this.request.get(`${this.baseUrl}/health`);
    return response.json();
  }

  // Conversations
  async createConversation(data: {
    name: string;
    policy_id?: string;
  }): Promise<ConversationResponse> {
    const response = await this.request.post(
      `${this.baseUrl}/api/v1/conversations`,
      {
        headers: this.getHeaders(),
        data,
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Create conversation failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getConversation(id: string): Promise<ConversationResponse> {
    const response = await this.request.get(
      `${this.baseUrl}/api/v1/conversations/${id}`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get conversation failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // Files
  async uploadFile(
    conversationId: string,
    filename: string,
    content: Buffer | string,
    mimeType: string = 'text/plain'
  ): Promise<PiiFileResponse> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/files/upload`, {
      headers: {
        Authorization: `Bearer ${this.authToken}`,
      },
      multipart: {
        file: {
          name: filename,
          mimeType,
          buffer: Buffer.isBuffer(content) ? content : Buffer.from(content),
        },
        conversation_id: conversationId,
      },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Upload file failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async processFile(fileId: string): Promise<{ status: string; job_id?: string }> {
    const response = await this.request.post(
      `${this.baseUrl}/api/v1/files/${fileId}/process`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Process file failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async getFile(conversationId: string, fileId: string): Promise<PiiFileResponse> {
    const response = await this.request.get(
      `${this.baseUrl}/api/v1/conversations/${conversationId}/files/${fileId}`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get file failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  async downloadRedactedFile(fileId: string): Promise<string> {
    const response = await this.request.get(
      `${this.baseUrl}/api/v1/files/${fileId}/download`,
      {
        headers: this.getHeaders(),
      }
    );

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Download file failed: ${response.status()} - ${error}`);
    }

    return response.text();
  }

  async waitForProcessing(
    conversationId: string,
    fileId: string,
    timeoutMs: number = 60000,
    pollIntervalMs: number = 1000
  ): Promise<PiiFileResponse> {
    const startTime = Date.now();

    while (Date.now() - startTime < timeoutMs) {
      const file = await this.getFile(conversationId, fileId);

      if (file.status === 'processed') {
        return file;
      }

      if (file.status === 'failed') {
        throw new Error(`File processing failed for file ${fileId}`);
      }

      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }

    throw new Error(`Timeout waiting for file ${fileId} to be processed`);
  }

  // PII Detection (direct)
  async detectPii(text: string): Promise<{ findings: PiiFinding[] }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/detect`, {
      headers: this.getHeaders(),
      data: { text },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Detect PII failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Extended PII Detection
  // ============================================================================

  /**
   * Detect PII with specific options
   */
  async detectPiiWithOptions(data: {
    text: string;
    entity_types?: string[];
    confidence_threshold?: number;
    locale?: string;
  }): Promise<{
    findings: PiiFinding[];
    text_length?: number;
    processing_time_ms?: number;
  }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/detect`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Detect PII with options failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  /**
   * Detect Malaysian-specific PII (NRIC, MY phone numbers, etc.)
   */
  async detectMalaysianPii(text: string): Promise<{ findings: PiiFinding[] }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/detect`, {
      headers: this.getHeaders(),
      data: {
        text,
        entity_types: ['NRIC', 'PHONE', 'EMAIL', 'NAME', 'ADDRESS'],
        locale: 'ms_MY',
      },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Detect Malaysian PII failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Redaction
  // ============================================================================

  /**
   * Redact PII from text
   */
  async redactText(data: {
    text: string;
    policy_id?: string;
    entity_types?: string[];
    redaction_mode?: 'mask' | 'tokenize' | 'remove';
  }): Promise<{
    redacted_text: string;
    findings: PiiFinding[];
    replacements: Array<{
      original: string;
      replacement: string;
      type: string;
      start: number;
      end: number;
    }>;
  }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/redact`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Redact text failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  /**
   * Redact text with a specific policy
   */
  async redactWithPolicy(
    text: string,
    policyId: string
  ): Promise<{
    redacted_text: string;
    findings: PiiFinding[];
  }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/redact`, {
      headers: this.getHeaders(),
      data: {
        text,
        policy_id: policyId,
      },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Redact with policy failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Tokenization
  // ============================================================================

  /**
   * Tokenize PII in text (replace with reversible tokens)
   */
  async tokenizeText(data: {
    text: string;
    entity_types?: string[];
    token_prefix?: string;
  }): Promise<{
    tokenized_text: string;
    token_map: Record<string, string>;
    findings: PiiFinding[];
  }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/tokenize`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Tokenize text failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  /**
   * Detokenize text (restore original PII from tokens)
   */
  async detokenizeText(data: {
    text: string;
    token_map: Record<string, string>;
  }): Promise<{
    original_text: string;
    tokens_replaced: number;
  }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/detokenize`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Detokenize text failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Redaction Policies
  // ============================================================================

  /**
   * List available redaction policies
   */
  async getRedactionPolicies(): Promise<{
    data: Array<{
      id: string;
      name: string;
      description: string;
      entity_types: string[];
      redaction_mode: string;
      is_default: boolean;
    }>;
  }> {
    const response = await this.request.get(`${this.baseUrl}/api/v1/policies`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get redaction policies failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  /**
   * Get a specific redaction policy
   */
  async getRedactionPolicy(policyId: string): Promise<{
    data: {
      id: string;
      name: string;
      description: string;
      entity_types: string[];
      redaction_mode: string;
      settings: Record<string, unknown>;
    };
  }> {
    const response = await this.request.get(`${this.baseUrl}/api/v1/policies/${policyId}`, {
      headers: this.getHeaders(),
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get redaction policy failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Batch Processing
  // ============================================================================

  /**
   * Detect PII in multiple texts
   */
  async detectPiiBatch(texts: string[]): Promise<{
    results: Array<{
      text_index: number;
      findings: PiiFinding[];
    }>;
  }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/detect/batch`, {
      headers: this.getHeaders(),
      data: { texts },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Batch detect PII failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Document Processing
  // ============================================================================

  /**
   * Process a document with specific document type handling
   */
  async processDocument(data: {
    content: string;
    document_type: 'text' | 'medical' | 'financial' | 'legal';
    policy_id?: string;
  }): Promise<{
    processed_content: string;
    findings: PiiFinding[];
    document_type: string;
    confidence_scores: Record<string, number>;
  }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/documents/process`, {
      headers: this.getHeaders(),
      data,
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Process document failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }

  // ============================================================================
  // Statistics & Metadata
  // ============================================================================

  /**
   * Get entity type statistics from detection
   */
  async getEntityStats(text: string): Promise<{
    total_findings: number;
    by_type: Record<string, number>;
    avg_confidence: number;
    coverage_percentage: number;
  }> {
    const response = await this.request.post(`${this.baseUrl}/api/v1/detect/stats`, {
      headers: this.getHeaders(),
      data: { text },
    });

    if (!response.ok()) {
      const error = await response.text();
      throw new Error(`Get entity stats failed: ${response.status()} - ${error}`);
    }

    return response.json();
  }
}

/**
 * Create API clients from Playwright request context
 */
export function createApiClients(request: APIRequestContext) {
  return {
    backend: new BackendApiClient(request),
    piiService: new PiiServiceApiClient(request),
  };
}
