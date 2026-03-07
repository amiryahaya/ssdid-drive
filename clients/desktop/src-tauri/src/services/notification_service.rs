//! Notification service for API communication

use crate::error::AppResult;
use crate::models::Notification;
use crate::services::ApiClient;
use std::sync::Arc;

/// Service for notification operations
pub struct NotificationService {
    api_client: Arc<ApiClient>,
}

impl NotificationService {
    /// Create a new notification service
    pub fn new(api_client: Arc<ApiClient>) -> Self {
        Self { api_client }
    }

    /// Get all notifications for the current user
    pub async fn get_notifications(&self) -> AppResult<Vec<Notification>> {
        tracing::debug!("Fetching notifications");
        self.api_client.get("/notifications").await
    }

    /// Mark a notification as read
    pub async fn mark_as_read(&self, notification_id: &str) -> AppResult<()> {
        tracing::debug!("Marking notification {} as read", notification_id);
        self.api_client
            .post::<(), ()>(&format!("/notifications/{}/read", notification_id), &())
            .await
    }

    /// Mark all notifications as read
    pub async fn mark_all_as_read(&self) -> AppResult<()> {
        tracing::debug!("Marking all notifications as read");
        self.api_client
            .post::<(), ()>("/notifications/read-all", &())
            .await
    }
}
