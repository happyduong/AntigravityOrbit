using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AntigravityOrbit.Views;
using AntigravityOrbit.Interop;

namespace AntigravityOrbit
{
    public sealed partial class MainWindow : Window
    {
        public bool Visible { get; private set; } = true;

        public MainWindow()
        {
            this.InitializeComponent();

            this.AppWindow.Title = "Antigravity Orbit - Cài đặt";
            this.AppWindow.Resize(new Windows.Graphics.SizeInt32(840, 620));

            // Intercept close event to hide to tray
            this.AppWindow.Closing += (sender, args) =>
            {
                args.Cancel = true;
                Hide();
            };

            // Select default Accounts page
            NavView.SelectedItem = NavView.MenuItems[0];
            ContentFrame.Navigate(typeof(AccountsPage));

            // Bind status badge text
            App.MainVm.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName == nameof(App.MainVm.StatusBadgeText))
                {
                    StatusBadgeTextBlock.Text = App.MainVm.StatusBadgeText;
                }
            };
        }

        public void Hide()
        {
            var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            NativeMethods.ShowWindow(hWnd, NativeMethods.SW_HIDE);
            Visible = false;
        }

        public void Show()
        {
            var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            NativeMethods.ShowWindow(hWnd, NativeMethods.SW_RESTORE);
            NativeMethods.SetForegroundWindow(hWnd);
            Visible = true;
        }

        private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
        {
            if (args.SelectedItem is NavigationViewItem item)
            {
                var tag = item.Tag?.ToString();
                switch (tag)
                {
                    case "accounts":
                        ContentFrame.Navigate(typeof(AccountsPage));
                        break;
                    case "rotation":
                        ContentFrame.Navigate(typeof(RotationPage));
                        break;
                    case "general":
                        ContentFrame.Navigate(typeof(GeneralPage));
                        break;
                    case "about":
                        ContentFrame.Navigate(typeof(AboutPage));
                        break;
                }
            }
        }
    }
}

