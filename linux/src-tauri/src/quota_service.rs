use std::fs;
use std::path::PathBuf;
use std::time::Duration;
use chrono::Utc;
use reqwest::Client;
use crate::models::{
    AccountDetailFile, AccountStatus, AccountsFile, LoadCodeAssistResponse,
    LocalApiAccountsResponse, ManagedAccount, QuotaSummaryResponse,
};
use crate::oauth_server::OAuthServer;

pub struct QuotaService {
    home_dir: PathBuf,
    orbit_dir: PathBuf,
    accounts_file: PathBuf,
    client: Client,
}

impl QuotaService {
    const USER_AGENT: &'static str = "antigravity/hub/2.23.1 (Windows NT 10.0; Win64; x64)";

    pub fn new() -> Self {
        let home_dir = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
        let orbit_dir = home_dir.join(".antigravity_orbit");
        let accounts_file = orbit_dir.join("accounts.json");
        let client = Client::builder()
            .timeout(Duration::from_secs(8))
            .build()
            .unwrap_or_default();

        Self {
            home_dir,
            orbit_dir,
            accounts_file,
            client,
        }
    }

    pub fn get_account_detail_path(&self, account_id: &str) -> PathBuf {
        self.orbit_dir.join("accounts").join(format!("{}.json", account_id))
    }

