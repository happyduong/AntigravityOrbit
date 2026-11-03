use std::fs;
use std::path::PathBuf;
use chrono::Utc;
use uuid::Uuid;
use crate::models::{AccountDetailFile, AccountDetailQuota, AccountToken, AccountsFile, ManagedAccount};
use crate::oauth_server::{OAuthTokenData, OAuthUserInfo};

#[allow(dead_code)]
pub struct AccountManager {
    home_dir: PathBuf,
    orbit_dir: PathBuf,
    accounts_file: PathBuf,
    accounts_dir: PathBuf,
    gemini_dir: PathBuf,
}

impl AccountManager {
    pub fn new() -> Self {
        let home_dir = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
        let orbit_dir = home_dir.join(".antigravity_orbit");
        let accounts_file = orbit_dir.join("accounts.json");
        let accounts_dir = orbit_dir.join("accounts");
        let gemini_dir = home_dir.join(".gemini");

        let _ = fs::create_dir_all(&orbit_dir);
        let _ = fs::create_dir_all(&accounts_dir);

        let mgr = Self {
            home_dir,
            orbit_dir,
            accounts_file,
            accounts_dir,
            gemini_dir,
        };
        mgr.ensure_accounts_file_exists();
        mgr
    }

    pub fn get_or_create_accounts_file(&self) -> AccountsFile {
        if self.accounts_file.exists() {
            if let Ok(content) = fs::read_to_string(&self.accounts_file) {
                if let Ok(parsed) = serde_json::from_str::<AccountsFile>(&content) {
                    return parsed;
                }
            }
        }
        let empty = AccountsFile {
            version: Some("2.0".to_string()),
            accounts: vec![],
            current_account_id: None,
            current_target_ide: Some("antigravity".to_string()),
            current_classic_account_id: None,
            current_ide_account_id: None,
            current_agy_account_id: None,
        };
        let _ = self.save_accounts_file(&empty);
        empty
    }

    pub fn save_accounts_file(&self, model: &AccountsFile) -> bool {
        if let Ok(json) = serde_json::to_string_pretty(model) {
            fs::write(&self.accounts_file, json).is_ok()
        } else {
            false
        }
    }

    fn ensure_accounts_file_exists(&self) {
        if !self.accounts_file.exists() {
            self.get_or_create_accounts_file();
        }
    }

