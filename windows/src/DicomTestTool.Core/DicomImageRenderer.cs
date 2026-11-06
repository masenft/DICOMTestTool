using FellowOakDicom;
using FellowOakDicom.Imaging;

namespace DicomTestTool.Core;

/// <summary>Renders DICOM frames to BGRA pixels with windowing (all codecs from fo-dicom.Codecs).</summary>
public sealed class DicomImageRenderer
{
    private readonly DicomImage _image;

    public int Width => _image.Width;
    public int Height => _image.Height;
    public int FrameCount => Math.Max(1, _image.NumberOfFrames);
    public bool IsGrayscale => _image.IsGrayscale;
    public double DefaultCenter { get; }
    public double DefaultWidth { get; }

    public DicomImageRenderer(DicomDataset dataset)
    {
        DicomSetup.Initialize();
        if (!dataset.Contains(DicomTag.PixelData)) throw new DicomToolException("Keine Pixeldaten vorhanden");
        _image = new DicomImage(dataset);
        DefaultCenter = _image.WindowCenter;
        DefaultWidth = _image.WindowWidth;
    }

    /// <summary>Returns BGRA8888 pixels (premultiplied alpha = opaque) for one frame.</summary>
    public int[] Render(int frame, double? center = null, double? width = null)
    {
        if (IsGrayscale)
        {
            if (width is { } w) _image.WindowWidth = Math.Max(1, w);
            if (center is { } c) _image.WindowCenter = c;
        }
        using var img = _image.RenderImage(Math.Clamp(frame, 0, FrameCount - 1));
        var src = img.Pixels.Data;
        var copy = new int[src.Length];
        Array.Copy(src, copy, src.Length);
        return copy;
    }

    public double CurrentCenter => _image.WindowCenter;
    public double CurrentWidth => _image.WindowWidth;
}
