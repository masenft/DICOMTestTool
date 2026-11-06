using Avalonia.Controls;
using Avalonia.Interactivity;
using DicomTestTool.Services;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Views;

public partial class GeneralView : UserControl
{
    public GeneralView()
    {
        InitializeComponent();
        DataContext = AppState.Shared;
        AttachedToVisualTree += (_, _) => AppState.Shared.RefreshNotificationPermission();
    }

    private void OnTest(object? sender, RoutedEventArgs e) => AppState.Shared.SendTestNotification();
    private void OnSettings(object? sender, RoutedEventArgs e) => Notifier.OpenSettings();
}
