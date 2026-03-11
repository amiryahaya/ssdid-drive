package com.securesharing.data.remote

import com.securesharing.data.remote.AcceptInviteRequest
import com.securesharing.data.remote.AuthProvidersResponse
import com.securesharing.data.remote.AcceptInviteResponse
import com.securesharing.data.remote.ApproveRecoveryRequest
import com.securesharing.data.remote.AuthResponse
import com.securesharing.data.remote.CompleteRecoveryRequest
import com.securesharing.data.remote.CreateFolderRequest
import com.securesharing.data.remote.CredentialDto
import com.securesharing.data.remote.CredentialsResponse
import com.securesharing.data.remote.CreateRecoveryRequestRequest
import com.securesharing.data.remote.CreateRecoveryShareRequest
import com.securesharing.data.remote.DeviceEnrollmentResponse
import com.securesharing.data.remote.DeviceEnrollmentsResponse
import com.securesharing.data.remote.DownloadUrlResponse
import com.securesharing.data.remote.EnrollDeviceRequest
import com.securesharing.data.remote.FileResponse
import com.securesharing.data.remote.FilesResponse
import com.securesharing.data.remote.FolderResponse
import com.securesharing.data.remote.FoldersResponse
import com.securesharing.data.remote.InvitationAcceptedResponse
import com.securesharing.data.remote.InvitationCreatedResponse
import com.securesharing.data.remote.InvitationsResponse
import com.securesharing.data.remote.InviteCodeInfoResponse
import com.securesharing.data.remote.InviteInfoResponse
import com.securesharing.data.remote.InviteMemberRequest
import com.securesharing.data.remote.LoginRequest
import com.securesharing.data.remote.MemberResponse
import com.securesharing.data.remote.MembersResponse
import com.securesharing.data.remote.MoveFileRequest
import com.securesharing.data.remote.OidcAuthorizeRequest
import com.securesharing.data.remote.OidcAuthorizeResponse
import com.securesharing.data.remote.OidcCallbackRequest
import com.securesharing.data.remote.OidcCallbackResponse
import com.securesharing.data.remote.OidcRegisterRequest
import com.securesharing.data.remote.OidcRegisterResponse
import com.securesharing.data.remote.MoveFolderRequest
import com.securesharing.data.remote.PublicKeyResponse
import com.securesharing.data.remote.RecoveryApprovalResponse
import com.securesharing.data.remote.RecoveryConfigResponse
import com.securesharing.data.remote.RecoveryRequestDetailResponse
import com.securesharing.data.remote.RecoveryRequestResponse
import com.securesharing.data.remote.RecoveryRequestsResponse
import com.securesharing.data.remote.RecoveryShareResponse
import com.securesharing.data.remote.RecoverySharesResponse
import com.securesharing.data.remote.RefreshTokenRequest
import com.securesharing.data.remote.RegisterPushRequest
import com.securesharing.data.remote.RegisterRequest
import com.securesharing.data.remote.RenameCredentialRequest
import com.securesharing.data.remote.SetExpiryRequest
import com.securesharing.data.remote.SetupRecoveryRequest
import com.securesharing.data.remote.ShareFileRequest
import com.securesharing.data.remote.ShareFolderRequest
import com.securesharing.data.remote.ShareResponse
import com.securesharing.data.remote.SharesResponse
import com.securesharing.data.remote.TenantConfigResponse
import com.securesharing.data.remote.TenantsResponse
import com.securesharing.data.remote.TenantSwitchRequest
import com.securesharing.data.remote.TenantSwitchResponse
import com.securesharing.data.remote.UpdateDeviceRequest
import com.securesharing.data.remote.UpdateFileRequest
import com.securesharing.data.remote.UpdateFolderRequest
import com.securesharing.data.remote.UpdateKeyMaterialRequest
import com.securesharing.data.remote.UpdateMemberRoleRequest
import com.securesharing.data.remote.UpdateProfileRequest
import com.securesharing.data.remote.UpdatePermissionRequest
import com.securesharing.data.remote.UploadUrlRequest
import com.securesharing.data.remote.UploadUrlResponse
import com.securesharing.data.remote.UserResponse
import com.securesharing.data.remote.UsersResponse
import com.securesharing.data.remote.WebAuthnBeginResponse
import com.securesharing.data.remote.WebAuthnLoginBeginRequest
import com.securesharing.data.remote.WebAuthnLoginCompleteRequest
import com.securesharing.data.remote.WebAuthnLoginResponse
import retrofit2.Response
import retrofit2.http.*

