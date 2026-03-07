package my.ssdid.drive.data.remote

import com.google.gson.annotations.SerializedName
import my.ssdid.drive.data.remote.AcceptInviteRequest
import my.ssdid.drive.data.remote.AcceptInviteResponse
import my.ssdid.drive.data.remote.ApproveRecoveryRequest
import my.ssdid.drive.data.remote.CompleteRecoveryRequest
import my.ssdid.drive.data.remote.CreateFolderRequest
import my.ssdid.drive.data.remote.CreateRecoveryRequestRequest
import my.ssdid.drive.data.remote.CreateRecoveryShareRequest
import my.ssdid.drive.data.remote.DeviceEnrollmentResponse
import my.ssdid.drive.data.remote.DeviceEnrollmentsResponse
import my.ssdid.drive.data.remote.DownloadUrlResponse
import my.ssdid.drive.data.remote.EnrollDeviceRequest
import my.ssdid.drive.data.remote.FileResponse
import my.ssdid.drive.data.remote.FilesResponse
import my.ssdid.drive.data.remote.FolderResponse
import my.ssdid.drive.data.remote.FoldersResponse
import my.ssdid.drive.data.remote.InvitationAcceptedResponse
import my.ssdid.drive.data.remote.InvitationCreatedResponse
import my.ssdid.drive.data.remote.InvitationsResponse
import my.ssdid.drive.data.remote.InviteInfoResponse
import my.ssdid.drive.data.remote.InviteMemberRequest
import my.ssdid.drive.data.remote.MemberResponse
import my.ssdid.drive.data.remote.MembersResponse
import my.ssdid.drive.data.remote.MoveFileRequest
import my.ssdid.drive.data.remote.MoveFolderRequest
import my.ssdid.drive.data.remote.PublicKeyResponse
import my.ssdid.drive.data.remote.RecoveryApprovalResponse
import my.ssdid.drive.data.remote.RecoveryConfigResponse
import my.ssdid.drive.data.remote.RecoveryRequestDetailResponse
import my.ssdid.drive.data.remote.RecoveryRequestResponse
import my.ssdid.drive.data.remote.RecoveryRequestsResponse
import my.ssdid.drive.data.remote.RecoveryShareResponse
import my.ssdid.drive.data.remote.RecoverySharesResponse
import my.ssdid.drive.data.remote.RegisterPushRequest
import my.ssdid.drive.data.remote.SetExpiryRequest
import my.ssdid.drive.data.remote.SetupRecoveryRequest
import my.ssdid.drive.data.remote.ShareFileRequest
import my.ssdid.drive.data.remote.ShareFolderRequest
import my.ssdid.drive.data.remote.ShareResponse
import my.ssdid.drive.data.remote.SharesResponse
import my.ssdid.drive.data.remote.TenantConfigResponse
import my.ssdid.drive.data.remote.TenantsResponse
import my.ssdid.drive.data.remote.TenantSwitchRequest
import my.ssdid.drive.data.remote.TenantSwitchResponse
import my.ssdid.drive.data.remote.UpdateDeviceRequest
import my.ssdid.drive.data.remote.UpdateFileRequest
import my.ssdid.drive.data.remote.UpdateFolderRequest
import my.ssdid.drive.data.remote.UpdateMemberRoleRequest
import my.ssdid.drive.data.remote.UpdateProfileRequest
import my.ssdid.drive.data.remote.UpdatePermissionRequest
import my.ssdid.drive.data.remote.UploadUrlRequest
import my.ssdid.drive.data.remote.UploadUrlResponse
import my.ssdid.drive.data.remote.UserResponse
import my.ssdid.drive.data.remote.UsersResponse
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

    // ==================== SSDID Authentication ====================

    /**
     * Get server info for SSDID Wallet authentication.
     * Returns server DID, challenge ID, and other info needed to build the wallet deep link.
     * This is an unauthenticated endpoint.
     */
    @GET("auth/ssdid/server-info")
    suspend fun getServerInfo(): ServerInfoResponse

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

/**
 * Server info response for SSDID Wallet authentication.
 * Returned by GET /auth/ssdid/server-info.
 */
data class ServerInfoResponse(
    @SerializedName("server_url") val serverUrl: String,
    @SerializedName("server_did") val serverDid: String,
    @SerializedName("server_key_id") val serverKeyId: String,
    @SerializedName("challenge_id") val challengeId: String,
    @SerializedName("service_name") val serviceName: String,
    @SerializedName("registry_url") val registryUrl: String
)
