//! HTTP API client for backend communication

use crate::error::{AppError, AppResult};
use reqwest::{header, Client, RequestBuilder, Response};
use serde::{de::DeserializeOwned, Serialize};
use std::sync::Arc;
use parking_lot::RwLock;
use std::future::Future;
use std::pin::Pin;
use zeroize::Zeroize;

/// Default API base URL (production)
const DEFAULT_API_BASE_URL: &str = "https://drive.ssdid.my/api";

/// Environment variable name for API URL override
const API_URL_ENV_VAR: &str = "SSDID_DRIVE_API_URL";

const USER_AGENT: &str = concat!("SsdidDrive-Desktop/", env!("CARGO_PKG_VERSION"));

/// Get the API base URL from environment or use default
fn get_api_base_url() -> String {
    std::env::var(API_URL_ENV_VAR).unwrap_or_else(|_| DEFAULT_API_BASE_URL.to_string())
}

/// Type alias for token refresh callback
/// Returns new access token on success
pub type RefreshCallback = Arc<dyn Fn() -> Pin<Box<dyn Future<Output = AppResult<String>> + Send>> + Send + Sync>;

/// HTTP client for API communication
pub struct ApiClient {
    client: Client,
    base_url: String,
    auth_token: RwLock<Option<String>>,
    /// Optional callback to refresh token on 401
    refresh_callback: RwLock<Option<RefreshCallback>>,
    /// Flag to prevent recursive refresh attempts
    is_refreshing: RwLock<bool>,
}

impl ApiClient {
    /// Create a new API client
    pub fn new() -> AppResult<Self> {
        let client = Client::builder()
            .user_agent(USER_AGENT)
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .map_err(|e| AppError::Network(e.to_string()))?;

        let base_url = get_api_base_url();
        tracing::info!("API client initialized with base URL: {}", base_url);

        Ok(Self {
            client,
            base_url,
            auth_token: RwLock::new(None),
            refresh_callback: RwLock::new(None),
            is_refreshing: RwLock::new(false),
        })
    }

    /// Get the base URL for this API client
    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    /// Set a callback for token refresh on 401
    /// The callback should attempt to refresh the token and return the new access token
    pub fn set_refresh_callback(&self, callback: RefreshCallback) {
        *self.refresh_callback.write() = Some(callback);
    }

    /// Clear the refresh callback
    pub fn clear_refresh_callback(&self) {
        *self.refresh_callback.write() = None;
    }

    /// Set the authentication token
    pub fn set_auth_token(&self, token: Option<String>) {
        let mut guard = self.auth_token.write();
        if let Some(ref mut old) = *guard {
            old.zeroize();
        }
        *guard = token;
    }

    /// Get the current auth token
    pub fn get_auth_token(&self) -> Option<String> {
        self.auth_token.read().clone()
    }

    /// Check if authenticated
    pub fn is_authenticated(&self) -> bool {
        self.auth_token.read().is_some()
    }

    /// Build a request with common headers
    fn build_request(&self, method: reqwest::Method, endpoint: &str) -> RequestBuilder {
        let url = format!("{}{}", self.base_url, endpoint);
        let mut builder = self.client.request(method, &url);

        // Add auth header if available
        if let Some(token) = self.auth_token.read().as_ref() {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {}", token));
        }

        builder
            .header(header::CONTENT_TYPE, "application/json")
            .header(header::ACCEPT, "application/json")
    }

    /// Execute a GET request with automatic token refresh on 401
    pub async fn get<T: DeserializeOwned>(&self, endpoint: &str) -> AppResult<T> {
        let response = self
            .build_request(reqwest::Method::GET, endpoint)
            .send()
            .await?;

        // Check for 401 and attempt refresh
        if response.status() == reqwest::StatusCode::UNAUTHORIZED {
            if self.try_refresh_token().await {
                // Retry request with new token
                let retry_response = self
                    .build_request(reqwest::Method::GET, endpoint)
                    .send()
                    .await?;
                return self.handle_response(retry_response).await;
            }
        }

        self.handle_response(response).await
    }

