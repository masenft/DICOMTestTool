using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;
using DicomTestTool.Controls;
using DicomTestTool.Core;
using DicomTestTool.ViewModels;
using FellowOakDicom;

namespace DicomTestTool.Views;

public partial class ViewerView : UserControl
{
    private readonly AppState _state = AppState.Shared;
    private string? _path;
    private List<TagRow> _rows = [];
    private DicomImageRenderer? _renderer;
    private WriteableBitmap? _bitmap;
    private double _center, _width;
    private int _frame;
    private Point? _dragStart;
    private (double C, double W) _dragOrigin;

    public ViewerView()
    {
        InitializeComponent();
        AddHandler(DragDrop.DragOverEvent, (_, e) => e.DragEffects = DragDropEffects.Copy);
        AddHandler(DragDrop.DropEvent, (_, e) => { if (Ui.DroppedPaths(e).FirstOrDefault() is { } p) Load(p); });
        _state.ViewerFileRequested += p => Dispatcher.UIThread.Post(() => Load(p));
        Filter.TextChanged += (_, _) => ApplyFilter();
        FrameSlider.PropertyChanged += (_, e) =>
        {
            if (e.Property == Slider.ValueProperty && _renderer != null && (int)FrameSlider.Value != _frame)
            {
                _frame = (int)FrameSlider.Value;
                Render();
            }
        };
        ImageArea.PointerPressed += OnPointerPressed;
        ImageArea.PointerMoved += OnPointerMoved;
        ImageArea.PointerReleased += (_, _) => _dragStart = null;
    }

    private async void OnOpen(object? sender, RoutedEventArgs e)
    {
        if ((await Ui.OpenFilesAsync(this, "DICOM-Datei öffnen", multiple: false)).FirstOrDefault() is { } p) Load(p);
    }

    private void OnSend(object? sender, RoutedEventArgs e)
    {
        if (_path != null) _state.SendWithStore([_path]);
    }

    public void Load(string path)
    {
        _path = path;
        _renderer = null;
        _bitmap = null;
        _frame = 0;
        Picture.Source = null;
        ImageControls.IsVisible = false;
        ParseWarning.IsVisible = false;
        FileName.Text = Path.GetFileName(path);
        SendButton.IsEnabled = true;
        try
        {
            var file = DicomFile.Open(path, FileReadOption.ReadAll);
            var ts = file.FileMetaInfo.TransferSyntax?.UID.UID ?? file.Dataset.InternalTransferSyntax.UID.UID;
            FileInfo.Text = $"· {DicomNames.TransferSyntax(ts)} · {DicomNames.SopClass(file.Dataset.GetSingleValueOrDefault(DicomTag.SOPClassUID, ""))}";
            _rows = TagRows.Flatten(file.FileMetaInfo);
            _rows.AddRange(TagRows.Flatten(file.Dataset));
            ApplyFilter();
            if (!file.Dataset.Contains(DicomTag.PixelData))
            {
                ImageMessage.Text = "Keine Bilddaten";
                ImageMessage.IsVisible = true;
                return;
            }
            try
            {
                _renderer = new DicomImageRenderer(file.Dataset);
                _center = _renderer.DefaultCenter;
                _width = _renderer.DefaultWidth;
                FramePanel.IsVisible = _renderer.FrameCount > 1;
                FrameSlider.Maximum = Math.Max(0, _renderer.FrameCount - 1);
                FrameSlider.Value = 0;
                SizeText.Text = $"{_renderer.Width}×{_renderer.Height}";
                WindowText.IsVisible = ResetButton.IsVisible = DragHint.IsVisible = _renderer.IsGrayscale;
                ImageControls.IsVisible = true;
                Render();
            }
            catch (Exception ex)
            {
                ImageMessage.Text = "Bild kann nicht dargestellt werden: " + ex.Message;
                ImageMessage.IsVisible = true;
            }
        }
        catch (Exception ex)
        {
            _rows = [];
            ApplyFilter();
            FileInfo.Text = "";
            ImageMessage.Text = "Datei kann nicht gelesen werden: " + ex.Message;
            ImageMessage.IsVisible = true;
            ParseWarning.Text = "Warnung: keine gültige DICOM-Datei";
            ParseWarning.IsVisible = true;
        }
    }

    private void ApplyFilter()
    {
        var f = Filter.Text?.Trim() ?? "";
        Tags.ItemsSource = f.Length == 0 ? _rows : _rows.Where(r => DatasetWindow.Matches(r, f)).ToList();
    }

    private void Render()
    {
        if (_renderer == null) return;
        try
        {
            var px = _renderer.Render(_frame, _center, _width);
            var size = new PixelSize(_renderer.Width, _renderer.Height);
            if (_bitmap == null || _bitmap.PixelSize != size)
                _bitmap = new WriteableBitmap(size, new Vector(96, 96), PixelFormat.Bgra8888, AlphaFormat.Opaque);
            using (var fb = _bitmap.Lock())
            {
                for (var y = 0; y < size.Height; y++)
                    Marshal.Copy(px, y * size.Width, fb.Address + y * fb.RowBytes, size.Width);
            }
            Picture.Source = null;
            Picture.Source = _bitmap;
            ImageMessage.IsVisible = false;
            WindowText.Text = $"W: {_width:0}  L: {_center:0}";
            FrameText.Text = $"Frame {_frame + 1}/{_renderer.FrameCount}";
        }
        catch (Exception ex)
        {
            Picture.Source = null;
            ImageMessage.Text = "Bild kann nicht dargestellt werden: " + ex.Message;
            ImageMessage.IsVisible = true;
        }
    }

    private void OnPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (_renderer is not { IsGrayscale: true }) return;
        _dragStart = e.GetPosition(ImageArea);
        _dragOrigin = (_center, _width);
    }

    private void OnPointerMoved(object? sender, PointerEventArgs e)
    {
        if (_dragStart is not { } start || !e.GetCurrentPoint(ImageArea).Properties.IsLeftButtonPressed) return;
        var p = e.GetPosition(ImageArea);
        var k = Math.Max(_dragOrigin.W, 1) / 300;
        _width = Math.Max(1, _dragOrigin.W + (p.X - start.X) * k);
        _center = _dragOrigin.C + (p.Y - start.Y) * k;
        Render();
    }

    private void OnResetWindow(object? sender, RoutedEventArgs e)
    {
        if (_renderer == null) return;
        _center = _renderer.DefaultCenter;
        _width = _renderer.DefaultWidth;
        Render();
    }

    private async void OnExport(object? sender, RoutedEventArgs e)
    {
        if (_bitmap == null) return;
        var name = Path.GetFileNameWithoutExtension(_path ?? "bild") + ".png";
        if (await Ui.SaveFileAsync(this, name, "PNG-Bild", "png") is not { } dest) return;
        try
        {
            _bitmap.Save(dest);
            _state.Append("Viewer", "PNG exportiert: " + dest);
        }
        catch (Exception ex)
        {
            _state.Append("Viewer", "PNG-Export fehlgeschlagen: " + ex.Message, error: true);
        }
    }
}
