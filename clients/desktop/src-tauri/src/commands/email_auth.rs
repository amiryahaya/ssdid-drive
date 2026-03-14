//! Email + OTP authentication commands

use crate::error::AppResult;
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Serialize, Deserialize)]
pub struct OtpSendResponse {
    pub message: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OtpVerifyResponse {
    pub token: String,
    pub totp_setup_required: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EmailLoginResponse {
    pub requires_totp: bool,
}

/// Send OTP to email for registration
#[tauri::command]
pub async fn send_otp(
    email: String,
    invitation_token: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<OtpSendResponse> {
    #[derive(Serialize)]
    struct Body {
        email: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        invitation_token: Option<String>,
    }

    state
        .api_client()
        .post_unauth::<Body, OtpSendResponse>(
            "/auth/email/register",
            &Body {
                email,
                invitation_token,
            },
        )
        .await
}

/// Verify OTP code for registration
#[tauri::command]
pub async fn verify_otp(
    email: String,
    code: String,
    invitation_token: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<OtpVerifyResponse> {
    #[derive(Serialize)]
    struct Body {
        email: String,
        code: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        invitation_token: Option<String>,
    }

    let response: OtpVerifyResponse = state
        .api_client()
        .post_unauth(
            "/auth/email/register/verify",
            &Body {
                email,
                code,
                invitation_token,
            },
        )
        .await?;

    state.complete_login(&response.token).await?;

    Ok(response)
}

/// Initiate email login (check if TOTP required)
#[tauri::command]
pub async fn email_login(
    email: String,
    state: State<'_, AppState>,
) -> AppResult<EmailLoginResponse> {
    #[derive(Serialize)]
    struct Body {
        email: String,
    }

    state
        .api_client()
        .post_unauth::<Body, EmailLoginResponse>("/auth/email/login", &Body { email })
        .await
}
