using CommunityToolkit.Mvvm.ComponentModel;
using DicomTestTool.Core;
using DicomTestTool.ViewModels;
using Velopack;
using Velopack.Sources;

namespace DicomTestTool.Services;

/// <summary>Updates from GitHub Releases via Velopack (only in the installed version).</summary>
public sealed partial class UpdateService : ObservableObject
{
    private readonly AppState _state;
    private UpdateInfo? _info;
    private CancellationTokenSource? _timer;

    [ObservableProperty] private bool _isChecking;
    [ObservableProperty] private bool _isInstalling;
    [ObservableProperty] private string _statusText = "";
    [ObservableProperty] private string? _availableVersion;
    [ObservableProperty] private string _releaseNotes = "";
    [ObservableProperty] private bool _showReleaseWindow;

    public UpdateService(AppState state) => _state = state;

    public static string RepositoryUrl => $"https://github.com/{AppInfo.DefaultRepository}";

    public bool IsInstalled
    {
        get
        {
            try { return new UpdateManager(new GithubSource(RepositoryUrl, null, false)).IsInstalled; }
            catch { return false; }
        }
    }

    public bool AutoCheck
    {
        get => _state.Settings.UpdateAutoCheck;
        set { _state.Settings.UpdateAutoCheck = value; _state.SaveSettings(); OnPropertyChanged(); RestartTimer(); }
    }

    public bool IncludePrereleases
    {
        get => _state.Settings.UpdatePrerelease;
        set { _state.Settings.UpdatePrerelease = value; _state.SaveSettings(); OnPropertyChanged(); OnPropertyChanged(nameof(ChannelHint)); }
    }

    public string ChannelHint => IncludePrereleases
        ? "Auch Beta-Versionen werden angeboten. Beim Wechsel zurück zu Stabil bleibt Ihre Version; das nächste Update kommt, sobald Stabil neuer ist."
        : "Nur freigegebene, stabile Versionen werden angeboten.";

    public string SkippedVersion
    {
        get => _state.Settings.UpdateSkippedVersion;
        set { _state.Settings.UpdateSkippedVersion = value; _state.SaveSettings(); OnPropertyChanged(); OnPropertyChanged(nameof(HasSkippedVersion)); }
    }

    public bool HasSkippedVersion => !string.IsNullOrEmpty(SkippedVersion);

    public string Subtitle
    {
        get
        {
            var s = $"Version {AppInfo.Version}";
            if (_state.Settings.UpdateLastCheck is { } d) s += $" · zuletzt geprüft {d.LocalDateTime:dd.MM.yyyy HH:mm}";
            return s;
        }
    }

    public void StartAutomaticChecks() => RestartTimer();

    private void RestartTimer()
    {
        _timer?.Cancel();
        if (!AutoCheck) return;
        var cts = _timer = new CancellationTokenSource();
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(20), cts.Token);
                while (!cts.IsCancellationRequested)
                {
                    var last = _state.Settings.UpdateLastCheck;
                    if (last == null || DateTimeOffset.Now - last > TimeSpan.FromHours(24))
                        await Avalonia.Threading.Dispatcher.UIThread.InvokeAsync(() => CheckAsync(userInitiated: false));
                    await Task.Delay(TimeSpan.FromHours(1), cts.Token);
                }
            }
            catch (OperationCanceledException) { }
        });
    }

    private UpdateManager Manager() => new(new GithubSource(RepositoryUrl, null, IncludePrereleases));

    public async Task CheckAsync(bool userInitiated)
    {
        if (IsChecking || IsInstalling) return;
        var mgr = Manager();
        if (!mgr.IsInstalled)
        {
            StatusText = "Updates sind nur in der installierten Version verfügbar (Setup von GitHub), nicht in der portablen.";
            if (userInitiated) _state.Append("Update", StatusText);
            return;
        }
        IsChecking = true;
        StatusText = "Suche nach Updates …";
        try
        {
            _info = await mgr.CheckForUpdatesAsync();
            _state.Settings.UpdateLastCheck = DateTimeOffset.Now;
            _state.SaveSettings();
            OnPropertyChanged(nameof(Subtitle));
            if (_info == null)
            {
                AvailableVersion = null;
                StatusText = $"Sie verwenden die neueste Version ({AppInfo.Version}).";
                if (userInitiated) _state.Append("Update", StatusText);
                return;
            }
            var v = _info.TargetFullRelease.Version.ToString();
            AvailableVersion = v;
            ReleaseNotes = string.IsNullOrWhiteSpace(_info.TargetFullRelease.NotesMarkdown) ? "Keine Release Notes vorhanden." : _info.TargetFullRelease.NotesMarkdown;
            StatusText = $"Version {v} ist verfügbar.";
            _state.Append("Update", $"Neue Version {v} verfügbar");
            if (userInitiated || v != SkippedVersion)
            {
                ShowReleaseWindow = true;
                if (!userInitiated) _state.Notify(AppInfo.Name, $"Version {v} ist verfügbar.");
            }
        }
        catch (Exception e)
        {
            StatusText = "Update-Prüfung fehlgeschlagen: " + e.Message;
            _state.Append("Update", StatusText, error: true);
        }
        finally
        {
            IsChecking = false;
        }
    }

    public void Skip()
    {
        if (AvailableVersion != null) SkippedVersion = AvailableVersion;
        ShowReleaseWindow = false;
    }

    public async Task InstallAsync()
    {
        if (_info == null || IsInstalling) return;
        IsInstalling = true;
        try
        {
            var mgr = Manager();
            StatusText = "Lade Update …";
            await mgr.DownloadUpdatesAsync(_info, p => Avalonia.Threading.Dispatcher.UIThread.Post(() => StatusText = $"Lade Update … {p} %"));
            _state.Append("Update", $"Update {AvailableVersion} heruntergeladen, App wird neu gestartet");
            _state.PrepareForShutdown();
            mgr.ApplyUpdatesAndRestart(_info);
        }
        catch (Exception e)
        {
            StatusText = "Installation fehlgeschlagen: " + e.Message;
            _state.Append("Update", StatusText, error: true);
            IsInstalling = false;
        }
    }
}
