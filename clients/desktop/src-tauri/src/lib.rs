//! SecureSharing Desktop Application
//!
//! Cross-platform desktop client with post-quantum cryptography support.

pub mod commands;
pub mod error;
pub mod models;
pub mod services;
pub mod state;
pub mod storage;
pub mod tray;

use tauri::Manager;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

pub use error::{AppError, AppResult};
pub use state::AppState;

/// Initialize Sentry error tracking
fn init_sentry() -> Option<sentry::ClientInitGuard> {
    // Read Sentry DSN from environment variable
    let dsn = std::env::var("SENTRY_DSN").ok()?;

    if dsn.is_empty() {
        tracing::info!("Sentry DSN not configured, error tracking disabled");
        return None;
    }

    let environment = if cfg!(debug_assertions) {
        "development"
    } else {
        "production"
    };

    let guard = sentry::init((
        dsn,
        sentry::ClientOptions {
            release: Some(std::borrow::Cow::Borrowed(concat!(
                "securesharing-desktop@",
                env!("CARGO_PKG_VERSION")
            ))),
            environment: Some(std::borrow::Cow::Borrowed(environment)),
            // Sample rate for transactions (performance monitoring)
            traces_sample_rate: if cfg!(debug_assertions) { 1.0 } else { 0.1 },
            // Attach stacktraces to messages
            attach_stacktrace: true,
            // Send default PII (be careful with GDPR)
            send_default_pii: false,
            ..Default::default()
        },
    ));

    // Configure Sentry tracing integration
    tracing::info!("Sentry initialized for {} environment", environment);

    Some(guard)
}

/// Initialize and run the Tauri application
pub fn run() {
    // Initialize Sentry first (before any errors can occur)
    let _sentry_guard = init_sentry();

    // Initialize logging with Sentry integration
    let sentry_layer = sentry_tracing::layer();

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "securesharing_desktop=debug,tauri=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .with(sentry_layer)
        .init();

    tracing::info!("Starting SecureSharing Desktop v{}", env!("CARGO_PKG_VERSION"));

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            // Initialize application state
            let state = AppState::new()?;
            app.manage(state);

            // Initialize system tray
            if let Err(e) = tray::setup_tray(app.handle()) {
                tracing::error!("Failed to setup system tray: {}", e);
            }

            // Register deep-link handler for OIDC callbacks
            let handle = app.handle().clone();
            app.listen("deep-link://new-url", move |event| {
                if let Ok(payload) = serde_json::from_str::<serde_json::Value>(event.payload()) {
                    if let Some(urls) = payload.get("urls").and_then(|u| u.as_array()) {
                        for url_val in urls {
                            if let Some(url) = url_val.as_str() {
                                // Check for OIDC callback URLs
                                if url.starts_with("securesharing://oidc/callback") {
                                    tracing::info!("OIDC callback deep-link received");
                                    // Parse code and state from URL
                                    if let Ok(parsed) = url::Url::parse(url) {
                                        let params: std::collections::HashMap<_, _> =
                                            parsed.query_pairs().collect();
                                        if let (Some(code), Some(state)) =
                                            (params.get("code"), params.get("state"))
                                        {
                                            let _ = handle.emit("oidc-callback", serde_json::json!({
                                                "code": code.as_ref(),
                                                "state": state.as_ref(),
                                            }));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            });

            tracing::info!("Application setup complete");
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // Auth commands
            commands::auth::login,
            commands::auth::register,
            commands::auth::logout,
            commands::auth::get_current_user,
            commands::auth::check_auth_status,
            commands::auth::change_password,
            commands::auth::update_profile,
            commands::auth::list_devices,
            commands::auth::revoke_device,
            // File commands
            commands::files::list_files,
            commands::files::upload_file,
            commands::files::download_file,
            commands::files::create_folder,
            commands::files::delete_item,
            commands::files::rename_item,
            commands::files::move_item,
            commands::files::get_file_preview,
            // Sharing commands
            commands::sharing::search_recipients,
            commands::sharing::create_share,
            commands::sharing::revoke_share,
            commands::sharing::update_share,
            commands::sharing::list_my_shares,
            commands::sharing::list_shared_with_me,
            commands::sharing::get_share_details,
            commands::sharing::accept_share,
            commands::sharing::decline_share,
            // Recovery commands
            commands::recovery::setup_recovery,
            commands::recovery::get_recovery_status,
            commands::recovery::initiate_recovery,
            commands::recovery::approve_recovery_request,
            commands::recovery::complete_recovery,
            commands::recovery::get_pending_recovery_requests,
            // Settings commands
            commands::settings::get_settings,
            commands::settings::update_settings,
            commands::settings::get_storage_info,
            commands::settings::clear_cache,
            // Crypto commands
            commands::crypto::generate_keys,
            commands::crypto::encrypt_data,
            commands::crypto::decrypt_data,
            commands::crypto::sign_data,
            commands::crypto::verify_signature,
            // Notification commands
            commands::notifications::get_notifications,
            commands::notifications::mark_notification_read,
            commands::notifications::mark_all_notifications_read,
            // Tenant commands
            commands::tenant::list_tenants,
            commands::tenant::switch_tenant,
            commands::tenant::get_tenant_config,
            commands::tenant::leave_tenant,
            commands::tenant::get_tenant_members,
            commands::tenant::invite_tenant_member,
            commands::tenant::update_tenant_member_role,
            commands::tenant::remove_tenant_member,
            commands::tenant::get_tenant_invitations,
            commands::tenant::accept_tenant_invitation,
            commands::tenant::decline_tenant_invitation,
            // Biometric commands
            commands::biometric::check_biometric_availability,
            commands::biometric::get_biometric_type,
            commands::biometric::is_biometric_enabled,
            commands::biometric::set_biometric_enabled,
            commands::biometric::authenticate_biometric,
            commands::biometric::unlock_with_biometric,
            // PII service commands
            commands::pii::pii_create_conversation,
            commands::pii::pii_get_conversation,
            commands::pii::pii_list_conversations,
            commands::pii::pii_register_kem_keys,
            commands::pii::pii_ask,
            commands::pii::pii_clear_kem_keys,
            // Tray commands
            tray::tray_set_recent_files,
            tray::tray_set_sync_status,
            tray::tray_set_notification_count,
            tray::tray_get_state,
            // Sync commands
            commands::sync::get_sync_status,
            commands::sync::set_online_status,
            commands::sync::get_cached_files,
            commands::sync::get_pending_sync_count,
            commands::sync::trigger_sync,
            commands::sync::clear_sync_queue,
            // OIDC commands
            commands::oidc::oidc_get_providers,
            commands::oidc::oidc_begin_login,
            commands::oidc::oidc_handle_callback,
            commands::oidc::oidc_complete_registration,
            // WebAuthn commands
            commands::webauthn::webauthn_login_begin,
            commands::webauthn::webauthn_login_complete,
            commands::webauthn::webauthn_register_begin,
            commands::webauthn::webauthn_register_complete,
            commands::webauthn::webauthn_add_credential_begin,
            commands::webauthn::webauthn_add_credential_complete,
            // Credential management commands
            commands::credentials::list_credentials,
            commands::credentials::rename_credential,
            commands::credentials::delete_credential,
            // File Provider commands (macOS Finder integration)
            commands::file_provider::register_file_provider_domain,
            commands::file_provider::unregister_file_provider_domain,
            commands::file_provider::signal_file_changed,
            commands::file_provider::process_crypto_requests,
            commands::file_provider::is_file_provider_available,
            commands::file_provider::get_file_provider_container_path,
            commands::file_provider::sync_file_metadata_to_extension,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
