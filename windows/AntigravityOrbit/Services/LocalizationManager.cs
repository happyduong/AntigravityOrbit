using System.Collections.Generic;

namespace AntigravityOrbit.Services
{
    public static class LocalizationManager
    {
        private static readonly Dictionary<string, Dictionary<string, string>> Locales = new()
        {
            ["vi"] = new()
            {
                ["app.title"] = "Antigravity Orbit",
                ["menu.loading"] = "Đang tải dữ liệu hạn mức...",
                ["menu.no_accounts"] = "Chưa kích hoạt tài khoản nào (Chờ)",
                ["menu.active_account"] = "Tài khoản đang hoạt động",
                ["menu.switch_to"] = "Chuyển sang tài khoản này",
                ["menu.manual_rotate"] = "Xoay vòng sang tài khoản tiếp theo (Ctrl+R)",
                ["menu.refresh"] = "Làm mới hạn mức ngay",
                ["menu.settings"] = "Cài đặt ứng dụng...",
                ["menu.about"] = "Về Antigravity Orbit...",
                ["menu.quit"] = "Thoát ứng dụng",
                ["tab.accounts"] = "Tài khoản",
                ["tab.rotation"] = "Xoay vòng",
                ["tab.general"] = "Hệ thống",
                ["tab.about"] = "Giới thiệu",
                ["btn.import"] = "Import từ IDE",
                ["btn.login"] = "Đăng nhập Google",
                ["btn.refresh"] = "Làm mới",
                ["btn.switch"] = "Kích hoạt",
                ["btn.delete"] = "Xóa",
                ["badge.active"] = "Đang hoạt động",
                ["badge.standby"] = "Dự phòng",
                ["quota.5h"] = "Hạn mức 5 giờ",
                ["quota.weekly"] = "Hạn mức tuần",
                ["rotation.title"] = "Cấu hình Xoay vòng Thông minh (Smart Round-Robin)",
                ["rotation.auto_enable"] = "Bật tự động xoay vòng tài khoản",
                ["rotation.auto_desc"] = "Tự động chuyển sang tài khoản có quota tốt nhất khi tài khoản hiện tại cạn hạn mức",
                ["rotation.threshold"] = "Ngưỡng kích hoạt xoay vòng (% còn lại)",
                ["rotation.interval"] = "Chu kỳ quét hạn mức",
                ["general.title"] = "Cài đặt Chung & Khởi động",
                ["general.lang"] = "Ngôn ngữ giao diện",
                ["general.autostart"] = "Khởi động cùng Windows 11",
                ["general.autostart_desc"] = "Tự động chạy ngầm trên khay Taskbar khi đăng nhập Windows",
                ["general.notif"] = "Bật thông báo đẩy (Toast Notification)",
                ["general.sound"] = "Phát âm thanh thông báo",
                ["notif.auto_rotate_title"] = "Antigravity Orbit",
                ["notif.auto_rotate_subtitle"] = "Đã tự động xoay vòng tài khoản",
                ["notif.manual_switch_subtitle"] = "Đã chuyển đổi tài khoản thành công"
            },
            ["en"] = new()
            {
                ["app.title"] = "Antigravity Orbit",
                ["menu.loading"] = "Loading quota data...",
                ["menu.no_accounts"] = "No accounts active (Standby)",
                ["menu.active_account"] = "Active Account",
                ["menu.switch_to"] = "Switch to this account",
                ["menu.manual_rotate"] = "Rotate to Next Account (Ctrl+R)",
                ["menu.refresh"] = "Refresh Quotas Now",
                ["menu.settings"] = "Settings...",
                ["menu.about"] = "About Antigravity Orbit...",
                ["menu.quit"] = "Quit Antigravity Orbit",
                ["tab.accounts"] = "Accounts",
                ["tab.rotation"] = "Rotation",
                ["tab.general"] = "General",
                ["tab.about"] = "About",
                ["btn.import"] = "Import from IDE",
                ["btn.login"] = "Google Login",
                ["btn.refresh"] = "Refresh",
                ["btn.switch"] = "Activate",
                ["btn.delete"] = "Delete",
                ["badge.active"] = "Active",
                ["badge.standby"] = "Standby",
                ["quota.5h"] = "5-Hour Quota",
                ["quota.weekly"] = "Weekly Quota",
                ["rotation.title"] = "Smart Round-Robin Rotation Configuration",
                ["rotation.auto_enable"] = "Enable Auto-Rotation",
                ["rotation.auto_desc"] = "Automatically switch to best account when active account quota runs low",
                ["rotation.threshold"] = "Rotation Trigger Threshold (%):",
                ["rotation.interval"] = "Check Interval",
                ["general.title"] = "General & Startup Settings",
                ["general.lang"] = "Display Language",
                ["general.autostart"] = "Launch at Windows Startup",
                ["general.autostart_desc"] = "Automatically start minimized in Taskbar System Tray",
                ["general.notif"] = "Enable Toast Notifications",
                ["general.sound"] = "Play Notification Sound",
                ["notif.auto_rotate_title"] = "Antigravity Orbit",
                ["notif.auto_rotate_subtitle"] = "Smart Account Rotated",
                ["notif.manual_switch_subtitle"] = "Account Switched"
            }
        };

        public static string CurrentLanguage { get; set; } = "vi";

        public static string Tr(string key)
        {
            if (Locales.TryGetValue(CurrentLanguage, out var dict) && dict.TryGetValue(key, out var val))
            {
                return val;
            }
            if (Locales["en"].TryGetValue(key, out var enVal))
            {
                return enVal;
            }
            return key;
        }
    }
}