/**
 * Retrofit API service interface for SecureSharing backend.
 */
interface ApiService {

    // ==================== Tenant Management ====================

    /**
     * Get list of all tenants the current user belongs to.
     */
    @GET("tenants")
    suspend fun getUserTenants(): Response<TenantsResponse>

    /**
     * Switch to a different tenant.
     * Returns new tokens scoped to the selected tenant.
     */
    @POST("tenant/switch")
    suspend fun switchTenant(@Body request: TenantSwitchRequest): Response<TenantSwitchResponse>

    /**
     * Leave a tenant (remove self from tenant).
     * Cannot leave if user is the only owner.
     */
    @DELETE("tenants/{id}/leave")
    suspend fun leaveTenant(@Path("id") tenantId: String): Response<Unit>

    /**
     * Get current tenant configuration.
     */
    @GET("tenant/config")
    suspend fun getTenantConfig(): Response<TenantConfigResponse>

    @GET("tenant/users")
    suspend fun getTenantUsers(): Response<UsersResponse>

    // ==================== Member Management ====================

    /**
     * Get list of members in a tenant.
     * Requires admin or owner role.
     */
    @GET("tenants/{tenant_id}/members")
    suspend fun getTenantMembers(@Path("tenant_id") tenantId: String): Response<MembersResponse>

    /**
     * Invite a user to a tenant by email.
     * Requires admin or owner role.
     */
    @POST("tenants/{tenant_id}/members")
    suspend fun inviteMember(
        @Path("tenant_id") tenantId: String,
        @Body request: InviteMemberRequest
    ): Response<InvitationCreatedResponse>

    /**
     * Update a member's role in a tenant.
     * Requires owner role.
     */
    @PUT("tenants/{tenant_id}/members/{user_id}/role")
    suspend fun updateMemberRole(
        @Path("tenant_id") tenantId: String,
        @Path("user_id") userId: String,
        @Body request: UpdateMemberRoleRequest
    ): Response<MemberResponse>

    /**
     * Remove a member from a tenant.
     * Requires admin or owner role. Cannot remove owners.
     */
    @DELETE("tenants/{tenant_id}/members/{user_id}")
    suspend fun removeMember(
        @Path("tenant_id") tenantId: String,
        @Path("user_id") userId: String
    ): Response<Unit>

    // ==================== Invitations (Authenticated) ====================

    /**
     * Get pending invitations for the current user.
     */
    @GET("invitations")
    suspend fun getPendingInvitations(): Response<InvitationsResponse>

    /**
     * Accept a tenant invitation.
     */
    @POST("invitations/{id}/accept")
    suspend fun acceptInvitation(@Path("id") invitationId: String): Response<InvitationAcceptedResponse>

    /**
     * Decline a tenant invitation.
     */
    @POST("invitations/{id}/decline")
    suspend fun declineInvitation(@Path("id") invitationId: String): Response<Unit>

    // ==================== Invite Code (Short Code Lookup) ====================

    /**
     * Look up an invitation by short code (e.g. "ACME-7K9X").
     * Public endpoint — no auth required.
     * Returns tenant name, role, and expiry for preview.
     */
    @GET("invitations/code/{code}")
    suspend fun getInviteByCode(@Path("code") code: String): Response<InviteCodeInfoResponse>

    // ==================== Invitation Token (Public - Unauthenticated) ====================

