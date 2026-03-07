//! System tray menu management for SSDID Drive Desktop
//!
//! Provides a menu bar / system tray interface with:
//! - Quick actions (open app, upload, settings)
//! - Recent files list
//! - Sync status indicator
//! - Notification badge

use std::sync::{Arc, Mutex};
use tauri::{
    menu::{Menu, MenuBuilder, MenuEvent, MenuItemBuilder, SubmenuBuilder},
    tray::{TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, Wry,
};

/// Maximum number of recent files to show in tray menu
const MAX_RECENT_FILES: usize = 5;

/// Represents a recent file entry for the tray menu
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct RecentFile {
    pub id: String,
    pub name: String,
    pub path: Option<String>,
}

/// Current sync status
#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub enum SyncStatus {
    #[default]
    Idle,
    Syncing {
        progress: u8,
        file_name: Option<String>,
    },
    Error(String),
}

impl SyncStatus {
    fn to_label(&self) -> String {
        match self {
            SyncStatus::Idle => "✓ All synced".to_string(),
            SyncStatus::Syncing { progress, file_name } => {
                if let Some(name) = file_name {
                    format!("⟳ Syncing: {} ({}%)", name, progress)
                } else {
                    format!("⟳ Syncing... ({}%)", progress)
                }
            }
            SyncStatus::Error(msg) => format!("⚠ Sync error: {}", msg),
        }
    }
}

/// Tray state for managing dynamic menu updates
#[derive(Default)]
pub struct TrayState {
    pub recent_files: Vec<RecentFile>,
    pub sync_status: SyncStatus,
    pub unread_notifications: u32,
}

/// Global tray state wrapped for thread-safe access
pub type SharedTrayState = Arc<Mutex<TrayState>>;

/// Menu item IDs for event handling
pub mod menu_ids {
    pub const OPEN_APP: &str = "open_app";
    pub const QUICK_UPLOAD: &str = "quick_upload";
    pub const RECENT_PREFIX: &str = "recent_";
    pub const VIEW_ALL_FILES: &str = "view_all_files";
    pub const NOTIFICATIONS: &str = "notifications";
    pub const SETTINGS: &str = "settings";
    pub const SYNC_STATUS: &str = "sync_status";
    pub const QUIT: &str = "quit";
}

/// Build the tray menu with current state
fn build_tray_menu(app: &AppHandle, state: &TrayState) -> tauri::Result<Menu<Wry>> {
    let mut menu_builder = MenuBuilder::new(app);

    // Open app
    let open_item = MenuItemBuilder::with_id(menu_ids::OPEN_APP, "Open SSDID Drive")
        .build(app)?;
    menu_builder = menu_builder.item(&open_item);

    // Quick Upload
    let upload_item = MenuItemBuilder::with_id(menu_ids::QUICK_UPLOAD, "Quick Upload...")
        .accelerator("CmdOrCtrl+U")
        .build(app)?;
    menu_builder = menu_builder.item(&upload_item);

    menu_builder = menu_builder.separator();

    // Recent Files submenu
    let mut recent_submenu_builder = SubmenuBuilder::new(app, "Recent Files");

    if state.recent_files.is_empty() {
        let no_recent = MenuItemBuilder::new("No recent files")
            .enabled(false)
            .build(app)?;
        recent_submenu_builder = recent_submenu_builder.item(&no_recent);
    } else {
        for (i, file) in state.recent_files.iter().take(MAX_RECENT_FILES).enumerate() {
            let item_id = format!("{}{}", menu_ids::RECENT_PREFIX, i);
            let recent_item = MenuItemBuilder::with_id(item_id, &file.name).build(app)?;
            recent_submenu_builder = recent_submenu_builder.item(&recent_item);
        }
        recent_submenu_builder = recent_submenu_builder.separator();
        let view_all = MenuItemBuilder::with_id(menu_ids::VIEW_ALL_FILES, "View All Files...")
            .build(app)?;
        recent_submenu_builder = recent_submenu_builder.item(&view_all);
    }

    let recent_submenu = recent_submenu_builder.build()?;
    menu_builder = menu_builder.item(&recent_submenu);

    // Notifications with badge
    let notif_label = if state.unread_notifications > 0 {
        format!("Notifications ({})", state.unread_notifications)
    } else {
        "Notifications".to_string()
    };
    let notif_item = MenuItemBuilder::with_id(menu_ids::NOTIFICATIONS, &notif_label)
        .build(app)?;
    menu_builder = menu_builder.item(&notif_item);

    menu_builder = menu_builder.separator();

    // Sync status (disabled, just for display)
    let sync_item = MenuItemBuilder::with_id(menu_ids::SYNC_STATUS, state.sync_status.to_label())
        .enabled(false)
        .build(app)?;
    menu_builder = menu_builder.item(&sync_item);

    menu_builder = menu_builder.separator();

    // Settings
    let settings_item = MenuItemBuilder::with_id(menu_ids::SETTINGS, "Settings...")
        .accelerator("CmdOrCtrl+,")
        .build(app)?;
    menu_builder = menu_builder.item(&settings_item);

    menu_builder = menu_builder.separator();

    // Quit
    let quit_item = MenuItemBuilder::with_id(menu_ids::QUIT, "Quit SSDID Drive")
        .accelerator("CmdOrCtrl+Q")
        .build(app)?;
    menu_builder = menu_builder.item(&quit_item);

    menu_builder.build()
}