    pub fn import_from_ide(&self) -> (bool, String) {
        let google_accs_path = self.gemini_dir.join("google_accounts.json");
        let oauth_creds_path = self.gemini_dir.join("oauth_creds.json");

        if !google_accs_path.exists() || !oauth_creds_path.exists() {
            return (false, "Không tìm thấy thông tin đăng nhập trong ~/.gemini.".to_string());
        }

        let accs_json: serde_json::Value = match fs::read_to_string(&google_accs_path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
        {
            Some(v) => v,
            None => return (false, "Không đọc được google_accounts.json.".to_string()),
        };

        let active_email = match accs_json.get("active").and_then(|v| v.as_str()) {
            Some(e) if !e.is_empty() => e.to_string(),
            _ => return (false, "Không đọc được email đang đăng nhập trong Antigravity.".to_string()),
        };

        let creds_json: serde_json::Value = match fs::read_to_string(&oauth_creds_path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
        {
            Some(v) => v,
            None => return (false, "Không đọc được token đăng nhập từ oauth_creds.json.".to_string()),
        };

        let mut accounts_file_model = self.get_or_create_accounts_file();
        if let Some(existing) = accounts_file_model.accounts.iter().find(|a| a.email.eq_ignore_ascii_case(&active_email)) {
            return (false, format!("Tài khoản [{}] đã tồn tại trong danh sách xoay vòng (ID: {}).", active_email, existing.id));
        }

        let new_id = Uuid::new_v4().to_string().to_lowercase();
        let name = active_email.split('@').next().unwrap_or(&active_email).to_string();
        let now = Utc::now().timestamp();
        let raw_expiry = creds_json.get("expiry_date").and_then(|v| v.as_i64()).unwrap_or(now + 3600);
        let expiry_sec = if raw_expiry > 100_000_000_000 { raw_expiry / 1000 } else { raw_expiry };

        let token_obj = AccountToken {
            access_token: creds_json.get("access_token").and_then(|v| v.as_str()).map(|s| s.to_string()),
            refresh_token: creds_json.get("refresh_token").and_then(|v| v.as_str()).map(|s| s.to_string()),
            expires_in: Some(3599),
            expiry_timestamp: Some(expiry_sec),
            token_type: Some("Bearer".to_string()),
            email: Some(active_email.clone()),
            id_token: creds_json.get("id_token").and_then(|v| v.as_str()).map(|s| s.to_string()),
        };

        let account_detail = AccountDetailFile {
            id: new_id.clone(),
            email: active_email.clone(),
            name: Some(name.clone()),
            token: Some(token_obj),
            model: None,
            active_model: None,
            quota: Some(AccountDetailQuota {
                subscription_tier: Some("Free".to_string()),
                tier_id: None,
                is_forbidden: Some(false),
                models: vec![],
                last_updated: Some(Utc::now().to_rfc3339()),
            }),
            disabled: Some(false),
            proxy_disabled: Some(false),
            created_at: Some(now),
            last_used: Some(now),
        };

        let detail_path = self.accounts_dir.join(format!("{}.json", new_id));
        if let Ok(json) = serde_json::to_string_pretty(&account_detail) {
            let _ = fs::write(detail_path, json);
        }

        let managed = ManagedAccount {
            id: new_id.clone(),
            email: active_email.clone(),
            name: Some(name),
            disabled: Some(false),
            proxy_disabled: Some(false),
            created_at: Some(now),
            last_used: Some(now),
            model: None,
            active_model: None,
        };

        accounts_file_model.accounts.push(managed);
        let active_id = accounts_file_model.current_account_id.clone().unwrap_or_else(|| new_id.clone());
        accounts_file_model.current_account_id = Some(active_id.clone());
        accounts_file_model.current_ide_account_id = Some(accounts_file_model.current_ide_account_id.clone().unwrap_or_else(|| new_id.clone()));
        accounts_file_model.current_classic_account_id = Some(accounts_file_model.current_classic_account_id.clone().unwrap_or_else(|| new_id.clone()));
        accounts_file_model.current_agy_account_id = Some(accounts_file_model.current_agy_account_id.clone().unwrap_or(new_id));

        if self.save_accounts_file(&accounts_file_model) {
            (true, format!("Đã import thành công tài khoản [{}] từ Antigravity IDE!", active_email))
        } else {
            (false, "Lỗi ghi accounts.json.".to_string())
        }
    }

    pub fn add_account_from_oauth(&self, token: OAuthTokenData, user: OAuthUserInfo) -> (bool, String) {
        let mut accounts_file_model = self.get_or_create_accounts_file();
        let email = user.email.trim().to_string();

        if let Some(existing) = accounts_file_model.accounts.iter().find(|a| a.email.eq_ignore_ascii_case(&email)) {
            return (false, format!("Tài khoản [{}] đã tồn tại trong danh sách (ID: {}).", email, existing.id));
        }

        let new_id = Uuid::new_v4().to_string().to_lowercase();
        let name = user.name.unwrap_or_else(|| email.split('@').next().unwrap_or(&email).to_string());
        let now = Utc::now().timestamp();

        let token_obj = AccountToken {
            access_token: Some(token.access_token),
            refresh_token: token.refresh_token,
            expires_in: token.expires_in.or(Some(3599)),
            expiry_timestamp: Some(now + token.expires_in.unwrap_or(3600)),
            token_type: Some(token.token_type.unwrap_or_else(|| "Bearer".to_string())),
            email: Some(email.clone()),
            id_token: token.id_token,
        };

        let account_detail = AccountDetailFile {
            id: new_id.clone(),
            email: email.clone(),
            name: Some(name.clone()),
            token: Some(token_obj),
            model: None,
            active_model: None,
            quota: Some(AccountDetailQuota {
                subscription_tier: Some("Free".to_string()),
                tier_id: None,
                is_forbidden: Some(false),
                models: vec![],
                last_updated: Some(Utc::now().to_rfc3339()),
            }),
            disabled: Some(false),
            proxy_disabled: Some(false),
            created_at: Some(now),
            last_used: Some(now),
        };

        let detail_path = self.accounts_dir.join(format!("{}.json", new_id));
        if let Ok(json) = serde_json::to_string_pretty(&account_detail) {
            let _ = fs::write(detail_path, json);
        }

        let managed = ManagedAccount {
            id: new_id.clone(),
            email: email.clone(),
            name: Some(name),
            disabled: Some(false),
            proxy_disabled: Some(false),
            created_at: Some(now),
            last_used: Some(now),
            model: None,
            active_model: None,
        };

        accounts_file_model.accounts.push(managed);
        if accounts_file_model.current_account_id.is_none() {
            accounts_file_model.current_account_id = Some(new_id.clone());
            accounts_file_model.current_ide_account_id = Some(new_id.clone());
            accounts_file_model.current_classic_account_id = Some(new_id.clone());
            accounts_file_model.current_agy_account_id = Some(new_id);
        }

        if self.save_accounts_file(&accounts_file_model) {
            (true, format!("Đã thêm tài khoản [{}] thành công!", email))
        } else {
            (false, "Lỗi ghi accounts.json.".to_string())
        }
    }

    pub fn delete_account(&self, id: &str) -> (bool, String) {
        let mut accounts_file_model = self.get_or_create_accounts_file();
        let active_id = accounts_file_model.current_ide_account_id.as_deref()
            .or_else(|| accounts_file_model.current_account_id.as_deref())
            .unwrap_or("");

        if id == active_id {
            return (false, "Không thể xóa tài khoản đang kích hoạt. Vui lòng chuyển sang tài khoản khác trước khi xóa.".to_string());
        }

        if let Some(pos) = accounts_file_model.accounts.iter().position(|a| a.id == id) {
            let deleted_email = accounts_file_model.accounts[pos].email.clone();
            accounts_file_model.accounts.remove(pos);

            let detail_path = self.accounts_dir.join(format!("{}.json", id));
            let _ = fs::remove_file(detail_path);

            if self.save_accounts_file(&accounts_file_model) {
                (true, format!("Đã xóa tài khoản [{}] thành công.", deleted_email))
            } else {
                (false, "Lỗi cập nhật accounts.json.".to_string())
            }
        } else {
            (false, "Không tìm thấy tài khoản cần xóa.".to_string())
        }
    }
}
