//! Activity log commands

use crate::error::AppResult;
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Serialize, Deserialize)]
pub struct ActivityItem {
    pub id: String,
    pub actor_id: String,
    pub actor_name: Option<String>,
    pub event_type: String,
    pub resource_type: String,
    pub resource_id: String,
    pub resource_name: String,
    pub details: Option<serde_json::Value>,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ActivityResponse {
    pub items: Vec<ActivityItem>,
    pub total: i64,
    pub page: i64,
    pub page_size: i64,
}

#[tauri::command]
pub async fn list_activity(
    state: State<'_, AppState>,
    page: Option<i64>,
    page_size: Option<i64>,
    event_type: Option<String>,
    resource_type: Option<String>,
    from: Option<String>,
    to: Option<String>,
) -> AppResult<ActivityResponse> {
    state.require_auth()?;
    let mut params = vec![];
    if let Some(p) = page { params.push(format!("page={p}")); }
    if let Some(ps) = page_size { params.push(format!("page_size={ps}")); }
    if let Some(ref et) = event_type { params.push(format!("event_type={et}")); }
    if let Some(ref rt) = resource_type { params.push(format!("resource_type={rt}")); }
    if let Some(ref f) = from { params.push(format!("from={f}")); }
    if let Some(ref t) = to { params.push(format!("to={t}")); }
    let query = if params.is_empty() { String::new() } else { format!("?{}", params.join("&")) };
    state.api_client().get(&format!("/activity{query}")).await
}

#[tauri::command]
pub async fn list_resource_activity(
    state: State<'_, AppState>,
    resource_id: String,
    page: Option<i64>,
    page_size: Option<i64>,
) -> AppResult<ActivityResponse> {
    state.require_auth()?;
    let mut params = vec![];
    if let Some(p) = page { params.push(format!("page={p}")); }
    if let Some(ps) = page_size { params.push(format!("page_size={ps}")); }
    let query = if params.is_empty() { String::new() } else { format!("?{}", params.join("&")) };
    state.api_client().get(&format!("/activity/resource/{resource_id}{query}")).await
}

#[tauri::command]
pub async fn list_admin_activity(
    state: State<'_, AppState>,
    page: Option<i64>,
    page_size: Option<i64>,
    actor_id: Option<String>,
    event_type: Option<String>,
    resource_type: Option<String>,
    from: Option<String>,
    to: Option<String>,
    search: Option<String>,
) -> AppResult<ActivityResponse> {
    state.require_auth()?;
    let mut params = vec![];
    if let Some(p) = page { params.push(format!("page={p}")); }
    if let Some(ps) = page_size { params.push(format!("page_size={ps}")); }
    if let Some(ref ai) = actor_id { params.push(format!("actor_id={ai}")); }
    if let Some(ref et) = event_type { params.push(format!("event_type={et}")); }
    if let Some(ref rt) = resource_type { params.push(format!("resource_type={rt}")); }
    if let Some(ref f) = from { params.push(format!("from={f}")); }
    if let Some(ref t) = to { params.push(format!("to={t}")); }
    if let Some(ref s) = search { params.push(format!("search={s}")); }
    let query = if params.is_empty() { String::new() } else { format!("?{}", params.join("&")) };
    state.api_client().get(&format!("/activity/admin{query}")).await
}
