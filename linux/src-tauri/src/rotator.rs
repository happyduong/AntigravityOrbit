use std::fs;
use std::path::PathBuf;
use std::process::Command;
use chrono::Utc;
use crate::account_manager::AccountManager;
use crate::keyring::KeyringManager;
use crate::models::AccountStatus;
use crate::notifications::NotificationManager;
use crate::quota_service::QuotaService;

#[allow(dead_code)]
pub struct AccountRotator {
    home_dir: PathBuf,
    orbit_dir: PathBuf,
    accounts_file: PathBuf,
    quota_service: QuotaService,
}

impl AccountRotator {
    pub fn new() -> Self {
        let home_dir = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
        let orbit_dir = home_dir.join(".antigravity_orbit");
        let accounts_file = orbit_dir.join("accounts.json");
        let quota_service = QuotaService::new();

        Self {
            home_dir,
            orbit_dir,
            accounts_file,
            quota_service,
        }
    }

    pub fn rotate_to_next(
        &self,
        current_statuses: &[AccountStatus],
        reason: &str,
        threshold: i32,
        notifications_enabled: bool,
        sound_enabled: bool,
    ) -> Option<AccountStatus> {
        let accounts_file = self.quota_service.load_accounts_file()?;
        let active_accounts: Vec<_> = accounts_file.accounts.into_iter().filter(|a| !a.disabled.unwrap_or(false)).collect();
        if active_accounts.len() <= 1 {
            println!("[AccountRotator] Only 1 account available, cannot rotate.");
            return None;
        }

        let active_id = accounts_file
            .current_classic_account_id
            .as_ref()
            .or_else(|| accounts_file.current_ide_account_id.as_ref())
            .or_else(|| accounts_file.current_account_id.as_ref())
            .cloned()
            .unwrap_or_default();

        let current_index = active_accounts.iter().position(|a| a.id == active_id).unwrap_or(0);
        let current_acc = &active_accounts[current_index];

        // 1. Candidate in round-robin order with quota > threshold
        let mut best_candidate = None;
        let mut best_status = None;

        for offset in 1..active_accounts.len() {
            let next_idx = (current_index + offset) % active_accounts.len();
            let candidate = &active_accounts[next_idx];
            let cand_status = current_statuses.iter().find(|s| s.id == candidate.id);
            let remaining_pct = cand_status.map(|s| s.remaining_percentage).unwrap_or(100);

            if remaining_pct > threshold {
                best_candidate = Some(candidate.clone());
                best_status = cand_status.cloned();
                break;
            }
        }

        // 2. If all accounts are under threshold, pick the one with highest quota
        if best_candidate.is_none() {
            let mut other_candidates: Vec<_> = active_accounts.iter().filter(|a| a.id != active_id).collect();
            other_candidates.sort_by(|a, b| {
                let pct_a = current_statuses.iter().find(|s| s.id == a.id).map(|s| s.remaining_percentage).unwrap_or(0);
                let pct_b = current_statuses.iter().find(|s| s.id == b.id).map(|s| s.remaining_percentage).unwrap_or(0);
                pct_b.cmp(&pct_a)
            });

            if let Some(&chosen) = other_candidates.first() {
                best_candidate = Some(chosen.clone());
                best_status = current_statuses.iter().find(|s| s.id == chosen.id).cloned();
            }
        }

        let target = best_candidate?;
        if self.switch_to_account(&target.id) {
            let old_email = &current_acc.email;
            let new_email = &target.email;
            let new_pct = best_status.as_ref().map(|s| s.remaining_percentage).unwrap_or(100);

            if notifications_enabled {
                let body = format!(
                    "Tài khoản [{}] cạn quota ({}). Đã tự động chuyển sang [{}] (Quota: {}%).",
                    old_email, reason, new_email, new_pct
                );
                NotificationManager::send(
                    "Antigravity Orbit",
                    "Đã tự động xoay vòng tài khoản",
                    &body,
                    sound_enabled,
                );
            }
            best_status
        } else {
            None
        }
    }

    pub fn switch_to_account(&self, account_id: &str) -> bool {
        // Run external CLI switch if present
        let cli_success = self.run_cli_switch(account_id);

        // Always perform native direct switch to ensure 3-way sync
        let native_success = self.execute_native_switch(account_id);

        cli_success || native_success
    }

