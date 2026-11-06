using Avalonia;
using Avalonia.Media;
using Avalonia.Styling;

namespace DicomTestTool.Services;

/// <summary>"Standard (Windows)" follows the system light/dark setting; "Klinik Dunkel" is black/grey with orange accents.</summary>
internal static class ThemeService
{
    private static readonly Color Orange = Color.FromRgb(0xEC, 0x66, 0x02);

    public static void Apply(string theme)
    {
        var app = Application.Current;
        if (app == null) return;
        var res = app.Resources;
        if (theme == "clinicalDark")
        {
            app.RequestedThemeVariant = ThemeVariant.Dark;
            res["SystemAccentColor"] = Orange;
            res["SystemAccentColorDark1"] = Color.FromRgb(0xC9, 0x57, 0x02);
            res["SystemAccentColorDark2"] = Color.FromRgb(0xA6, 0x47, 0x01);
            res["SystemAccentColorDark3"] = Color.FromRgb(0x82, 0x38, 0x01);
            res["SystemAccentColorLight1"] = Color.FromRgb(0xF0, 0x80, 0x2E);
            res["SystemAccentColorLight2"] = Color.FromRgb(0xF4, 0x9A, 0x5A);
            res["SystemAccentColorLight3"] = Color.FromRgb(0xF8, 0xB5, 0x86);
            res["AppBackground"] = new SolidColorBrush(Color.FromRgb(0x17, 0x17, 0x17));
            res["AppSidebar"] = new SolidColorBrush(Color.FromRgb(0x0D, 0x0D, 0x0D));
            res["AppPanel"] = new SolidColorBrush(Color.FromRgb(0x26, 0x26, 0x26));
            res["AppPanelBorder"] = new SolidColorBrush(Color.FromRgb(0x47, 0x47, 0x47));
            res["AppAccentBrush"] = new SolidColorBrush(Orange);
        }
        else
        {
            app.RequestedThemeVariant = ThemeVariant.Default;
            foreach (var k in new[] { "SystemAccentColor", "SystemAccentColorDark1", "SystemAccentColorDark2", "SystemAccentColorDark3",
                                      "SystemAccentColorLight1", "SystemAccentColorLight2", "SystemAccentColorLight3",
                                      "AppBackground", "AppSidebar", "AppPanel", "AppPanelBorder", "AppAccentBrush" })
                res.Remove(k);
        }
    }

    public static string Title(string theme) => theme == "clinicalDark" ? "Klinik Dunkel (Schwarz/Orange)" : "Standard (Windows)";
}
