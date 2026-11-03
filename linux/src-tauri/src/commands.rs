use tauri::{AppHandle, Emitter, Manager, State};
use crate::AppState;
use crate::autostart::AutostartManager;
use crate::locales::L10n;
use crate::models::{AccountStatus, RotatorConfig};
use crate::notifications::NotificationManager;
use crate::oauth_server::OAuthServer;
use crate::tray::TrayManager;

#[tauri::command]
pub async fn get_accounts_status(state: State<'_, AppState>) -> Result<Vec<AccountStatus>, String> {
    let statuses = state.current_statuses.lock().unwrap().clone();
    Ok(statuses)
}

#[tauri::command]
pub async fn get_config(state: State<'_, AppState>) -> Result<RotatorConfig, String> {
    Ok(state.config_manager.get_config())
}

#[tauri::command]
pub async fn save_config(
    app: AppHandle,
    state: State<'_, AppState>,
    config: RotatorConfig,
) -> Result<bool, String> {
    let old_cfg = state.config_manager.get_config();
    let lang = config.language.clone();

    // Sync autostart
    if old_cfg.launch_at_login != config.launch_at_login {
        AutostartManager::set_enabled(config.launch_at_login);
    }

    state.config_manager.save_config(config)?;

    // Update tray with new language
    let statuses = state.current_statuses.lock().unwrap().clone();
    TrayManager::update_tray(&app, &statuses, &lang);

    Ok(true)
}

#[tauri::command]
pub async fn switch_account(
    app: AppHandle,
    state: State<'_, AppState>,
    account_id: String,
) -> Result<bool, String> {
    let success = state.rotator.switch_to_account(&account_id);
    if success {
        let statuses = state.quota_service.fetch_all_quotas().await;
        *state.current_statuses.lock().unwrap() = statuses.clone();
        let lang = state.config_manager.get_config().language;
        TrayManager::update_tray(&app, &statuses, &lang);

        if let Some(switched) = statuses.iter().find(|s| s.id == account_id) {
            let cfg = state.config_manager.get_config();
            if cfg.notifications_enabled {
                let body = format!("Đã kích hoạt tài khoản [{}] (Quota: {}%).", switched.email, switched.remaining_percentage);
                NotificationManager::send(
                    &L10n::tr("notif.auto_rotate_title", &lang),
                    &L10n::tr("notif.manual_switch_subtitle", &lang),
                    &body,
                    cfg.sound_enabled,
                );
            }
        }
    }
    Ok(success)
}

#[tauri::command]
pub async fn rotate_account(
    app: AppHandle,
    state: State<'_, AppState>,
    reason: Option<String>,
) -> Result<bool, String> {
    let cfg = state.config_manager.get_config();
    let statuses = state.current_statuses.lock().unwrap().clone();
    let reason_str = reason.unwrap_or_else(|| "Thao tác thủ công".to_string());

    if let Some(_) = state.rotator.rotate_to_next(
        &statuses,
        &reason_str,
        cfg.threshold_percentage,
        cfg.notifications_enabled,
        cfg.sound_enabled,
    ) {
        let new_statuses = state.quota_service.fetch_all_quotas().await;
        *state.current_statuses.lock().unwrap() = new_statuses.clone();
        TrayManager::update_tray(&app, &new_statuses, &cfg.language);
        Ok(true)
    } else {
        Ok(false)
    }
}

#[tauri::command]
pub async fn import_from_ide(
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<serde_json::Value, String> {
    let (success, message) = state.account_manager.import_from_ide();
    if success {
        let new_statuses = state.quota_service.fetch_all_quotas().await;
        *state.current_statuses.lock().unwrap() = new_statuses.clone();
        let lang = state.config_manager.get_config().language;
        TrayManager::update_tray(&app, &new_statuses, &lang);
    }
    Ok(serde_json::json!({
        "success": success,
        "message": message
    }))
}

#[tauri::command]
pub async fn start_google_login(
    app: AppHandle,
) -> Result<String, String> {
    let app_handle = app.clone();
    let auth_url = OAuthServer::start_login_flow(move |success, msg, token, user| {
        if success {
            if let (Some(t), Some(u)) = (token, user) {
                let state = app_handle.state::<AppState>();
                let (add_ok, add_msg) = state.account_manager.add_account_from_oauth(t, u);
                let _ = app_handle.emit("oauth_completed", serde_json::json!({
                    "success": add_ok,
                    "message": add_msg
                }));

                // Refresh quotas
                let app_inner = app_handle.clone();
                tauri::async_runtime::spawn(async move {
                    let st = app_inner.state::<AppState>();
                    let new_statuses = st.quota_service.fetch_all_quotas().await;
                    *st.current_statuses.lock().unwrap() = new_statuses.clone();
                    let lang = st.config_manager.get_config().language;
                    TrayManager::update_tray(&app_inner, &new_statuses, &lang);
                });
                return;
            }
        }
        let _ = app_handle.emit("oauth_completed", serde_json::json!({
            "success": success,
            "message": msg
        }));
    }).await?;

    Ok(auth_url)
}

#[tauri::command]
pub async fn delete_account(
    app: AppHandle,
    state: State<'_, AppState>,
    account_id: String,
) -> Result<serde_json::Value, String> {
    let (success, message) = state.account_manager.delete_account(&account_id);
    if success {
        let new_statuses = state.quota_service.fetch_all_quotas().await;
        *state.current_statuses.lock().unwrap() = new_statuses.clone();
        let lang = state.config_manager.get_config().language;
        TrayManager::update_tray(&app, &new_statuses, &lang);
    }
    Ok(serde_json::json!({
        "success": success,
        "message": message
    }))
}

#[tauri::command]
pub async fn refresh_quotas(
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<Vec<AccountStatus>, String> {
    let new_statuses = state.quota_service.fetch_all_quotas().await;
    *state.current_statuses.lock().unwrap() = new_statuses.clone();
    let lang = state.config_manager.get_config().language;
    TrayManager::update_tray(&app, &new_statuses, &lang);
    Ok(new_statuses)
}
