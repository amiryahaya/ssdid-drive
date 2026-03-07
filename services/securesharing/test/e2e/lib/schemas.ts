/**
 * Zod Schemas for E2E API Response Validation
 *
 * These schemas provide runtime validation for API responses,
 * ensuring the backend returns data in the expected format.
 */

import { z } from 'zod';

// ============================================================================
// Common Schemas
// ============================================================================

// API uses "pagination" key with "total" (not "meta" with "total_count")
export const PaginationSchema = z.object({
  page: z.number().int().nonnegative(),
  per_page: z.number().int().positive(),
  total: z.number().int().nonnegative(),
  total_pages: z.number().int().nonnegative(),
});

export type Pagination = z.infer<typeof PaginationSchema>;

// Legacy alias for backwards compatibility
export const PaginationMetaSchema = PaginationSchema;
export type PaginationMeta = Pagination;

export const createPaginatedSchema = <T extends z.ZodTypeAny>(itemSchema: T) =>
  z.object({
    data: z.array(itemSchema),
    pagination: PaginationSchema,
  });

// Some endpoints don't have pagination, just data array
export const createSimpleListSchema = <T extends z.ZodTypeAny>(itemSchema: T) =>
  z.object({
    data: z.array(itemSchema),
  });

// ============================================================================
// User & Auth Schemas
// ============================================================================

export const TenantSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1),
  slug: z.string().min(1),
  role: z.enum(['owner', 'admin', 'member']).optional(),
  status: z.string().optional(),
});

export type Tenant = z.infer<typeof TenantSchema>;

export const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  display_name: z.string().nullable().optional(),
  status: z.string(),
  tenants: z.array(TenantSchema).optional(),
  current_tenant_id: z.string().uuid().optional().nullable(),
});

export type User = z.infer<typeof UserSchema>;

export const AuthDataSchema = z.object({
  access_token: z.string().min(1),
  refresh_token: z.string().min(1),
  expires_in: z.number().int().positive(),
  token_type: z.literal('Bearer').or(z.string()),
  user: UserSchema,
});

export const AuthResponseSchema = z.object({
  data: AuthDataSchema,
});

export type AuthResponse = z.infer<typeof AuthResponseSchema>;

// Token refresh only returns access_token (no refresh_token or user)
export const TokenRefreshDataSchema = z.object({
  access_token: z.string().min(1),
  expires_in: z.number().int().positive(),
  token_type: z.literal('Bearer').or(z.string()),
});

export const TokenRefreshResponseSchema = z.object({
  data: TokenRefreshDataSchema,
});

export type TokenRefreshResponse = z.infer<typeof TokenRefreshResponseSchema>;

// ============================================================================
// File & Folder Schemas
// ============================================================================

export const FolderSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1),
  parent_id: z.string().uuid().nullable(),
  created_at: z.string().datetime({ offset: true }).or(z.string()),
  updated_at: z.string().datetime({ offset: true }).or(z.string()),
  file_count: z.number().int().nonnegative().optional(),
  folder_count: z.number().int().nonnegative().optional(),
});

export type Folder = z.infer<typeof FolderSchema>;

export const FileSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1),
  folder_id: z.string().uuid().nullable(),
  size: z.number().int().nonnegative(),
  content_type: z.string(),
  status: z.enum(['pending', 'uploading', 'uploaded', 'processing', 'ready', 'failed']),
  created_at: z.string().datetime({ offset: true }).or(z.string()),
  updated_at: z.string().datetime({ offset: true }).or(z.string()),
});

export type File = z.infer<typeof FileSchema>;

export const FileUploadUrlResponseSchema = z.object({
  upload_url: z.string().url(),
  file_id: z.string().uuid(),
  blob_id: z.string(),
});

export type FileUploadUrlResponse = z.infer<typeof FileUploadUrlResponseSchema>;

export const FileDownloadUrlResponseSchema = z.object({
  download_url: z.string().url(),
});

export type FileDownloadUrlResponse = z.infer<typeof FileDownloadUrlResponseSchema>;

// ============================================================================
// Share Schemas
// ============================================================================

export const SharePermissionSchema = z.enum(['view', 'edit', 'admin']);

export type SharePermission = z.infer<typeof SharePermissionSchema>;