    /// Execute a POST request with automatic token refresh on 401
    pub async fn post<B: Serialize, T: DeserializeOwned>(
        &self,
        endpoint: &str,
        body: &B,
    ) -> AppResult<T> {
        let response = self
            .build_request(reqwest::Method::POST, endpoint)
            .json(body)
            .send()
            .await?;

        // Check for 401 and attempt refresh (skip for auth endpoints)
        if response.status() == reqwest::StatusCode::UNAUTHORIZED
            && !endpoint.starts_with("/auth/")
        {
            if self.try_refresh_token().await {
                // Retry request with new token
                let retry_response = self
                    .build_request(reqwest::Method::POST, endpoint)
                    .json(body)
                    .send()
                    .await?;
                return self.handle_response(retry_response).await;
            }
        }

        self.handle_response(response).await
    }

    /// Execute a PUT request with automatic token refresh on 401
    pub async fn put<B: Serialize, T: DeserializeOwned>(
        &self,
        endpoint: &str,
        body: &B,
    ) -> AppResult<T> {
        let response = self
            .build_request(reqwest::Method::PUT, endpoint)
            .json(body)
            .send()
            .await?;

        // Check for 401 and attempt refresh
        if response.status() == reqwest::StatusCode::UNAUTHORIZED {
            if self.try_refresh_token().await {
                // Retry request with new token
                let retry_response = self
                    .build_request(reqwest::Method::PUT, endpoint)
                    .json(body)
                    .send()
                    .await?;
                return self.handle_response(retry_response).await;
            }
        }

        self.handle_response(response).await
    }

    /// Execute a DELETE request with automatic token refresh on 401
    pub async fn delete<T: DeserializeOwned>(&self, endpoint: &str) -> AppResult<T> {
        let response = self
            .build_request(reqwest::Method::DELETE, endpoint)
            .send()
            .await?;

        // Check for 401 and attempt refresh
        if response.status() == reqwest::StatusCode::UNAUTHORIZED {
            if self.try_refresh_token().await {
                // Retry request with new token
                let retry_response = self
                    .build_request(reqwest::Method::DELETE, endpoint)
                    .send()
                    .await?;
                return self.handle_response(retry_response).await;
            }
        }

        self.handle_response(response).await
    }

    /// Execute a DELETE request with no response body and automatic token refresh on 401
    pub async fn delete_no_content(&self, endpoint: &str) -> AppResult<()> {
        let response = self
            .build_request(reqwest::Method::DELETE, endpoint)
            .send()
            .await?;

        // Check for 401 and attempt refresh
        if response.status() == reqwest::StatusCode::UNAUTHORIZED {
            if self.try_refresh_token().await {
                // Retry request with new token
                let retry_response = self
                    .build_request(reqwest::Method::DELETE, endpoint)
                    .send()
                    .await?;
                if retry_response.status().is_success() {
                    return Ok(());
                } else {
                    let status = retry_response.status();
                    let error_text = retry_response.text().await.unwrap_or_default();
                    return Err(self.parse_error(status, &error_text));
                }
            }
        }

        if response.status().is_success() {
            Ok(())
        } else {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();
            Err(self.parse_error(status, &error_text))
        }
    }

    /// Execute a GET request without authentication (for public endpoints)
    pub async fn get_unauth<T: DeserializeOwned>(&self, endpoint: &str) -> AppResult<T> {
        let url = format!("{}{}", self.base_url, endpoint);
        let response = self
            .client
            .get(&url)
            .header(header::ACCEPT, "application/json")
            .send()
            .await?;
        self.handle_response(response).await
    }

    /// Execute a POST request without authentication (for public endpoints)
    pub async fn post_unauth<B: Serialize, T: DeserializeOwned>(
        &self,
        endpoint: &str,
        body: &B,
    ) -> AppResult<T> {
        let url = format!("{}{}", self.base_url, endpoint);
        let response = self
            .client
            .post(&url)
            .header(header::CONTENT_TYPE, "application/json")
            .header(header::ACCEPT, "application/json")
            .json(body)
            .send()
            .await?;
        self.handle_response(response).await
    }

