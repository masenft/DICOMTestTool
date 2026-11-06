using Avalonia;
using Avalonia.Controls;
using Avalonia.Data;
using Avalonia.Input;
using DicomTestTool.Core;

namespace DicomTestTool.Controls;

/// <summary>Date input as TTMMJJJJ / TT.MM.JJJJ (ranges with „-“) plus a calendar – the value is a DICOM DA string.</summary>
public partial class DateField : UserControl
{
    public static readonly StyledProperty<string> LabelProperty = AvaloniaProperty.Register<DateField, string>(nameof(Label), "");
    public static readonly StyledProperty<string> ValueProperty =
        AvaloniaProperty.Register<DateField, string>(nameof(Value), "", defaultBindingMode: BindingMode.TwoWay);
    public static readonly StyledProperty<bool> AllowsRangeProperty = AvaloniaProperty.Register<DateField, bool>(nameof(AllowsRange));
    public static readonly StyledProperty<double> FieldWidthProperty = AvaloniaProperty.Register<DateField, double>(nameof(FieldWidth), 110);

    public string Label { get => GetValue(LabelProperty); set => SetValue(LabelProperty, value); }
    /// <summary>DICOM value: "" | JJJJMMTT | JJJJMMTT-JJJJMMTT (or unrecognised raw input, passed on unchanged).</summary>
    public string Value { get => GetValue(ValueProperty); set => SetValue(ValueProperty, value); }
    public bool AllowsRange { get => GetValue(AllowsRangeProperty); set => SetValue(AllowsRangeProperty, value); }
    public double FieldWidth { get => GetValue(FieldWidthProperty); set => SetValue(FieldWidthProperty, value); }

    private bool _updating;

    public DateField()
    {
        InitializeComponent();
        Input.LostFocus += (_, _) => Commit();
        Input.KeyDown += (_, e) => { if (e.Key == Key.Enter) Commit(); };
        Input.TextChanged += (_, _) =>
        {
            if (_updating) return;
            _updating = true;
            Value = DicomDateInput.Normalize(Input.Text, AllowsRange);
            _updating = false;
            Hint.Text = DicomDateInput.Describe(Input.Text);
        };
        Cal.SelectedDatesChanged += (_, _) => OnCalendar();
        CalendarButton.Flyout!.Opened += (_, _) => SyncCalendar();
        Rebuild();
    }

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == LabelProperty) LabelText.Text = Label;
        else if (change.Property == FieldWidthProperty) Input.Width = FieldWidth;
        else if (change.Property == AllowsRangeProperty) Rebuild();
        else if (change.Property == ValueProperty && !_updating)
        {
            _updating = true;
            Input.Text = DicomDateInput.Display(Value ?? "");
            _updating = false;
        }
    }

    private void Rebuild()
    {
        Input.Watermark = AllowsRange ? "TT.MM.JJJJ - TT.MM.JJJJ" : "TT.MM.JJJJ";
        if (AllowsRange && Input.Width < 215) Input.Width = Math.Max(FieldWidth, 215);
        Cal.SelectionMode = AllowsRange ? CalendarSelectionMode.SingleRange : CalendarSelectionMode.SingleDate;
        Quick.Children.Clear();
        var today = DateTime.Today;
        AddQuick("Heute", today, today);
        AddQuick("Gestern", today.AddDays(-1), today.AddDays(-1));
        if (AllowsRange)
        {
            AddQuick("Letzte 7 Tage", today.AddDays(-6), today);
            AddQuick("Letzte 30 Tage", today.AddDays(-29), today);
        }
        var clear = new Button { Content = "Leeren", Margin = new Thickness(2) };
        clear.Click += (_, _) => { Value = ""; CalendarButton.Flyout?.Hide(); };
        Quick.Children.Add(clear);
    }

    private void AddQuick(string title, DateTime from, DateTime to)
    {
        var b = new Button { Content = title, Margin = new Thickness(2) };
        b.Click += (_, _) => { Set(from, to); CalendarButton.Flyout?.Hide(); };
        Quick.Children.Add(b);
    }

    private void Commit()
    {
        _updating = true;
        Value = DicomDateInput.Normalize(Input.Text, AllowsRange);
        Input.Text = DicomDateInput.Display(Value);
        _updating = false;
    }

    private bool _syncingCalendar;

    private void SyncCalendar()
    {
        _syncingCalendar = true;
        var (from, to, _) = DicomDateInput.Parse(Value);
        Cal.SelectedDates.Clear();
        if (from is { } f)
        {
            Cal.DisplayDate = f;
            if (AllowsRange && to is { } t && t >= f) Cal.SelectedDates.AddRange(f, t);
            else Cal.SelectedDate = f;
        }
        Hint.Text = DicomDateInput.Describe(Value);
        _syncingCalendar = false;
    }

    private void OnCalendar()
    {
        if (_syncingCalendar || Cal.SelectedDates.Count == 0) return;
        var dates = Cal.SelectedDates.OrderBy(d => d).ToList();
        Set(dates[0], dates[^1]);
    }

    private void Set(DateTime from, DateTime to)
    {
        var a = DicomDateInput.ToDicom(from);
        var b = DicomDateInput.ToDicom(to);
        Value = AllowsRange && a != b ? $"{a}-{b}" : a;
        Hint.Text = DicomDateInput.Describe(Value);
    }
}
