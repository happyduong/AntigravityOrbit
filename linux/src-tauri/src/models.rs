#![allow(non_snake_case, dead_code)]
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManagedAccount {
    pub id: String,
    pub email: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub disabled: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub proxy_disabled: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_used: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active_model: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AccountsFile {
    pub version: Option<String>,
    pub accounts: Vec<ManagedAccount>,
    pub current_account_id: Option<String>,
    pub current_target_ide: Option<String>,
    pub current_classic_account_id: Option<String>,
    pub current_ide_account_id: Option<String>,
    pub current_agy_account_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountToken {
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    pub expires_in: Option<i64>,
    pub expiry_timestamp: Option<i64>,
    pub token_type: Option<String>,
    pub email: Option<String>,
    pub id_token: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountDetailQuota {
    pub subscription_tier: Option<String>,
    pub tier_id: Option<String>,
    pub is_forbidden: Option<bool>,
    #[serde(default)]
    pub models: Vec<serde_json::Value>,
    pub last_updated: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountDetailFile {
    pub id: String,
    pub email: String,
    pub name: Option<String>,
    pub token: Option<AccountToken>,
    pub model: Option<String>,
    pub active_model: Option<String>,
    pub quota: Option<AccountDetailQuota>,
    pub disabled: Option<bool>,
    pub proxy_disabled: Option<bool>,
    pub created_at: Option<i64>,
    pub last_used: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuotaBucket {
    pub bucketId: Option<String>,
    pub displayName: Option<String>,
    pub window: Option<String>,
    pub resetTime: Option<String>,
    pub description: Option<String>,
    pub remainingFraction: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuotaGroup {
    pub displayName: Option<String>,
    pub description: Option<String>,
    pub buckets: Option<Vec<QuotaBucket>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuotaSummaryResponse {
    pub groups: Option<Vec<QuotaGroup>>,
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeAssistTier {
    pub id: Option<String>,
    pub name: Option<String>,
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadCodeAssistResponse {
    pub currentTier: Option<CodeAssistTier>,
    pub paidTier: Option<CodeAssistTier>,
    pub cloudaicompanionProject: Option<String>,
    pub gcpManaged: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalApiAccountModelQuota {
    pub name: String,
    pub percentage: i32,
    pub reset_time: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalApiAccountQuota {
    pub models: Option<Vec<LocalApiAccountModelQuota>>,
    pub subscription_tier: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalApiAccount {
    pub id: String,
    pub email: String,
    pub name: Option<String>,
    pub is_current: Option<bool>,
    pub disabled: Option<bool>,
    pub quota: Option<LocalApiAccountQuota>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalApiAccountsResponse {
    pub accounts: Option<Vec<LocalApiAccount>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountStatus {
    pub id: String,
    pub email: String,
    pub name: String,
    pub is_current: bool,
    pub remaining_percentage: i32,
    pub gemini_5h_percentage: Option<i32>,
    pub gemini_weekly_percentage: Option<i32>,
    pub gemini_reset_time: Option<String>,
    pub other_5h_percentage: Option<i32>,
    pub other_weekly_percentage: Option<i32>,
    pub last_updated: Option<String>,
    pub active_model: Option<String>,
    pub subscription_tier: Option<String>,
    pub tier_id: Option<String>,
}

impl AccountStatus {
    pub fn display_model_name(&self) -> &str {
        self.active_model.as_deref().unwrap_or("Standby")
    }

    pub fn display_tier_name(&self) -> &str {
        self.subscription_tier.as_deref().unwrap_or("Free")
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RotatorConfig {
    pub threshold_percentage: i32,
    pub check_interval_seconds: i32,
    pub auto_rotate_enabled: bool,
    pub notifications_enabled: bool,
    pub sound_enabled: bool,
    pub launch_at_login: bool,
    pub language: String,
}

impl Default for RotatorConfig {
    fn default() -> Self {
        Self {
            threshold_percentage: 10,
            check_interval_seconds: 60,
            auto_rotate_enabled: true,
            notifications_enabled: true,
            sound_enabled: true,
            launch_at_login: true,
            language: "vi".to_string(),
        }
    }
}
