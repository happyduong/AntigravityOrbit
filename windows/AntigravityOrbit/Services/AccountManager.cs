using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using AntigravityOrbit.Models;

namespace AntigravityOrbit.Services
{
    public class AccountManager
    {
        private static AccountManager? _instance;
        public static AccountManager Instance => _instance ??= new AccountManager();

        private readonly string _homeDir;
        private readonly string _orbitDir;
        private readonly string _accountsFile;
        private readonly string _accountsDir;
        private readonly string _geminiDir;

        private AccountManager()
        {
            _homeDir = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            _orbitDir = Path.Combine(_homeDir, ".antigravity_orbit");
            _accountsFile = Path.Combine(_orbitDir, "accounts.json");
            _accountsDir = Path.Combine(_orbitDir, "accounts");
            _geminiDir = Path.Combine(_homeDir, ".gemini");

            Directory.CreateDirectory(_orbitDir);
            Directory.CreateDirectory(_accountsDir);
        }

        public AccountsFile GetOrCreateAccountsFile()
        {
            if (File.Exists(_accountsFile))
            {
                try
                {
                    var content = File.ReadAllText(_accountsFile);
                    var file = JsonSerializer.Deserialize<AccountsFile>(content);
                    if (file != null) return file;
                }
                catch { }
            }

            var empty = new AccountsFile();
            SaveAccountsFile(empty);
            return empty;
        }

