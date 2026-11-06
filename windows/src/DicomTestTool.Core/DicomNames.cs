using FellowOakDicom;
using FellowOakDicom.Network;

namespace DicomTestTool.Core;

/// <summary>Display names and texts, identical to the macOS app where possible.</summary>
public static class DicomNames
{
    public const string Verification = "1.2.840.10008.1.1";
    public const string PatientRootFind = "1.2.840.10008.5.1.4.1.2.1.1";
    public const string PatientRootMove = "1.2.840.10008.5.1.4.1.2.1.2";
    public const string StudyRootFind = "1.2.840.10008.5.1.4.1.2.2.1";
    public const string StudyRootMove = "1.2.840.10008.5.1.4.1.2.2.2";
    public const string ModalityWorklistFind = "1.2.840.10008.5.1.4.31";
    public const string SecondaryCapture = "1.2.840.10008.5.1.4.1.1.7";

    private static readonly Dictionary<string, string> SopNames = new()
    {
        [Verification] = "Verification",
        [PatientRootFind] = "Patient Root Q/R – FIND",
        [PatientRootMove] = "Patient Root Q/R – MOVE",
        [StudyRootFind] = "Study Root Q/R – FIND",
        [StudyRootMove] = "Study Root Q/R – MOVE",
        [ModalityWorklistFind] = "Modality Worklist – FIND",
        ["1.2.840.10008.5.1.4.1.1.1"] = "CR Image Storage",
        ["1.2.840.10008.5.1.4.1.1.1.1"] = "Digital X-Ray Image Storage – Presentation",
        ["1.2.840.10008.5.1.4.1.1.1.1.1"] = "Digital X-Ray Image Storage – Processing",
        ["1.2.840.10008.5.1.4.1.1.1.2"] = "Digital Mammography Image Storage – Presentation",
        ["1.2.840.10008.5.1.4.1.1.1.3"] = "Digital Intra-Oral X-Ray Image Storage – Presentation",
        ["1.2.840.10008.5.1.4.1.1.2"] = "CT Image Storage",
        ["1.2.840.10008.5.1.4.1.1.2.1"] = "Enhanced CT Image Storage",
        ["1.2.840.10008.5.1.4.1.1.3.1"] = "Ultrasound Multi-frame Image Storage",
        ["1.2.840.10008.5.1.4.1.1.4"] = "MR Image Storage",
        ["1.2.840.10008.5.1.4.1.1.4.1"] = "Enhanced MR Image Storage",
        ["1.2.840.10008.5.1.4.1.1.6.1"] = "Ultrasound Image Storage",
        [SecondaryCapture] = "Secondary Capture Image Storage",
        ["1.2.840.10008.5.1.4.1.1.7.4"] = "Multi-frame True Color SC Image Storage",
        ["1.2.840.10008.5.1.4.1.1.11.1"] = "Grayscale Softcopy Presentation State",
        ["1.2.840.10008.5.1.4.1.1.12.1"] = "X-Ray Angiographic Image Storage",
        ["1.2.840.10008.5.1.4.1.1.13.1.3"] = "Breast Tomosynthesis Image Storage",
        ["1.2.840.10008.5.1.4.1.1.20"] = "Nuclear Medicine Image Storage",
        ["1.2.840.10008.5.1.4.1.1.77.1.4"] = "VL Photographic Image Storage",
        ["1.2.840.10008.5.1.4.1.1.88.11"] = "Basic Text SR",
        ["1.2.840.10008.5.1.4.1.1.88.22"] = "Enhanced SR",
        ["1.2.840.10008.5.1.4.1.1.88.33"] = "Comprehensive SR",
        ["1.2.840.10008.5.1.4.1.1.88.59"] = "Key Object Selection Document",
        ["1.2.840.10008.5.1.4.1.1.104.1"] = "Encapsulated PDF Storage",
        ["1.2.840.10008.5.1.4.1.1.128"] = "PET Image Storage",
        ["1.2.840.10008.5.1.4.1.1.481.1"] = "RT Image Storage",
        ["1.2.840.10008.5.1.4.1.1.481.2"] = "RT Dose Storage",
        ["1.2.840.10008.5.1.4.1.1.481.3"] = "RT Structure Set Storage",
        ["1.2.840.10008.5.1.4.1.1.481.5"] = "RT Plan Storage",
    };

    private static readonly Dictionary<string, string> TsNames = new()
    {
        ["1.2.840.10008.1.2"] = "Implicit VR Little Endian",
        ["1.2.840.10008.1.2.1"] = "Explicit VR Little Endian",
        ["1.2.840.10008.1.2.1.99"] = "Deflated Explicit VR Little Endian",
        ["1.2.840.10008.1.2.2"] = "Explicit VR Big Endian",
        ["1.2.840.10008.1.2.4.50"] = "JPEG Baseline (Process 1)",
        ["1.2.840.10008.1.2.4.51"] = "JPEG Extended (Process 2 & 4)",
        ["1.2.840.10008.1.2.4.57"] = "JPEG Lossless (Process 14)",
        ["1.2.840.10008.1.2.4.70"] = "JPEG Lossless SV1",
        ["1.2.840.10008.1.2.4.80"] = "JPEG-LS Lossless",
        ["1.2.840.10008.1.2.4.81"] = "JPEG-LS Near-Lossless",
        ["1.2.840.10008.1.2.4.90"] = "JPEG 2000 Lossless",
        ["1.2.840.10008.1.2.4.91"] = "JPEG 2000",
        ["1.2.840.10008.1.2.4.100"] = "MPEG2 Main Profile",
        ["1.2.840.10008.1.2.4.102"] = "MPEG-4 AVC/H.264",
        ["1.2.840.10008.1.2.4.201"] = "HTJ2K Lossless",
        ["1.2.840.10008.1.2.4.203"] = "HTJ2K",
        ["1.2.840.10008.1.2.5"] = "RLE Lossless",
    };

