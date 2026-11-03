use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::tray::{TrayIcon, TrayIconBuilder};
use tauri::{AppHandle, Emitter, Manager, Wry};
use crate::locales::L10n;
use crate::models::AccountStatus;

pub struct TrayManager;

impl TrayManager {
    pub const TRAY_ID: &'static str = "antigravity_orbit_tray";

    pub fn build_tray(app: &AppHandle) -> Result<TrayIcon, tauri::Error> {
        let menu = Self::create_menu(app, &[], "vi")?;
        TrayIconBuilder::with_id(Self::TRAY_ID)
            .tooltip("Antigravity Orbit")
            .menu(&menu)
            .show_menu_on_left_click(true)
            .on_menu_event(|app, event| {
                let id = event.id().as_ref();
                Self::handle_menu_event(app, id);
            })
            .build(app)
    }

    pub fn update_tray(app: &AppHandle, statuses: &[AccountStatus], lang: &str) {
        let tray = match app.tray_by_id(Self::TRAY_ID) {
            Some(t) => t,
            None => return,
        };

        // 1. Build updated tooltip
        let active = statuses.iter().find(|s| s.is_current);
        let tooltip = if let Some(acc) = active {
            let g5h = acc.gemini_5h_percentage.map(|p| format!("{}%", p)).unwrap_or_else(|| "--%".to_string());
            let g_week = acc.gemini_weekly_percentage.map(|p| format!("{}%", p)).unwrap_or_else(|| "--%".to_string());
            format!(
                "Antigravity Orbit: {}\nModel: {}\n(5h: {} • Tuần: {})",
                acc.email,
                acc.display_model_name(),
                g5h,
                g_week
            )
        } else {
            format!("Antigravity Orbit\n{}", L10n::tr("menu.no_accounts", lang))
        };
        let _ = tray.set_tooltip(Some(tooltip));

        // 2. Set Tray Title (Percentage & indicator) if supported
        if let Some(acc) = active {
            let pct = acc.remaining_percentage;
            let icon_dot = if pct > 30 {
                "🟢"
            } else if pct > 10 {
                "🟡"
            } else if pct >= 0 {
                "🔴"
            } else {
                "⚪"
            };
            let title = format!("{}% {}", if pct >= 0 { pct.to_string() } else { "--".to_string() }, icon_dot);
            let _ = tray.set_title(Some(title));
        }

        // 3. Update Menu
        if let Ok(new_menu) = Self::create_menu(app, statuses, lang) {
            let _ = tray.set_menu(Some(new_menu));
        }
    }

    fn create_menu(app: &AppHandle, statuses: &[AccountStatus], lang: &str) -> Result<Menu<Wry>, tauri::Error> {
        let menu = Menu::new(app)?;

        // Active account info header
        let active = statuses.iter().find(|s| s.is_current);
        if let Some(acc) = active {
            let info_title = format!("✔ {} ({}%)", acc.email, acc.remaining_percentage);
            let item = MenuItem::with_id(app, "active_info", &info_title, false, None::<&str>)?;
            menu.append(&item)?;

            let model_title = format!("   Model: {}", acc.display_model_name());
            let m_item = MenuItem::with_id(app, "active_model", &model_title, false, None::<&str>)?;
            menu.append(&m_item)?;
        } else {
            let item = MenuItem::with_id(app, "no_active", L10n::tr("menu.no_accounts", lang), false, None::<&str>)?;
            menu.append(&item)?;
        }

        menu.append(&PredefinedMenuItem::separator(app)?)?;

        // Accounts Submenu
        let accounts_submenu = Submenu::new(app, L10n::tr("settings.tab_accounts", lang), true)?;
        if statuses.is_empty() {
            let empty_item = MenuItem::with_id(app, "empty_accounts", L10n::tr("menu.no_accounts", lang), false, None::<&str>)?;
            accounts_submenu.append(&empty_item)?;
        } else {
            for (idx, acc) in statuses.iter().enumerate() {
                let check = if acc.is_current { "● " } else { "○ " };
                let g5h = acc.gemini_5h_percentage.map(|p| format!("{}%", p)).unwrap_or_else(|| "--%".to_string());
                let title = format!("{}{}. {} (5h: {})", check, idx + 1, acc.email, g5h);
                let switch_id = format!("switch_to_{}", acc.id);
                let item = MenuItem::with_id(app, &switch_id, &title, !acc.is_current, None::<&str>)?;
                accounts_submenu.append(&item)?;
            }
        }
        menu.append(&accounts_submenu)?;

        // Manual rotate
        let rotate_item = MenuItem::with_id(app, "rotate_next", L10n::tr("menu.manual_rotate", lang), true, Some("Ctrl+R"))?;
        menu.append(&rotate_item)?;

        // Refresh Quotas
        let refresh_item = MenuItem::with_id(app, "refresh_quotas", L10n::tr("menu.refresh", lang), true, None::<&str>)?;
        menu.append(&refresh_item)?;

        menu.append(&PredefinedMenuItem::separator(app)?)?;

        // Settings Window
        let settings_item = MenuItem::with_id(app, "open_settings", L10n::tr("menu.settings", lang), true, Some("Ctrl+,"))?;
        menu.append(&settings_item)?;

        // About
        let about_item = MenuItem::with_id(app, "open_about", L10n::tr("menu.about", lang), true, None::<&str>)?;
        menu.append(&about_item)?;

        menu.append(&PredefinedMenuItem::separator(app)?)?;

        // Quit
        let quit_item = MenuItem::with_id(app, "quit_app", L10n::tr("menu.quit", lang), true, Some("Ctrl+Q"))?;
        menu.append(&quit_item)?;

        Ok(menu)
    }

    fn handle_menu_event(app: &AppHandle, id: &str) {
        if id == "quit_app" {
            app.exit(0);
        } else if id == "open_settings" {
            if let Some(win) = app.get_webview_window("main") {
                let _ = win.show();
                let _ = win.set_focus();
                let _ = win.emit("navigate_tab", 0);
            }
        } else if id == "open_about" {
            if let Some(win) = app.get_webview_window("main") {
                let _ = win.show();
                let _ = win.set_focus();
                let _ = win.emit("navigate_tab", 3); // 3 = About Tab
            }
        } else if id == "rotate_next" {
            let app_clone = app.clone();
            tauri::async_runtime::spawn(async move {
                let _ = app_clone.emit("action_rotate", ());
            });
        } else if id == "refresh_quotas" {
            let app_clone = app.clone();
            tauri::async_runtime::spawn(async move {
                let _ = app_clone.emit("action_refresh", ());
            });
        } else if let Some(acc_id) = id.strip_prefix("switch_to_") {
            let acc_id_owned = acc_id.to_string();
            let app_clone = app.clone();
            tauri::async_runtime::spawn(async move {
                let _ = app_clone.emit("action_switch", acc_id_owned);
            });
        }
    }
}
