//! Data models for SSDID Drive Desktop

mod auth_provider;
mod file;
mod notification;
mod share;
mod tenant;
mod user;

pub use auth_provider::*;
pub use file::*;
pub use notification::*;
pub use share::*;
pub use tenant::*;
pub use user::*;

use serde::{Deserialize, Serialize};

/// Pagination parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaginationParams {
    pub page: u32,
    pub per_page: u32,
}

impl Default for PaginationParams {
    fn default() -> Self {
        Self {
            page: 1,
            per_page: 50,
        }
    }
}

/// Paginated response wrapper
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaginatedResponse<T> {
    pub items: Vec<T>,
    pub total: u64,
    pub page: u32,
    pub per_page: u32,
    pub total_pages: u32,
}