    /**
     * Get public invitation info by token.
     * This is an unauthenticated endpoint for new users receiving invitations.
     */
    @GET("invite/{token}")
    suspend fun getInviteInfo(@Path("token") token: String): Response<InviteInfoResponse>

    /**
     * Accept an invitation and register a new account.
     * This is an unauthenticated endpoint for new users.
     * Generates keys on the client and sends public keys + encrypted private keys.
     */
    @POST("invite/{token}/accept")
    suspend fun acceptInvite(
        @Path("token") token: String,
        @Body request: AcceptInviteRequest
    ): Response<AcceptInviteResponse>

    // ==================== Authentication ====================

    @POST("auth/register")
    suspend fun register(@Body request: RegisterRequest): Response<AuthResponse>

    @POST("auth/login")
    suspend fun login(@Body request: LoginRequest): Response<AuthResponse>

    @POST("auth/refresh")
    suspend fun refreshToken(@Body request: RefreshTokenRequest): Response<AuthResponse>

    @POST("auth/logout")
    suspend fun logout(): Response<Unit>

    // ==================== User ====================

    @GET("me")
    suspend fun getCurrentUser(): Response<UserResponse>

    /**
     * Update current user's profile (display name).
     */
    @PUT("me")
    suspend fun updateProfile(@Body request: UpdateProfileRequest): Response<UserResponse>

    /**
     * Update current user's key material.
     * Used after password change to sync new encrypted master key with server.
     */
    @PUT("me/keys")
    suspend fun updateKeyMaterial(@Body request: UpdateKeyMaterialRequest): Response<UserResponse>

    @GET("users")
    suspend fun searchUsers(@Query("query") query: String): Response<UsersResponse>

    @GET("users/{id}")
    suspend fun getUser(@Path("id") userId: String): Response<UserResponse>

    @GET("users/{id}/public-key")
    suspend fun getUserPublicKey(@Path("id") userId: String): Response<PublicKeyResponse>

    // ==================== Folders ====================

    @GET("folders/root")
    suspend fun getRootFolder(): Response<FolderResponse>

    @GET("folders")
    suspend fun listFolders(): Response<FoldersResponse>

    @POST("folders")
    suspend fun createFolder(@Body request: CreateFolderRequest): Response<FolderResponse>

    @GET("folders/{id}")
    suspend fun getFolder(@Path("id") folderId: String): Response<FolderResponse>

    @PUT("folders/{id}")
    suspend fun updateFolder(
        @Path("id") folderId: String,
        @Body request: UpdateFolderRequest
    ): Response<FolderResponse>

    @DELETE("folders/{id}")
    suspend fun deleteFolder(@Path("id") folderId: String): Response<Unit>

    @GET("folders/{id}/children")
    suspend fun getFolderChildren(@Path("id") folderId: String): Response<FoldersResponse>

    @GET("folders/{id}/files")
    suspend fun getFolderFiles(@Path("id") folderId: String): Response<FilesResponse>

    @POST("folders/{id}/move")
    suspend fun moveFolder(
        @Path("id") folderId: String,
        @Body request: MoveFolderRequest
    ): Response<FolderResponse>

    // ==================== Files ====================

    @POST("files/upload-url")
    suspend fun getUploadUrl(@Body request: UploadUrlRequest): Response<UploadUrlResponse>

    @GET("files/{id}")
    suspend fun getFile(@Path("id") fileId: String): Response<FileResponse>

    @PUT("files/{id}")
    suspend fun updateFile(
        @Path("id") fileId: String,
        @Body request: UpdateFileRequest
    ): Response<FileResponse>

    @DELETE("files/{id}")
    suspend fun deleteFile(@Path("id") fileId: String): Response<Unit>

    @GET("files/{id}/download-url")
    suspend fun getDownloadUrl(@Path("id") fileId: String): Response<DownloadUrlResponse>

    @POST("files/{id}/move")
    suspend fun moveFile(
        @Path("id") fileId: String,
        @Body request: MoveFileRequest
    ): Response<FileResponse>

