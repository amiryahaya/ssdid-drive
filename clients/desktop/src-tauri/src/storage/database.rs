//! Local SQLite database for caching
//!
//! Uses on-demand connection opening to ensure thread safety.
//! Each operation opens a new connection, which is safe for SQLite
//! with WAL mode enabled.

use crate::commands::settings::AppSettings;
use crate::error::{AppError, AppResult};
use parking_lot::Mutex;
use rusqlite::{params, Connection};
use std::path::PathBuf;

/// Local database for caching and settings
///
/// Thread-safe by opening connections on demand rather than
/// holding a persistent connection.
pub struct Database {
    /// Path to the database file
    pub(crate) db_path: PathBuf,
    /// Mutex to serialize write operations
    pub(crate) write_lock: Mutex<()>,
}

// Database is now naturally Send + Sync because it only contains
// PathBuf (Send + Sync) and Mutex<()> (Send + Sync)

impl Database {
    /// Create a new database instance
    pub fn new() -> AppResult<Self> {
        let db_path = Self::get_db_path()?;

        // Ensure parent directory exists
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| AppError::Storage(format!("Failed to create data directory: {}", e)))?;
        }

        let db = Self {
            db_path: db_path.clone(),
            write_lock: Mutex::new(()),
        };

        // Initialize schema with a fresh connection
        db.with_connection(|conn| {
            // Enable WAL mode for better concurrency
            conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")?;

            conn.execute_batch(
                r#"
                -- Settings table
                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                -- File cache
                CREATE TABLE IF NOT EXISTS file_cache (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    item_type TEXT NOT NULL,
                    size INTEGER NOT NULL,
                    mime_type TEXT,
                    folder_id TEXT,
                    owner_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    is_shared INTEGER NOT NULL DEFAULT 0,
                    is_received_share INTEGER NOT NULL DEFAULT 0,
                    cached_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                -- Folder cache
                CREATE TABLE IF NOT EXISTS folder_cache (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    parent_id TEXT,
                    cached_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                -- DEK cache (encrypted)
                CREATE TABLE IF NOT EXISTS dek_cache (
                    file_id TEXT PRIMARY KEY,
                    encrypted_dek TEXT NOT NULL,
                    cached_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                -- Offline queue
                CREATE TABLE IF NOT EXISTS offline_queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    action TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    retry_count INTEGER NOT NULL DEFAULT 0
                );

                -- Create indexes
                CREATE INDEX IF NOT EXISTS idx_file_cache_folder ON file_cache(folder_id);
                CREATE INDEX IF NOT EXISTS idx_file_cache_updated ON file_cache(updated_at);
                "#,
            )?;
            Ok(())
        })?;

        tracing::info!("Database initialized at: {:?}", db_path);
        Ok(db)
    }

    /// Get the database file path
    fn get_db_path() -> AppResult<PathBuf> {
        let data_dir = dirs::data_dir()
            .ok_or_else(|| AppError::Storage("Could not find data directory".to_string()))?;

        Ok(data_dir.join("SecureSharing").join("securesharing.db"))
    }

    /// Open a new connection to the database
    pub fn open_connection(&self) -> AppResult<Connection> {
        Connection::open(&self.db_path)
            .map_err(|e| AppError::Database(format!("Failed to open database: {}", e)))
    }

    /// Execute a read operation with a fresh connection
    pub fn with_connection<F, T>(&self, f: F) -> AppResult<T>
    where
        F: FnOnce(&Connection) -> Result<T, rusqlite::Error>,
    {
        let conn = self.open_connection()?;
        f(&conn).map_err(|e| AppError::Database(e.to_string()))
    }

    /// Execute a write operation with serialization
    pub fn with_write_connection<F, T>(&self, f: F) -> AppResult<T>
    where
        F: FnOnce(&Connection) -> Result<T, rusqlite::Error>,
    {
        let _lock = self.write_lock.lock();
        let conn = self.open_connection()?;
        f(&conn).map_err(|e| AppError::Database(e.to_string()))
    }

    /// Get application settings
    pub async fn get_settings(&self) -> AppResult<AppSettings> {
        self.with_connection(|conn| {
            let json: Option<String> = conn
                .query_row(
                    "SELECT value FROM settings WHERE key = 'app_settings'",
                    [],
                    |row| row.get(0),
                )
                .ok();

            match json {
                Some(s) => serde_json::from_str(&s)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e))),
                None => Ok(AppSettings::default()),
            }
        })
        .map_err(|e| AppError::Storage(format!("Failed to get settings: {}", e)))
    }

    /// Save application settings
    pub async fn save_settings(&self, settings: &AppSettings) -> AppResult<()> {
        let json = serde_json::to_string(settings)
            .map_err(|e| AppError::Storage(format!("Failed to serialize settings: {}", e)))?;

        self.with_write_connection(|conn| {
            conn.execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES ('app_settings', ?1)",
                params![json],
            )?;
            Ok(())
        })
    }

    /// Clear the cache tables
    pub async fn clear_cache(&self) -> AppResult<()> {
        self.with_write_connection(|conn| {
            conn.execute_batch(
                r#"
                DELETE FROM file_cache;
                DELETE FROM folder_cache;
                DELETE FROM dek_cache;
                VACUUM;
                "#,
            )?;
            Ok(())
        })?;

        tracing::info!("Cache cleared");
        Ok(())
    }

    /// Get the database size in bytes
    pub async fn get_cache_size(&self) -> AppResult<u64> {
        let metadata = std::fs::metadata(&self.db_path)
            .map_err(|e| AppError::Storage(format!("Failed to get database size: {}", e)))?;
        Ok(metadata.len())
    }

    // =========================================================================
    // Sync / Offline Queue Methods
    // =========================================================================

    /// Queue an offline operation
    pub fn queue_offline_operation(&self, action: &str, payload: &str) -> AppResult<()> {
        self.with_write_connection(|conn| {
            conn.execute(
                "INSERT INTO offline_queue (action, payload) VALUES (?1, ?2)",
                params![action, payload],
            )?;
            Ok(())
        })
    }

    /// Get pending operations
    pub fn get_pending_operations(&self) -> AppResult<Vec<(i64, String, String)>> {
        self.with_connection(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id, action, payload FROM offline_queue ORDER BY created_at ASC LIMIT 100",
            )?;
            let rows = stmt
                .query_map([], |row| {
                    Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?))
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// Get pending operation count
    pub fn get_pending_operation_count(&self) -> AppResult<usize> {
        self.with_connection(|conn| {
            let count: i64 = conn.query_row(
                "SELECT COUNT(*) FROM offline_queue",
                [],
                |row| row.get(0),
            )?;
            Ok(count as usize)
        })
    }

    /// Remove a completed operation
    pub fn remove_offline_operation(&self, id: i64) -> AppResult<()> {
        self.with_write_connection(|conn| {
            conn.execute("DELETE FROM offline_queue WHERE id = ?1", params![id])?;
            Ok(())
        })
    }

    /// Increment retry count
    pub fn increment_operation_retry(&self, id: i64) -> AppResult<()> {
        self.with_write_connection(|conn| {
            conn.execute(
                "UPDATE offline_queue SET retry_count = retry_count + 1 WHERE id = ?1",
                params![id],
            )?;
            Ok(())
        })
    }

    // =========================================================================
    // File Cache Methods
    // =========================================================================

    /// Cache file metadata
    pub fn cache_files(&self, files: &[CachedFileRow]) -> AppResult<()> {
        self.with_write_connection(|conn| {
            let mut stmt = conn.prepare(
                r#"
                INSERT OR REPLACE INTO file_cache
                (id, name, item_type, size, mime_type, folder_id, owner_id, created_at, updated_at, is_shared, is_received_share, cached_at)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, datetime('now'))
                "#,
            )?;

            for file in files {
                stmt.execute(params![
                    file.id,
                    file.name,
                    file.item_type,
                    file.size,
                    file.mime_type,
                    file.folder_id,
                    file.owner_id,
                    file.created_at,
                    file.updated_at,
                    file.is_shared as i32,
                    file.is_received_share as i32,
                ])?;
            }
            Ok(())
        })
    }

    /// Get cached files for a folder
    pub fn get_cached_files(&self, folder_id: Option<&str>) -> AppResult<Vec<CachedFileRow>> {
        self.with_connection(|conn| {
            let sql = if folder_id.is_some() {
                "SELECT id, name, item_type, size, mime_type, folder_id, owner_id, created_at, updated_at, is_shared, is_received_share
                 FROM file_cache WHERE folder_id = ?1 ORDER BY item_type DESC, name ASC"
            } else {
                "SELECT id, name, item_type, size, mime_type, folder_id, owner_id, created_at, updated_at, is_shared, is_received_share
                 FROM file_cache WHERE folder_id IS NULL ORDER BY item_type DESC, name ASC"
            };

            let mut stmt = conn.prepare(sql)?;

            let map_row = |row: &rusqlite::Row| -> rusqlite::Result<CachedFileRow> {
                Ok(CachedFileRow {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    item_type: row.get(2)?,
                    size: row.get(3)?,
                    mime_type: row.get(4)?,
                    folder_id: row.get(5)?,
                    owner_id: row.get(6)?,
                    created_at: row.get(7)?,
                    updated_at: row.get(8)?,
                    is_shared: row.get::<_, i32>(9)? != 0,
                    is_received_share: row.get::<_, i32>(10)? != 0,
                })
            };

            let rows = if let Some(fid) = folder_id {
                stmt.query_map([fid], map_row)?
            } else {
                stmt.query_map([], map_row)?
            };

            rows.collect::<Result<Vec<_>, _>>()
        })
    }

    /// Clear cache for a folder
    pub fn clear_folder_cache(&self, folder_id: Option<&str>) -> AppResult<()> {
        self.with_write_connection(|conn| {
            if let Some(fid) = folder_id {
                conn.execute("DELETE FROM file_cache WHERE folder_id = ?1", params![fid])?;
            } else {
                conn.execute("DELETE FROM file_cache WHERE folder_id IS NULL", [])?;
            }
            Ok(())
        })
    }
}

/// Cached file row structure
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct CachedFileRow {
    pub id: String,
    pub name: String,
    pub item_type: String,
    pub size: i64,
    pub mime_type: Option<String>,
    pub folder_id: Option<String>,
    pub owner_id: String,
    pub created_at: String,
    pub updated_at: String,
    pub is_shared: bool,
    pub is_received_share: bool,
}
