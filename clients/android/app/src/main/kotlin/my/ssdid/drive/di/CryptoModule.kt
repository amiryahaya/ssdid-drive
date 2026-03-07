package my.ssdid.drive.di

import android.content.Context
import my.ssdid.drive.crypto.CryptoConfig
import my.ssdid.drive.crypto.CryptoManager
import my.ssdid.drive.crypto.FileDecryptor
import my.ssdid.drive.crypto.FileEncryptor
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.KeyEncapsulation
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.crypto.PublicKeyCache
import my.ssdid.drive.crypto.RecoveryKeyManager
import my.ssdid.drive.crypto.ShamirSecretSharing
import my.ssdid.drive.crypto.providers.AesGcmProvider
import my.ssdid.drive.crypto.providers.HkdfProvider
import my.ssdid.drive.crypto.providers.KazKemProvider
import my.ssdid.drive.crypto.providers.KazSignProvider
import my.ssdid.drive.crypto.providers.MlKemProvider
import my.ssdid.drive.crypto.providers.MlDsaProvider
import my.ssdid.drive.util.BufferPool
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object CryptoModule {

    @Provides
    @Singleton
    fun provideCryptoConfig(): CryptoConfig {
        return CryptoConfig()
    }

    @Provides
    @Singleton
    fun provideAesGcmProvider(): AesGcmProvider {
        return AesGcmProvider()
    }

    @Provides
    @Singleton
    fun provideHkdfProvider(): HkdfProvider {
        return HkdfProvider()
    }

    @Provides
    @Singleton
    fun provideKazKemProvider(): KazKemProvider {
        return KazKemProvider()
    }

    @Provides
    @Singleton
    fun provideKazSignProvider(): KazSignProvider {
        return KazSignProvider()
    }

    @Provides
    @Singleton
    fun provideMlKemProvider(): MlKemProvider {
        return MlKemProvider()
    }

    @Provides
    @Singleton
    fun provideMlDsaProvider(): MlDsaProvider {
        return MlDsaProvider()
    }

    @Provides
    @Singleton
    fun provideCryptoManager(
        aesGcmProvider: AesGcmProvider,
        hkdfProvider: HkdfProvider,
        kazKemProvider: KazKemProvider,
        kazSignProvider: KazSignProvider,
        mlKemProvider: MlKemProvider,
        mlDsaProvider: MlDsaProvider,
        cryptoConfig: CryptoConfig
    ): CryptoManager {
        return CryptoManager(
            aesGcmProvider = aesGcmProvider,
            hkdfProvider = hkdfProvider,
            kazKemProvider = kazKemProvider,
            kazSignProvider = kazSignProvider,
            mlKemProvider = mlKemProvider,
            mlDsaProvider = mlDsaProvider,
            cryptoConfig = cryptoConfig
        )
    }

    @Provides
    @Singleton
    fun provideKeyManager(
        @ApplicationContext context: Context,
        cryptoManager: CryptoManager
    ): KeyManager {
        return KeyManager(context, cryptoManager)
    }

    @Provides
    @Singleton
    fun provideFolderKeyManager(
        cryptoManager: CryptoManager,
        keyManager: KeyManager
    ): FolderKeyManager {
        return FolderKeyManager(cryptoManager, keyManager)
    }

    @Provides
    @Singleton
    fun provideBufferPool(): BufferPool {
        return BufferPool()
    }

    @Provides
    @Singleton
    fun providePublicKeyCache(): PublicKeyCache {
        return PublicKeyCache()
    }

    @Provides
    @Singleton
    fun provideFileEncryptor(
        @ApplicationContext context: Context,
        cryptoManager: CryptoManager,
        keyManager: KeyManager,
        folderKeyManager: FolderKeyManager,
        bufferPool: BufferPool
    ): FileEncryptor {
        return FileEncryptor(context, cryptoManager, keyManager, folderKeyManager, bufferPool)
    }

    @Provides
    @Singleton
    fun provideFileDecryptor(
        @ApplicationContext context: Context,
        cryptoManager: CryptoManager,
        keyManager: KeyManager,
        folderKeyManager: FolderKeyManager
    ): FileDecryptor {
        return FileDecryptor(context, cryptoManager, keyManager, folderKeyManager)
    }

    @Provides
    @Singleton
    fun provideKeyEncapsulation(
        cryptoManager: CryptoManager,
        keyManager: KeyManager
    ): KeyEncapsulation {
        return KeyEncapsulation(cryptoManager, keyManager)
    }

    @Provides
    @Singleton
    fun provideShamirSecretSharing(): ShamirSecretSharing {
        return ShamirSecretSharing()
    }

    @Provides
    @Singleton
    fun provideRecoveryKeyManager(
        cryptoManager: CryptoManager,
        keyManager: KeyManager,
        shamirSecretSharing: ShamirSecretSharing
    ): RecoveryKeyManager {
        return RecoveryKeyManager(cryptoManager, keyManager, shamirSecretSharing)
    }
}
