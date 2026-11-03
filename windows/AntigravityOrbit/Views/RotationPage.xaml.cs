using Microsoft.UI.Xaml.Controls;
using AntigravityOrbit.Services;

namespace AntigravityOrbit.Views
{
    public sealed partial class RotationPage : Page
    {
        private bool _isInitializing = true;

        public RotationPage()
        {
            this.InitializeComponent();
            LoadConfig();
            _isInitializing = false;
        }

        private void LoadConfig()
        {
            var cfg = ConfigManager.Instance.Config;
            AutoRotateToggle.IsOn = cfg.AutoRotateEnabled;

            foreach (ComboBoxItem item in ThresholdComboBox.Items)
            {
                if (item.Tag?.ToString() == cfg.ThresholdPercentage.ToString())
                {
                    ThresholdComboBox.SelectedItem = item;
                    break;
                }
            }

            foreach (ComboBoxItem item in IntervalComboBox.Items)
            {
                if (item.Tag?.ToString() == cfg.CheckIntervalSeconds.ToString())
                {
                    IntervalComboBox.SelectedItem = item;
                    break;
                }
            }
        }

        private void ConfigControl_Changed(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            if (_isInitializing) return;

            var cfg = ConfigManager.Instance.Config;
            cfg.AutoRotateEnabled = AutoRotateToggle.IsOn;

            if (ThresholdComboBox.SelectedItem is ComboBoxItem tItem && int.TryParse(tItem.Tag?.ToString(), out int tVal))
            {
                cfg.ThresholdPercentage = tVal;
            }

            if (IntervalComboBox.SelectedItem is ComboBoxItem iItem && int.TryParse(iItem.Tag?.ToString(), out int iVal))
            {
                cfg.CheckIntervalSeconds = iVal;
            }

            ConfigManager.Instance.Save(cfg);
        }
    }
}

