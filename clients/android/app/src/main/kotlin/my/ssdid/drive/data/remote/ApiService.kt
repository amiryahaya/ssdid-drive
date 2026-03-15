package my.ssdid.drive.data.remote

import com.google.gson.annotations.SerializedName
import my.ssdid.drive.data.remote.dto.ActivityResponseDto
import my.ssdid.drive.data.remote.dto.AuthResponse
import my.ssdid.drive.data.remote.dto.AcceptInviteRequest
import my.ssdid.drive.data.remote.dto.AcceptInviteResponse
import my.ssdid.drive.data.remote.dto.CompleteRecoveryRequest
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.data.remote.dto.CreateFolderRequest
import my.ssdid.drive.data.remote.dto.DeviceEnrollmentResponse
import my.ssdid.drive.data.remote.dto.DeviceEnrollmentsResponse
import my.ssdid.drive.data.remote.dto.DownloadUrlResponse
import my.ssdid.drive.data.remote.dto.EnrollDeviceRequest
import my.ssdid.drive.data.remote.dto.FileResponse
import my.ssdid.drive.data.remote.dto.FilesResponse
import my.ssdid.drive.data.remote.dto.FolderResponse
import my.ssdid.drive.data.remote.dto.FoldersResponse
import my.ssdid.drive.data.remote.dto.InvitationAcceptedResponse
import my.ssdid.drive.data.remote.dto.InvitationCreatedResponse
import my.ssdid.drive.data.remote.dto.InvitationsResponse
import my.ssdid.drive.data.remote.dto.InviteCodeInfoResponse
import my.ssdid.drive.data.remote.dto.InviteInfoResponse
import my.ssdid.drive.data.remote.dto.InviteMemberRequest
import my.ssdid.drive.data.remote.dto.MemberResponse
import my.ssdid.drive.data.remote.dto.MembersResponse
import my.ssdid.drive.data.remote.dto.MoveFileRequest
import my.ssdid.drive.data.remote.dto.MoveFolderRequest
import my.ssdid.drive.data.remote.dto.PublicKeyResponse
import my.ssdid.drive.data.remote.dto.RegisterPushRequest
import my.ssdid.drive.data.remote.dto.SubmitTenantRequestBody
import my.ssdid.drive.data.remote.dto.TenantRequestResponseDto
import my.ssdid.drive.data.remote.dto.SetExpiryRequest
import my.ssdid.drive.data.remote.dto.SetupRecoveryRequest
import my.ssdid.drive.data.remote.dto.ShareFileRequest
import my.ssdid.drive.data.remote.dto.ShareFolderRequest
import my.ssdid.drive.data.remote.dto.ShareResponse
import my.ssdid.drive.data.remote.dto.SharesResponse
import my.ssdid.drive.data.remote.dto.TenantConfigResponse
import my.ssdid.drive.data.remote.dto.TenantsResponse
import my.ssdid.drive.data.remote.dto.TenantSwitchRequest
import my.ssdid.drive.data.remote.dto.TenantSwitchResponse
import my.ssdid.drive.data.remote.dto.UpdateDeviceRequest
import my.ssdid.drive.data.remote.dto.UpdateFileRequest
import my.ssdid.drive.data.remote.dto.UpdateFolderRequest
import my.ssdid.drive.data.remote.dto.UpdateMemberRoleRequest
import my.ssdid.drive.data.remote.dto.UpdateProfileRequest
import my.ssdid.drive.data.remote.dto.UpdatePermissionRequest
import my.ssdid.drive.data.remote.dto.UploadUrlRequest
import my.ssdid.drive.data.remote.dto.UploadUrlResponse
import my.ssdid.drive.data.remote.dto.UserResponse
import my.ssdid.drive.data.remote.dto.UsersResponse
import retrofit2.Response
import retrofit2.http.*