    public static string SopClass(string? uid)
    {
        if (string.IsNullOrEmpty(uid)) return "";
        if (SopNames.TryGetValue(uid, out var n)) return n;
        try { var u = DicomUID.Parse(uid); if (!string.IsNullOrEmpty(u.Name) && u.Name != uid) return u.Name; } catch { }
        return uid;
    }

    public static string TransferSyntax(string? uid)
    {
        if (string.IsNullOrEmpty(uid)) return "";
        if (TsNames.TryGetValue(uid, out var n)) return n;
        try { var u = DicomUID.Parse(uid); if (!string.IsNullOrEmpty(u.Name) && u.Name != uid) return u.Name; } catch { }
        return uid;
    }

    public static bool IsPending(ushort s) => s is 0xFF00 or 0xFF01;
    public static bool IsSuccess(ushort s) => s == 0x0000;
    public static bool IsWarning(ushort s) => s == 0x0001 || (s & 0xF000) == 0xB000 || s == 0x0107 || s == 0x0116;

    public static string Status(ushort s)
    {
        var hex = $"0x{s:X4}";
        return s switch
        {
            0x0000 => $"{hex} Erfolg",
            0xFF00 => $"{hex} Ausstehend (Pending)",
            0xFF01 => $"{hex} Ausstehend (optionale Keys nicht unterstützt)",
            0xFE00 => $"{hex} Abgebrochen (Cancel)",
            0x0105 => $"{hex} Attribut nicht erkannt",
            0x0107 => $"{hex} Warnung: Attributliste fehlerhaft",
            0x0110 => $"{hex} Verarbeitungsfehler",
            0x0111 => $"{hex} Doppelte SOP Instance",
            0x0112 => $"{hex} Keine solche SOP Instance",
            0x0116 => $"{hex} Warnung: Attributwert außerhalb des Bereichs",
            0x0117 => $"{hex} Ungültige SOP Instance",
            0x0118 => $"{hex} Keine solche SOP-Klasse",
            0x0122 => $"{hex} SOP-Klasse nicht unterstützt",
            0x0124 => $"{hex} Nicht autorisiert",
            0x0211 => $"{hex} Operation nicht erkannt",
            0x0212 => $"{hex} Fehlerhafter Typ",
            >= 0xA700 and <= 0xA7FF => $"{hex} Fehler: Ressourcen erschöpft",
            0xA801 => $"{hex} Fehler: Move-Ziel unbekannt",
            >= 0xA900 and <= 0xA9FF => $"{hex} Fehler: Datensatz passt nicht zur SOP-Klasse",
            0xB000 => $"{hex} Warnung: Sub-Operationen mit Fehlern",
            >= 0xB000 and <= 0xBFFF => $"{hex} Warnung",
            >= 0xC000 and <= 0xCFFF => $"{hex} Fehler: kann nicht verarbeitet werden",
            _ => hex,
        };
    }

    public static string PresentationContextResult(DicomPresentationContextResult r) => r switch
    {
        DicomPresentationContextResult.Accept => "akzeptiert",
        DicomPresentationContextResult.RejectUser => "abgelehnt (Benutzer)",
        DicomPresentationContextResult.RejectNoReason => "abgelehnt (ohne Grund)",
        DicomPresentationContextResult.RejectAbstractSyntaxNotSupported => "abgelehnt: SOP-Klasse nicht unterstützt",
        DicomPresentationContextResult.RejectTransferSyntaxesNotSupported => "abgelehnt: Transfer Syntax nicht unterstützt",
        _ => r.ToString(),
    };

    public static string RejectReason(DicomRejectSource source, DicomRejectReason reason)
    {
        var s = (int)source; var r = (int)reason & 0x0F; // fo-dicom encodes the reason as (source << 4) | reason
        return (s, r) switch
        {
            (1, 1) => "kein Grund angegeben (Service-User)",
            (1, 2) => "Application Context nicht unterstützt",
            (1, 3) => "Calling AE-Titel nicht erkannt",
            (1, 7) => "Called AE-Titel nicht erkannt",
            (2, 1) => "kein Grund angegeben (Service-Provider ACSE)",
            (2, 2) => "Protokollversion nicht unterstützt",
            (3, 1) => "temporäre Überlastung",
            (3, 2) => "lokales Limit überschritten",
            _ => $"Quelle {s}, Grund {r}",
        };
    }

    /// <summary>"MUSTERMANN^MAX" → "MUSTERMANN, MAX".</summary>
    public static string FormatPN(string? s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        var first = s.Split('=')[0];
        return string.Join(", ", first.Split('^').Where(p => p.Length > 0));
    }

    /// <summary>DA "20261103" → "03.11.2026".</summary>
    public static string FormatDA(string? s) =>
        s is { Length: 8 } ? $"{s[6..8]}.{s[4..6]}.{s[..4]}" : s ?? "";

    public static string FormatTM(string? s) =>
        s is { Length: >= 4 } ? $"{s[..2]}:{s[2..4]}" : s ?? "";

    public static string FormatSize(long bytes)
    {
        string[] units = ["Byte", "KB", "MB", "GB"];
        double v = bytes; var i = 0;
        while (v >= 1000 && i < units.Length - 1) { v /= 1000; i++; }
        return i == 0 ? $"{bytes} Byte" : $"{v:0.#} {units[i]}";
    }
}
