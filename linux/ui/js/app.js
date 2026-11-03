// Tauri v2 API Bridge
const invoke = (cmd, args = {}) => {
  if (window.__TAURI__ && window.__TAURI__.core && window.__TAURI__.core.invoke) {
    return window.__TAURI__.core.invoke(cmd, args);
  }
  console.warn(`[Tauri Mock] Invoke '${cmd}'`, args);
  return Promise.resolve(null);
};

const listen = (event, callback) => {
  if (window.__TAURI__ && window.__TAURI__.event && window.__TAURI__.event.listen) {
    return window.__TAURI__.event.listen(event, callback);
  }
  return Promise.resolve(() => {});
};

// State
let accounts = [];
let currentConfig = null;

// DOM Elements
const accountsContainer = document.getElementById("accounts-container");
const globalStatusBadge = document.getElementById("global-status-badge");
const toast = document.getElementById("toast");

// Show Toast
function showToast(message, isError = false) {
  toast.textContent = message;
  toast.style.borderColor = isError ? "var(--accent-red)" : "var(--accent-blue)";
  toast.style.display = "block";
  setTimeout(() => {
    toast.style.display = "none";
  }, 3500);
}

// Format Percent
function getProgressColorClass(percentage) {
  if (percentage > 30) return "progress-green";
  if (percentage > 10) return "progress-yellow";
  return "progress-red";
}

// Render Accounts Cards
function renderAccounts(data) {
  accounts = data || [];
  if (accounts.length === 0) {
    accountsContainer.innerHTML = `
      <div style="text-align: center; padding: 40px; color: var(--text-muted); background: var(--bg-secondary); border-radius: var(--radius-md);">
        <p style="font-size: 14px; margin-bottom: 12px;">Chưa có tài khoản nào được thêm.</p>
        <p style="font-size: 12px;">Nhấn <b>"Import từ IDE"</b> hoặc <b>"Đăng nhập Google"</b> để bắt đầu quản lý và xoay vòng quota.</p>
      </div>
    `;
    globalStatusBadge.className = "badge badge-standby";
    globalStatusBadge.textContent = "⚪ Chờ";
    return;
  }

  // Find active account
  const active = accounts.find(a => a.is_current);
  if (active) {
    const pct = active.remaining_percentage >= 0 ? `${active.remaining_percentage}%` : "--%";
    const dot = active.remaining_percentage > 30 ? "🟢" : (active.remaining_percentage > 10 ? "🟡" : "🔴");
    globalStatusBadge.className = "badge badge-active";
    globalStatusBadge.textContent = `${dot} ${active.email} (${pct})`;
  } else {
    globalStatusBadge.className = "badge badge-standby";
    globalStatusBadge.textContent = "⚪ Standby";
  }

  let html = "";
  accounts.forEach((acc, idx) => {
    const isActive = acc.is_current;
    const g5h = acc.gemini_5h_percentage !== null && acc.gemini_5h_percentage !== undefined ? acc.gemini_5h_percentage : acc.remaining_percentage;
    const gWeek = acc.gemini_weekly_percentage !== null && acc.gemini_weekly_percentage !== undefined ? acc.gemini_weekly_percentage : 100;

    const tierClass = (acc.subscription_tier || "").toLowerCase().includes("ultra")
      ? "badge-ultra"
      : ((acc.subscription_tier || "").toLowerCase().includes("pro") ? "badge-pro" : "badge-standby");

    html += `
      <div class="account-card ${isActive ? 'active-account' : ''}">
        <div class="account-header">
          <div>
            <div class="account-title-group">
              <span class="account-email">${idx + 1}. ${acc.email}</span>
              <span class="badge ${isActive ? 'badge-active' : 'badge-standby'}">
                ${isActive ? i18n.t("badge.active") : i18n.t("badge.standby")}
              </span>
              <span class="badge ${tierClass}">${acc.subscription_tier || 'Free'}</span>
            </div>
            <div class="account-meta">
              <span class="badge badge-model">🤖 ${acc.active_model || 'Standby'}</span>
            </div>
          </div>

          <div class="account-actions">
            ${!isActive ? `
              <button class="btn btn-primary" onclick="switchAccount('${acc.id}')">
                <span>⚡</span> ${i18n.t("btn.switch")}
              </button>
            ` : ''}
            <button class="btn btn-danger" ${isActive ? 'disabled title="Không thể xóa tài khoản đang hoạt động"' : ''} onclick="deleteAccount('${acc.id}', '${acc.email}')">
              <span>🗑️</span> ${i18n.t("btn.delete")}
            </button>
          </div>
        </div>

        <div class="quota-bars">
          <div class="quota-bar-item">
            <div class="quota-bar-header">
              <span class="label">${i18n.t("quota.5h")}</span>
              <span class="val">${g5h >= 0 ? g5h + '%' : '--%'}</span>
            </div>
            <div class="progress-track">
              <div class="progress-fill ${getProgressColorClass(g5h)}" style="width: ${Math.max(0, Math.min(100, g5h))}%;"></div>
            </div>
          </div>

          <div class="quota-bar-item">
            <div class="quota-bar-header">
              <span class="label">${i18n.t("quota.weekly")}</span>
              <span class="val">${gWeek >= 0 ? gWeek + '%' : '--%'}</span>
            </div>
            <div class="progress-track">
              <div class="progress-fill ${getProgressColorClass(gWeek)}" style="width: ${Math.max(0, Math.min(100, gWeek))}%;"></div>
            </div>
          </div>
        </div>
      </div>
    `;
  });

  accountsContainer.innerHTML = html;
}

