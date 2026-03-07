//! Biometric authentication service
//!
//! Provides platform-specific biometric authentication:
//! - Windows: Windows Hello (fingerprint, face, PIN)
//! - macOS: Touch ID

use crate::error::{AppError, AppResult};
use crate::storage::Database;
use parking_lot::RwLock;
use std::sync::Arc;

/// Biometric authentication availability status
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BiometricAvailability {
    /// Biometric authentication is available and ready
    Available,
    /// Device has biometric hardware but it's not configured
    NotConfigured,
    /// No biometric hardware available
    NotAvailable,
    /// Biometric is disabled by policy
    DisabledByPolicy,
    /// Unknown status
    Unknown,
}

/// Biometric authentication result
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BiometricStatus {
    pub available: bool,
    pub availability: BiometricAvailability,
    pub biometric_type: Option<String>,
    pub message: String,
}

/// Service for biometric authentication
pub struct BiometricService {
    /// Whether biometric is enabled by user preference
    enabled: RwLock<bool>,
    /// Database for persisting preferences
    database: Arc<Database>,
}

impl BiometricService {
    /// Create a new biometric service, loading saved preference from database
    pub fn new(database: Arc<Database>) -> Self {
        // Load saved biometric preference from settings
        let saved_enabled = database
            .with_connection(|conn| {
                let json: Option<String> = conn
                    .query_row(
                        "SELECT value FROM settings WHERE key = 'app_settings'",
                        [],
                        |row| row.get(0),
                    )
                    .ok();
                match json {
                    Some(s) => {
                        let settings: serde_json::Value = serde_json::from_str(&s)
                            .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
                        Ok(settings
                            .get("biometric_enabled")
                            .and_then(|v| v.as_bool())
                            .unwrap_or(false))
                    }
                    None => Ok(false),
                }
            })
            .unwrap_or(false);

        Self {
            enabled: RwLock::new(saved_enabled),
            database,
        }
    }

    /// Check if biometric is enabled by user
    pub fn is_enabled(&self) -> bool {
        *self.enabled.read()
    }