/// Setup the system tray with menu
pub fn setup_tray(app: &AppHandle) -> tauri::Result<()> {
    let state = TrayState::default();
    let shared_state = Arc::new(Mutex::new(state));

    // Store state in app
    app.manage(shared_state.clone());

    // Build initial menu
    let menu = {
        let state = shared_state.lock().unwrap();
        build_tray_menu(app, &state)?
    };

    // Get the existing tray icon (configured in tauri.conf.json)
    if let Some(tray) = app.tray_by_id("main") {
        tray.set_menu(Some(menu))?;
        tray.set_tooltip(Some("SSDID Drive"))?;

        // Handle menu events
        let app_handle = app.clone();
        tray.on_menu_event(move |_app, event| {
            handle_menu_event(&app_handle, event);
        });

        // Handle tray icon click
        let app_handle = app.clone();
        tray.on_tray_icon_event(move |_tray, event| {
            handle_tray_event(&app_handle, event);
        });
    } else {
        tracing::warn!("No tray icon found with id 'main', creating one");

        // Create tray if not configured
        let _tray = TrayIconBuilder::with_id("main")
            .menu(&menu)
            .tooltip("SSDID Drive")
            .menu_on_left_click(false)
            .on_menu_event({
                let app_handle = app.clone();
                move |_app, event| {
                    handle_menu_event(&app_handle, event);
                }
            })
            .on_tray_icon_event({
                let app_handle = app.clone();
                move |_tray, event| {
                    handle_tray_event(&app_handle, event);
                }
            })
            .build(app)?;
    }

    tracing::info!("System tray initialized");
    Ok(())
}

