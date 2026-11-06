using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using DicomTestTool.Controls;
using DicomTestTool.Core;
using DicomTestTool.Services;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Views;

public partial class AboutView : UserControl
{
    private readonly AppState _state = AppState.Shared;

    public AboutView()
    {
        InitializeComponent();
        DataContext = _state.Updater;
        VersionText.Text = $"Version {AppInfo.Version} · {(OperatingSystem.IsWindows() ? "Windows" : "Entwicklungsversion")}";

        Row(PrivacyRows, "Keine Nutzungsdaten",
            "Die App erhebt keine Statistiken, verwendet keine Analyse- oder Tracking-Dienste und sendet nichts an den Entwickler.");
        Row(PrivacyRows, "Netzwerkverbindungen",
            "Verbindungen entstehen nur zu den DICOM-Knoten, die Sie selbst eintragen, sowie für die Update-Prüfung zu GitHub (api.github.com, github.com). Dabei sieht GitHub Ihre IP-Adresse; es gilt die Datenschutzerklärung von GitHub. Die automatische Update-Suche lässt sich oben unter „Updates“ abschalten.");
        Row(PrivacyRows, "Lokale Speicherung",
            "Einstellungen und Knoten liegen unter %APPDATA%\\DICOM Test Tool, Protokolle unter %LOCALAPPDATA%\\DICOM Test Tool\\Logs (30 Tage). Empfangene DICOM-Dateien speichert der Storage SCP nur im von Ihnen gewählten Ordner.");
        Row(PrivacyRows, "Patientendaten",
            "DICOM-Objekte, Protokolle und Log-Dateien können Patientendaten enthalten (z. B. Name, ID, Geburtsdatum). Bitte behandeln Sie sie entsprechend den Vorgaben Ihrer Einrichtung und entfernen Sie Patientendaten, bevor Sie Protokolle weitergeben oder in einer Fehlermeldung veröffentlichen. Für Tests eignen sich die Testbilder unter „Store“.");
        Row(PrivacyRows, "Benachrichtigungen und Absturzberichte",
            "Popup-Hinweise erzeugt Windows lokal. Absturzberichte sammelt nur Windows selbst, sofern Sie das erlaubt haben; die App sendet keine eigenen Berichte.");

        Row(LegalRows, "Wofür die App gedacht ist",
            "Für Administratorinnen und Administratoren, Medizintechnik und IT-Support: zum Einrichten, Testen und zur Fehlersuche von DICOM-Verbindungen zwischen PACS, RIS, Modalitäten und Arbeitsplätzen.");
        Row(LegalRows, "Nicht für diagnostische Zwecke",
            "Die App ist kein Medizinprodukt im Sinne der Verordnung (EU) 2017/745 (MDR). Sie darf nicht zur Befundung, Diagnose, Therapieplanung oder für andere medizinische Entscheidungen verwendet werden. Die Bildanzeige im Viewer dient nur der technischen Kontrolle übertragener Daten.", warning: true);
        Row(LegalRows, "Keine Zertifizierung",
            "Die App ist weder von der NEMA noch von einer anderen Stelle zertifiziert oder geprüft und erhebt keinen Anspruch auf vollständige DICOM-Konformität. Ein DICOM Conformance Statement liegt nicht vor.");
        Row(LegalRows, "Marken",
            "DICOM® ist eine eingetragene Marke der National Electrical Manufacturers Association (NEMA) für ihre Normen zur digitalen Kommunikation medizinischer Informationen. Die Nennung erfolgt nur beschreibend; es besteht keine Verbindung zur NEMA. Windows ist eine Marke der Microsoft Corporation.");
        Row(LegalRows, "Lizenz und Haftung",
            "Privates, nicht-kommerzielles Open-Source-Projekt unter der MIT-Lizenz. Die Software wird ohne jede Gewährleistung bereitgestellt; die Nutzung erfolgt auf eigene Verantwortung. Verwendete Bibliotheken: fo-dicom und fo-dicom.Codecs (MS-PL), Avalonia, Velopack und CommunityToolkit (MIT) – siehe Lizenzen.");
    }

    private static void Row(Panel panel, string title, string text, bool warning = false)
    {
        var titleBlock = new TextBlock { Text = title, FontWeight = FontWeight.Bold };
        if (warning) titleBlock.Classes.Add("warning");
        if (warning) titleBlock.FontSize = 14;
        panel.Children.Add(new StackPanel
        {
            Spacing = 2,
            Children = { titleBlock, new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Classes = { "secondary" } } },
        });
    }

    private void OnGitHub(object? sender, RoutedEventArgs e) => Shell.OpenUri(UpdateService.RepositoryUrl);
    private void OnWebsite(object? sender, RoutedEventArgs e) => Shell.OpenUri("https://masenft.github.io/DICOMTestTool/de/");
    private void OnCheck(object? sender, RoutedEventArgs e) => _ = _state.Updater.CheckAsync(userInitiated: true);
    private void OnShowRelease(object? sender, RoutedEventArgs e) => _state.Updater.ShowReleaseWindow = true;
    private void OnUnskip(object? sender, RoutedEventArgs e) => _state.Updater.SkippedVersion = "";
    private void OnDataFolder(object? sender, RoutedEventArgs e) => Shell.OpenFolder(AppInfo.DataDirectory);
    private void OnReceiveFolder(object? sender, RoutedEventArgs e) => Shell.OpenFolder(_state.ScpDirectory);
    private void OnLogs(object? sender, RoutedEventArgs e) => new LogBrowserWindow().ShowFor(this);

    private void OnLicenses(object? sender, RoutedEventArgs e)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "THIRD-PARTY-NOTICES.txt");
        if (File.Exists(path)) Shell.OpenFile(path);
        else Shell.OpenUri(UpdateService.RepositoryUrl + "/blob/main/windows/licenses/THIRD-PARTY-NOTICES.txt");
    }

    private async void OnReset(object? sender, RoutedEventArgs e)
    {
        if (await Ui.ConfirmAsync(this, "Alle Einstellungen zurücksetzen?",
                "Gespeicherte Knoten und Einstellungen gehen verloren. SCP und Watchdog werden gestoppt.", "Zurücksetzen"))
            _state.ResetToDefaults();
    }
}
