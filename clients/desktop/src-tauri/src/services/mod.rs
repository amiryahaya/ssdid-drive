//! Business logic services

mod api_client;
mod app_group_service;
pub mod cert_pinner;
mod auth_service;
mod biometric_service;
mod crypto_service;
mod file_service;
mod notification_service;
mod pii_service;
mod recovery_service;
mod sharing_service;
mod sync_service;
mod tenant_service;

pub use api_client::{ApiClient, RefreshCallback};
pub use app_group_service::{
    AppGroupService, AppGroupError, CryptoRequest, CryptoRequestType, CryptoResponse,
    SharedFileMetadata,
};
pub use auth_service::AuthService;
pub use biometric_service::{BiometricService, BiometricStatus, BiometricAvailability};
pub use crypto_service::CryptoService;
pub use file_service::FileService;
pub use notification_service::NotificationService;
pub use pii_service::{
    PiiServiceClient, CreateConversationRequest, Conversation,
    RegisterKemKeysResponse, DecryptedAskResponse,
};
pub use recovery_service::{
    RecoveryService, RecoveryFile, RecoveryStatus, ServerShareResponse, CompleteRecoveryResponse,
    TrusteeRecoverySetup, TrusteeInfo, PendingRecoveryRequest,
    SetupTrusteesRequest, ShareEntry as RecoveryShareEntry,
};
pub use sharing_service::SharingService;
pub use sync_service::{SyncService, SyncStatus, OfflineOperation, CachedFile};
pub use tenant_service::TenantService;