/**
 * Retrofit API service interface for SSDID Drive backend.
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

    // ==================== Tenant Requests ====================

    /**
     * Submit a request to create a new tenant/organization.
     */
    @POST("tenant-requests")
    suspend fun submitTenantRequest(@Body request: SubmitTenantRequestBody): Response<TenantRequestResponseDto>

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

    // ==================== Invitations - Create & Sent ====================

    /**
     * Create a new invitation.
     * Requires admin or owner role.
     */
    @POST("invitations")
    suspend fun createInvitation(@Body request: my.ssdid.drive.data.remote.dto.CreateInvitationRequest): Response<my.ssdid.drive.data.remote.dto.CreateInvitationResponse>

    /**
     * Get invitations sent by the current user.
     */
    @GET("invitations/sent")
    suspend fun getSentInvitations(
        @Query("page") page: Int = 1,
        @Query("per_page") perPage: Int = 20
    ): Response<my.ssdid.drive.data.remote.dto.SentInvitationsResponse>

    /**
     * Revoke a pending invitation.
     */
    @DELETE("invitations/{id}")
    suspend fun revokeInvitation(@Path("id") invitationId: String): Response<Unit>

    // ==================== Invite Code (Short Code Lookup) ====================

    /**
     * Look up an invitation by short code (e.g. "ACME-7K9X").
     * Public endpoint -- no auth required.
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

    // ==================== Email + TOTP Authentication ====================

    /**
     * Initiate email login. Returns whether TOTP is required.
     */
    @POST("auth/email/login")
    suspend fun emailLogin(@Body request: my.ssdid.drive.data.remote.dto.EmailLoginRequest): Response<my.ssdid.drive.data.remote.dto.EmailLoginResponse>

    /**
     * Register via email with invitation token.
     */
    @POST("auth/email/register")
    suspend fun emailRegister(@Body request: my.ssdid.drive.data.remote.dto.EmailRegisterRequest): Response<my.ssdid.drive.data.remote.dto.SendOtpResponse>

    /**
     * Verify email registration OTP.
     */
    @POST("auth/email/register/verify")
    suspend fun emailRegisterVerify(@Body request: my.ssdid.drive.data.remote.dto.EmailRegisterVerifyRequest): Response<AuthResponse>

    /**
     * Initiate TOTP setup. Returns secret and otpauth URI.
     */
    @POST("auth/totp/setup")
    suspend fun totpSetup(): Response<my.ssdid.drive.data.remote.dto.TotpSetupResponse>

    /**
     * Confirm TOTP setup with first code.
     */
    @POST("auth/totp/setup/confirm")
    suspend fun totpSetupConfirm(@Body request: my.ssdid.drive.data.remote.dto.TotpSetupConfirmRequest): Response<my.ssdid.drive.data.remote.dto.TotpSetupConfirmResponse>

    /**
     * Verify a TOTP code for login.
     */
    @POST("auth/totp/verify")
    suspend fun totpVerify(@Body request: my.ssdid.drive.data.remote.dto.TotpVerifyRequest): Response<AuthResponse>

    /**
     * Initiate TOTP recovery (sends email OTP).
     */
    @POST("auth/totp/recovery")
    suspend fun totpRecovery(@Body request: my.ssdid.drive.data.remote.dto.TotpRecoveryRequest): Response<my.ssdid.drive.data.remote.dto.SendOtpResponse>

    /**
     * Verify TOTP recovery code.
     */
    @POST("auth/totp/recovery/verify")
    suspend fun totpRecoveryVerify(@Body request: my.ssdid.drive.data.remote.dto.TotpRecoveryVerifyRequest): Response<AuthResponse>

    // ==================== OIDC Authentication ====================

    /**
     * Verify an OIDC ID token (login or register).
     */
    @POST("auth/oidc/verify")
    suspend fun oidcVerify(@Body request: my.ssdid.drive.data.remote.dto.OidcVerifyRequest): Response<AuthResponse>

    // ==================== Account Logins (Linking) ====================

    /**
     * List linked logins for the current account.
     */
    @GET("account/logins")
    suspend fun getLinkedLogins(): Response<my.ssdid.drive.data.remote.dto.LinkedLoginsResponse>

    /**
     * Initiate linking an email login.
     */
    @POST("account/logins/email")
    suspend fun linkEmail(@Body request: my.ssdid.drive.data.remote.dto.LinkEmailRequest): Response<my.ssdid.drive.data.remote.dto.SendOtpResponse>

    /**
     * Verify email link OTP.
     */
    @POST("account/logins/email/verify")
    suspend fun linkEmailVerify(@Body request: my.ssdid.drive.data.remote.dto.LinkEmailVerifyRequest): Response<my.ssdid.drive.data.remote.dto.LinkedLoginDto>

    /**
     * Link an OIDC login.
     */
    @POST("account/logins/oidc")
    suspend fun linkOidc(@Body request: my.ssdid.drive.data.remote.dto.LinkOidcRequest): Response<my.ssdid.drive.data.remote.dto.LinkedLoginDto>

    /**
     * Unlink a login method.
     */
    @DELETE("account/logins/{id}")
    suspend fun unlinkLogin(@Path("id") loginId: String): Response<Unit>

    // ==================== Legacy SSDID Authentication ====================

    @GET("auth/ssdid/server-info")
    suspend fun getServerInfo(): ServerInfoResponse

    @POST("auth/ssdid/login/initiate")
    suspend fun loginInitiate(): LoginInitiateResponse

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

    @POST("recovery/setup")
    suspend fun setupRecovery(@Body request: SetupRecoveryRequest): Response<Unit>

    @GET("recovery/status")
    suspend fun getRecoveryStatus(): Response<RecoveryStatusResponse>

    @GET("recovery/share")
    suspend fun getRecoveryShare(@Query("did") did: String): Response<ServerShareResponse>

    @POST("recovery/complete")
    suspend fun completeRecovery(@Body request: CompleteRecoveryRequest): Response<CompleteRecoveryResponse>

    @DELETE("recovery/setup")
    suspend fun deleteRecoverySetup(): Response<Unit>

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

    // ==================== Activity Logs ====================

    /**
     * Get activity log entries with optional filtering and pagination.
     */
    @GET("activity")
    suspend fun getActivity(
        @Query("page") page: Int? = null,
        @Query("page_size") pageSize: Int? = null,
        @Query("event_type") eventType: String? = null,
        @Query("resource_type") resourceType: String? = null
    ): Response<ActivityResponseDto>

    /**
     * Get activity log entries for a specific resource.
     */
    @GET("activity/resource/{id}")
    suspend fun getResourceActivity(
        @Path("id") resourceId: String,
        @Query("page") page: Int? = null,
        @Query("page_size") pageSize: Int? = null
    ): Response<ActivityResponseDto>

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