/// Handle tray menu item clicks
fn handle_menu_event(app: &AppHandle, event: MenuEvent) {
    let id = event.id().as_ref();
    tracing::debug!("Tray menu event: {}", id);

    match id {
        menu_ids::OPEN_APP => {
            show_main_window(app);
        }
        menu_ids::QUICK_UPLOAD => {
            // Emit event to frontend for file picker
            show_main_window(app);
            let _ = app.emit("tray://quick-upload", ());
        }
        menu_ids::VIEW_ALL_FILES => {
            show_main_window(app);
            let _ = app.emit("tray://navigate", "/files");
        }
        menu_ids::NOTIFICATIONS => {
            show_main_window(app);
            let _ = app.emit("tray://navigate", "/notifications");
        }
        menu_ids::SETTINGS => {
            show_main_window(app);
            let _ = app.emit("tray://navigate", "/settings");
        }
        menu_ids::QUIT => {
            tracing::info!("Quit requested from tray menu");
            app.exit(0);
        }
        id if id.starts_with(menu_ids::RECENT_PREFIX) => {
            // Handle recent file click
            if let Ok(index) = id[menu_ids::RECENT_PREFIX.len()..].parse::<usize>() {
                let state: tauri::State<SharedTrayState> = app.state();
                let file_id = state
                    .lock()
                    .ok()
                    .and_then(|s| s.recent_files.get(index).map(|f| f.id.clone()));

                if let Some(file_id) = file_id {
                    show_main_window(app);
                    let _ = app.emit("tray://open-file", file_id);
                }
            }
        }
        _ => {
            tracing::debug!("Unknown tray menu event: {}", id);
        }
    }
}

/// Handle tray icon events (click, double-click)
fn handle_tray_event(app: &AppHandle, event: TrayIconEvent) {
    match event {
        TrayIconEvent::Click { button, .. } => {
            if button == tauri::tray::MouseButton::Left {
                show_main_window(app);
            }
        }
        TrayIconEvent::DoubleClick { button, .. } => {
            if button == tauri::tray::MouseButton::Left {
                show_main_window(app);
            }
        }
        _ => {}
    }
}

/// Show and focus the main window
fn show_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

/// Update the tray menu with new state
pub fn update_tray_menu(app: &AppHandle) -> tauri::Result<()> {
    let state: tauri::State<SharedTrayState> = app.state();
    let state = state.lock().map_err(|_| tauri::Error::Anyhow(anyhow::anyhow!("Failed to lock tray state")))?;

    let menu = build_tray_menu(app, &state)?;

    if let Some(tray) = app.tray_by_id("main") {
        tray.set_menu(Some(menu))?;
    }

    Ok(())
}

// ============================================================================
// Tauri Commands for Frontend Integration
// ============================================================================

/// Update recent files list from frontend
#[tauri::command]
pub async fn tray_set_recent_files(
    app: AppHandle,
    files: Vec<RecentFile>,
) -> Result<(), String> {
    {
        let state: tauri::State<SharedTrayState> = app.state();
        let mut state = state.lock().map_err(|e| e.to_string())?;
        state.recent_files = files;
    }
    update_tray_menu(&app).map_err(|e| e.to_string())
}

/// Update sync status from frontend
#[tauri::command]
pub async fn tray_set_sync_status(
    app: AppHandle,
    status: SyncStatus,
) -> Result<(), String> {
    {
        let state: tauri::State<SharedTrayState> = app.state();
        let mut state = state.lock().map_err(|e| e.to_string())?;
        state.sync_status = status;
    }
    update_tray_menu(&app).map_err(|e| e.to_string())
}

/// Update notification count from frontend
#[tauri::command]
pub async fn tray_set_notification_count(
    app: AppHandle,
    count: u32,
) -> Result<(), String> {
    {
        let state: tauri::State<SharedTrayState> = app.state();
        let mut state = state.lock().map_err(|e| e.to_string())?;
        state.unread_notifications = count;
    }
    update_tray_menu(&app).map_err(|e| e.to_string())
}

/// Get current tray state
#[tauri::command]
pub async fn tray_get_state(
    app: AppHandle,
) -> Result<TrayStateSnapshot, String> {
    let state: tauri::State<SharedTrayState> = app.state();
    let state = state.lock().map_err(|e| e.to_string())?;

    Ok(TrayStateSnapshot {
        recent_files: state.recent_files.clone(),
        sync_status: state.sync_status.clone(),
        unread_notifications: state.unread_notifications,
    })
}

/// Snapshot of tray state for serialization
#[derive(Clone, Debug, serde::Serialize)]
pub struct TrayStateSnapshot {
    pub recent_files: Vec<RecentFile>,
    pub sync_status: SyncStatus,
    pub unread_notifications: u32,
}
