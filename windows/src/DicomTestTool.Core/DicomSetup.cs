using FellowOakDicom;
using FellowOakDicom.Imaging;
using FellowOakDicom.Imaging.NativeCodec;

namespace DicomTestTool.Core;

/// <summary>Initialises fo-dicom once: native codecs (JPEG, JPEG-LS, JPEG 2000, RLE) and raw image rendering.</summary>
public static class DicomSetup
{
    private static int _done;

    public static void Initialize()
    {
        if (Interlocked.Exchange(ref _done, 1) == 1) return;
        new DicomSetupBuilder()
            .RegisterServices(s => s
                .AddFellowOakDicom()
                .AddTranscoderManager<NativeTranscoderManager>()
                .AddImageManager<RawImageManager>())
            .SkipValidation()
            .Build();
    }
}
