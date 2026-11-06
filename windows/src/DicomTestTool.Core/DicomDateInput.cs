using System.Globalization;

namespace DicomTestTool.Core;

/// <summary>Parses user date input (single date or range) into DICOM DA – same rules as the macOS app.</summary>
public static class DicomDateInput
{
    public static string ToDicom(DateTime d) => d.ToString("yyyyMMdd", CultureInfo.InvariantCulture);

    /// <summary>Accepts TTMMJJJJ, JJJJMMTT, TT.MM.JJJJ, T.M.JJ, JJJJ-MM-TT; returns JJJJMMTT or null.</summary>
    public static string? Date(string raw)
    {
        var s = raw.Trim();
        if (s.Length == 8 && s.All(char.IsAsciiDigit))
        {
            int Num(int start, int len) => int.Parse(s.AsSpan(start, len), CultureInfo.InvariantCulture);
            // JJJJMMTT if it is a plausible date, otherwise TTMMJJJJ (e.g. 04111970).
            if (Num(0, 4) is >= 1800 and <= 2199 && Build(Num(0, 4), Num(4, 2), Num(6, 2)) is { } a) return a;
            if (Num(4, 4) is >= 1800 and <= 2199 && Build(Num(4, 4), Num(2, 2), Num(0, 2)) is { } b) return b;
            return null;
        }
        var iso = s.Split('-');
        if (iso.Length == 3 && iso[0].Length == 4 && int.TryParse(iso[0], out var y1) && int.TryParse(iso[1], out var m1) && int.TryParse(iso[2], out var d1))
            return Build(y1, m1, d1);
        var parts = s.Split('.', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 3 && int.TryParse(parts[0], out var d) && int.TryParse(parts[1], out var m) && int.TryParse(parts[2], out var y))
        {
            if (parts[2].Length == 2) y += y > 50 ? 1900 : 2000;
            return Build(y, m, d);
        }
        return null;
    }

    private static string? Build(int y, int m, int d)
    {
        if (y < 1 || y > 9999 || m < 1 || m > 12 || d < 1 || d > DateTime.DaysInMonth(y, m)) return null; // rejects 31.02.
        return $"{y:0000}{m:00}{d:00}";
    }

    /// <summary>Splits "A-B", "A - B", "A-" and "-B"; ISO dates (with dashes) are only accepted as single values.</summary>
    private static (string, string)? Split(string s)
    {
        var i = s.IndexOf(" - ", StringComparison.Ordinal);
        if (i >= 0) return (s[..i], s[(i + 3)..]);
        if (s.Count(c => c == '-') != 1) return null;
        i = s.IndexOf('-');
        return (s[..i], s[(i + 1)..]);
    }

    public static string Normalize(string? raw, bool allowsRange)
    {
        var s = (raw ?? "").Trim();
        if (s.Length == 0) return "";
        if (Date(s) is { } d) return d;
        if (allowsRange && Split(s) is (string a, string b))
        {
            var na = string.IsNullOrWhiteSpace(a) ? "" : Date(a);
            var nb = string.IsNullOrWhiteSpace(b) ? "" : Date(b);
            if (na != null && nb != null && !(na.Length == 0 && nb.Length == 0)) return $"{na}-{nb}";
        }
        return s; // unknown input (e.g. wildcards) is passed on unchanged
    }

    public static (DateTime? From, DateTime? To, bool IsRange) Parse(string? raw)
    {
        var s = Normalize(raw, true);
        static DateTime? P(string x) => DateTime.TryParseExact(x, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;
        if (Split(s) is (string a, string b)) return (P(a), P(b), true);
        var one = P(s);
        return (one, one, false);
    }

    /// <summary>DICOM value → what the field shows: "04.11.2026" or "01.11.2026 - 04.11.2026".</summary>
    public static string Display(string value)
    {
        if (value.Length == 8 && Date(value) == value) return DicomNames.FormatDA(value);
        if (Split(value) is (string a, string b) && (a.Length == 0 || Date(a) == a) && (b.Length == 0 || Date(b) == b))
            return $"{(a.Length == 0 ? "" : DicomNames.FormatDA(a))} - {(b.Length == 0 ? "" : DicomNames.FormatDA(b))}".Trim();
        return value;
    }

    public static string Describe(string? raw)
    {
        var s = Normalize(raw, true);
        if (s.Length == 0) return "Kein Datum: alle Einträge";
        if (Split(s) is (string a, string b))
            return $"Zeitraum {(a.Length == 0 ? "…" : DicomNames.FormatDA(a))} bis {(b.Length == 0 ? "…" : DicomNames.FormatDA(b))}";
        return s.Length == 8 ? DicomNames.FormatDA(s) : s;
    }
}
