using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using H.NotifyIcon;
using H.NotifyIcon.Core;
using AntigravityOrbit.Services;
using AntigravityOrbit.ViewModels;

namespace AntigravityOrbit
{
    public partial class App : Application
    {
        private static Mutex? _singleInstanceMutex;
        private MainWindow? _mainWindow;
        private TaskbarIcon? _trayIcon;
        private DispatcherTimer? _quotaTimer;

        public static MainViewModel MainVm { get; } = new();

        public App()
        {
            this.InitializeComponent();

            // 1. Single Instance check via Global Mutex
            _singleInstanceMutex = new Mutex(true, "Global\\AntigravityOrbitWinUI3Mutex", out bool createdNew);
            if (!createdNew)
            {
                // Another instance is already running
                Environment.Exit(0);
                return;
            }
        }

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            _mainWindow = new MainWindow();

            // 2. Setup Taskbar Tray Icon
            SetupTrayIcon();

            // 3. Start Background Quota Timer
            StartQuotaTimer();

            // Check if launched with --minimized
            var cmdArgs = Environment.GetCommandLineArgs();
            bool startMinimized = cmdArgs.Any(a => a.Equals("--minimized", StringComparison.OrdinalIgnoreCase));

            if (!startMinimized)
            {
                _mainWindow.Activate();
            }
        }

        private void SetupTrayIcon()
        {
            _trayIcon = new TaskbarIcon
            {
                IconSource = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri("ms-appx:///Assets/AppIcon1024.png")),
                ToolTipText = "Antigravity Orbit"
            };

            // Left-click to toggle MainWindow
            _trayIcon.LeftClickCommand = new CommunityToolkit.Mvvm.Input.RelayCommand(() =>
            {
                if (_mainWindow == null) return;
                if (_mainWindow.Visible)
                {
                    _mainWindow.Hide();
                }
                else
                {
                    _mainWindow.Show();
                    _mainWindow.Activate();
                }
            });

            // Context Menu
            var menu = new Microsoft.UI.Xaml.Controls.MenuFlyout();

            var rotateItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem
            {
                Text = LocalizationManager.Tr("menu.manual_rotate"),
                Command = new CommunityToolkit.Mvvm.Input.RelayCommand(async () => await MainVm.RotateToNextAsync())
            };
            menu.Items.Add(rotateItem);

            var refreshItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem
            {
                Text = LocalizationManager.Tr("menu.refresh"),
                Command = new CommunityToolkit.Mvvm.Input.RelayCommand(async () => await MainVm.RefreshQuotasAsync())
            };
            menu.Items.Add(refreshItem);

            menu.Items.Add(new Microsoft.UI.Xaml.Controls.MenuFlyoutSeparator());

            var settingsItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem
            {
                Text = LocalizationManager.Tr("menu.settings"),
                Command = new CommunityToolkit.Mvvm.Input.RelayCommand(() =>
                {
                    _mainWindow?.Show();
                    _mainWindow?.Activate();
                })
            };
            menu.Items.Add(settingsItem);

            menu.Items.Add(new Microsoft.UI.Xaml.Controls.MenuFlyoutSeparator());

            var quitItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem
            {
                Text = LocalizationManager.Tr("menu.quit"),
                Command = new CommunityToolkit.Mvvm.Input.RelayCommand(() =>
                {
                    _trayIcon.Dispose();
                    _singleInstanceMutex?.ReleaseMutex();
                    Environment.Exit(0);
                })
            };
            menu.Items.Add(quitItem);

            _trayIcon.ContextFlyout = menu;
            _trayIcon.ForceCreate();
        }

        private void StartQuotaTimer()
        {
            _quotaTimer = new DispatcherTimer();
            var intervalSec = Math.Max(10, ConfigManager.Instance.Config.CheckIntervalSeconds);
            _quotaTimer.Interval = TimeSpan.FromSeconds(intervalSec);
            _quotaTimer.Tick += async (s, e) =>
            {
                await MainVm.RefreshQuotasAsync();

                // Auto-rotation check
                var cfg = ConfigManager.Instance.Config;
                if (cfg.AutoRotateEnabled && MainVm.CurrentAccount != null)
                {
                    if (MainVm.CurrentAccount.RemainingPercentage <= cfg.ThresholdPercentage && MainVm.CurrentAccount.RemainingPercentage >= 0)
                    {
                        var reason = $"Hạn mức còn {MainVm.CurrentAccount.RemainingPercentage}% (ngưỡng: {cfg.ThresholdPercentage}%)";
                        await AccountRotator.Instance.RotateToNextAsync(MainVm.Accounts.ToList(), reason);
                        await MainVm.RefreshQuotasAsync();
                    }
                }

                if (_trayIcon != null)
                {
                    _trayIcon.ToolTipText = MainVm.TrayTooltip;
                }
            };
            _quotaTimer.Start();
        }
    }
}

