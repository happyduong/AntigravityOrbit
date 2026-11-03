using Microsoft.UI.Xaml.Controls;
using AntigravityOrbit.Services;

namespace AntigravityOrbit.Views
{
    public sealed partial class GeneralPage : Page
    {
        private bool _isInitializing = true;

        public GeneralPage()
        {
            this.InitializeComponent();
            LoadConfig();
            _isInitializing = false;
        }

        private void LoadConfig()
        {
            var cfg = ConfigManager.Instance.Config;
            AutostartToggle.IsOn = cfg.LaunchAtLogin;
            NotificationsToggle.IsOn = cfg.NotificationsEnabled;
            SoundToggle.IsOn = cfg.SoundEnabled;

            foreach (ComboBoxItem item in LanguageComboBox.Items)
            {
                if (item.Tag?.ToString() == cfg.Language)
                {
                    LanguageComboBox.SelectedItem = item;
                    break;
                }
            }
        }

        private void ConfigControl_Changed(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            if (_isInitializing) return;

            var cfg = ConfigManager.Instance.Config;
            bool oldAutostart = cfg.LaunchAtLogin;

            cfg.LaunchAtLogin = AutostartToggle.IsOn;
            cfg.NotificationsEnabled = NotificationsToggle.IsOn;
            cfg.SoundEnabled = SoundToggle.IsOn;

            if (LanguageComboBox.SelectedItem is ComboBoxItem langItem && langItem.Tag is string lang)
            {
                cfg.Language = lang;
            }

            if (oldAutostart != cfg.LaunchAtLogin)
            {
                AutostartManager.SetEnabled(cfg.LaunchAtLogin);
            }

            ConfigManager.Instance.Save(cfg);
        }
    }
}

