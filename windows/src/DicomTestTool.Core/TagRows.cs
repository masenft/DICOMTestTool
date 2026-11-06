using System.Text;
using FellowOakDicom;

namespace DicomTestTool.Core;

public sealed record TagRow(int Depth, string Tag, string VR, string Name, string Length, string Value);

/// <summary>Flattens a dataset (including sequences) into rows for the tag dump.</summary>
public static class TagRows
{
    public static List<TagRow> Flatten(DicomDataset ds, int depth = 0)
    {
        var rows = new List<TagRow>();
        var indent = new string(' ', depth * 4);
        foreach (var item in ds.OrderBy(i => i.Tag))
        {
            var tag = $"({item.Tag.Group:X4},{item.Tag.Element:X4})";
            var name = item.Tag.DictionaryEntry?.Name ?? "";
            if (item.Tag.IsPrivate && string.IsNullOrEmpty(name)) name = "Private Tag";
            if (string.IsNullOrEmpty(name) || name == "Unknown") name = item.Tag.IsPrivate ? "Private Tag" : "";
            switch (item)
            {
                case DicomSequence seq:
                    rows.Add(new TagRow(depth, indent + tag, "SQ", name, "", $"{seq.Items.Count} Item(s)"));
                    for (var i = 0; i < seq.Items.Count; i++)
                    {
                        rows.Add(new TagRow(depth + 1, indent + $"  > Item {i + 1}", "", "", "", ""));
                        rows.AddRange(Flatten(seq.Items[i], depth + 1));
                    }
                    break;
                case DicomFragmentSequence frag:
                    rows.Add(new TagRow(depth, indent + tag, item.ValueRepresentation.Code, name, "undef.",
                        $"{frag.Fragments.Count} Fragment(e), {DicomNames.FormatSize(frag.Fragments.Sum(f => (long)f.Size))}"));
                    break;
                case DicomElement el:
                    rows.Add(new TagRow(depth, indent + tag, el.ValueRepresentation.Code, name, el.Buffer.Size.ToString(), DisplayValue(ds, el)));
                    break;
                default:
                    rows.Add(new TagRow(depth, indent + tag, item.ValueRepresentation.Code, name, "", ""));
                    break;
            }
        }
        return rows;
    }

    private static string DisplayValue(DicomDataset ds, DicomElement el)
    {
        try
        {
            if (el.Tag == DicomTag.PixelData || el.Buffer.Size > 4096 && !el.ValueRepresentation.IsString)
                return $"<{DicomNames.FormatSize(el.Buffer.Size)} Binärdaten>";
            if (el.Count == 0) return "";
            var vr = el.ValueRepresentation;
            string value;
            if (vr.IsString)
            {
                value = string.Join("\\", ds.GetValues<string>(el.Tag));
                if (vr == DicomVR.UI) value += UidSuffix(value);
            }
            else if (vr == DicomVR.AT)
            {
                value = string.Join("\\", ds.GetValues<DicomTag>(el.Tag).Select(t => $"({t.Group:X4},{t.Element:X4})"));
            }
            else
            {
                var values = ds.GetValues<object>(el.Tag);
                value = string.Join("\\", values.Take(32).Select(v => Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture)));
                if (values.Length > 32) value += $"\\… ({values.Length} Werte)";
            }
            return value.Length > 512 ? value[..512] + " …" : value;
        }
        catch
        {
            return "<nicht darstellbar>";
        }
    }

    private static string UidSuffix(string uid)
    {
        var sop = DicomNames.SopClass(uid);
        if (sop != uid && sop.Length > 0) return $"  [{sop}]";
        var ts = DicomNames.TransferSyntax(uid);
        return ts != uid && ts.Length > 0 ? $"  [{ts}]" : "";
    }

    public static string ToText(IEnumerable<TagRow> rows)
    {
        var sb = new StringBuilder();
        foreach (var r in rows) sb.AppendLine($"{r.Tag,-28} {r.VR,-2} {r.Name,-40} {r.Length,6}  {r.Value}");
        return sb.ToString();
    }
}
