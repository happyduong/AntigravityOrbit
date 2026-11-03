use std::fs;
use std::path::PathBuf;

pub struct AutostartManager;

impl AutostartManager {
    pub fn set_enabled(enabled: bool) -> bool {
        let home = match dirs::home_dir() {
            Some(h) => h,
            None => return false,
        };

        let autostart_dir = home.join(".config").join("autostart");
        let desktop_file = autostart_dir.join("antigravity-orbit.desktop");

        if enabled {
            let _ = fs::create_dir_all(&autostart_dir);
            let current_exe = std::env::current_exe()
                .unwrap_or_else(|_| PathBuf::from("antigravity-orbit"));
            let exe_str = current_exe.to_string_lossy();

            let content = format!(
                r#"[Desktop Entry]
Type=Application
Name=Antigravity Orbit
Comment=Google AI Quota Monitor & Smart Account Rotator
Exec={} --minimized
Icon=antigravity-orbit
Terminal=false
Categories=Utility;Development;
X-GNOME-Autostart-enabled=true
"#,
                exe_str
            );

            fs::write(desktop_file, content).is_ok()
        } else {
            if desktop_file.exists() {
                fs::remove_file(desktop_file).is_ok()
            } else {
                true
            }
        }
    }

    pub fn is_enabled() -> bool {
        let home = match dirs::home_dir() {
            Some(h) => h,
            None => return false,
        };
        let desktop_file = home.join(".config").join("autostart").join("antigravity-orbit.desktop");
        desktop_file.exists()
    }
}

