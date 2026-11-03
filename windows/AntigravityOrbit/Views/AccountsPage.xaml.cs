using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Data;
using AntigravityOrbit.Services;

namespace AntigravityOrbit.Views
{
    public sealed partial class AccountsPage : Page
    {
        public AccountsPage()
        {
            this.InitializeComponent();
            AccountsItemsControl.ItemsSource = App.MainVm.Accounts;
        }

        private async void ImportIdeButton_Click(object sender, RoutedEventArgs e)
        {
            var (success, msg) = AccountManager.Instance.ImportFromIde();
            await ShowDialogAsync(success ? "Thành công" : "Thông báo", msg);
            if (success) await App.MainVm.RefreshQuotasAsync();
        }

        private async void GoogleLoginButton_Click(object sender, RoutedEventArgs e)
        {
            await OAuthServer.StartLoginFlowAsync(async (success, msg, token, user) =>
            {
                if (success && token.HasValue && user.HasValue)
                {
                    var (ok, addMsg) = AccountManager.Instance.AddAccountFromOAuth(token.Value, user.Value);
                    await ShowDialogAsync(ok ? "Thành công" : "Thông báo", addMsg);
                    await App.MainVm.RefreshQuotasAsync();
                }
                else
                {
                    await ShowDialogAsync("Lỗi đăng nhập", msg);
                }
            });
        }

        private async void RefreshButton_Click(object sender, RoutedEventArgs e)
        {
            await App.MainVm.RefreshQuotasAsync();
        }

        private async void SwitchButton_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string accountId)
            {
                await App.MainVm.SwitchAccountAsync(accountId);
            }
        }

        private async void DeleteButton_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string accountId)
            {
                var (success, msg) = AccountManager.Instance.DeleteAccount(accountId);
                await ShowDialogAsync(success ? "Đã xóa" : "Lỗi", msg);
                if (success) await App.MainVm.RefreshQuotasAsync();
            }
        }

        private async System.Threading.Tasks.Task ShowDialogAsync(string title, string content)
        {
            var dialog = new ContentDialog
            {
                Title = title,
                Content = content,
                CloseButtonText = "Đóng",
                XamlRoot = this.XamlRoot
            };
            await dialog.ShowAsync();
        }
    }

    public class InverseBoolConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, string language)
        {
            if (value is bool b) return !b;
            return true;
        }

        public object ConvertBack(object value, Type targetType, object parameter, string language)
        {
            if (value is bool b) return !b;
            return false;
        }
    }
}