    pub fn get_api_key(&self) -> String {
        let cfg_path = self.orbit_dir.join("gui_config.json");
        if let Ok(content) = fs::read_to_string(&cfg_path) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(key) = v.get("proxy").and_then(|p| p.get("api_key")).and_then(|k| k.as_str()) {
                    return key.to_string();
                }
            }
        }
        "sk-2d9c1aad60db498ebdb8818970541d02".to_string()
    }

    pub fn load_accounts_file(&self) -> Option<AccountsFile> {
        let content = fs::read_to_string(&self.accounts_file).ok()?;
        serde_json::from_str(&content).ok()
    }

    pub async fn fetch_all_quotas(&self) -> Vec<AccountStatus> {
        let accounts_file = match self.load_accounts_file() {
            Some(f) => f,
            None => return vec![],
        };

        let active_id = accounts_file
            .current_classic_account_id
            .as_ref()
            .or_else(|| accounts_file.current_ide_account_id.as_ref())
            .or_else(|| accounts_file.current_account_id.as_ref())
            .cloned()
            .unwrap_or_default();

        // 1. Try local proxy
        let local_res = self.fetch_from_local_api(&accounts_file, &active_id).await;
        if !local_res.is_empty() {
            return local_res;
        }

        // 2. Fallback to Google API
        self.fetch_from_google_api(&accounts_file, &active_id).await
    }

    async fn fetch_from_local_api(&self, _accounts_file: &AccountsFile, active_id: &str) -> Vec<AccountStatus> {
        let api_key = self.get_api_key();
        let res = self.client
            .get("http://127.0.0.1:8045/api/accounts")
            .header("Authorization", format!("Bearer {}", api_key))
            .timeout(Duration::from_secs(3))
            .send()
            .await;

        let accounts = match res {
            Ok(r) if r.status().is_success() => {
                r.json::<LocalApiAccountsResponse>().await.ok().and_then(|resp| resp.accounts)
            }
            _ => None,
        };

        let accounts = match accounts {
            Some(a) if !a.is_empty() => a,
            _ => return vec![],
        };

        let mut results = Vec::new();
        for acc in accounts {
            let mut min_percent = 100;
            let mut gemini_5h = None;
            let mut gemini_weekly = None;
            let mut gemini_reset = None;

            if let Some(quota) = &acc.quota {
                if let Some(models) = &quota.models {
                    for m in models {
                        min_percent = min_percent.min(m.percentage);
                        let name_lower = m.name.to_lowercase();
                        if name_lower.contains("5h") {
                            gemini_5h = Some(m.percentage);
                        } else if name_lower.contains("week") {
                            gemini_weekly = Some(m.percentage);
                            gemini_reset = m.reset_time.clone();
                        }
                    }
                }
            }

            let is_active = acc.id == active_id || acc.is_current.unwrap_or(false);
            let model_name = self.resolve_model_for_account(&acc.id, is_active);
            let tier = acc.quota.as_ref().and_then(|q| q.subscription_tier.clone()).unwrap_or_else(|| "Google AI Pro".to_string());

            results.push(AccountStatus {
                id: acc.id.clone(),
                email: acc.email.clone(),
                name: acc.name.unwrap_or_else(|| acc.email.clone()),
                is_current: is_active,
                remaining_percentage: gemini_5h.unwrap_or(min_percent),
                gemini_5h_percentage: gemini_5h,
                gemini_weekly_percentage: gemini_weekly,
                gemini_reset_time: gemini_reset,
                other_5h_percentage: None,
                other_weekly_percentage: None,
                last_updated: Some(Utc::now().to_rfc3339()),
                active_model: model_name,
                subscription_tier: Some(tier),
                tier_id: None,
            });
        }
        results
    }

    async fn fetch_from_google_api(&self, accounts_file: &AccountsFile, active_id: &str) -> Vec<AccountStatus> {
        let mut results = Vec::new();
        for acc in &accounts_file.accounts {
            if acc.disabled.unwrap_or(false) {
                continue;
            }
            let status = self.fetch_single_account_quota(acc, active_id).await;
            results.push(status);
        }
        results
    }

    async fn fetch_single_account_quota(&self, acc: &ManagedAccount, active_id: &str) -> AccountStatus {
        let is_active = acc.id == active_id;
        let detail_path = self.get_account_detail_path(&acc.id);
        let model_name = self.resolve_model_for_account(&acc.id, is_active);
        let cached_tier = self.get_cached_tier_for_account(&acc.id);

        let detail: Option<AccountDetailFile> = fs::read_to_string(&detail_path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok());

        let token = match detail.and_then(|d| d.token) {
            Some(t) => t,
            None => {
                return AccountStatus {
                    id: acc.id.clone(),
                    email: acc.email.clone(),
                    name: acc.name.clone().unwrap_or_else(|| acc.email.clone()),
                    is_current: is_active,
                    remaining_percentage: -1,
                    gemini_5h_percentage: None,
                    gemini_weekly_percentage: None,
                    gemini_reset_time: None,
                    other_5h_percentage: None,
                    other_weekly_percentage: None,
                    last_updated: None,
                    active_model: model_name,
                    subscription_tier: cached_tier,
                    tier_id: None,
                };
            }
        };

        let now = Utc::now().timestamp();
        let expiry = token.expiry_timestamp.unwrap_or(0);
        let current_access = token.access_token.unwrap_or_default();
        let refresh_token = token.refresh_token.unwrap_or_default();

        let should_refresh = (expiry <= now + 120) || current_access.is_empty();

        let effective_token = if should_refresh && !refresh_token.is_empty() {
            match self.refresh_google_token(&acc.id, &refresh_token, is_active).await {
                Some(t) => t,
                None => current_access,
            }
        } else {
            current_access
        };

        self.execute_quota_query(acc, active_id, &effective_token, &refresh_token).await
    }

    async fn execute_quota_query(
        &self,
        acc: &ManagedAccount,
        active_id: &str,
        access_token: &str,
        _refresh_token: &str,
    ) -> AccountStatus {
        let is_active = acc.id == active_id;
        let model_name = self.resolve_model_for_account(&acc.id, is_active);

        // 1. Quota Summary
        let quota_res = self.client
            .post("https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .header("User-Agent", Self::USER_AGENT)
            .body("{}")
            .send()
            .await;

        let summary: Option<QuotaSummaryResponse> = match quota_res {
            Ok(r) if r.status().is_success() => r.json().await.ok(),
            _ => None,
        };

        // 2. Code Assist Tier
        let tier_res = self.client
            .post("https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .header("User-Agent", Self::USER_AGENT)
            .body("{}")
            .send()
            .await;

        let tier_resp: Option<LoadCodeAssistResponse> = match tier_res {
            Ok(r) if r.status().is_success() => r.json().await.ok(),
            _ => None,
        };

        let (tier_name, tier_id) = self.resolve_tier(tier_resp.as_ref(), &acc.id);
        self.update_account_tier_on_disk(&acc.id, &tier_name, tier_id.as_deref());

        let mut status = AccountStatus {
            id: acc.id.clone(),
            email: acc.email.clone(),
            name: acc.name.clone().unwrap_or_else(|| acc.email.clone()),
            is_current: is_active,
            remaining_percentage: if summary.is_some() { 100 } else { -1 },
            gemini_5h_percentage: None,
            gemini_weekly_percentage: None,
            gemini_reset_time: None,
            other_5h_percentage: None,
            other_weekly_percentage: None,
            last_updated: Some(Utc::now().to_rfc3339()),
            active_model: model_name,
            subscription_tier: Some(tier_name),
            tier_id,
        };

        if let Some(s) = summary {
            if let Some(groups) = s.groups {
                let mut min_fraction: f64 = 1.0;
                for g in groups {
                    let is_gemini = g.displayName.as_deref().unwrap_or("").to_lowercase().contains("gemini");
                    if let Some(buckets) = g.buckets {
                        for b in buckets {
                            if let Some(frac) = b.remainingFraction {
                                let pct = (frac * 100.0).round() as i32;
                                let window = b.window.as_deref().or(b.bucketId.as_deref()).unwrap_or("").to_lowercase();
                                if is_gemini {
                                    min_fraction = min_fraction.min(frac);
                                    if window.contains("5h") {
                                        status.gemini_5h_percentage = Some(pct);
                                    } else if window.contains("week") {
                                        status.gemini_weekly_percentage = Some(pct);
                                        status.gemini_reset_time = b.resetTime;
                                    }
                                } else {
                                    if window.contains("5h") {
                                        status.other_5h_percentage = Some(pct);
                                    } else if window.contains("week") {
                                        status.other_weekly_percentage = Some(pct);
                                    }
                                }
                            }
                        }
                    }
                }

                if let Some(g5h) = status.gemini_5h_percentage {
                    status.remaining_percentage = g5h;
                } else {
                    status.remaining_percentage = (min_fraction * 100.0).round() as i32;
                }
            }
        }

        status
    }

    pub async fn refresh_google_token(&self, account_id: &str, refresh_token: &str, is_active: bool) -> Option<String> {
        let params = [
            ("client_id", OAuthServer::client_id()),
            ("client_secret", OAuthServer::client_secret()),
            ("refresh_token", refresh_token.to_string()),
            ("grant_type", "refresh_token".to_string()),
        ];

        let res = self.client
            .post("https://oauth2.googleapis.com/token")
            .form(&params)
            .send()
            .await
            .ok()?;

        if !res.status().is_success() {
            return None;
        }

        let json: serde_json::Value = res.json().await.ok()?;
        let new_access = json.get("access_token")?.as_str()?.to_string();
        let expires_in = json.get("expires_in").and_then(|v| v.as_i64()).unwrap_or(3600);
        let now = Utc::now().timestamp();

        // Update detail file on disk
        let detail_path = self.get_account_detail_path(account_id);
        if let Ok(content) = fs::read_to_string(&detail_path) {
            if let Ok(mut val) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(token_obj) = val.get_mut("token").and_then(|t| t.as_object_mut()) {
                    token_obj.insert("access_token".to_string(), serde_json::Value::String(new_access.clone()));
                    token_obj.insert("expires_in".to_string(), serde_json::Value::Number(expires_in.into()));
                    token_obj.insert("expiry_timestamp".to_string(), serde_json::Value::Number((now + expires_in).into()));
                }
                if let Ok(serialized) = serde_json::to_string_pretty(&val) {
                    let _ = fs::write(detail_path, serialized);
                }
            }
        }

        // If this is active account, also update ~/.gemini/oauth_creds.json
        if is_active {
            let oauth_creds_path = self.home_dir.join(".gemini").join("oauth_creds.json");
            if let Ok(content) = fs::read_to_string(&oauth_creds_path) {
                if let Ok(mut val) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(obj) = val.as_object_mut() {
                        obj.insert("access_token".to_string(), serde_json::Value::String(new_access.clone()));
                        obj.insert("expiry_date".to_string(), serde_json::Value::Number(((now + expires_in) * 1000).into()));
                    }
                    if let Ok(serialized) = serde_json::to_string_pretty(&val) {
                        let _ = fs::write(oauth_creds_path, serialized);
                    }
                }
            }
        }

        Some(new_access)
    }

    pub fn get_raw_antigravity_model_id(&self) -> String {
        let state_path = self.home_dir.join(".gemini").join("antigravity").join("antigravity_state.pbtxt");
        if let Ok(content) = fs::read_to_string(state_path) {
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with("last_selected_agent_model:") {
                    let parts: Vec<&str> = trimmed.split(':').collect();
                    if parts.len() > 1 {
                        return parts[1].trim().replace('"', "");
                    }
                }
            }
        }
        String::new()
    }

    pub fn format_model_identifier(&self, raw: &str) -> String {
        let key = raw.trim();
        match key {
            "MODEL_PLACEHOLDER_M318" | "gemini-3.8-flash-high" => "Gemini 3.8 Flash (High)".to_string(),
            "MODEL_PLACEHOLDER_M319" | "gemini-3.8-flash-medium" => "Gemini 3.8 Flash (Medium)".to_string(),
            "MODEL_PLACEHOLDER_M320" | "gemini-3.8-flash-low" => "Gemini 3.8 Flash (Low)".to_string(),
            "MODEL_PLACEHOLDER_M322" | "gemini-3.8-flash-tiered" => "Gemini 3.8 Flash (Tiered)".to_string(),
            "MODEL_PLACEHOLDER_M26" | "claude-opus-4-6-thinking" => "Claude Opus 4.6 (Thinking)".to_string(),
            "MODEL_PLACEHOLDER_M35" | "claude-sonnet-4-6" => "Claude Sonnet 4.6 (Thinking)".to_string(),
            "MODEL_OPENAI_GPT_OSS_120B_MEDIUM" | "gpt-oss-120b-medium" => "GPT-OSS 120B (Medium)".to_string(),
            "MODEL_PLACEHOLDER_M50" | "gemini-3.1-flash-lite" => "Gemini 3.1 Flash Lite".to_string(),
            "MODEL_PLACEHOLDER_M198" | "gemini-3.5-flash-lite" => "Gemini 3.5 Flash Lite".to_string(),
            "MODEL_PLACEHOLDER_M21" | "gemini-3.1-flash-image" => "Gemini 3.1 Flash Image".to_string(),
            "gemini-3-pro-high" => "Gemini 3 Pro (High)".to_string(),
            "claude-opus-5-5-high" => "Claude Opus 5.5 (High)".to_string(),
            "claude-opus-5-5-medium" => "Claude Opus 5.5 (Medium)".to_string(),
            _ => {
                if key.is_empty() {
                    "Gemini 3.8 Flash (High)".to_string()
                } else {
                    key.to_string()
                }
            }
        }
    }

    pub fn resolve_model_for_account(&self, account_id: &str, is_active: bool) -> Option<String> {
        if is_active {
            let raw_id = self.get_raw_antigravity_model_id();
            if !raw_id.is_empty() {
                return Some(self.format_model_identifier(&raw_id));
            }
            return Some("Gemini 3.8 Flash (High)".to_string());
        }

        let detail_path = self.get_account_detail_path(account_id);
        if let Ok(content) = fs::read_to_string(detail_path) {
            if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(m) = val.get("active_model").or_else(|| val.get("model")).and_then(|v| v.as_str()) {
                    if !m.is_empty() {
                        return Some(self.format_model_identifier(m));
                    }
                }
            }
        }
        None
    }

    fn get_cached_tier_for_account(&self, account_id: &str) -> Option<String> {
        let detail_path = self.get_account_detail_path(account_id);
        let content = fs::read_to_string(detail_path).ok()?;
        let val: serde_json::Value = serde_json::from_str(&content).ok()?;
        let quota = val.get("quota")?;
        quota.get("subscription_tier").and_then(|v| v.as_str()).map(|s| s.to_string())
    }

    fn resolve_tier(&self, resp: Option<&LoadCodeAssistResponse>, account_id: &str) -> (String, Option<String>) {
        if let Some(r) = resp {
            if let Some(paid) = &r.paidTier {
                if let Some(id) = &paid.id {
                    let id_l = id.to_lowercase();
                    if id_l.contains("ultra") {
                        return ("Google AI Ultra".to_string(), Some(id.clone()));
                    } else if id_l.contains("pro") {
                        return ("Google AI Pro".to_string(), Some(id.clone()));
                    } else if id_l.contains("standard") || id_l.contains("enterprise") {
                        return ("Google Cloud / Enterprise".to_string(), Some(id.clone()));
                    } else {
                        return (paid.name.clone().unwrap_or_else(|| id.clone()), Some(id.clone()));
                    }
                }
            }
            if let Some(curr) = &r.currentTier {
                if let Some(id) = &curr.id {
                    let id_l = id.to_lowercase();
                    if id_l.contains("ultra") {
                        return ("Google AI Ultra".to_string(), Some(id.clone()));
                    } else if id_l.contains("pro") {
                        return ("Google AI Pro".to_string(), Some(id.clone()));
                    } else if id_l.contains("free") {
                        return ("Free".to_string(), Some(id.clone()));
                    }
                }
            }
        }
        if let Some(cached) = self.get_cached_tier_for_account(account_id) {
            return (cached, None);
        }
        ("Free".to_string(), None)
    }

    fn update_account_tier_on_disk(&self, account_id: &str, tier_name: &str, tier_id: Option<&str>) {
        let detail_path = self.get_account_detail_path(account_id);
        if let Ok(content) = fs::read_to_string(&detail_path) {
            if let Ok(mut val) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(quota) = val.get_mut("quota").and_then(|q| q.as_object_mut()) {
                    quota.insert("subscription_tier".to_string(), serde_json::Value::String(tier_name.to_string()));
                    if let Some(tid) = tier_id {
                        quota.insert("tier_id".to_string(), serde_json::Value::String(tid.to_string()));
                    }
                }
                if let Ok(serialized) = serde_json::to_string_pretty(&val) {
                    let _ = fs::write(detail_path, serialized);
                }
            }
        }
    }
}
