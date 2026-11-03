#[allow(unused_imports)]
use std::io::Write;
#[allow(unused_imports)]
use std::process::{Command, Stdio};
use base64::Engine;
use chrono::{DateTime, Utc};

pub struct KeyringManager;

impl KeyringManager {
    pub fn sync_credentials(
        email: &str,
        access_token: &str,
        refresh_token: &str,
        token_type: &str,
        expiry_timestamp: i64,
    ) -> bool {
        let expiry_dt = DateTime::<Utc>::from_timestamp(expiry_timestamp, 0)
            .unwrap_or_else(|| Utc::now());
        let expiry_str = expiry_dt.to_rfc3339();

        let payload = serde_json::json!({
            "token": {
                "access_token": access_token,
                "token_type": token_type,
                "refresh_token": refresh_token,
                "expiry": expiry_str,
                "expires_in": 3599
            },
            "auth_method": "consumer",
            "id_token_email": email,
            "writer_id": "NvKBhN12_VheJ5FGOlmYSg"
        });

        let json_bytes = match serde_json::to_vec(&payload) {
            Ok(b) => b,
            Err(e) => {
                eprintln!("[Keyring] Failed to serialize keyring payload: {}", e);
                return false;
            }
        };

        let b64 = base64::engine::general_purpose::STANDARD.encode(json_bytes);
        let secret_value = format!("go-keyring-base64:{}", b64);

        #[cfg(target_os = "linux")]
        {
            // On Linux, use secret-tool (standard CLI for Freedesktop Secret Service)
            let mut child = match Command::new("secret-tool")
                .args(["store", "--label=gemini", "service", "gemini", "account", "antigravity"])
                .stdin(Stdio::piped())
                .stdout(Stdio::null())
                .stderr(Stdio::piped())
                .spawn()
            {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("[Keyring] secret-tool not available on Linux: {}. Skipping secret-tool store.", e);
                    return false;
                }
            };

            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(secret_value.as_bytes());
            }

            match child.wait() {
                Ok(status) => status.success(),
                Err(e) => {
                    eprintln!("[Keyring] secret-tool wait error: {}", e);
                    false
                }
            }
        }

        #[cfg(target_os = "macos")]
        {
            // On macOS fallback to security CLI
            let status = Command::new("/usr/bin/security")
                .args([
                    "add-generic-password",
                    "-U",
                    "-s",
                    "gemini",
                    "-a",
                    "antigravity",
                    "-w",
                    &secret_value,
                ])
                .status();
            match status {
                Ok(s) => s.success(),
                Err(e) => {
                    eprintln!("[Keyring] macOS security error: {}", e);
                    false
                }
            }
        }

        #[cfg(not(any(target_os = "linux", target_os = "macos")))]
        {
            true
        }
    }
}