    @GET("files/search")
    suspend fun searchFiles(@Query("q") query: String): Response<FilesResponse>

    // ==================== Sharing ====================

    @GET("shares/received")
    suspend fun getReceivedShares(): Response<SharesResponse>

    @GET("shares/created")
    suspend fun getCreatedShares(): Response<SharesResponse>

    @GET("shares/{id}")
    suspend fun getShare(@Path("id") shareId: String): Response<ShareResponse>

    @POST("shares/file")
    suspend fun shareFile(@Body request: ShareFileRequest): Response<ShareResponse>

    @POST("shares/folder")
    suspend fun shareFolder(@Body request: ShareFolderRequest): Response<ShareResponse>

    @PUT("shares/{id}/permission")
    suspend fun updateSharePermission(
        @Path("id") shareId: String,
        @Body request: UpdatePermissionRequest
    ): Response<ShareResponse>

    @PUT("shares/{id}/expiry")
    suspend fun setShareExpiry(
        @Path("id") shareId: String,
        @Body request: SetExpiryRequest
    ): Response<ShareResponse>

    @DELETE("shares/{id}")
    suspend fun revokeShare(@Path("id") shareId: String): Response<Unit>

    // ==================== Recovery ====================

    @GET("recovery/config")
    suspend fun getRecoveryConfig(): Response<RecoveryConfigResponse>

    @POST("recovery/setup")
    suspend fun setupRecovery(@Body request: SetupRecoveryRequest): Response<RecoveryConfigResponse>

    /**
     * Disable recovery - deletes config and all shares.
     */
    @DELETE("recovery/config")
    suspend fun disableRecovery(): Response<Unit>

    @POST("recovery/shares")
    suspend fun createRecoveryShare(@Body request: CreateRecoveryShareRequest): Response<RecoveryShareResponse>

    @GET("recovery/shares/trustee")
    suspend fun getTrusteeShares(): Response<RecoverySharesResponse>

    @GET("recovery/shares/created")
    suspend fun getCreatedRecoveryShares(): Response<RecoverySharesResponse>

    @POST("recovery/shares/{id}/accept")
    suspend fun acceptRecoveryShare(@Path("id") shareId: String): Response<RecoveryShareResponse>

    /**
     * Reject a recovery share (as trustee).
     */
    @POST("recovery/shares/{id}/reject")
    suspend fun rejectRecoveryShare(@Path("id") shareId: String): Response<Unit>

    /**
     * Revoke a recovery share (as grantor/owner).
     */
    @DELETE("recovery/shares/{id}")
    suspend fun revokeRecoveryShare(@Path("id") shareId: String): Response<Unit>

    @POST("recovery/request")
    suspend fun createRecoveryRequest(@Body request: CreateRecoveryRequestRequest): Response<RecoveryRequestResponse>

    @GET("recovery/requests")
    suspend fun getRecoveryRequests(): Response<RecoveryRequestsResponse>

    @GET("recovery/requests/pending")
    suspend fun getPendingRecoveryRequests(): Response<RecoveryRequestsResponse>

    @GET("recovery/requests/{id}")
    suspend fun getRecoveryRequest(@Path("id") requestId: String): Response<RecoveryRequestDetailResponse>

    @POST("recovery/requests/{id}/approve")
    suspend fun approveRecoveryRequest(
        @Path("id") requestId: String,
        @Body request: ApproveRecoveryRequest
    ): Response<RecoveryApprovalResponse>

    @POST("recovery/requests/{id}/complete")
    suspend fun completeRecovery(
        @Path("id") requestId: String,
        @Body request: CompleteRecoveryRequest
    ): Response<UserResponse>

    /**
     * Cancel a pending recovery request.
     */
    @DELETE("recovery/requests/{id}")
    suspend fun cancelRecoveryRequest(@Path("id") requestId: String): Response<Unit>

    // ==================== WebAuthn ====================

