package com.securesharing.di

import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.securesharing.BuildConfig
import com.securesharing.data.remote.ApiService
import com.securesharing.data.remote.PiiApiService
import com.securesharing.data.remote.AuthInterceptor
import com.securesharing.data.remote.DeviceSignatureInterceptor
import com.securesharing.data.remote.TokenRefreshAuthenticator
import com.securesharing.crypto.DeviceManager
import com.securesharing.data.local.SecureStorage
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.CertificatePinner
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Qualifier
import javax.inject.Singleton

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class AuthenticatedClient

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class UnauthenticatedClient

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    private const val CONNECT_TIMEOUT = 30L
    private const val READ_TIMEOUT = 30L
    private const val WRITE_TIMEOUT = 60L

    @Provides
    @Singleton
    fun provideGson(): Gson {
        return GsonBuilder()
            .setDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
            .create()
    }

    @Provides
    @Singleton
    fun provideLoggingInterceptor(): HttpLoggingInterceptor {
        return HttpLoggingInterceptor().apply {
            // SECURITY: Use HEADERS instead of BODY to avoid logging sensitive data
            // BODY level would log tokens, passwords, and encrypted content
            level = if (BuildConfig.DEBUG) {
                HttpLoggingInterceptor.Level.HEADERS
            } else {
                HttpLoggingInterceptor.Level.NONE
            }
        }
    }

    /**
     * Provides certificate pinning for SSL/TLS connections.
     *
     * SECURITY: Certificate pinning prevents MITM attacks even if a CA is compromised.
     *
     * To generate pins from your server certificate, use:
     * ```bash
     * openssl s_client -servername YOUR_DOMAIN -connect YOUR_DOMAIN:443 2>/dev/null | \
     *   openssl x509 -pubkey -noout | \
     *   openssl pkey -pubin -outform der | \
     *   openssl dgst -sha256 -binary | \
     *   openssl enc -base64
     * ```
     *
     * Always include a backup pin for certificate rotation.
     * Configure CERT_PIN_PRIMARY and CERT_PIN_BACKUP in build.gradle.kts for each flavor.
     */
    @Provides
    @Singleton
    fun provideCertificatePinner(): CertificatePinner {
        // Extract domain from API_BASE_URL (e.g., "https://api.example.com/api/" -> "api.example.com")
        val apiDomain = try {
            val url = java.net.URL(BuildConfig.API_BASE_URL)
            url.host
        } catch (e: Exception) {
            "api.securesharing.example"
        }

        return CertificatePinner.Builder()
            .apply {
                // SECURITY: Use BuildConfig fields configured in build.gradle.kts
                val primaryPin = BuildConfig.CERT_PIN_PRIMARY
                val backupPin = BuildConfig.CERT_PIN_BACKUP

                // Only add pins if they are configured (not placeholder values)
                if (!primaryPin.isNullOrBlank() && !primaryPin.startsWith("REPLACE_")) {
                    add(apiDomain, "sha256/$primaryPin")
                }
                if (!backupPin.isNullOrBlank() && !backupPin.startsWith("REPLACE_")) {
                    add(apiDomain, "sha256/$backupPin")
                }
            }
            .build()
    }

    @Provides
    @Singleton
    fun provideAuthInterceptor(secureStorage: SecureStorage): AuthInterceptor {
        return AuthInterceptor(secureStorage)
    }

    @Provides
    @Singleton
    fun provideTokenRefreshAuthenticator(
        secureStorage: SecureStorage,
        gson: Gson
    ): TokenRefreshAuthenticator {
        return TokenRefreshAuthenticator(secureStorage, gson)
    }

    @Provides
    @Singleton
    fun provideDeviceSignatureInterceptor(
        secureStorage: SecureStorage,
        deviceManager: DeviceManager
    ): DeviceSignatureInterceptor {
        return DeviceSignatureInterceptor(secureStorage, deviceManager)
    }

    @Provides
    @Singleton
    @UnauthenticatedClient
    fun provideUnauthenticatedOkHttpClient(
        loggingInterceptor: HttpLoggingInterceptor,
        certificatePinner: CertificatePinner
    ): OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(CONNECT_TIMEOUT, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT, TimeUnit.SECONDS)
            .writeTimeout(WRITE_TIMEOUT, TimeUnit.SECONDS)
            .addInterceptor(loggingInterceptor)
            // SECURITY: Certificate pinning to prevent MITM attacks
            // Disabled for debug builds to allow local development with self-signed certs
            .apply {
                if (!BuildConfig.DEBUG) {
                    certificatePinner(certificatePinner)
                }
            }
            .build()
    }

    @Provides
    @Singleton
    @AuthenticatedClient
    fun provideAuthenticatedOkHttpClient(
        loggingInterceptor: HttpLoggingInterceptor,
        authInterceptor: AuthInterceptor,
        deviceSignatureInterceptor: DeviceSignatureInterceptor,
        tokenRefreshAuthenticator: TokenRefreshAuthenticator,
        certificatePinner: CertificatePinner
    ): OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(CONNECT_TIMEOUT, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT, TimeUnit.SECONDS)
            .writeTimeout(WRITE_TIMEOUT, TimeUnit.SECONDS)
            .addInterceptor(authInterceptor)
            .addInterceptor(deviceSignatureInterceptor)
            .addInterceptor(loggingInterceptor)
            .authenticator(tokenRefreshAuthenticator)
            // SECURITY: Certificate pinning to prevent MITM attacks
            // Disabled for debug builds to allow local development with self-signed certs
            .apply {
                if (!BuildConfig.DEBUG) {
                    certificatePinner(certificatePinner)
                }
            }
            .build()
    }

    @Provides
    @Singleton
    fun provideRetrofit(
        @AuthenticatedClient okHttpClient: OkHttpClient,
        gson: Gson
    ): Retrofit {
        return Retrofit.Builder()
            .baseUrl(BuildConfig.API_BASE_URL)
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
    }

    @Provides
    @Singleton
    fun provideApiService(retrofit: Retrofit): ApiService {
        return retrofit.create(ApiService::class.java)
    }

    @Provides
    @Singleton
    fun providePiiApiService(retrofit: Retrofit): PiiApiService {
        return retrofit.create(PiiApiService::class.java)
    }
}
