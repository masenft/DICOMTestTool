using Avalonia.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using DicomTestTool.Core;

namespace DicomTestTool.ViewModels;

/// <summary>A DICOM node with live watchdog status.</summary>
public sealed partial class NodeItem : ObservableObject
{
    public Guid Id { get; init; } = Guid.NewGuid();
    [ObservableProperty, NotifyPropertyChangedFor(nameof(Display))] private string _name = "";
    [ObservableProperty, NotifyPropertyChangedFor(nameof(Summary), nameof(Display), nameof(AeTooLong))] private string _aeTitle = "";
    [ObservableProperty, NotifyPropertyChangedFor(nameof(Summary), nameof(Display))] private string _host = "";
    [ObservableProperty, NotifyPropertyChangedFor(nameof(Summary), nameof(Display))] private int _port = 104;

    // Watchdog
    [ObservableProperty] private bool _watched;
    [ObservableProperty, NotifyPropertyChangedFor(nameof(StatusText), nameof(StatusBrush))] private bool? _watchOk;
    [ObservableProperty] private string _lastCheck = "";
    [ObservableProperty] private string _latency = "";
    [ObservableProperty] private int _failures;
    [ObservableProperty] private string _message = "";

    public event Action? Changed;

    partial void OnNameChanged(string value) => Changed?.Invoke();
    partial void OnAeTitleChanged(string value) => Changed?.Invoke();
    partial void OnHostChanged(string value) => Changed?.Invoke();
    partial void OnPortChanged(int value) => Changed?.Invoke();
    partial void OnWatchedChanged(bool value) => Changed?.Invoke();

    public string Summary => $"{AeTitle}@{Host}:{Port}";
    public string Display => $"{Name}  –  {Summary}";
    public bool AeTooLong => AeTitle.Length > 16;
    public string StatusText => WatchOk switch { null => "–", true => "OK", false => "Ausfall" };
    public IBrush StatusBrush => WatchOk switch { null => Brushes.Gray, true => Brushes.LimeGreen, false => Brushes.Red };

    public DicomNode ToNode() => new() { Id = Id, Name = Name, AeTitle = AeTitle, Host = Host, Port = Port };

    public static NodeItem From(DicomNode n) => new() { Id = n.Id, Name = n.Name, AeTitle = n.AeTitle, Host = n.Host, Port = n.Port };

    public void ResetWatch()
    {
        WatchOk = null; LastCheck = ""; Latency = ""; Failures = 0; Message = "";
    }
}