// Actions
window.switchAccount = async (accountId) => {
  try {
    const success = await invoke("switch_account", { accountId });
    if (success) {
      showToast("Đã kích hoạt tài khoản thành công!");
      await loadAccounts();
    } else {
      showToast("Lỗi chuyển đổi tài khoản.", true);
    }
  } catch (err) {
    showToast(String(err), true);
  }
};

window.deleteAccount = async (accountId, email) => {
  if (!confirm(`Bạn có chắc chắn muốn xóa tài khoản [${email}] khỏi Antigravity Orbit?`)) {
    return;
  }
  try {
    const res = await invoke("delete_account", { accountId });
    if (res && res.success) {
      showToast(res.message);
      await loadAccounts();
    } else {
      showToast((res && res.message) || "Lỗi xóa tài khoản.", true);
    }
  } catch (err) {
    showToast(String(err), true);
  }
};

async function loadAccounts() {
  try {
    const data = await invoke("get_accounts_status");
    renderAccounts(data);
  } catch (err) {
    console.error("Load accounts error:", err);
  }
}

async function loadConfig() {
  try {
    const cfg = await invoke("get_config");
    if (!cfg) return;
    currentConfig = cfg;

    document.getElementById("cfg-auto-rotate").checked = cfg.auto_rotate_enabled;
    document.getElementById("cfg-threshold").value = String(cfg.threshold_percentage);
    document.getElementById("cfg-interval").value = String(cfg.check_interval_seconds);
    document.getElementById("cfg-language").value = cfg.language;
    document.getElementById("cfg-autostart").checked = cfg.launch_at_login;
    document.getElementById("cfg-notifications").checked = cfg.notifications_enabled;
    document.getElementById("cfg-sound").checked = cfg.sound_enabled;

    i18n.setLang(cfg.language);
  } catch (err) {
    console.error("Load config error:", err);
  }
}

async function saveCurrentConfig() {
  if (!currentConfig) return;

  const newConfig = {
    threshold_percentage: parseInt(document.getElementById("cfg-threshold").value, 10),
    check_interval_seconds: parseInt(document.getElementById("cfg-interval").value, 10),
    auto_rotate_enabled: document.getElementById("cfg-auto-rotate").checked,
    notifications_enabled: document.getElementById("cfg-notifications").checked,
    sound_enabled: document.getElementById("cfg-sound").checked,
    launch_at_login: document.getElementById("cfg-autostart").checked,
    language: document.getElementById("cfg-language").value,
  };

  try {
    await invoke("save_config", { config: newConfig });
    currentConfig = newConfig;
    i18n.setLang(newConfig.language);
    showToast("Đã lưu cấu hình thành công!");
  } catch (err) {
    showToast(String(err), true);
  }
}

// Bind Toolbar Buttons
document.getElementById("btn-import-ide").addEventListener("click", async () => {
  try {
    const res = await invoke("import_from_ide");
    if (res && res.success) {
      showToast(res.message);
      await loadAccounts();
    } else {
      showToast((res && res.message) || "Không thể import từ IDE.", true);
    }
  } catch (err) {
    showToast(String(err), true);
  }
});

document.getElementById("btn-google-login").addEventListener("click", async () => {
  try {
    showToast("Đang mở trình duyệt để xác thực Google OAuth...");
    await invoke("start_google_login");
  } catch (err) {
    showToast(String(err), true);
  }
});

document.getElementById("btn-refresh-quotas").addEventListener("click", async () => {
  try {
    showToast("Đang cập nhật hạn mức...");
    const data = await invoke("refresh_quotas");
    renderAccounts(data);
    showToast("Đã làm mới dữ liệu quota thành công!");
  } catch (err) {
    showToast(String(err), true);
  }
});

// Bind Config Form Changes
["cfg-auto-rotate", "cfg-threshold", "cfg-interval", "cfg-language", "cfg-autostart", "cfg-notifications", "cfg-sound"].forEach(id => {
  document.getElementById(id).addEventListener("change", saveCurrentConfig);
});

// Tab Navigation
document.querySelectorAll(".tab-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
    document.querySelectorAll(".tab-pane").forEach(p => p.classList.remove("active"));

    btn.classList.add("active");
    const tabId = btn.getAttribute("data-tab");
    document.getElementById(tabId).classList.add("active");
  });
});

// Listen to Tauri events
listen("quotas_updated", (event) => {
  if (event.payload) {
    renderAccounts(event.payload);
  }
});

listen("oauth_completed", (event) => {
  if (event.payload) {
    showToast(event.payload.message, !event.payload.success);
    loadAccounts();
  }
});

listen("navigate_tab", (event) => {
  const tabIndex = event.payload || 0;
  const tabButtons = document.querySelectorAll(".tab-btn");
  if (tabButtons[tabIndex]) {
    tabButtons[tabIndex].click();
  }
});

// Init on load
window.addEventListener("DOMContentLoaded", async () => {
  await loadConfig();
  await loadAccounts();
});

