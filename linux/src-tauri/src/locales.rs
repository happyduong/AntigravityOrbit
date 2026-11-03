use std::collections::HashMap;

pub struct L10n;

impl L10n {
    pub fn tr(key: &str, lang: &str) -> String {
        let dict = Self::get_dictionary(lang);
        if let Some(&val) = dict.get(key) {
            return val.to_string();
        }
        // Fallback to Vietnamese, then English
        if lang != "vi" {
            let vi_dict = Self::get_dictionary("vi");
            if let Some(&val) = vi_dict.get(key) {
                return val.to_string();
            }
        }
        let en_dict = Self::get_dictionary("en");
        en_dict.get(key).copied().unwrap_or(key).to_string()
    }

    fn get_dictionary(lang: &str) -> HashMap<&'static str, &'static str> {
        let mut m = HashMap::new();
        match lang {
            "en" => {
                m.insert("menu.loading", "Loading quota data...");
                m.insert("menu.no_accounts", "No accounts active (Standby)");
                m.insert("menu.active_account", "Active Account");
                m.insert("menu.switch_to", "Switch to this account");
                m.insert("menu.manual_rotate", "Rotate to Next Account (Ctrl+R)");
                m.insert("menu.refresh", "Refresh Quotas Now");
                m.insert("menu.settings", "Settings...");
                m.insert("menu.about", "About Antigravity Orbit...");
                m.insert("menu.quit", "Quit Antigravity Orbit");
                m.insert("settings.title", "Antigravity Orbit Settings");
                m.insert("settings.tab_accounts", "Accounts");
                m.insert("settings.tab_rotation", "Rotation");
                m.insert("settings.tab_general", "General");
                m.insert("settings.accounts_list_title", "Managed Google AI Accounts");
                m.insert("settings.btn_import", "Import from Antigravity IDE");
                m.insert("settings.btn_login", "Add Account (Google OAuth)");
                m.insert("settings.btn_delete", "Delete Account");
                m.insert("settings.btn_switch", "Switch to Account");
                m.insert("settings.btn_refresh", "Refresh Quotas");
                m.insert("settings.auto_rotate", "Enable Smart Auto-Rotation when quota is low");
                m.insert("settings.threshold", "Rotation Trigger Threshold (%):");
                m.insert("settings.interval", "Quota Check Interval:");
                m.insert("settings.language", "Display Language:");
                m.insert("settings.launch_at_login", "Launch at System Startup");
                m.insert("settings.notifications", "Enable Desktop Notifications");
                m.insert("settings.sound", "Play Notification Sound");
                m.insert("notif.auto_rotate_title", "Antigravity Orbit");
                m.insert("notif.auto_rotate_subtitle", "Smart Account Rotated");
                m.insert("notif.manual_switch_subtitle", "Account Switched");
            }
            "zh-Hans" => {
                m.insert("menu.loading", "正在加载额度数据...");
                m.insert("menu.no_accounts", "无有效账号（待机中）");
                m.insert("menu.active_account", "当前活动账号");
                m.insert("menu.switch_to", "切换至此账号");
                m.insert("menu.manual_rotate", "轮换到下一个可用账号 (Ctrl+R)");
                m.insert("menu.refresh", "立即刷新配额");
                m.insert("menu.settings", "设置...");
                m.insert("menu.about", "关于 Antigravity Orbit...");
                m.insert("menu.quit", "退出应用程序");
                m.insert("settings.title", "Antigravity Orbit 设置");
                m.insert("settings.tab_accounts", "账号管理");
                m.insert("settings.tab_rotation", "轮换策略");
                m.insert("settings.tab_general", "常规设置");
                m.insert("settings.accounts_list_title", "Google AI 托管账号列表");
                m.insert("settings.btn_import", "从 Antigravity IDE 导入");
                m.insert("settings.btn_login", "添加新账号 (Google OAuth)");
                m.insert("settings.btn_delete", "删除账号");
                m.insert("settings.btn_switch", "立即激活");
                m.insert("settings.btn_refresh", "刷新数据");
                m.insert("settings.auto_rotate", "当额度不足时自动轮换账号");
                m.insert("settings.threshold", "轮换触发阈值 (剩余百分比):");
                m.insert("settings.interval", "配额检查周期:");
                m.insert("settings.language", "显示语言:");
                m.insert("settings.launch_at_login", "开机自启动");
                m.insert("settings.notifications", "启用桌面通知");
                m.insert("settings.sound", "播放提示音");
                m.insert("notif.auto_rotate_title", "Antigravity Orbit");
                m.insert("notif.auto_rotate_subtitle", "已自动轮换账号");
                m.insert("notif.manual_switch_subtitle", "已成功切换账号");
            }
            "ja" => {
                m.insert("menu.loading", "クォータデータを読み込み中...");
                m.insert("menu.no_accounts", "アクティブなアカウントがありません");
                m.insert("menu.active_account", "現在のアカウント");
                m.insert("menu.switch_to", "このアカウントに切り替える");
                m.insert("menu.manual_rotate", "次のアカウントへローテーション (Ctrl+R)");
                m.insert("menu.refresh", "クォータを今すぐ更新");
                m.insert("menu.settings", "設定...");
                m.insert("menu.about", "Antigravity Orbit について...");
                m.insert("menu.quit", "終了");
                m.insert("settings.title", "Antigravity Orbit 設定");
                m.insert("settings.tab_accounts", "アカウント");
                m.insert("settings.tab_rotation", "ローテーション");
                m.insert("settings.tab_general", "一般設定");
                m.insert("settings.accounts_list_title", "管理対象 Google AI アカウント");
                m.insert("settings.btn_import", "Antigravity IDE からインポート");
                m.insert("settings.btn_login", "アカウントを追加 (Google OAuth)");
                m.insert("settings.btn_delete", "アカウントを削除");
                m.insert("settings.btn_switch", "アカウントをアクティブ化");
                m.insert("settings.btn_refresh", "データを更新");
                m.insert("settings.auto_rotate", "クォータ低下時に自動ローテーションを有効化");
                m.insert("settings.threshold", "ローテーションしきい値 (%):");
                m.insert("settings.interval", "クォータ確認間隔:");
                m.insert("settings.language", "表示言語:");
                m.insert("settings.launch_at_login", "システム起動時に自動起動");
                m.insert("settings.notifications", "デスクトップ通知を有効にする");
                m.insert("settings.sound", "通知サウンドを再生");
                m.insert("notif.auto_rotate_title", "Antigravity Orbit");
                m.insert("notif.auto_rotate_subtitle", "アカウントが自動ローテーションされました");
                m.insert("notif.manual_switch_subtitle", "アカウントを切り替えました");
            }
            _ => {
                // Default: Vietnamese (vi)
                m.insert("menu.loading", "Đang tải dữ liệu hạn mức...");
                m.insert("menu.no_accounts", "Chưa kích hoạt tài khoản nào (Chờ)");
                m.insert("menu.active_account", "Tài khoản đang hoạt động");
                m.insert("menu.switch_to", "Chuyển sang tài khoản này");
                m.insert("menu.manual_rotate", "Xoay vòng sang tài khoản tiếp theo (Ctrl+R)");
                m.insert("menu.refresh", "Làm mới hạn mức ngay");
                m.insert("menu.settings", "Cài đặt ứng dụng...");
                m.insert("menu.about", "Về Antigravity Orbit...");
                m.insert("menu.quit", "Thoát ứng dụng");
                m.insert("settings.title", "Cài đặt Antigravity Orbit");
                m.insert("settings.tab_accounts", "Tài khoản");
                m.insert("settings.tab_rotation", "Xoay vòng");
                m.insert("settings.tab_general", "Hệ thống");
                m.insert("settings.accounts_list_title", "Danh sách tài khoản Google AI");
                m.insert("settings.btn_import", "Import từ Antigravity IDE");
                m.insert("settings.btn_login", "Thêm tài khoản mới (Google OAuth)");
                m.insert("settings.btn_delete", "Xóa tài khoản");
                m.insert("settings.btn_switch", "Kích hoạt tài khoản");
                m.insert("settings.btn_refresh", "Làm mới dữ liệu");
                m.insert("settings.auto_rotate", "Tự động xoay vòng tài khoản khi cạn hạn mức");
                m.insert("settings.threshold", "Ngưỡng kích hoạt xoay vòng (% còn lại):");
                m.insert("settings.interval", "Chu kỳ kiểm tra hạn mức:");
                m.insert("settings.language", "Ngôn ngữ hiển thị (Language):");
                m.insert("settings.launch_at_login", "Tự động khởi động cùng hệ thống");
                m.insert("settings.notifications", "Bật thông báo đẩy trên màn hình");
                m.insert("settings.sound", "Phát âm thanh thông báo");
                m.insert("notif.auto_rotate_title", "Antigravity Orbit");
                m.insert("notif.auto_rotate_subtitle", "Đã tự động xoay vòng tài khoản");
                m.insert("notif.manual_switch_subtitle", "Đã chuyển đổi tài khoản thành công");
            }
        }
        m
    }
}