        public bool SaveAccountsFile(AccountsFile file)
        {
            try
            {
                var json = JsonSerializer.Serialize(file, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(_accountsFile, json);
                return true;
            }
            catch
            {
                return false;
            }
        }

        public (bool success, string message) ImportFromIde()
        {
            var googleAccsPath = Path.Combine(_geminiDir, "google_accounts.json");
            var oauthCredsPath = Path.Combine(_geminiDir, "oauth_creds.json");

            if (!File.Exists(googleAccsPath) || !File.Exists(oauthCredsPath))
            {
                return (false, "Không tìm thấy thông tin đăng nhập trong %USERPROFILE%\\.gemini.");
            }

            try
            {
                var accsJson = JsonDocument.Parse(File.ReadAllText(googleAccsPath)).RootElement;
                var activeEmail = accsJson.GetProperty("active").GetString();
                if (string.IsNullOrEmpty(activeEmail))
                {
                    return (false, "Không đọc được email đang đăng nhập trong Antigravity IDE.");
                }

                var credsJson = JsonDocument.Parse(File.ReadAllText(oauthCredsPath)).RootElement;

                var accountsFile = GetOrCreateAccountsFile();
                if (accountsFile.Accounts.Any(a => string.Equals(a.Email, activeEmail, StringComparison.OrdinalIgnoreCase)))
                {
                    return (false, $"Tài khoản [{activeEmail}] đã tồn tại trong danh sách xoay vòng.");
                }

                var newId = Guid.NewGuid().ToString().ToLowerInvariant();
                var name = activeEmail.Split('@').First();
                var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                long rawExpiry = credsJson.TryGetProperty("expiry_date", out var expProp) ? expProp.GetInt64() : (now + 3600);
                long expirySec = rawExpiry > 100_000_000_000 ? rawExpiry / 1000 : rawExpiry;

                var token = new AccountToken
                {
                    AccessToken = credsJson.TryGetProperty("access_token", out var at) ? at.GetString() : null,
                    RefreshToken = credsJson.TryGetProperty("refresh_token", out var rt) ? rt.GetString() : null,
                    ExpiresIn = 3599,
                    ExpiryTimestamp = expirySec,
                    TokenType = "Bearer",
                    Email = activeEmail,
                    IdToken = credsJson.TryGetProperty("id_token", out var idt) ? idt.GetString() : null
                };

                var detail = new AccountDetailFile
                {
                    Id = newId,
                    Email = activeEmail,
                    Name = name,
                    Token = token,
                    Quota = new AccountDetailQuota
                    {
                        SubscriptionTier = "Free",
                        LastUpdated = DateTime.UtcNow.ToString("o")
                    },
                    CreatedAt = now,
                    LastUsed = now
                };

                var detailPath = Path.Combine(_accountsDir, $"{newId}.json");
                File.WriteAllText(detailPath, JsonSerializer.Serialize(detail, new JsonSerializerOptions { WriteIndented = true }));

                accountsFile.Accounts.Add(new ManagedAccount
                {
                    Id = newId,
                    Email = activeEmail,
                    Name = name,
                    CreatedAt = now,
                    LastUsed = now
                });

                accountsFile.CurrentAccountId ??= newId;
                accountsFile.CurrentIdeAccountId ??= newId;
                accountsFile.CurrentClassicAccountId ??= newId;
                accountsFile.CurrentAgyAccountId ??= newId;

                SaveAccountsFile(accountsFile);
                return (true, $"Đã import thành công tài khoản [{activeEmail}] từ Antigravity IDE!");
            }
            catch (Exception ex)
            {
                return (false, $"Lỗi import: {ex.Message}");
            }
        }

        public (bool success, string message) AddAccountFromOAuth(JsonElement tokenData, JsonElement userData)
        {
            var email = userData.GetProperty("email").GetString()?.Trim() ?? "";
            if (string.IsNullOrEmpty(email)) return (false, "Email không hợp lệ.");

            var accountsFile = GetOrCreateAccountsFile();
            if (accountsFile.Accounts.Any(a => string.Equals(a.Email, email, StringComparison.OrdinalIgnoreCase)))
            {
                return (false, $"Tài khoản [{email}] đã tồn tại trong danh sách.");
            }

            var newId = Guid.NewGuid().ToString().ToLowerInvariant();
            var name = userData.TryGetProperty("name", out var n) ? n.GetString() : email.Split('@').First();
            var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            long expiresIn = tokenData.TryGetProperty("expires_in", out var exp) ? exp.GetInt64() : 3600;

            var token = new AccountToken
            {
                AccessToken = tokenData.TryGetProperty("access_token", out var at) ? at.GetString() : null,
                RefreshToken = tokenData.TryGetProperty("refresh_token", out var rt) ? rt.GetString() : null,
                ExpiresIn = expiresIn,
                ExpiryTimestamp = now + expiresIn,
                TokenType = "Bearer",
                Email = email,
                IdToken = tokenData.TryGetProperty("id_token", out var idt) ? idt.GetString() : null
            };

            var detail = new AccountDetailFile
            {
                Id = newId,
                Email = email,
                Name = name,
                Token = token,
                Quota = new AccountDetailQuota
                {
                    SubscriptionTier = "Free",
                    LastUpdated = DateTime.UtcNow.ToString("o")
                },
                CreatedAt = now,
                LastUsed = now
            };

            var detailPath = Path.Combine(_accountsDir, $"{newId}.json");
            File.WriteAllText(detailPath, JsonSerializer.Serialize(detail, new JsonSerializerOptions { WriteIndented = true }));

            accountsFile.Accounts.Add(new ManagedAccount
            {
                Id = newId,
                Email = email,
                Name = name,
                CreatedAt = now,
                LastUsed = now
            });

            if (accountsFile.CurrentAccountId == null)
            {
                accountsFile.CurrentAccountId = newId;
                accountsFile.CurrentIdeAccountId = newId;
                accountsFile.CurrentClassicAccountId = newId;
                accountsFile.CurrentAgyAccountId = newId;
            }

            SaveAccountsFile(accountsFile);
            return (true, $"Đã thêm tài khoản [{email}] thành công!");
        }

        public (bool success, string message) DeleteAccount(string id)
        {
            var accountsFile = GetOrCreateAccountsFile();
            var activeId = accountsFile.CurrentIdeAccountId ?? accountsFile.CurrentAccountId ?? "";

            if (id == activeId)
            {
                return (false, "Không thể xóa tài khoản đang kích hoạt. Vui lòng chuyển sang tài khoản khác trước khi xóa.");
            }

            var target = accountsFile.Accounts.FirstOrDefault(a => a.Id == id);
            if (target == null) return (false, "Không tìm thấy tài khoản cần xóa.");

            accountsFile.Accounts.Remove(target);
            var detailPath = Path.Combine(_accountsDir, $"{id}.json");
            if (File.Exists(detailPath)) File.Delete(detailPath);

            SaveAccountsFile(accountsFile);
            return (true, $"Đã xóa tài khoản [{target.Email}] thành công.");
        }
    }
}