    fn execute_native_switch(&self, account_id: &str) -> bool {
        let account_mgr = AccountManager::new();
        let mut accounts_file = account_mgr.get_or_create_accounts_file();

        let target_account = match accounts_file.accounts.iter().find(|a| a.id == account_id).cloned() {
            Some(a) => a,
            None => return false,
        };

        let target_email = target_account.email.clone();
        let detail_path = self.orbit_dir.join("accounts").join(format!("{}.json", account_id));
        let detail_content = match fs::read_to_string(&detail_path) {
            Ok(c) => c,
            Err(_) => return false,
        };

        let mut detail_json: serde_json::Value = match serde_json::from_str(&detail_content) {
            Ok(v) => v,
            Err(_) => return false,
        };

        let token_obj = detail_json.get("token").and_then(|t| t.as_object()).cloned().unwrap_or_default();
        let access_token = token_obj.get("access_token").and_then(|v| v.as_str()).unwrap_or_default().to_string();
        let refresh_token = token_obj.get("refresh_token").and_then(|v| v.as_str()).unwrap_or_default().to_string();
        let id_token = token_obj.get("id_token").and_then(|v| v.as_str()).unwrap_or_default().to_string();
        let token_type = token_obj.get("token_type").and_then(|v| v.as_str()).unwrap_or("Bearer").to_string();
        let now = Utc::now().timestamp();
        let expiry = token_obj.get("expiry_timestamp").and_then(|v| v.as_i64()).unwrap_or(now + 3600);

        // 1. Update accounts.json
        accounts_file.current_ide_account_id = Some(account_id.to_string());
        accounts_file.current_agy_account_id = Some(account_id.to_string());
        accounts_file.current_account_id = Some(account_id.to_string());
        accounts_file.current_classic_account_id = Some(account_id.to_string());

        for acc in &mut accounts_file.accounts {
            if acc.id == account_id {
                acc.last_used = Some(now);
            }
        }
        let _ = account_mgr.save_accounts_file(&accounts_file);

        // 2. Update account detail file last_used
        if let Some(obj) = detail_json.as_object_mut() {
            obj.insert("last_used".to_string(), serde_json::Value::Number(now.into()));
        }
        if let Ok(json) = serde_json::to_string_pretty(&detail_json) {
            let _ = fs::write(&detail_path, json);
        }

        // 3. Update ~/.gemini credentials
        let gemini_dir = self.home_dir.join(".gemini");
        let _ = fs::create_dir_all(&gemini_dir);

        let google_accounts_path = gemini_dir.join("google_accounts.json");
        let ga_val = serde_json::json!({
            "active": target_email,
            "old": []
        });
        if let Ok(json) = serde_json::to_string_pretty(&ga_val) {
            let _ = fs::write(google_accounts_path, json);
        }

        let oauth_creds_path = gemini_dir.join("oauth_creds.json");
        let expiry_ms = if expiry < 10_000_000_000 { expiry * 1000 } else { expiry };
        let creds_val = serde_json::json!({
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": token_type,
            "expiry_date": expiry_ms,
            "id_token": id_token,
            "scope": "openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/cde"
        });
        if let Ok(json) = serde_json::to_string_pretty(&creds_val) {
            let _ = fs::write(oauth_creds_path, json);
        }

        // 4. Update Keyring for agy CLI & Go
        KeyringManager::sync_credentials(&target_email, &access_token, &refresh_token, &token_type, expiry);

        println!("[AccountRotator] Native switch to account [{}] successful.", target_email);
        true
    }

    fn run_cli_switch(&self, account_id: &str) -> bool {
        let candidates = [
            self.home_dir.join(".local/bin/antigravity-orbit"),
            PathBuf::from("/usr/local/bin/antigravity-orbit"),
            PathBuf::from("/usr/bin/antigravity-orbit"),
        ];

        let bin_path = candidates.iter().find(|p| p.is_file());
        let bin_path = match bin_path {
            Some(p) => p,
            None => return false,
        };

        let mut success = false;
        for target in &["classic", "ide", "agy"] {
            let status = Command::new(bin_path)
                .args(["switch", account_id, "--target", target])
                .status();
            if let Ok(s) = status {
                if s.success() {
                    success = true;
                }
            }
        }
        success
    }
}