export const ShareSchema = z.object({
  id: z.string().uuid(),
  file_id: z.string().uuid().optional(),
  folder_id: z.string().uuid().optional(),
  shared_with_user_id: z.string().uuid().optional(),
  shared_with_email: z.string().email().optional(),
  permission: SharePermissionSchema,
  status: z.enum(['pending', 'accepted', 'declined', 'revoked']),
  created_at: z.string().datetime({ offset: true }).or(z.string()),
  expires_at: z.string().datetime({ offset: true }).or(z.string()).nullable().optional(),
});

export type Share = z.infer<typeof ShareSchema>;

export const ShareResponseSchema = z.object({
  data: ShareSchema,
});

export const ShareListResponseSchema = createPaginatedSchema(ShareSchema);

// ============================================================================
// Invitation Schemas
// ============================================================================

export const InvitationStatusSchema = z.enum(['pending', 'accepted', 'expired', 'revoked']);

export type InvitationStatus = z.infer<typeof InvitationStatusSchema>;

export const InvitationSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  token: z.string().optional(),
  role: z.enum(['owner', 'admin', 'member']),
  status: InvitationStatusSchema,
  expires_at: z.string().datetime({ offset: true }).or(z.string()),
  created_at: z.string().datetime({ offset: true }).or(z.string()),
  tenant_id: z.string().uuid(),
  tenant_name: z.string().optional(),
});

export type Invitation = z.infer<typeof InvitationSchema>;

export const InvitationResponseSchema = z.object({
  data: InvitationSchema,
});

export const InvitationListResponseSchema = createPaginatedSchema(InvitationSchema);

// ============================================================================
// PII Schemas
// ============================================================================

export const PiiFindingSchema = z.object({
  type: z.string(),
  value: z.string(),
  start: z.number().int().nonnegative(),
  end: z.number().int().positive(),
  confidence: z.number().min(0).max(1),
  category: z.string().optional(),
  replacement: z.string().optional(),
});

export type PiiFinding = z.infer<typeof PiiFindingSchema>;

export const PiiDetectionResponseSchema = z.object({
  findings: z.array(PiiFindingSchema),
  text_length: z.number().int().nonnegative().optional(),
  processing_time_ms: z.number().nonnegative().optional(),
});

export type PiiDetectionResponse = z.infer<typeof PiiDetectionResponseSchema>;

export const PiiFileStatusSchema = z.enum(['pending', 'processing', 'processed', 'failed']);

export const PiiFileSchema = z.object({
  id: z.string().uuid(),
  filename: z.string(),
  status: PiiFileStatusSchema,
  redacted_content_url: z.string().url().optional(),
  pii_findings: z.array(PiiFindingSchema).optional(),
  error_message: z.string().optional(),
});

export type PiiFile = z.infer<typeof PiiFileSchema>;

// ============================================================================
// Error Response Schema
// ============================================================================

export const ErrorResponseSchema = z.object({
  error: z.object({
    code: z.string().optional(),
    message: z.string(),
    details: z.record(z.unknown()).optional(),
  }),
});

export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;

// ============================================================================
// Health Check Schema
// ============================================================================

export const HealthCheckSchema = z.object({
  status: z.enum(['ok', 'healthy', 'degraded', 'unhealthy']),
  version: z.string().optional(),
  timestamp: z.string().optional(),
});

export type HealthCheck = z.infer<typeof HealthCheckSchema>;

// ============================================================================
// Validation Helpers
// ============================================================================

/**
 * Validate a response against a schema and return typed data
 */
export function validateResponse<T>(schema: z.ZodType<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) {
    const errors = result.error.errors.map((e) => `${e.path.join('.')}: ${e.message}`).join(', ');
    throw new Error(`Response validation failed: ${errors}`);
  }
  return result.data;
}

/**
 * Check if a response matches a schema (returns boolean)
 */
export function isValidResponse<T>(schema: z.ZodType<T>, data: unknown): data is T {
  return schema.safeParse(data).success;
}

/**
 * Get validation errors for a response
 */
export function getValidationErrors<T>(
  schema: z.ZodType<T>,
  data: unknown
): { path: string; message: string }[] {
  const result = schema.safeParse(data);
  if (result.success) return [];
  return result.error.errors.map((e) => ({
    path: e.path.join('.'),
    message: e.message,
  }));
}
