pub mod models;
pub mod config;
pub mod locales;
pub mod quota_service;
pub mod account_manager;
pub mod rotator;
pub mod oauth_server;
pub mod keyring;
pub mod autostart;
pub mod notifications;
pub mod tray;
pub mod commands;

use std::fs::{self, OpenOptions};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use fs2::FileExt;
use tauri::{AppHandle, Emitter, Listener, Manager, WindowEvent};
use crate::account_manager::AccountManager;
use crate::config::ConfigManager;
use crate::models::AccountStatus;
use crate::quota_service::QuotaService;
use crate::rotator::AccountRotator;
use crate::tray::TrayManager;

pub struct AppState {
    pub config_manager: ConfigManager,
    pub quota_service: QuotaService,
    pub account_manager: AccountManager,
    pub rotator: AccountRotator,
    pub current_statuses: Arc<Mutex<Vec<AccountStatus>>>,
}

pub fn start_background_quota_loop(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        // Initial fetch
        {
            let state = app.state::<AppState>();
            let initial = state.quota_service.fetch_all_quotas().await;
            *state.current_statuses.lock().unwrap() = initial.clone();
            let lang = state.config_manager.get_config().language;
            TrayManager::update_tray(&app, &initial, &lang);
        }

        loop {
            let interval_secs = {
                let state = app.state::<AppState>();
                state.config_manager.get_config().check_interval_seconds.max(10) as u64
            };

            tokio::time::sleep(Duration::from_secs(interval_secs)).await;

            let state = app.state::<AppState>();
            let statuses = state.quota_service.fetch_all_quotas().await;
            *state.current_statuses.lock().unwrap() = statuses.clone();

            let cfg = state.config_manager.get_config();

            // Auto-rotation check
            if cfg.auto_rotate_enabled {
                if let Some(active) = statuses.iter().find(|s| s.is_current) {
                    if active.remaining_percentage <= cfg.threshold_percentage && active.remaining_percentage >= 0 {
                        println!(
                            "[AutoRotate] Active account {} quota ({}%) <= threshold ({}%). Rotating...",
                            active.email, active.remaining_percentage, cfg.threshold_percentage
                        );
                        let reason = format!("Hạn mức còn {}% (ngưỡng: {}%)", active.remaining_percentage, cfg.threshold_percentage);
                        if let Some(_) = state.rotator.rotate_to_next(
                            &statuses,
                            &reason,
                            cfg.threshold_percentage,
                            cfg.notifications_enabled,
                            cfg.sound_enabled,
                        ) {
                            let refreshed = state.quota_service.fetch_all_quotas().await;
                            *state.current_statuses.lock().unwrap() = refreshed.clone();
                            TrayManager::update_tray(&app, &refreshed, &cfg.language);
                            let _ = app.emit("quotas_updated", refreshed);
                            continue;
                        }
                    }
                }
            }

            TrayManager::update_tray(&app, &statuses, &cfg.language);
            let _ = app.emit("quotas_updated", statuses);
        }
    });
}

pub fn run() {
    // 1. Single instance lock via ~/.antigravity_orbit/orbit.lock
    let home = dirs::home_dir().unwrap_or_else(|| std::path::PathBuf::from("/"));
    let orbit_dir = home.join(".antigravity_orbit");
    let _ = fs::create_dir_all(&orbit_dir);
    let lock_path = orbit_dir.join("orbit.lock");

    let lock_file = match OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .open(&lock_path)
    {
        Ok(f) => f,
        Err(e) => {
            eprintln!("[AntigravityOrbit] Failed to open lock file: {}", e);
            std::process::exit(1);
        }
    };

    if lock_file.try_lock_exclusive().is_err() {
        println!("[AntigravityOrbit] Another instance is already running. Exiting immediately.");
        std::process::exit(0);
    }

    // Keep lock_file alive for process duration
    let _keep_lock = Box::leak(Box::new(lock_file));

    // 2. Initialize Tauri Application
    tauri::Builder::default()
        .setup(|app| {
            let config_mgr = ConfigManager::new();
            let quota_svc = QuotaService::new();
            let account_mgr = AccountManager::new();
            let rotator = AccountRotator::new();

            let state = AppState {
                config_manager: config_mgr,
                quota_service: quota_svc,
                account_manager: account_mgr,
                rotator,
                current_statuses: Arc::new(Mutex::new(Vec::new())),
            };

            app.manage(state);

            // Build Tray Icon
            let _ = TrayManager::build_tray(app.handle())?;

            // Setup Event Listeners for Tray actions
            let app_handle = app.handle().clone();
            app.listen("action_switch", move |event| {
                if let Ok(acc_id) = serde_json::from_str::<String>(event.payload()) {
                    let h = app_handle.clone();
                    tauri::async_runtime::spawn(async move {
                        let st = h.state::<AppState>();
                        let _ = commands::switch_account(h.clone(), st, acc_id).await;
                    });
                }
            });

            let app_handle2 = app.handle().clone();
            app.listen("action_rotate", move |_| {
                let h = app_handle2.clone();
                tauri::async_runtime::spawn(async move {
                    let st = h.state::<AppState>();
                    let _ = commands::rotate_account(h.clone(), st, None).await;
                });
            });

            let app_handle3 = app.handle().clone();
            app.listen("action_refresh", move |_| {
                let h = app_handle3.clone();
                tauri::async_runtime::spawn(async move {
                    let st = h.state::<AppState>();
                    let _ = commands::refresh_quotas(h.clone(), st).await;
                });
            });

            // Start background monitoring & auto-rotation loop
            start_background_quota_loop(app.handle().clone());

            println!("[AntigravityOrbit] Linux daemon started successfully.");
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                // Prevent window destruction, hide to tray instead
                window.hide().unwrap_or_default();
                api.prevent_close();
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_accounts_status,
            commands::get_config,
            commands::save_config,
            commands::switch_account,
            commands::rotate_account,
            commands::import_from_ide,
            commands::start_google_login,
            commands::delete_account,
            commands::refresh_quotas,
        ])
        .run(tauri::generate_context!())
        .expect("error while running antigravity-orbit");
}
