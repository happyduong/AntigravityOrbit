use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use crate::models::RotatorConfig;

pub struct ConfigManager {
    config_path: PathBuf,
    pub config: Arc<Mutex<RotatorConfig>>,
}

impl ConfigManager {
    pub fn new() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
        let orbit_dir = home.join(".antigravity_orbit");
        let _ = fs::create_dir_all(&orbit_dir);
        let config_path = orbit_dir.join("rotator_config.json");

        let loaded_config = if config_path.exists() {
            match fs::read_to_string(&config_path) {
                Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
                Err(_) => RotatorConfig::default(),
            }
        } else {
            let default_cfg = RotatorConfig::default();
            if let Ok(json) = serde_json::to_string_pretty(&default_cfg) {
                let _ = fs::write(&config_path, json);
            }
            default_cfg
        };

        Self {
            config_path,
            config: Arc::new(Mutex::new(loaded_config)),
        }
    }

    pub fn get_config(&self) -> RotatorConfig {
        self.config.lock().unwrap().clone()
    }

    pub fn save_config(&self, new_config: RotatorConfig) -> Result<(), String> {
        let mut cfg = self.config.lock().unwrap();
        *cfg = new_config.clone();

        let json = serde_json::to_string_pretty(&new_config)
            .map_err(|e| format!("Serialization error: {}", e))?;
        fs::write(&self.config_path, json)
            .map_err(|e| format!("Write error: {}", e))?;
        Ok(())
    }

    pub fn update_language(&self, lang: &str) {
        let mut cfg = self.config.lock().unwrap();
        cfg.language = lang.to_string();
        if let Ok(json) = serde_json::to_string_pretty(&*cfg) {
            let _ = fs::write(&self.config_path, json);
        }
    }
}

