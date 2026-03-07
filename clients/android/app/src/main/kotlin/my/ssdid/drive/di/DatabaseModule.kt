package my.ssdid.drive.di

import android.content.Context
import androidx.room.Room
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import my.ssdid.drive.data.local.SsdidDriveDatabase
import my.ssdid.drive.data.local.dao.ChatMessageDao
import my.ssdid.drive.data.local.dao.ConversationDao
import my.ssdid.drive.data.local.dao.FileDao
import my.ssdid.drive.data.local.dao.FolderDao
import my.ssdid.drive.data.local.dao.NotificationDao
import my.ssdid.drive.data.local.dao.PendingOperationDao
import my.ssdid.drive.data.local.dao.ShareDao
import my.ssdid.drive.data.local.dao.UserDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import net.sqlcipher.database.SupportFactory
import java.security.SecureRandom
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    private const val DATABASE_NAME = "ssdid_drive.db"
    private const val DB_KEY_PREFS = "ssdid_drive_db_key_prefs"
    private const val DB_KEY = "database_encryption_key"
    private const val DB_KEY_LENGTH = 32 // 256-bit key

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): SsdidDriveDatabase {
        // Get or generate the database encryption key
        val passphrase = getOrCreateDatabaseKey(context)

        // Create SQLCipher SupportFactory with the passphrase
        val factory = SupportFactory(passphrase)

        return Room.databaseBuilder(
            context,
            SsdidDriveDatabase::class.java,
            DATABASE_NAME
        )
        .openHelperFactory(factory)
        .fallbackToDestructiveMigration()
        .build()
    }

    /**
     * Get or create the database encryption key.
     * The key is stored securely in EncryptedSharedPreferences.
     */
    private fun getOrCreateDatabaseKey(context: Context): ByteArray {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        val encryptedPrefs = EncryptedSharedPreferences.create(
            context,
            DB_KEY_PREFS,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )

        // Check if key already exists
        val existingKey = encryptedPrefs.getString(DB_KEY, null)
        if (existingKey != null) {
            return android.util.Base64.decode(existingKey, android.util.Base64.NO_WRAP)
        }

        // Generate new key
        val newKey = ByteArray(DB_KEY_LENGTH)
        SecureRandom().nextBytes(newKey)

        // Store the key
        encryptedPrefs.edit()
            .putString(DB_KEY, android.util.Base64.encodeToString(newKey, android.util.Base64.NO_WRAP))
            .apply()

        return newKey
    }

    @Provides
    @Singleton
    fun provideFolderDao(database: SsdidDriveDatabase): FolderDao {
        return database.folderDao()
    }

    @Provides
    @Singleton
    fun provideFileDao(database: SsdidDriveDatabase): FileDao {
        return database.fileDao()
    }

    @Provides
    @Singleton
    fun provideShareDao(database: SsdidDriveDatabase): ShareDao {
        return database.shareDao()
    }

    @Provides
    @Singleton
    fun provideUserDao(database: SsdidDriveDatabase): UserDao {
        return database.userDao()
    }

    @Provides
    @Singleton
    fun providePendingOperationDao(database: SsdidDriveDatabase): PendingOperationDao {
        return database.pendingOperationDao()
    }

    @Provides
    @Singleton
    fun provideNotificationDao(database: SsdidDriveDatabase): NotificationDao {
        return database.notificationDao()
    }

    @Provides
    @Singleton
    fun provideConversationDao(database: SsdidDriveDatabase): ConversationDao {
        return database.conversationDao()
    }

    @Provides
    @Singleton
    fun provideChatMessageDao(database: SsdidDriveDatabase): ChatMessageDao {
        return database.chatMessageDao()
    }
}
