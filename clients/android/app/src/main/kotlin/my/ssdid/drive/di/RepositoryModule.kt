package my.ssdid.drive.di

import my.ssdid.drive.data.repository.AuthRepositoryImpl
import my.ssdid.drive.data.repository.DeviceRepositoryImpl
import my.ssdid.drive.data.repository.FileRepositoryImpl
import my.ssdid.drive.data.repository.FolderRepositoryImpl
import my.ssdid.drive.data.repository.NotificationRepositoryImpl
import my.ssdid.drive.data.repository.OidcRepositoryImpl
import my.ssdid.drive.data.repository.PiiChatRepositoryImpl
import my.ssdid.drive.data.repository.RecoveryRepositoryImpl
import my.ssdid.drive.data.repository.ShareRepositoryImpl
import my.ssdid.drive.data.repository.TenantRepositoryImpl
import my.ssdid.drive.data.repository.WebAuthnRepositoryImpl
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.DeviceRepository
import my.ssdid.drive.domain.repository.FileRepository
import my.ssdid.drive.domain.repository.FolderRepository
import my.ssdid.drive.domain.repository.NotificationRepository
import my.ssdid.drive.domain.repository.OidcRepository
import my.ssdid.drive.domain.repository.PiiChatRepository
import my.ssdid.drive.domain.repository.RecoveryRepository
import my.ssdid.drive.domain.repository.ShareRepository
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.domain.repository.WebAuthnRepository
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
