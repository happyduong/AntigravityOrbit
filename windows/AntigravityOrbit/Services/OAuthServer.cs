using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace AntigravityOrbit.Services
{
    public class OAuthServer
    {
        private const byte Key = 0x5A;
        private static readonly byte[] RawIdBytes =
        {
            107, 106, 109, 107, 106, 106, 108, 106, 108, 106, 111, 99, 107, 119, 46, 55, 50, 41, 41, 51,
            52, 104, 50, 104, 107, 54, 57, 40, 63, 104, 105, 111, 44, 46, 53, 54, 53, 48, 50, 110,
            61, 110, 106, 105, 63, 42, 116, 59, 42, 42, 41, 116, 61, 53, 53, 61, 54, 63, 47, 41,
            63, 40, 57, 53, 52, 46, 63, 52, 46, 116, 57, 53, 55
        };
        private static readonly byte[] RawSecretBytes =
        {
            29, 21, 25, 9, 10, 2, 119, 17, 111, 98, 28, 13, 8, 110, 98, 108, 22, 62, 22, 16,
            107, 55, 22, 24, 98, 41, 2, 25, 110, 32, 108, 43, 30, 27, 60
        };

        public static string ClientId
        {
            get
            {
                var env = Environment.GetEnvironmentVariable("ANTIGRAVITY_CLIENT_ID");
                if (!string.IsNullOrEmpty(env)) return env;
                var bytes = new byte[RawIdBytes.Length];
                for (int i = 0; i < RawIdBytes.Length; i++) bytes[i] = (byte)(RawIdBytes[i] ^ Key);
                return Encoding.UTF8.GetString(bytes);
            }
        }

        public static string ClientSecret
        {
            get
            {
                var env = Environment.GetEnvironmentVariable("ANTIGRAVITY_CLIENT_SECRET");
                if (!string.IsNullOrEmpty(env)) return env;
                var bytes = new byte[RawSecretBytes.Length];
                for (int i = 0; i < RawSecretBytes.Length; i++) bytes[i] = (byte)(RawSecretBytes[i] ^ Key);
                return Encoding.UTF8.GetString(bytes);
            }
        }

        public const string Scopes = "https://www.googleapis.com/auth/userinfo.email openid https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.profile";

        public static async Task StartLoginFlowAsync(Action<bool, string, JsonElement?, JsonElement?> onComplete)
        {
            int port = 0;
            HttpListener? listener = null;
            var rand = new Random();

            for (int i = 0; i < 20; i++)
            {
                int p = rand.Next(49152, 65530);
                try
                {
                    listener = new HttpListener();
                    listener.Prefixes.Add($"http://localhost:{p}/auth/callback/");
                    listener.Start();
                    port = p;
                    break;
                }
                catch
                {
                    listener?.Close();
                }
            }

            if (listener == null || port == 0)
            {
                onComplete(false, "Không thể mở cổng mạng local để nhận phản hồi từ trình duyệt.", null, null);
                return;
            }

            var redirectUri = $"http://localhost:{port}/auth/callback/";
            var authUrl = $"https://accounts.google.com/o/oauth2/v2/auth?client_id={ClientId}&redirect_uri={Uri.EscapeDataString(redirectUri)}&response_type=code&scope={Uri.EscapeDataString(Scopes)}&access_type=offline&prompt=consent";

            // Open browser on Windows
            Process.Start(new ProcessStartInfo
            {
                FileName = authUrl,
                UseShellExecute = true
            });

            _ = Task.Run(async () =>
            {
                try
                {
                    var context = await listener.GetContextAsync();
                    var code = context.Request.QueryString["code"];

                    if (!string.IsNullOrEmpty(code))
                    {
                        var (success, token, user) = await ExchangeCodeAsync(code, redirectUri);
                        var responseHtml = success
                            ? "<!DOCTYPE html><html><body style='font-family:sans-serif;text-align:center;padding:50px;background:#18181b;color:#f4f4f5;'><h1 style='color:#22c55e;'>✔ Đăng nhập thành công!</h1><p>Bạn có thể đóng tab này và quay lại Antigravity Orbit.</p></body></html>"
                            : "<!DOCTYPE html><html><body style='font-family:sans-serif;text-align:center;padding:50px;background:#18181b;color:#f4f4f5;'><h1 style='color:#ef4444;'>❌ Đăng nhập thất bại</h1></body></html>";

                        var buffer = Encoding.UTF8.GetBytes(responseHtml);
                        context.Response.ContentLength64 = buffer.Length;
                        context.Response.ContentType = "text/html; charset=utf-8";
                        await context.Response.OutputStream.WriteAsync(buffer, 0, buffer.Length);
                        context.Response.OutputStream.Close();

                        onComplete(success, success ? "Đăng nhập thành công!" : "Lỗi đổi token", token, user);
                    }
                    else
                    {
                        onComplete(false, "Không nhận được authorization code từ Google.", null, null);
                    }
                }
                catch (Exception ex)
                {
                    onComplete(false, ex.Message, null, null);
                }
                finally
                {
                    listener.Stop();
                    listener.Close();
                }
            });
        }

        private static async Task<(bool, JsonElement?, JsonElement?)> ExchangeCodeAsync(string code, string redirectUri)
        {
            using var client = new HttpClient();
            var dict = new Dictionary<string, string>
            {
                ["client_id"] = ClientId,
                ["client_secret"] = ClientSecret,
                ["code"] = code,
                ["grant_type"] = "authorization_code",
                ["redirect_uri"] = redirectUri
            };

            var res = await client.PostAsync("https://oauth2.googleapis.com/token", new FormUrlEncodedContent(dict));
            if (!res.IsSuccessStatusCode) return (false, null, null);

            var tokenJson = await res.Content.ReadAsStringAsync();
            var tokenDoc = JsonDocument.Parse(tokenJson);

            var accessToken = tokenDoc.RootElement.GetProperty("access_token").GetString();
            if (string.IsNullOrEmpty(accessToken)) return (false, null, null);

            // Fetch user info
            client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
            var userRes = await client.GetAsync("https://www.googleapis.com/oauth2/v2/userinfo");
            if (!userRes.IsSuccessStatusCode) return (false, null, null);

            var userJson = await userRes.Content.ReadAsStringAsync();
            var userDoc = JsonDocument.Parse(userJson);

            return (true, tokenDoc.RootElement, userDoc.RootElement);
        }
    }
}

