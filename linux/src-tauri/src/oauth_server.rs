use std::io::{Read, Write};
use std::net::TcpListener;
use reqwest::Client;
use serde::{Deserialize, Serialize};

pub struct OAuthServer;

impl OAuthServer {
    const KEY: u8 = 0x5A;
    const RAW_ID_BYTES: &'static [u8] = &[
        107, 106, 109, 107, 106, 106, 108, 106, 108, 106, 111, 99, 107, 119, 46, 55, 50, 41, 41, 51,
        52, 104, 50, 104, 107, 54, 57, 40, 63, 104, 105, 111, 44, 46, 53, 54, 53, 48, 50, 110,
        61, 110, 106, 105, 63, 42, 116, 59, 42, 42, 41, 116, 61, 53, 53, 61, 54, 63, 47, 41,
        63, 40, 57, 53, 52, 46, 63, 52, 46, 116, 57, 53, 55,
    ];
    const RAW_SECRET_BYTES: &'static [u8] = &[
        29, 21, 25, 9, 10, 2, 119, 17, 111, 98, 28, 13, 8, 110, 98, 108, 22, 62, 22, 16,
        107, 55, 22, 24, 98, 41, 2, 25, 110, 32, 108, 43, 30, 27, 60,
    ];

    pub fn client_id() -> String {
        if let Ok(id) = std::env::var("ANTIGRAVITY_CLIENT_ID") {
            if !id.is_empty() {
                return id;
            }
        }
        let deobf: Vec<u8> = Self::RAW_ID_BYTES.iter().map(|b| b ^ Self::KEY).collect();
        String::from_utf8(deobf).unwrap_or_default()
    }

    pub fn client_secret() -> String {
        if let Ok(secret) = std::env::var("ANTIGRAVITY_CLIENT_SECRET") {
            if !secret.is_empty() {
                return secret;
            }
        }
        let deobf: Vec<u8> = Self::RAW_SECRET_BYTES.iter().map(|b| b ^ Self::KEY).collect();
        String::from_utf8(deobf).unwrap_or_default()
    }

    pub const SCOPES: &'static str = "https://www.googleapis.com/auth/userinfo.email openid https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.profile";

    pub async fn start_login_flow<F>(on_complete: F) -> Result<String, String>
    where
        F: FnOnce(bool, String, Option<OAuthTokenData>, Option<OAuthUserInfo>) + Send + 'static,
    {
        // Bind to a random port in range 49152..65530
        let mut port = 49152;
        let mut listener = None;
        for p in 49152..65530 {
            if let Ok(l) = TcpListener::bind(format!("127.0.0.1:{}", p)) {
                port = p;
                listener = Some(l);
                break;
            }
        }

        let listener = listener.ok_or_else(|| "Could not bind local loopback port for OAuth callback.".to_string())?;

        let redirect_uri = format!("http://localhost:{}/auth/callback", port);
        let auth_url = format!(
            "https://accounts.google.com/o/oauth2/v2/auth?client_id={}&redirect_uri={}&response_type=code&scope={}&access_type=offline&prompt=consent",
            Self::client_id(),
            urlencoding::encode(&redirect_uri),
            urlencoding::encode(Self::SCOPES),
        );

        // Open browser
        let _ = open::that(&auth_url);

        // Spawn listener in thread
        tokio::task::spawn_blocking(move || {
            let mut buffer = [0u8; 4096];
            if let Ok((mut stream, _)) = listener.accept() {
                let n = stream.read(&mut buffer).unwrap_or(0);
                let req_str = String::from_utf8_lossy(&buffer[..n]);

                // Extract 'code=' query parameter
                let mut auth_code = None;
                if let Some(path_line) = req_str.lines().next() {
                    if let Some(query_start) = path_line.find("code=") {
                        let code_part = &path_line[query_start + 5..];
                        let code = code_part.split(|c| c == ' ' || c == '&').next().unwrap_or("");
                        if !code.is_empty() {
                            auth_code = Some(code.to_string());
                        }
                    }
                }

                if let Some(code) = auth_code {
                    let runtime = tokio::runtime::Handle::current();
                    let redirect_uri_clone = redirect_uri.clone();
                    let res = runtime.block_on(async {
                        Self::exchange_code_and_get_user(&code, &redirect_uri_clone).await
                    });

                    match res {
                        Ok((token_data, user_info)) => {
                            let response_body = r#"<!DOCTYPE html><html><head><meta charset="utf-8"><title>Antigravity Orbit</title><style>body{font-family:sans-serif;text-align:center;padding:50px;background:#18181b;color:#f4f4f5;}h1{color:#22c55e;}</style></head><body><h1>✔ Đăng nhập thành công!</h1><p>Bạn có thể đóng tab này và quay lại Antigravity Orbit.</p></body></html>"#;
                            let http_resp = format!("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", response_body.len(), response_body);
                            let _ = stream.write_all(http_resp.as_bytes());
                            let _ = stream.flush();
                            on_complete(true, "Đăng nhập thành công!".to_string(), Some(token_data), Some(user_info));
                        }
                        Err(err) => {
                            let response_body = format!(r#"<!DOCTYPE html><html><head><meta charset="utf-8"><title>Error</title><style>body{{font-family:sans-serif;text-align:center;padding:50px;background:#18181b;color:#f4f4f5;}}h1{{color:#ef4444;}}</style></head><body><h1>❌ Đăng nhập thất bại</h1><p>{}</p></body></html>"#, err);
                            let http_resp = format!("HTTP/1.1 400 Bad Request\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", response_body.len(), response_body);
                            let _ = stream.write_all(http_resp.as_bytes());
                            let _ = stream.flush();
                            on_complete(false, err, None, None);
                        }
                    }
                } else {
                    let response_body = "No auth code found.";
                    let http_resp = format!("HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", response_body.len(), response_body);
                    let _ = stream.write_all(http_resp.as_bytes());
                    let _ = stream.flush();
                    on_complete(false, "Không tìm thấy authorization code từ Google OAuth.".to_string(), None, None);
                }
            }
        });

        Ok(auth_url)
    }

    async fn exchange_code_and_get_user(code: &str, redirect_uri: &str) -> Result<(OAuthTokenData, OAuthUserInfo), String> {
        let client = Client::new();
        let params = [
            ("client_id", Self::client_id()),
            ("client_secret", Self::client_secret()),
            ("code", code.to_string()),
            ("grant_type", "authorization_code".to_string()),
            ("redirect_uri", redirect_uri.to_string()),
        ];

        let res = client
            .post("https://oauth2.googleapis.com/token")
            .form(&params)
            .send()
            .await
            .map_err(|e| format!("Token request failed: {}", e))?;

        if !res.status().is_success() {
            let txt = res.text().await.unwrap_or_default();
            return Err(format!("Google token exchange error: {}", txt));
        }

        let token_data: OAuthTokenData = res
            .json()
            .await
            .map_err(|e| format!("Failed to parse token response: {}", e))?;

        // Fetch user info
        let access_token = &token_data.access_token;
        let user_res = client
            .get("https://www.googleapis.com/oauth2/v2/userinfo")
            .header("Authorization", format!("Bearer {}", access_token))
            .send()
            .await
            .map_err(|e| format!("UserInfo request failed: {}", e))?;

        if !user_res.status().is_success() {
            let txt = user_res.text().await.unwrap_or_default();
            return Err(format!("Failed to retrieve user info: {}", txt));
        }

        let user_info: OAuthUserInfo = user_res
            .json()
            .await
            .map_err(|e| format!("Failed to parse userinfo: {}", e))?;

        Ok((token_data, user_info))
    }
}

mod urlencoding {
    pub fn encode(data: &str) -> String {
        let mut res = String::new();
        for b in data.bytes() {
            match b {
                b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                    res.push(b as char);
                }
                _ => {
                    res.push_str(&format!("%{:02X}", b));
                }
            }
        }
        res
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthTokenData {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in: Option<i64>,
    pub token_type: Option<String>,
    pub id_token: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthUserInfo {
    pub email: String,
    pub name: Option<String>,
    pub picture: Option<String>,
}