/**
 * Server info response for SSDID Wallet authentication.
 * Returned by GET /auth/ssdid/server-info.
 */
data class ServerInfoResponse(
    @SerializedName("server_did") val serverDid: String,
    @SerializedName("server_key_id") val serverKeyId: String,
    @SerializedName("service_name") val serviceName: String,
    @SerializedName("registry_url") val registryUrl: String
)

/**
 * Response from POST /auth/ssdid/login/initiate.
 * Contains challenge info and QR payload for wallet authentication.
 */
data class LoginInitiateResponse(
    @SerializedName("challenge_id") val challengeId: String,
    @SerializedName("subscriber_secret") val subscriberSecret: String,
    @SerializedName("qr_payload") val qrPayload: QrPayload
)

data class QrPayload(
    @SerializedName("action") val action: String,
    @SerializedName("service_url") val serviceUrl: String,
    @SerializedName("service_name") val serviceName: String,
    @SerializedName("challenge_id") val challengeId: String,
    @SerializedName("challenge") val challenge: String,
    @SerializedName("server_did") val serverDid: String,
    @SerializedName("server_key_id") val serverKeyId: String,
    @SerializedName("server_signature") val serverSignature: String,
    @SerializedName("registry_url") val registryUrl: String,
    @SerializedName("requested_claims") val requestedClaims: RequestedClaims? = null
)

data class RequestedClaims(
    @SerializedName("required") val required: List<String>? = null,
    @SerializedName("optional") val optional: List<String>? = null
)
