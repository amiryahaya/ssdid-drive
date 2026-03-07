//! Notification data models

use serde::{Deserialize, Serialize};

/// Notification type
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NotificationType {
    ShareReceived,
    ShareAccepted,
    RecoveryRequest,
    System,
}

/// A notification for the user
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notification {
    /// Unique identifier
    pub id: String,
    /// Type of notification
    #[serde(rename = "type")]
    pub notification_type: NotificationType,
    /// Short title
    pub title: String,
    /// Detailed message
    pub message: String,
    /// Whether the notification has been read
    pub read: bool,
    /// When the notification was created
    pub created_at: String,
    /// Optional metadata
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<serde_json::Value>,
}
