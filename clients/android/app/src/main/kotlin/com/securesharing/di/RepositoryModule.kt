package com.securesharing.di

import com.securesharing.data.repository.AuthRepositoryImpl
import com.securesharing.data.repository.DeviceRepositoryImpl
import com.securesharing.data.repository.FileRepositoryImpl
import com.securesharing.data.repository.FolderRepositoryImpl
import com.securesharing.data.repository.NotificationRepositoryImpl
import com.securesharing.data.repository.OidcRepositoryImpl
import com.securesharing.data.repository.PiiChatRepositoryImpl
import com.securesharing.data.repository.RecoveryRepositoryImpl
import com.securesharing.data.repository.ShareRepositoryImpl
import com.securesharing.data.repository.TenantRepositoryImpl
import com.securesharing.data.repository.WebAuthnRepositoryImpl
import com.securesharing.domain.repository.AuthRepository
import com.securesharing.domain.repository.DeviceRepository
import com.securesharing.domain.repository.FileRepository
import com.securesharing.domain.repository.FolderRepository
import com.securesharing.domain.repository.NotificationRepository
import com.securesharing.domain.repository.OidcRepository
import com.securesharing.domain.repository.PiiChatRepository
import com.securesharing.domain.repository.RecoveryRepository
import com.securesharing.domain.repository.ShareRepository
import com.securesharing.domain.repository.TenantRepository
import com.securesharing.domain.repository.WebAuthnRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindAuthRepository(
        authRepositoryImpl: AuthRepositoryImpl
    ): AuthRepository

    @Binds
    @Singleton
    abstract fun bindTenantRepository(
        tenantRepositoryImpl: TenantRepositoryImpl
    ): TenantRepository

    @Binds
    @Singleton
    abstract fun bindFolderRepository(
        folderRepositoryImpl: FolderRepositoryImpl
    ): FolderRepository

    @Binds
    @Singleton
    abstract fun bindFileRepository(
        fileRepositoryImpl: FileRepositoryImpl
    ): FileRepository

    @Binds
    @Singleton
    abstract fun bindShareRepository(
        shareRepositoryImpl: ShareRepositoryImpl
    ): ShareRepository

    @Binds
    @Singleton
    abstract fun bindRecoveryRepository(
        recoveryRepositoryImpl: RecoveryRepositoryImpl
    ): RecoveryRepository

    @Binds
    @Singleton
    abstract fun bindNotificationRepository(
        notificationRepositoryImpl: NotificationRepositoryImpl
    ): NotificationRepository

    @Binds
    @Singleton
    abstract fun bindDeviceRepository(
        deviceRepositoryImpl: DeviceRepositoryImpl
    ): DeviceRepository

    @Binds
    @Singleton
    abstract fun bindPiiChatRepository(
        piiChatRepositoryImpl: PiiChatRepositoryImpl
    ): PiiChatRepository

    @Binds
    @Singleton
    abstract fun bindOidcRepository(
        oidcRepositoryImpl: OidcRepositoryImpl
    ): OidcRepository

    @Binds
    @Singleton
    abstract fun bindWebAuthnRepository(
        webAuthnRepositoryImpl: WebAuthnRepositoryImpl
    ): WebAuthnRepository
}
