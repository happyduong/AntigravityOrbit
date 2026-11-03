using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using AntigravityOrbit.Models;

namespace AntigravityOrbit.Services
{
    public class QuotaService
    {
        private static QuotaService? _instance;
        public static QuotaService Instance => _instance ??= new QuotaService();

        private readonly HttpClient _client;
        private readonly string _homeDir;
        private readonly string _orbitDir;
        private readonly string _accountsFile;
        private const string UserAgent = "antigravity/hub/2.23.1 (Windows NT 10.0; Win64; x64)";

        private QuotaService()
        {
            _client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
            _homeDir = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            _orbitDir = Path.Combine(_homeDir, ".antigravity_orbit");
            _accountsFile = Path.Combine(_orbitDir, "accounts.json");
        }

        public string GetApiKey()
        {
            var configPath = Path.Combine(_orbitDir, "gui_config.json");
            if (File.Exists(configPath))
            {
                try
                {
                    var doc = JsonDocument.Parse(File.ReadAllText(configPath));
                    if (doc.RootElement.TryGetProperty("proxy", out var p) && p.TryGetProperty("api_key", out var k))
                    {
                        var key = k.GetString();
                        if (!string.IsNullOrEmpty(key)) return key;
                    }
                }
                catch { }
            }
            return "sk-2d9c1aad60db498ebdb8818970541d02";
        }

        public async Task<List<AccountStatus>> FetchAllQuotasAsync()
        {
            var accountsFile = AccountManager.Instance.GetOrCreateAccountsFile();
            var activeId = accountsFile.CurrentClassicAccountId ?? accountsFile.CurrentIdeAccountId ?? accountsFile.CurrentAccountId ?? "";

            // 1. Try local proxy
            var localStatuses = await FetchFromLocalApiAsync(accountsFile, activeId);
            if (localStatuses.Count > 0) return localStatuses;

            // 2. Fallback to Google API
            return await FetchFromGoogleApiAsync(accountsFile, activeId);
        }

        private async Task<List<AccountStatus>> FetchFromLocalApiAsync(AccountsFile file, string activeId)
        {
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Get, "http://127.0.0.1:8045/api/accounts");
                req.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", GetApiKey());
                using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(3));

                var res = await _client.SendAsync(req, cts.Token);
                if (!res.IsSuccessStatusCode) return new List<AccountStatus>();

                var json = await res.Content.ReadAsStringAsync();
                var resp = JsonSerializer.Deserialize<LocalApiAccountsResponse>(json);
                if (resp?.Accounts == null || resp.Accounts.Count == 0) return new List<AccountStatus>();

