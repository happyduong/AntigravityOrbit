use notify_rust::Notification;
use std::process::Command;

pub struct NotificationManager;

impl NotificationManager {
    pub fn send(title: &str, subtitle: &str, body: &str, sound: bool) {
        let full_body = if !subtitle.is_empty() {
            format!("{}\n{}", subtitle, body)
        } else {
            body.to_string()
        };

        // Attempt notify-rust
        let mut n = Notification::new();
        n.summary(title)
            .body(&full_body)
            .appname("Antigravity Orbit")
            .icon("antigravity-orbit");

        if sound {
            n.sound_name("message-new-instant");
        }

        if n.show().is_err() {
            // Fallback to notify-send CLI
            let _ = Command::new("notify-send")
                .args(["-a", "Antigravity Orbit", title, &full_body])
                .status();
        }
    }
}

