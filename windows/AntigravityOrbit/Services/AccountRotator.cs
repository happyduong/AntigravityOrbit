using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using AntigravityOrbit.Models;

namespace AntigravityOrbit.Services
{
    public class AccountRotator
    {
        private static AccountRotator? _instance;
        public static AccountRotator Instance => _instance ??= new AccountRotator();

        private readonly string _homeDir;
        private readonly string _orbitDir;

        private AccountRotator()
        {
            _homeDir = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            _orbitDir = Path.Combine(_homeDir, ".antigravity_orbit");
        }

        public async Task<AccountStatus?> RotateToNextAsync(List<AccountStatus> currentStatuses, string reason)
        {
            var file = AccountManager.Instance.GetOrCreateAccountsFile();
            var activeAccounts = file.Accounts.Where(a => a.Disabled != true).ToList();
            if (activeAccounts.Count <= 1) return null;

            var activeId = file.CurrentClassicAccountId ?? file.CurrentIdeAccountId ?? file.CurrentAccountId ?? "";
            int currentIndex = activeAccounts.FindIndex(a => a.Id == activeId);
            if (currentIndex < 0) currentIndex = 0;

            var currentAccount = activeAccounts[currentIndex];
            ManagedAccount? bestCandidate = null;
            AccountStatus? bestStatus = null;
            int threshold = ConfigManager.Instance.Config.ThresholdPercentage;

            // Round-robin scan
            for (int offset = 1; offset < activeAccounts.Count; offset++)
            {
                int nextIndex = (currentIndex + offset) % activeAccounts.Count;
                var candidate = activeAccounts[nextIndex];
                var status = currentStatuses.FirstOrDefault(s => s.Id == candidate.Id);
                int pct = status?.RemainingPercentage ?? 100;

                if (pct > threshold)
                {
                    bestCandidate = candidate;
                    bestStatus = status;
                    break;
                }
            }

            // Fallback to highest quota
            if (bestCandidate == null)
            {
                var sorted = activeAccounts.Where(a => a.Id != activeId)
                    .OrderByDescending(a => currentStatuses.FirstOrDefault(s => s.Id == a.Id)?.RemainingPercentage ?? 0)
                    .ToList();
                bestCandidate = sorted.FirstOrDefault();
                if (bestCandidate != null)
                {
                    bestStatus = currentStatuses.FirstOrDefault(s => s.Id == bestCandidate.Id);
                }
            }

            if (bestCandidate == null) return null;

            bool switched = SwitchToAccount(bestCandidate.Id);
            if (switched)
            {
                var cfg = ConfigManager.Instance.Config;
                int newPct = bestStatus?.RemainingPercentage ?? 100;
                var body = $"Tài khoản [{currentAccount.Email}] cạn quota ({reason}). Đã tự động chuyển sang [{bestCandidate.Email}] (Quota: {newPct}%).";
                NotificationManager.SendNotification("Antigravity Orbit", "Đã tự động xoay vòng tài khoản", body, cfg.SoundEnabled);
                return bestStatus;
            }

            return null;
        }

        public bool SwitchToAccount(string accountId)
        {
            var accountMgr = AccountManager.Instance;
            var accountsFile = accountMgr.GetOrCreateAccountsFile();
            var target = accountsFile.Accounts.FirstOrDefault(a => a.Id == accountId);
            if (target == null) return false;

            var detailPath = Path.Combine(_orbitDir, "accounts", $"{accountId}.json");
            if (!File.Exists(detailPath)) return false;

            AccountDetailFile? detail = null;
            try
            {
                detail = JsonSerializer.Deserialize<AccountDetailFile>(File.ReadAllText(detailPath));
            }
            catch { return false; }

            var token = detail?.Token;
            if (token == null) return false;

            var accessToken = token.AccessToken ?? "";
            var refreshToken = token.RefreshToken ?? "";
            var tokenType = token.TokenType ?? "Bearer";
            long expiry = token.ExpiryTimestamp ?? (DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 3600);
            var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

            // 1. Update accounts.json
            accountsFile.CurrentAccountId = accountId;
            accountsFile.CurrentIdeAccountId = accountId;
            accountsFile.CurrentClassicAccountId = accountId;
            accountsFile.CurrentAgyAccountId = accountId;

            foreach (var acc in accountsFile.Accounts)
            {
                if (acc.Id == accountId) acc.LastUsed = now;
            }
            accountMgr.SaveAccountsFile(accountsFile);

            // 2. Update detail JSON last_used
            detail.LastUsed = now;
            File.WriteAllText(detailPath, JsonSerializer.Serialize(detail, new JsonSerializerOptions { WriteIndented = true }));

            // 3. Update %USERPROFILE%\.gemini credentials
            var geminiDir = Path.Combine(_homeDir, ".gemini");
            Directory.CreateDirectory(geminiDir);

            var googleAccountsPath = Path.Combine(geminiDir, "google_accounts.json");
            var gaPayload = new { active = target.Email, old = Array.Empty<string>() };
            File.WriteAllText(googleAccountsPath, JsonSerializer.Serialize(gaPayload, new JsonSerializerOptions { WriteIndented = true }));

            var oauthCredsPath = Path.Combine(geminiDir, "oauth_creds.json");
            long expiryMs = expiry < 10_000_000_000 ? expiry * 1000 : expiry;
            var credsPayload = new
            {
                access_token = accessToken,
                refresh_token = refreshToken,
                token_type = tokenType,
                expiry_date = expiryMs,
                id_token = token.IdToken ?? "",
                scope = "openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/cde"
            };
            File.WriteAllText(oauthCredsPath, JsonSerializer.Serialize(credsPayload, new JsonSerializerOptions { WriteIndented = true }));

            // 4. Update Windows Credential Manager (wincred) for agy CLI & Go
            CredentialManager.SyncCredentials(target.Email, accessToken, refreshToken, tokenType, expiry);

            System.Diagnostics.Debug.WriteLine($"[AccountRotator] Switched to [{target.Email}] successfully.");
            return true;
        }
    }
}