                var list = new List<AccountStatus>();
                foreach (var acc in resp.Accounts)
                {
                    int minPct = 100;
                    int? gemini5h = null;
                    int? geminiWeekly = null;
                    string? geminiReset = null;

                    if (acc.Quota?.Models != null)
                    {
                        foreach (var m in acc.Quota.Models)
                        {
                            minPct = Math.Min(minPct, m.Percentage);
                            var nameLower = m.Name.ToLowerInvariant();
                            if (nameLower.Contains("5h")) gemini5h = m.Percentage;
                            else if (nameLower.Contains("week"))
                            {
                                geminiWeekly = m.Percentage;
                                geminiReset = m.ResetTime;
                            }
                        }
                    }

                    bool isActive = acc.Id == activeId || (acc.IsCurrent ?? false);
                    var modelName = ResolveModelForAccount(acc.Id, isActive);

                    list.Add(new AccountStatus
                    {
                        Id = acc.Id,
                        Email = acc.Email,
                        Name = acc.Name ?? acc.Email,
                        IsCurrent = isActive,
                        RemainingPercentage = gemini5h ?? minPct,
                        Gemini5hPercentage = gemini5h,
                        GeminiWeeklyPercentage = geminiWeekly,
                        GeminiResetTime = geminiReset,
                        ActiveModel = modelName,
                        SubscriptionTier = acc.Quota?.SubscriptionTier ?? "Google AI Pro",
                        LastUpdated = DateTime.Now
                    });
                }
                return list;
            }
            catch
            {
                return new List<AccountStatus>();
            }
        }

        private async Task<List<AccountStatus>> FetchFromGoogleApiAsync(AccountsFile file, string activeId)
        {
            var list = new List<AccountStatus>();
            foreach (var acc in file.Accounts)
            {
                if (acc.Disabled == true) continue;
                var status = await FetchSingleAccountQuotaAsync(acc, activeId);
                list.Add(status);
            }
            return list;
        }

        private async Task<AccountStatus> FetchSingleAccountQuotaAsync(ManagedAccount acc, string activeId)
        {
            bool isActive = acc.Id == activeId;
            var detailPath = Path.Combine(_orbitDir, "accounts", $"{acc.Id}.json");
            var modelName = ResolveModelForAccount(acc.Id, isActive);
            var cachedTier = GetCachedTier(acc.Id);

            if (!File.Exists(detailPath))
            {
                return new AccountStatus { Id = acc.Id, Email = acc.Email, Name = acc.Name ?? acc.Email, IsCurrent = isActive, RemainingPercentage = -1, ActiveModel = modelName, SubscriptionTier = cachedTier };
            }

            AccountDetailFile? detail = null;
            try
            {
                detail = JsonSerializer.Deserialize<AccountDetailFile>(File.ReadAllText(detailPath));
            }
            catch { }

            var token = detail?.Token;
            if (token == null)
            {
                return new AccountStatus { Id = acc.Id, Email = acc.Email, Name = acc.Name ?? acc.Email, IsCurrent = isActive, RemainingPercentage = -1, ActiveModel = modelName, SubscriptionTier = cachedTier };
            }

            var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            long expiry = token.ExpiryTimestamp ?? 0;
            var currentAccess = token.AccessToken ?? "";
            var refreshToken = token.RefreshToken ?? "";

            bool shouldRefresh = (expiry <= now + 120) || string.IsNullOrEmpty(currentAccess);
            if (shouldRefresh && !string.IsNullOrEmpty(refreshToken))
            {
                var refreshed = await RefreshGoogleTokenAsync(acc.Id, refreshToken, isActive);
                if (!string.IsNullOrEmpty(refreshed)) currentAccess = refreshed;
            }

            return await ExecuteQuotaQueryAsync(acc, activeId, currentAccess);
        }

        private async Task<AccountStatus> ExecuteQuotaQueryAsync(ManagedAccount acc, string activeId, string accessToken)
        {
            bool isActive = acc.Id == activeId;
            var modelName = ResolveModelForAccount(acc.Id, isActive);

            // 1. Quota Summary
            QuotaSummaryResponse? summary = null;
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Post, "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")
                {
                    Content = new StringContent("{}", Encoding.UTF8, "application/json")
                };
                req.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
                req.Headers.UserAgent.ParseAdd(UserAgent);

                var res = await _client.SendAsync(req);
                if (res.IsSuccessStatusCode)
                {
                    summary = JsonSerializer.Deserialize<QuotaSummaryResponse>(await res.Content.ReadAsStringAsync());
                }
            }
            catch { }

            // 2. Code Assist Tier
            string tierName = GetCachedTier(acc.Id) ?? "Free";
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Post, "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")
                {
                    Content = new StringContent("{}", Encoding.UTF8, "application/json")
                };
                req.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
                req.Headers.UserAgent.ParseAdd(UserAgent);

                var res = await _client.SendAsync(req);
                if (res.IsSuccessStatusCode)
                {
                    var resp = JsonSerializer.Deserialize<LoadCodeAssistResponse>(await res.Content.ReadAsStringAsync());
                    if (resp?.PaidTier?.Id != null)
                    {
                        var pid = resp.PaidTier.Id.ToLowerInvariant();
                        if (pid.Contains("ultra")) tierName = "Google AI Ultra";
                        else if (pid.Contains("pro")) tierName = "Google AI Pro";
                        else tierName = resp.PaidTier.Name ?? "Google Cloud / Enterprise";
                    }
                }
            }
            catch { }

            var status = new AccountStatus
            {
                Id = acc.Id,
                Email = acc.Email,
                Name = acc.Name ?? acc.Email,
                IsCurrent = isActive,
                RemainingPercentage = summary != null ? 100 : -1,
                ActiveModel = modelName,
                SubscriptionTier = tierName,
                LastUpdated = DateTime.Now
            };

            if (summary?.Groups != null)
            {
                double minFraction = 1.0;
                foreach (var g in summary.Groups)
                {
                    bool isGemini = (g.DisplayName ?? "").ToLowerInvariant().Contains("gemini");
                    if (g.Buckets != null)
                    {
                        foreach (var b in g.Buckets)
                        {
                            if (b.RemainingFraction.HasValue)
                            {
                                int pct = (int)Math.Round(b.RemainingFraction.Value * 100);
                                var window = (b.Window ?? b.BucketId ?? "").ToLowerInvariant();
                                if (isGemini)
                                {
                                    minFraction = Math.Min(minFraction, b.RemainingFraction.Value);
                                    if (window.Contains("5h")) status.Gemini5hPercentage = pct;
                                    else if (window.Contains("week"))
                                    {
                                        status.GeminiWeeklyPercentage = pct;
                                        status.GeminiResetTime = b.ResetTime;
                                    }
                                }
                            }
                        }
                    }
                }
                status.RemainingPercentage = status.Gemini5hPercentage ?? (int)Math.Round(minFraction * 100);
            }

            return status;
        }

        public async Task<string?> RefreshGoogleTokenAsync(string accountId, string refreshToken, bool isActive)
        {
            try
            {
                var dict = new Dictionary<string, string>
                {
                    ["client_id"] = OAuthServer.ClientId,
                    ["client_secret"] = OAuthServer.ClientSecret,
                    ["refresh_token"] = refreshToken,
                    ["grant_type"] = "refresh_token"
                };

                var res = await _client.PostAsync("https://oauth2.googleapis.com/token", new FormUrlEncodedContent(dict));
                if (!res.IsSuccessStatusCode) return null;

                var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
                var newAccess = doc.RootElement.GetProperty("access_token").GetString();
                long expiresIn = doc.RootElement.TryGetProperty("expires_in", out var exp) ? exp.GetInt64() : 3600;
                var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

                // Update detail file on disk
                var detailPath = Path.Combine(_orbitDir, "accounts", $"{accountId}.json");
                if (File.Exists(detailPath))
                {
                    var detail = JsonSerializer.Deserialize<AccountDetailFile>(File.ReadAllText(detailPath));
                    if (detail?.Token != null)
                    {
                        detail.Token.AccessToken = newAccess;
                        detail.Token.ExpiresIn = expiresIn;
                        detail.Token.ExpiryTimestamp = now + expiresIn;
                        File.WriteAllText(detailPath, JsonSerializer.Serialize(detail, new JsonSerializerOptions { WriteIndented = true }));
                    }
                }

                // If active, update %USERPROFILE%\.gemini\oauth_creds.json
                if (isActive)
                {
                    var credsPath = Path.Combine(_homeDir, ".gemini", "oauth_creds.json");
                    if (File.Exists(credsPath))
                    {
                        var jsonNode = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(credsPath));
                        if (jsonNode != null)
                        {
                            jsonNode["access_token"] = newAccess;
                            jsonNode["expiry_date"] = (now + expiresIn) * 1000;
                            File.WriteAllText(credsPath, jsonNode.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
                        }
                    }
                }

                return newAccess;
            }
            catch
            {
                return null;
            }
        }

        public string ResolveModelForAccount(string accountId, bool isActive)
        {
            if (isActive)
            {
                var statePath = Path.Combine(_homeDir, ".gemini", "antigravity", "antigravity_state.pbtxt");
                if (File.Exists(statePath))
                {
                    foreach (var line in File.ReadAllLines(statePath))
                    {
                        var trimmed = line.Trim();
                        if (trimmed.StartsWith("last_selected_agent_model:"))
                        {
                            var parts = trimmed.Split(':');
                            if (parts.Length > 1)
                            {
                                return FormatModel(parts[1].Trim().Replace("\"", ""));
                            }
                        }
                    }
                }
                return "Gemini 3.8 Flash (High)";
            }

            var detailPath = Path.Combine(_orbitDir, "accounts", $"{accountId}.json");
            if (File.Exists(detailPath))
            {
                try
                {
                    var detail = JsonSerializer.Deserialize<AccountDetailFile>(File.ReadAllText(detailPath));
                    var m = detail?.ActiveModel ?? detail?.Model;
                    if (!string.IsNullOrEmpty(m)) return FormatModel(m);
                }
                catch { }
            }
            return "Standby";
        }

        private string FormatModel(string raw)
        {
            return raw switch
            {
                "MODEL_PLACEHOLDER_M318" or "gemini-3.8-flash-high" => "Gemini 3.8 Flash (High)",
                "MODEL_PLACEHOLDER_M319" or "gemini-3.8-flash-medium" => "Gemini 3.8 Flash (Medium)",
                "MODEL_PLACEHOLDER_M26" or "claude-opus-4-6-thinking" => "Claude Opus 4.6 (Thinking)",
                "MODEL_PLACEHOLDER_M35" or "claude-sonnet-4-6" => "Claude Sonnet 4.6 (Thinking)",
                "MODEL_OPENAI_GPT_OSS_120B_MEDIUM" or "gpt-oss-120b-medium" => "GPT-OSS 120B (Medium)",
                _ => string.IsNullOrEmpty(raw) ? "Gemini 3.8 Flash (High)" : raw
            };
        }

        private string? GetCachedTier(string accountId)
        {
            var detailPath = Path.Combine(_orbitDir, "accounts", $"{accountId}.json");
            if (File.Exists(detailPath))
            {
                try
                {
                    var detail = JsonSerializer.Deserialize<AccountDetailFile>(File.ReadAllText(detailPath));
                    return detail?.Quota?.SubscriptionTier;
                }
                catch { }
            }
            return null;
        }
    }
}

