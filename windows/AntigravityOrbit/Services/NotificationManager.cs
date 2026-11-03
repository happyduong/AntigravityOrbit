using System;
using System.Diagnostics;

namespace AntigravityOrbit.Services
{
    public static class NotificationManager
    {
        public static void SendNotification(string title, string subtitle, string body, bool sound = true)
        {
            if (!ConfigManager.Instance.Config.NotificationsEnabled) return;

            try
            {
                // In Windows App SDK 1.5/1.6, AppNotificationManager can send toast notifications
                var fullBody = string.IsNullOrEmpty(subtitle) ? body : $"{subtitle}\n{body}";
                
                // Fallback to PowerShell Toast if AppNotificationManager is not registered
                var script = $@"
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
$template = @""
<toast>
    <visual>
        <binding template=""ToastGeneric"">
            <text>{title.Replace("\"", "`\"")}</text>
            <text>{fullBody.Replace("\"", "`\"")}</text>
        </binding>
    </visual>
    {(sound ? "" : "<audio silent=\"true\"/>")}
</toast>
""@
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($template)
$toast = New-Object Windows.UI.Notifications.ToastNotification $xml
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(""Antigravity Orbit"").Show($toast)
";

                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{script}\"",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[NotificationManager] Toast error: {ex.Message}");
            }
        }
    }
}

