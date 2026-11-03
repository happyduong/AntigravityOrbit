using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AntigravityOrbit.Models;
using AntigravityOrbit.Services;

namespace AntigravityOrbit.ViewModels
{
    public partial class MainViewModel : ObservableObject
    {
        [ObservableProperty]
        private ObservableCollection<AccountStatus> _accounts = new();

        [ObservableProperty]
        private AccountStatus? _currentAccount;

        [ObservableProperty]
        private string _statusBadgeText = "⚪ Standby";

        [ObservableProperty]
        private string _trayTooltip = "Antigravity Orbit";

        [ObservableProperty]
        private bool _isRefreshing;

        public MainViewModel()
        {
            _ = RefreshQuotasAsync();
        }

        [RelayCommand]
        public async Task RefreshQuotasAsync()
        {
            if (IsRefreshing) return;
            IsRefreshing = true;

            try
            {
                var list = await QuotaService.Instance.FetchAllQuotasAsync();
                Accounts.Clear();
                foreach (var acc in list)
                {
                    Accounts.Add(acc);
                }

                CurrentAccount = Accounts.FirstOrDefault(a => a.IsCurrent);

                UpdateTrayAndBadge();
            }
            finally
            {
                IsRefreshing = false;
            }
        }

        public void UpdateTrayAndBadge()
        {
            if (CurrentAccount != null)
            {
                int pct = CurrentAccount.RemainingPercentage;
                string dot = pct > 30 ? "🟢" : (pct > 10 ? "🟡" : "🔴");
                string pctStr = pct >= 0 ? $"{pct}%" : "--%";
                StatusBadgeText = $"{dot} {CurrentAccount.Email} ({pctStr})";

                string g5h = CurrentAccount.Gemini5hPercentage.HasValue ? $"{CurrentAccount.Gemini5hPercentage}%" : "--%";
                string gWeek = CurrentAccount.GeminiWeeklyPercentage.HasValue ? $"{CurrentAccount.GeminiWeeklyPercentage}%" : "--%";
                TrayTooltip = $"Antigravity Orbit: {CurrentAccount.Email}\nModel: {CurrentAccount.DisplayModelName}\n(5h: {g5h} • Tuần: {gWeek})";
            }
            else
            {
                StatusBadgeText = "⚪ Standby";
                TrayTooltip = "Antigravity Orbit\nChưa kích hoạt tài khoản nào";
            }
        }

        [RelayCommand]
        public async Task SwitchAccountAsync(string accountId)
        {
            bool ok = AccountRotator.Instance.SwitchToAccount(accountId);
            if (ok)
            {
                await RefreshQuotasAsync();
                var switched = Accounts.FirstOrDefault(a => a.Id == accountId);
                if (switched != null)
                {
                    NotificationManager.SendNotification("Antigravity Orbit", "Đã chuyển đổi tài khoản thành công", $"Đã kích hoạt [{switched.Email}] (Quota: {switched.RemainingPercentage}%).");
                }
            }
        }

        [RelayCommand]
        public async Task RotateToNextAsync()
        {
            var res = await AccountRotator.Instance.RotateToNextAsync(Accounts.ToList(), "Thao tác thủ công");
            if (res != null)
            {
                await RefreshQuotasAsync();
            }
        }
    }
}