    @POST("auth/webauthn/login/begin")
    suspend fun webauthnLoginBegin(@Body request: WebAuthnLoginBeginRequest): Response<WebAuthnBeginResponse>

    @POST("auth/webauthn/login/complete")
    suspend fun webauthnLoginComplete(@Body request: WebAuthnLoginCompleteRequest): Response<WebAuthnLoginResponse>

    @POST("auth/webauthn/register/begin")
    suspend fun webauthnRegisterBegin(@Body request: WebAuthnLoginBeginRequest): Response<WebAuthnBeginResponse>

    @POST("auth/webauthn/register/complete")
    suspend fun webauthnRegisterComplete(@Body request: com.google.gson.JsonObject): Response<WebAuthnLoginResponse>

    @POST("auth/webauthn/credentials/begin")
    suspend fun webauthnCredentialBegin(): Response<WebAuthnBeginResponse>

    @POST("auth/webauthn/credentials/complete")
    suspend fun webauthnCredentialComplete(@Body request: com.google.gson.JsonObject): Response<CredentialDto>

    // ==================== OIDC ====================

    @POST("auth/oidc/authorize")
    suspend fun oidcAuthorize(@Body request: OidcAuthorizeRequest): Response<OidcAuthorizeResponse>

    @POST("auth/oidc/callback")
    suspend fun oidcCallback(@Body request: OidcCallbackRequest): Response<OidcCallbackResponse>

    @POST("auth/oidc/register")
    suspend fun oidcRegister(@Body request: OidcRegisterRequest): Response<OidcRegisterResponse>

    // ==================== Auth Providers ====================

    @GET("auth/providers")
    suspend fun getAuthProviders(@Query("tenant_slug") tenantSlug: String): Response<AuthProvidersResponse>

    // ==================== Credential Management ====================

    @GET("auth/credentials")
    suspend fun getCredentials(): Response<CredentialsResponse>

    @PUT("auth/credentials/{id}")
    suspend fun renameCredential(
        @Path("id") credentialId: String,
        @Body request: RenameCredentialRequest
    ): Response<CredentialDto>

    @DELETE("auth/credentials/{id}")
    suspend fun deleteCredential(@Path("id") credentialId: String): Response<Unit>

    // ==================== Device Enrollment ====================

    /**
     * Enroll a device with cryptographic binding.
     */
    @POST("devices/enroll")
    suspend fun enrollDevice(@Body request: EnrollDeviceRequest): Response<DeviceEnrollmentResponse>

    /**
     * List all enrolled devices for the current user.
     */
    @GET("devices")
    suspend fun listDeviceEnrollments(): Response<DeviceEnrollmentsResponse>

    /**
     * Get a specific device enrollment.
     */
    @GET("devices/{id}")
    suspend fun getDeviceEnrollment(@Path("id") enrollmentId: String): Response<DeviceEnrollmentResponse>

    /**
     * Update a device enrollment (e.g., rename).
     */
    @PUT("devices/{id}")
    suspend fun updateDeviceEnrollment(
        @Path("id") enrollmentId: String,
        @Body request: UpdateDeviceRequest
    ): Response<DeviceEnrollmentResponse>

    /**
     * Revoke a device enrollment.
     */
    @DELETE("devices/{id}")
    suspend fun revokeDeviceEnrollment(@Path("id") enrollmentId: String): Response<Unit>

    // ==================== Push Notifications (OneSignal) ====================

    /**
     * Register push notification player ID for a device enrollment.
     */
    @POST("devices/{id}/push")
    suspend fun registerPushPlayerId(
        @Path("id") enrollmentId: String,
        @Body request: RegisterPushRequest
    ): Response<DeviceEnrollmentResponse>

    /**
     * Unregister push notifications for a device enrollment.
     */
    @DELETE("devices/{id}/push")
    suspend fun unregisterPush(@Path("id") enrollmentId: String): Response<DeviceEnrollmentResponse>
}
