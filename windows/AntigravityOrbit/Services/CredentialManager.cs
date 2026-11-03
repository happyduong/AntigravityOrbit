using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using AntigravityOrbit.Interop;

namespace AntigravityOrbit.Services
{
    public static class CredentialManager
    {
        public static bool SyncCredentials(string email, string accessToken, string refreshToken, string tokenType, long expiryTimestamp)
        {
            try
            {
                var expiryDate = DateTimeOffset.FromUnixTimeSeconds(expiryTimestamp).ToString("yyyy-MM-ddTHH:mm:ssZ");

                var payload = new
                {
                    token = new
                    {
                        access_token = accessToken,
                        token_type = tokenType,
                        refresh_token = refreshToken,
                        expiry = expiryDate,
                        expires_in = 3599
                    },
                    auth_method = "consumer",
                    id_token_email = email,
                    writer_id = "NvKBhN12_VheJ5FGOlmYSg"
                };

                var json = JsonSerializer.Serialize(payload);
                var b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(json));
                var secretString = "go-keyring-base64:" + b64;
                var secretBytes = Encoding.Unicode.GetBytes(secretString);

                var blobPtr = Marshal.AllocHGlobal(secretBytes.Length);
                Marshal.Copy(secretBytes, 0, blobPtr, secretBytes.Length);

                try
                {
                    // agy on Windows targets "gemini" with username "antigravity"
                    var cred = new NativeMethods.CREDENTIAL
                    {
                        Flags = 0,
                        Type = NativeMethods.CRED_TYPE_GENERIC,
                        TargetName = "gemini",
                        Comment = "Antigravity Orbit Keyring",
                        CredentialBlob = blobPtr,
                        CredentialBlobSize = (uint)secretBytes.Length,
                        Persist = NativeMethods.CRED_PERSIST_LOCAL_MACHINE,
                        UserName = "antigravity"
                    };

                    bool success = NativeMethods.CredWrite(ref cred, 0);

                    // Also write "gemini:antigravity" as alias
                    var credAlias = new NativeMethods.CREDENTIAL
                    {
                        Flags = 0,
                        Type = NativeMethods.CRED_TYPE_GENERIC,
                        TargetName = "gemini:antigravity",
                        Comment = "Antigravity Orbit Keyring Alias",
                        CredentialBlob = blobPtr,
                        CredentialBlobSize = (uint)secretBytes.Length,
                        Persist = NativeMethods.CRED_PERSIST_LOCAL_MACHINE,
                        UserName = "antigravity"
                    };
                    NativeMethods.CredWrite(ref credAlias, 0);

                    return success;
                }
                finally
                {
                    Marshal.FreeHGlobal(blobPtr);
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CredentialManager] WinCred write error: {ex.Message}");
                return false;
            }
        }
    }
}