    /// Set biometric enabled state and persist to database
    pub fn set_enabled(&self, enabled: bool) {
        *self.enabled.write() = enabled;

        // Persist to database settings
        let db = self.database.clone();
        let _ = db.with_write_connection(|conn| {
            // Read current settings
            let json: Option<String> = conn
                .query_row(
                    "SELECT value FROM settings WHERE key = 'app_settings'",
                    [],
                    |row| row.get(0),
                )
                .ok();

            let mut settings: serde_json::Value = json
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!({}));

            settings["biometric_enabled"] = serde_json::json!(enabled);

            let updated = serde_json::to_string(&settings)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;

            conn.execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES ('app_settings', ?1)",
                rusqlite::params![updated],
            )?;
            Ok(())
        });
    }

    /// Check biometric availability on this device
    pub async fn check_availability(&self) -> AppResult<BiometricStatus> {
        #[cfg(target_os = "windows")]
        {
            self.check_windows_hello().await
        }

        #[cfg(target_os = "macos")]
        {
            self.check_touch_id().await
        }

        #[cfg(not(any(target_os = "windows", target_os = "macos")))]
        {
            Ok(BiometricStatus {
                available: false,
                availability: BiometricAvailability::NotAvailable,
                biometric_type: None,
                message: "Biometric authentication is not supported on this platform".to_string(),
            })
        }
    }

    /// Authenticate using biometric
    pub async fn authenticate(&self, reason: &str) -> AppResult<bool> {
        // Check if enabled first
        if !self.is_enabled() {
            return Err(AppError::Auth("Biometric authentication is not enabled".to_string()));
        }

        #[cfg(target_os = "windows")]
        {
            self.authenticate_windows_hello(reason).await
        }

        #[cfg(target_os = "macos")]
        {
            self.authenticate_touch_id(reason).await
        }

        #[cfg(not(any(target_os = "windows", target_os = "macos")))]
        {
            Err(AppError::Auth("Biometric authentication is not supported on this platform".to_string()))
        }
    }

    // =========================================================================
    // Windows Hello Implementation
    // =========================================================================

    #[cfg(target_os = "windows")]
    async fn check_windows_hello(&self) -> AppResult<BiometricStatus> {
        use windows::Security::Credentials::UI::{
            UserConsentVerifier, UserConsentVerifierAvailability,
        };

        tracing::debug!("Checking Windows Hello availability");

        // Windows IAsyncOperation requires blocking - use spawn_blocking
        let availability = tokio::task::spawn_blocking(|| {
            UserConsentVerifier::CheckAvailabilityAsync()
                .and_then(|op| op.get())
        })
        .await
        .map_err(|e| AppError::Auth(format!("Task join error: {}", e)))?
        .map_err(|e| AppError::Auth(format!("Failed to check Windows Hello: {}", e)))?;

        let (available, bio_availability, message) = match availability {
            UserConsentVerifierAvailability::Available => (
                true,
                BiometricAvailability::Available,
                "Windows Hello is available".to_string(),
            ),
            UserConsentVerifierAvailability::DeviceNotPresent => (
                false,
                BiometricAvailability::NotAvailable,
                "No biometric device found".to_string(),
            ),
            UserConsentVerifierAvailability::NotConfiguredForUser => (
                false,
                BiometricAvailability::NotConfigured,
                "Windows Hello is not set up. Please configure it in Windows Settings.".to_string(),
            ),
            UserConsentVerifierAvailability::DisabledByPolicy => (
                false,
                BiometricAvailability::DisabledByPolicy,
                "Windows Hello is disabled by system policy".to_string(),
            ),
            UserConsentVerifierAvailability::DeviceBusy => (
                false,
                BiometricAvailability::Unknown,
                "Biometric device is busy".to_string(),
            ),
            _ => (
                false,
                BiometricAvailability::Unknown,
                "Unknown Windows Hello status".to_string(),
            ),
        };

        tracing::info!("Windows Hello availability: {:?}", bio_availability);

        Ok(BiometricStatus {
            available,
            availability: bio_availability,
            biometric_type: if available {
                Some("Windows Hello".to_string())
            } else {
                None
            },
            message,
        })
    }

    #[cfg(target_os = "windows")]
    async fn authenticate_windows_hello(&self, reason: &str) -> AppResult<bool> {
        use windows::Security::Credentials::UI::{
            UserConsentVerificationResult, UserConsentVerifier,
        };
        use windows::core::HSTRING;

        tracing::info!("Requesting Windows Hello authentication");

        let message = HSTRING::from(reason);

        // Windows IAsyncOperation requires blocking - use spawn_blocking
        let result = tokio::task::spawn_blocking(move || {
            UserConsentVerifier::RequestVerificationAsync(&message)
                .and_then(|op| op.get())
        })
        .await
        .map_err(|e| AppError::Auth(format!("Task join error: {}", e)))?
        .map_err(|e| AppError::Auth(format!("Windows Hello authentication failed: {}", e)))?;

        match result {
            UserConsentVerificationResult::Verified => {
                tracing::info!("Windows Hello authentication successful");
                Ok(true)
            }
            UserConsentVerificationResult::DeviceNotPresent => {
                tracing::warn!("Windows Hello: device not present");
                Err(AppError::Auth("No biometric device available".to_string()))
            }
            UserConsentVerificationResult::NotConfiguredForUser => {
                tracing::warn!("Windows Hello: not configured");
                Err(AppError::Auth("Windows Hello is not configured".to_string()))
            }
            UserConsentVerificationResult::DisabledByPolicy => {
                tracing::warn!("Windows Hello: disabled by policy");
                Err(AppError::Auth("Windows Hello is disabled by policy".to_string()))
            }
            UserConsentVerificationResult::DeviceBusy => {
                tracing::warn!("Windows Hello: device busy");
                Err(AppError::Auth("Biometric device is busy".to_string()))
            }
            UserConsentVerificationResult::RetriesExhausted => {
                tracing::warn!("Windows Hello: retries exhausted");
                Err(AppError::Auth("Too many failed attempts".to_string()))
            }
            UserConsentVerificationResult::Canceled => {
                tracing::info!("Windows Hello: canceled by user");
                Ok(false)
            }
            _ => {
                tracing::warn!("Windows Hello: unknown result");
                Err(AppError::Auth("Authentication failed".to_string()))
            }
        }
    }

    // =========================================================================
    // macOS Touch ID Implementation
    // =========================================================================

    #[cfg(target_os = "macos")]
    async fn check_touch_id(&self) -> AppResult<BiometricStatus> {
        use std::process::Command;

        tracing::debug!("Checking Touch ID availability");

        // Use bioutil to check if Touch ID is available
        // This is a simpler approach that works reliably
        let output = Command::new("bioutil")
            .args(["-r", "-s"])
            .output();

        match output {
            Ok(result) => {
                let stdout = String::from_utf8_lossy(&result.stdout);
                let has_touch_id = stdout.contains("Touch ID") || result.status.success();

                if has_touch_id {
                    // Check if Touch ID is actually enrolled
                    let enrolled = Command::new("bioutil")
                        .args(["-c"])
                        .output()
                        .map(|o| o.status.success())
                        .unwrap_or(false);

                    if enrolled {
                        tracing::info!("Touch ID is available and configured");
                        Ok(BiometricStatus {
                            available: true,
                            availability: BiometricAvailability::Available,
                            biometric_type: Some("Touch ID".to_string()),
                            message: "Touch ID is available".to_string(),
                        })
                    } else {
                        tracing::info!("Touch ID hardware present but not configured");
                        Ok(BiometricStatus {
                            available: false,
                            availability: BiometricAvailability::NotConfigured,
                            biometric_type: Some("Touch ID".to_string()),
                            message: "Touch ID is not set up. Please configure it in System Preferences.".to_string(),
                        })
                    }
                } else {
                    tracing::info!("Touch ID not available on this device");
                    Ok(BiometricStatus {
                        available: false,
                        availability: BiometricAvailability::NotAvailable,
                        biometric_type: None,
                        message: "Touch ID is not available on this device".to_string(),
                    })
                }
            }
            Err(_) => {
                // bioutil not available, try alternative detection
                // Check if running on Apple Silicon or has Touch ID via system_profiler
                let hw_check = Command::new("system_profiler")
                    .args(["SPiBridgeDataType"])
                    .output();

                let has_secure_enclave = hw_check
                    .map(|o| {
                        let stdout = String::from_utf8_lossy(&o.stdout);
                        stdout.contains("T2") || stdout.contains("Apple")
                    })
                    .unwrap_or(false);

                if has_secure_enclave {
                    Ok(BiometricStatus {
                        available: false,
                        availability: BiometricAvailability::NotConfigured,
                        biometric_type: Some("Touch ID".to_string()),
                        message: "Touch ID may be available. Please check System Preferences.".to_string(),
                    })
                } else {
                    Ok(BiometricStatus {
                        available: false,
                        availability: BiometricAvailability::NotAvailable,
                        biometric_type: None,
                        message: "Touch ID is not available on this device".to_string(),
                    })
                }
            }
        }
    }

    #[cfg(target_os = "macos")]
    async fn authenticate_touch_id(&self, reason: &str) -> AppResult<bool> {
        use std::process::Command;

        tracing::info!("Requesting Touch ID authentication");

        // Use osascript to trigger Touch ID via LocalAuthentication
        // This provides a native Touch ID prompt
        let script = format!(
            r#"
            use framework "LocalAuthentication"
            set authContext to current application's LAContext's alloc()'s init()
            set authReason to "{}"

            set canAuth to authContext's canEvaluatePolicy:1 |error|:(missing value)
            if canAuth then
                set authResult to authContext's evaluatePolicy:1 localizedReason:authReason |error|:(missing value)
                if authResult then
                    return "success"
                else
                    return "failed"
                end if
            else
                return "unavailable"
            end if
            "#,
            reason.replace('"', r#"\""#)
        );

        let output = Command::new("osascript")
            .args(["-l", "AppleScript", "-e", &script])
            .output()
            .map_err(|e| AppError::Auth(format!("Failed to invoke Touch ID: {}", e)))?;

        let result = String::from_utf8_lossy(&output.stdout).trim().to_string();

        match result.as_str() {
            "success" => {
                tracing::info!("Touch ID authentication successful");
                Ok(true)
            }
            "failed" => {
                tracing::warn!("Touch ID authentication failed or canceled");
                Ok(false)
            }
            "unavailable" => {
                tracing::warn!("Touch ID unavailable");
                Err(AppError::Auth("Touch ID is not available".to_string()))
            }
            _ => {
                // Check stderr for more info
                let stderr = String::from_utf8_lossy(&output.stderr);
                if stderr.contains("cancel") || stderr.contains("Cancel") {
                    tracing::info!("Touch ID canceled by user");
                    Ok(false)
                } else {
                    tracing::error!("Touch ID error: {}", stderr);
                    Err(AppError::Auth("Touch ID authentication failed".to_string()))
                }
            }
        }
    }
}

// Note: BiometricService no longer implements Default since it requires a Database reference
