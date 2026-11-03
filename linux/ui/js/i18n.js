const i18n = {
  currentLang: "vi",
  locales: {
    vi: {
      "tab.accounts": "Tài khoản",
      "tab.rotation": "Xoay vòng",
      "tab.general": "Hệ thống",
      "tab.about": "Giới thiệu",
      "btn.import": "Import từ IDE",
      "btn.login": "Đăng nhập Google",
      "btn.refresh": "Làm mới",
      "btn.switch": "Kích hoạt",
      "btn.delete": "Xóa",
      "badge.active": "Đang hoạt động",
      "badge.standby": "Dự phòng",
      "quota.5h": "Hạn mức 5 giờ",
      "quota.weekly": "Hạn mức tuần",
      "rotation.title": "Cấu hình Xoay vòng Thông minh (Smart Round-Robin)",
      "rotation.auto_enable": "Bật tự động xoay vòng tài khoản",
      "rotation.auto_desc": "Tự động chuyển sang tài khoản có quota tốt nhất khi tài khoản hiện tại cạn hạn mức",
      "rotation.threshold": "Ngưỡng kích hoạt xoay vòng",
      "rotation.threshold_desc": "Tự động chuyển khi hạn mức 5h còn dưới mức này",
      "rotation.interval": "Chu kỳ quét hạn mức",
      "rotation.interval_desc": "Khoảng thời gian kiểm tra lại quota thực tế từ API",
      "general.title": "Cài đặt Chung & Khởi động",
      "general.lang": "Ngôn ngữ giao diện",
      "general.autostart": "Khởi động cùng hệ điều hành",
      "general.autostart_desc": "Tạo dịch vụ XDG Autostart tự động chạy khi đăng nhập Linux",
      "general.notif": "Thông báo trên màn hình",
      "general.notif_desc": "Gửi thông báo desktop khi xoay vòng hoặc đổi tài khoản",
      "general.sound": "Âm thanh thông báo",
      "general.sound_desc": "Phát chuông thông báo khi có sự kiện",
      "about.desc": "Ứng dụng mã nguồn mở tối ưu, tự động giám sát quota và xoay vòng tài khoản Google AI Pro / Ultra cho Antigravity IDE, agy CLI & Desktop App trên hệ điều hành Linux.",
      "about.docs": "Tài liệu GitHub",
      "about.license": "Giấy phép MIT"
    },
    en: {
      "tab.accounts": "Accounts",
      "tab.rotation": "Rotation",
      "tab.general": "General",
      "tab.about": "About",
      "btn.import": "Import from IDE",
      "btn.login": "Google Login",
      "btn.refresh": "Refresh",
      "btn.switch": "Activate",
      "btn.delete": "Delete",
      "badge.active": "Active",
      "badge.standby": "Standby",
      "quota.5h": "5-Hour Quota",
      "quota.weekly": "Weekly Quota",
      "rotation.title": "Smart Round-Robin Rotation Configuration",
      "rotation.auto_enable": "Enable Auto-Rotation",
      "rotation.auto_desc": "Automatically switch to best account when active account quota runs low",
      "rotation.threshold": "Trigger Threshold",
      "rotation.threshold_desc": "Auto-rotate when 5h quota drops below this percentage",
      "rotation.interval": "Check Interval",
      "rotation.interval_desc": "Frequency of checking real-time quota from API",
      "general.title": "General & Startup Settings",
      "general.lang": "Display Language",
      "general.autostart": "Launch at System Startup",
      "general.autostart_desc": "Create XDG Autostart entry on Linux desktop session login",
      "general.notif": "Desktop Notifications",
      "general.notif_desc": "Send system notifications on account rotation",
      "general.sound": "Notification Sound",
      "general.sound_desc": "Play audible alert on notification events",
      "about.desc": "Open-source quota monitor and smart account rotator for Google AI Pro / Ultra accounts across Antigravity IDE, agy CLI & Desktop App on Linux.",
      "about.docs": "GitHub Repository",
      "about.license": "MIT License"
    },
    "zh-Hans": {
      "tab.accounts": "账号",
      "tab.rotation": "轮换",
      "tab.general": "常规",
      "tab.about": "关于",
      "btn.import": "从 IDE 导入",
      "btn.login": "Google 登录",
      "btn.refresh": "刷新",
      "btn.switch": "激活",
      "btn.delete": "删除",
      "badge.active": "当前激活",
      "badge.standby": "待机",
      "quota.5h": "5小时配额",
      "quota.weekly": "每周配额",
      "rotation.title": "智能轮换配置 (Smart Round-Robin)",
      "rotation.auto_enable": "启用自动轮换",
      "rotation.auto_desc": "当额度不足时自动切换至最佳备用账号",
      "rotation.threshold": "轮换触发阈值",
      "rotation.threshold_desc": "当5小时额度低于此百分比时自动触发轮换",
      "rotation.interval": "检查周期",
      "rotation.interval_desc": "从 API 刷新配额的时间间隔",
      "general.title": "常规与开机自启",
      "general.lang": "显示语言",
      "general.autostart": "开机自动启动",
      "general.autostart_desc": "在 Linux 桌面登录时通过 XDG 自动启动",
      "general.notif": "桌面通知",
      "general.notif_desc": "在轮换或切换账号时发送桌面通知",
      "general.sound": "提示音效",
      "general.sound_desc": "发送通知时播放提示音",
      "about.desc": "专为 Linux 平台 Antigravity IDE、agy CLI 和 Desktop App 打造的 Google AI Pro / Ultra 额度监控与智能轮换工具。",
      "about.docs": "GitHub 仓库",
      "about.license": "MIT 许可证"
    },
    ja: {
      "tab.accounts": "アカウント",
      "tab.rotation": "ローテーション",
      "tab.general": "一般",
      "tab.about": "情報",
      "btn.import": "IDEからインポート",
      "btn.login": "Googleログイン",
      "btn.refresh": "更新",
      "btn.switch": "有効化",
      "btn.delete": "削除",
      "badge.active": "アクティブ",
      "badge.standby": "スタンバイ",
      "quota.5h": "5時間クォータ",
      "quota.weekly": "週間クォータ",
      "rotation.title": "スマートローテーション設定",
      "rotation.auto_enable": "自動ローテーションを有効化",
      "rotation.auto_desc": "クォータ低下時に最適な待機アカウントへ自動切り替え",
      "rotation.threshold": "トリガーしきい値",
      "rotation.threshold_desc": "5時間クォータがこの値を下回るとローテーションを実行",
      "rotation.interval": "確認間隔",
      "rotation.interval_desc": "APIからのクォータ取得間隔",
      "general.title": "一般設定と自動起動",
      "general.lang": "表示言語",
      "general.autostart": "システム起動時に自動実行",
      "general.autostart_desc": "XDG Autostart を使用して自動起動",
      "general.notif": "デスクトップ通知",
      "general.notif_desc": "アカウント切り替え時に通知を表示",
      "general.sound": "通知音",
      "general.sound_desc": "通知時にサウンドを再生",
      "about.desc": "Antigravity IDE、agy CLI およびデスクトップ版向けの Google AI Pro / Ultra クォータ監視・自動ローテーションツール。",
      "about.docs": "GitHub リポジトリ",
      "about.license": "MIT ライセンス"
    }
  },

  t(key) {
    const dict = this.locales[this.currentLang] || this.locales["vi"];
    return dict[key] || this.locales["en"][key] || key;
  },

  setLang(lang) {
    if (this.locales[lang]) {
      this.currentLang = lang;
    } else {
      this.currentLang = "en";
    }
    this.updateDom();
  },

  updateDom() {
    document.querySelectorAll("[data-i18n]").forEach(el => {
      const key = el.getAttribute("data-i18n");
      el.textContent = this.t(key);
    });
  }
};

