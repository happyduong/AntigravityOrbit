using System;
using System.IO;
using System.Text.Json;
using AntigravityOrbit.Models;

namespace AntigravityOrbit.Services
{
    public class ConfigManager
    {
        private static ConfigManager? _instance;
        public static ConfigManager Instance => _instance ??= new ConfigManager();

        private readonly string _orbitDir;
        private readonly string _configPath;
        private RotatorConfig _config;

        public RotatorConfig Config => _config;

        private ConfigManager()
        {
            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            _orbitDir = Path.Combine(userProfile, ".antigravity_orbit");
            _configPath = Path.Combine(_orbitDir, "rotator_config.json");

            Directory.CreateDirectory(_orbitDir);
            _config = Load();
        }

        public RotatorConfig Load()
        {
            if (File.Exists(_configPath))
            {
                try
                {
                    var json = File.ReadAllText(_configPath);
                    var cfg = JsonSerializer.Deserialize<RotatorConfig>(json);
                    if (cfg != null)
                    {
                        LocalizationManager.CurrentLanguage = cfg.Language;
                        return cfg;
                    }
                }
                catch
                {
                    // Fallback to default
                }
            }

            var defaultCfg = new RotatorConfig();
            Save(defaultCfg);
            LocalizationManager.CurrentLanguage = defaultCfg.Language;
            return defaultCfg;
        }

        public void Save(RotatorConfig config)
        {
            _config = config;
            LocalizationManager.CurrentLanguage = config.Language;
            try
            {
                var json = JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(_configPath, json);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[ConfigManager] Save error: {ex.Message}");
            }
        }
    }
}