    /// Attempt to refresh the token using the registered callback
    /// Returns true if refresh was successful, false otherwise
    async fn try_refresh_token(&self) -> bool {
        // Atomically check-and-set the refreshing flag in a single write lock
        // to prevent TOCTOU race between read and write
        {
            let mut is_refreshing = self.is_refreshing.write();
            if *is_refreshing {
                return false;
            }
            *is_refreshing = true;
        }

        // Get the refresh callback
        let callback = {
            let cb = self.refresh_callback.read();
            cb.clone()
        };

        if let Some(refresh_fn) = callback {

            // Attempt refresh
            let result = refresh_fn().await;

            // Clear refreshing flag
            *self.is_refreshing.write() = false;

            match result {
                Ok(new_token) => {
                    self.set_auth_token(Some(new_token));
                    tracing::info!("Token refreshed successfully");
                    true
                }
                Err(e) => {
                    tracing::warn!("Token refresh failed: {}", e);
                    false
                }
            }
        } else {
            // No callback registered, clear the refreshing flag
            *self.is_refreshing.write() = false;
            false
        }
    }

    /// Handle API response
    async fn handle_response<T: DeserializeOwned>(&self, response: Response) -> AppResult<T> {
        let status = response.status();

        if status.is_success() {
            response
                .json()
                .await
                .map_err(|e| AppError::Network(format!("Failed to parse response: {}", e)))
        } else {
            let error_text = response.text().await.unwrap_or_default();
            Err(self.parse_error(status, &error_text))
        }
    }

    /// Parse error response
    /// Extracts user-friendly message and sanitizes internal details
    fn parse_error(&self, status: reqwest::StatusCode, body: &str) -> AppError {
        // Try to extract a user-friendly message from JSON error response
        let user_message = Self::extract_error_message(body);

        match status.as_u16() {
            401 => AppError::NotAuthenticated,
            403 => AppError::PermissionDenied(user_message),
            404 => AppError::NotFound(user_message),
            422 => AppError::Validation(user_message),
            429 => AppError::Network("Too many requests. Please try again later.".to_string()),
            500..=599 => AppError::Network("Server error. Please try again later.".to_string()),
            _ => AppError::Network(format!("Request failed (HTTP {})", status)),
        }
    }

    /// Extract user-friendly error message from API response
    /// Filters out internal details like stack traces, SQL errors, etc.
    fn extract_error_message(body: &str) -> String {
        // Try to parse as JSON and extract message field
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(body) {
            // Common API error response formats
            if let Some(message) = json.get("message").and_then(|m| m.as_str()) {
                return Self::sanitize_message(message);
            }
            if let Some(error) = json.get("error").and_then(|e| e.as_str()) {
                return Self::sanitize_message(error);
            }
            if let Some(detail) = json.get("detail").and_then(|d| d.as_str()) {
                return Self::sanitize_message(detail);
            }
        }

        // Fallback: return a generic message if body looks like it contains internal details
        if body.contains("stack") || body.contains("trace") ||
           body.contains("SQL") || body.contains("at ") ||
           body.len() > 500 {
            return "An error occurred. Please try again.".to_string();
        }

        // If body is short and doesn't look like internal details, use it
        Self::sanitize_message(body)
    }

    /// Sanitize error message to remove potentially sensitive information
    fn sanitize_message(message: &str) -> String {
        // Truncate to reasonable length
        let truncated = if message.len() > 200 {
            let mut end = 197;
            while !message.is_char_boundary(end) && end > 0 {
                end -= 1;
            }
            format!("{}...", &message[..end])
        } else {
            message.to_string()
        };

        // Remove common sensitive patterns
        let sanitized = truncated
            .replace(|c: char| c.is_control(), " ")  // Remove control chars
            .trim()
            .to_string();

        if sanitized.is_empty() {
            "An error occurred".to_string()
        } else {
            sanitized
        }
    }
}
