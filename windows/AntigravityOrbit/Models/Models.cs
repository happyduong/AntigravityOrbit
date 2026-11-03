using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace AntigravityOrbit.Models
{
    public class ManagedAccount
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("email")]
        public string Email { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("disabled")]
        public bool? Disabled { get; set; }

        [JsonPropertyName("proxy_disabled")]
        public bool? ProxyDisabled { get; set; }

        [JsonPropertyName("created_at")]
        public long? CreatedAt { get; set; }

        [JsonPropertyName("last_used")]
        public long? LastUsed { get; set; }

        [JsonPropertyName("model")]
        public string? Model { get; set; }

        [JsonPropertyName("active_model")]
        public string? ActiveModel { get; set; }
    }

    public class AccountsFile
    {
        [JsonPropertyName("version")]
        public string? Version { get; set; } = "2.0";

        [JsonPropertyName("accounts")]
        public List<ManagedAccount> Accounts { get; set; } = new();

        [JsonPropertyName("current_account_id")]
        public string? CurrentAccountId { get; set; }

        [JsonPropertyName("current_target_ide")]
        public string? CurrentTargetIde { get; set; } = "antigravity";

        [JsonPropertyName("current_classic_account_id")]
        public string? CurrentClassicAccountId { get; set; }

        [JsonPropertyName("current_ide_account_id")]
        public string? CurrentIdeAccountId { get; set; }

        [JsonPropertyName("current_agy_account_id")]
        public string? CurrentAgyAccountId { get; set; }
    }

    public class AccountToken
    {
        [JsonPropertyName("access_token")]
        public string? AccessToken { get; set; }

        [JsonPropertyName("refresh_token")]
        public string? RefreshToken { get; set; }

        [JsonPropertyName("expires_in")]
        public long? ExpiresIn { get; set; }

        [JsonPropertyName("expiry_timestamp")]
        public long? ExpiryTimestamp { get; set; }

        [JsonPropertyName("token_type")]
        public string? TokenType { get; set; } = "Bearer";

        [JsonPropertyName("email")]
        public string? Email { get; set; }

        [JsonPropertyName("id_token")]
        public string? IdToken { get; set; }
    }

    public class AccountDetailQuota
    {
        [JsonPropertyName("subscription_tier")]
        public string? SubscriptionTier { get; set; }

        [JsonPropertyName("tier_id")]
        public string? TierId { get; set; }

        [JsonPropertyName("is_forbidden")]
        public bool? IsForbidden { get; set; }

        [JsonPropertyName("last_updated")]
        public string? LastUpdated { get; set; }
    }

    public class AccountDetailFile
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("email")]
        public string Email { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("token")]
        public AccountToken? Token { get; set; }

        [JsonPropertyName("model")]
        public string? Model { get; set; }

        [JsonPropertyName("active_model")]
        public string? ActiveModel { get; set; }

        [JsonPropertyName("quota")]
        public AccountDetailQuota? Quota { get; set; }

        [JsonPropertyName("disabled")]
        public bool? Disabled { get; set; }

        [JsonPropertyName("proxy_disabled")]
        public bool? ProxyDisabled { get; set; }

        [JsonPropertyName("created_at")]
        public long? CreatedAt { get; set; }

        [JsonPropertyName("last_used")]
        public long? LastUsed { get; set; }
    }

    public class AccountStatus
    {
        public string Id { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public bool IsCurrent { get; set; }
        public int RemainingPercentage { get; set; } = 100;
        public int? Gemini5hPercentage { get; set; }
        public int? GeminiWeeklyPercentage { get; set; }
        public string? GeminiResetTime { get; set; }
        public int? Other5hPercentage { get; set; }
        public int? OtherWeeklyPercentage { get; set; }
        public DateTime? LastUpdated { get; set; }
        public string? ActiveModel { get; set; }
        public string? SubscriptionTier { get; set; }
        public string? TierId { get; set; }

        public string DisplayModelName => ActiveModel ?? "Standby";
        public string DisplayTierName => SubscriptionTier ?? "Free";
    }

    public class RotatorConfig
    {
        [JsonPropertyName("threshold_percentage")]
        public int ThresholdPercentage { get; set; } = 10;

        [JsonPropertyName("check_interval_seconds")]
        public int CheckIntervalSeconds { get; set; } = 60;

        [JsonPropertyName("auto_rotate_enabled")]
        public bool AutoRotateEnabled { get; set; } = true;

        [JsonPropertyName("notifications_enabled")]
        public bool NotificationsEnabled { get; set; } = true;

        [JsonPropertyName("sound_enabled")]
        public bool SoundEnabled { get; set; } = true;

        [JsonPropertyName("launch_at_login")]
        public bool LaunchAtLogin { get; set; } = true;

        [JsonPropertyName("language")]
        public string Language { get; set; } = "vi";
    }

    public class QuotaBucket
    {
        [JsonPropertyName("bucketId")]
        public string? BucketId { get; set; }

        [JsonPropertyName("displayName")]
        public string? DisplayName { get; set; }

        [JsonPropertyName("window")]
        public string? Window { get; set; }

        [JsonPropertyName("resetTime")]
        public string? ResetTime { get; set; }

        [JsonPropertyName("remainingFraction")]
        public double? RemainingFraction { get; set; }
    }

    public class QuotaGroup
    {
        [JsonPropertyName("displayName")]
        public string? DisplayName { get; set; }

        [JsonPropertyName("buckets")]
        public List<QuotaBucket>? Buckets { get; set; }
    }

    public class QuotaSummaryResponse
    {
        [JsonPropertyName("groups")]
        public List<QuotaGroup>? Groups { get; set; }
    }

    public class CodeAssistTier
    {
        [JsonPropertyName("id")]
        public string? Id { get; set; }

        [JsonPropertyName("name")]
        public string? Name { get; set; }
    }

    public class LoadCodeAssistResponse
    {
        [JsonPropertyName("currentTier")]
        public CodeAssistTier? CurrentTier { get; set; }

        [JsonPropertyName("paidTier")]
        public CodeAssistTier? PaidTier { get; set; }
    }

    public class LocalApiAccountModelQuota
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("percentage")]
        public int Percentage { get; set; }

        [JsonPropertyName("reset_time")]
        public string? ResetTime { get; set; }
    }

    public class LocalApiAccountQuota
    {
        [JsonPropertyName("models")]
        public List<LocalApiAccountModelQuota>? Models { get; set; }

        [JsonPropertyName("subscription_tier")]
        public string? SubscriptionTier { get; set; }
    }

    public class LocalApiAccount
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("email")]
        public string Email { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("is_current")]
        public bool? IsCurrent { get; set; }

        [JsonPropertyName("disabled")]
        public bool? Disabled { get; set; }

        [JsonPropertyName("quota")]
        public LocalApiAccountQuota? Quota { get; set; }
    }

    public class LocalApiAccountsResponse
    {
        [JsonPropertyName("accounts")]
        public List<LocalApiAccount>? Accounts { get; set; }
    }
}

