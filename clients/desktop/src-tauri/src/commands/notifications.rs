//! Notification commands

use crate::error::AppResult;
use crate::models::Notification;
use crate::state::AppState;
use tauri::State;

/// Get all notifications for the current user
#[tauri::command]
pub async fn get_notifications(
    state: State<'_, AppState>,
) -> AppResult<Vec<Notification>> {
    state.require_auth()?;
    tracing::debug!("Command: get_notifications");
    state.notification_service().get_notifications().await
}

/// Mark a notification as read
#[tauri::command]
pub async fn mark_notification_read(
    notification_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    tracing::debug!("Command: mark_notification_read({})", notification_id);
    state.notification_service().mark_as_read(&notification_id).await
}

/// Mark all notifications as read
#[tauri::command]
pub async fn mark_all_notifications_read(
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    tracing::debug!("Command: mark_all_notifications_read");
    state.notification_service().mark_all_as_read().await
}
