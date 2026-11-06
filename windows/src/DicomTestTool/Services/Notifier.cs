#if WINDOWS
using Microsoft.Toolkit.Uwp.Notifications;
#endif

namespace DicomTestTool.Services;

/// <summary>Windows toast notifications (Windows 10/11 Action Center). No-op on other platforms.</summary>
internal static class Notifier
{
    public static bool IsSupported =>
#if WINDOWS
        true;
#else
        false;
#endif

    public static string Show(string title, string body)
    {
#if WINDOWS
        try
        {
            new ToastContentBuilder().AddText(title).AddText(body).Show();
            return "";
        }
        catch (Exception e)
        {
            return e.Message;
        }
#else
        return "Benachrichtigungen gibt es nur unter Windows";
#endif
    }

    public static void Uninstall()
    {
#if WINDOWS
        try { ToastNotificationManagerCompat.Uninstall(); } catch { }
#endif
    }

    public static string PermissionText
    {
        get
        {
#if WINDOWS
            try
            {
                return ToastNotificationManagerCompat.CreateToastNotifier().Setting switch
                {
                    Windows.UI.Notifications.NotificationSetting.Enabled => "erlaubt",
                    Windows.UI.Notifications.NotificationSetting.DisabledForApplication => "für diese App abgeschaltet – bitte in den Windows-Einstellungen › System › Benachrichtigungen erlauben",
                    Windows.UI.Notifications.NotificationSetting.DisabledForUser => "für diesen Benutzer abgeschaltet – Windows-Einstellungen › System › Benachrichtigungen",
                    Windows.UI.Notifications.NotificationSetting.DisabledByGroupPolicy => "durch Gruppenrichtlinie deaktiviert",
                    Windows.UI.Notifications.NotificationSetting.DisabledByManifest => "nicht verfügbar",
                    _ => "unbekannt",
                };
            }
            catch (Exception e)
            {
                return "unbekannt (" + e.Message + ")";
            }
#else
            return "nur unter Windows verfügbar";
#endif
        }
    }

    public static void OpenSettings() => Shell.OpenUri("ms-settings:notifications");
}
