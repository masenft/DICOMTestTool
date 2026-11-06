using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;
using DicomTestTool.Core;
using DicomTestTool.ViewModels;
using FellowOakDicom;

namespace DicomTestTool.Views;

public sealed class WorklistRow(DicomDataset ds)
{
    public DicomDataset Dataset { get; } = ds;
    private DicomDataset Sps => Dataset.TryGetSequence(DicomTag.ScheduledProcedureStepSequence, out var seq) && seq.Items.Count > 0 ? seq.Items[0] : new DicomDataset();
    private static string S(DicomDataset d, DicomTag t) => d.GetSingleValueOrDefault(t, "");
    public string Name => DicomNames.FormatPN(S(Dataset, DicomTag.PatientName));
    public string PatientId => S(Dataset, DicomTag.PatientID);
    public string BirthDate => DicomNames.FormatDA(S(Dataset, DicomTag.PatientBirthDate));
    public string Sex => S(Dataset, DicomTag.PatientSex);
    public string Accession => S(Dataset, DicomTag.AccessionNumber);
    public string Procedure { get { var p = S(Dataset, DicomTag.RequestedProcedureDescription); return p.Length > 0 ? p : S(Sps, DicomTag.ScheduledProcedureStepDescription); } }
    public string Modality => S(Sps, DicomTag.Modality);
    public string Scheduled => $"{DicomNames.FormatDA(S(Sps, DicomTag.ScheduledProcedureStepStartDate))} {DicomNames.FormatTM(S(Sps, DicomTag.ScheduledProcedureStepStartTime))}".Trim();
    public string Station => S(Sps, DicomTag.ScheduledStationAETitle);
}

public partial class WorklistView : UserControl
{
    private readonly AppState _state = AppState.Shared;
    private readonly ObservableCollection<WorklistRow> _rows = [];
    private bool _running;

    public WorklistView()
    {
        InitializeComponent();
        Grid.ItemsSource = _rows;
        Date.Value = DicomDateInput.ToDicom(DateTime.Today);
        Grid.DoubleTapped += (_, _) => { if (Grid.SelectedItem is WorklistRow r) ShowDetails(r); };
        Grid.ContextRequested += (_, e) =>
        {
            if (Grid.SelectedItem is not WorklistRow r) return;
            var mi = new MenuItem { Header = "Details …" };
            mi.Click += (_, _) => ShowDetails(r);
            var menu = new ContextMenu();
            menu.Items.Add(mi);
            menu.Open(Grid);
            e.Handled = true;
        };
    }

    private void ShowDetails(WorklistRow r) => new DatasetWindow(r.Dataset, "Worklist-Eintrag").ShowFor(this);
    private void OnToday(object? sender, RoutedEventArgs e) => Date.Value = DicomDateInput.ToDicom(DateTime.Today);
    private void OnAll(object? sender, RoutedEventArgs e) => Date.Value = "";
    private static string T(TextBox b) => b.Text?.Trim() ?? "";

    private async void OnQuery(object? sender, RoutedEventArgs e)
    {
        if (_running || _state.SelectedNode is not { } item) return;
        var q = new DicomDataset();
        if (T(PatName).Any(ch => ch > 127)) q.Add(DicomTag.SpecificCharacterSet, "ISO_IR 100");
        q.Add(DicomTag.PatientName, T(PatName)); q.Add(DicomTag.PatientID, T(PatId)); q.Add(DicomTag.PatientBirthDate, ""); q.Add(DicomTag.PatientSex, "");
        q.Add(DicomTag.AccessionNumber, T(Accession)); q.Add(DicomTag.ReferringPhysicianName, "");
        q.Add(DicomTag.RequestedProcedureDescription, ""); q.Add(DicomTag.RequestedProcedureID, ""); q.Add(DicomTag.StudyInstanceUID, "");
        var sps = new DicomDataset
        {
            { DicomTag.Modality, T(Modality).ToUpperInvariant() }, { DicomTag.ScheduledStationAETitle, T(StationAe) },
            { DicomTag.ScheduledProcedureStepStartDate, DicomDateInput.Normalize(Date.Value, allowsRange: true) },
            { DicomTag.ScheduledProcedureStepStartTime, "" }, { DicomTag.ScheduledPerformingPhysicianName, "" },
            { DicomTag.ScheduledProcedureStepDescription, "" }, { DicomTag.ScheduledProcedureStepID, "" }, { DicomTag.ScheduledStationName, "" },
        };
        q.Add(new DicomSequence(DicomTag.ScheduledProcedureStepSequence, sps));
        _rows.Clear();
        CountText.Text = "0 Einträge";
        _running = true;
        QueryButton.IsEnabled = false;
        Busy.IsVisible = true;
        try
        {
            await Task.Run(() => DicomScu.FindAsync(item.ToNode(), _state.ScuSettings, DicomNames.ModalityWorklistFind, q,
                ds => Dispatcher.UIThread.Post(() => { _rows.Add(new WorklistRow(ds)); CountText.Text = $"{_rows.Count} Einträge"; }),
                _state.Logger("MWL")));
        }
        catch (Exception ex)
        {
            _state.Append("MWL", DicomErrors.Describe(ex), error: true);
        }
        _running = false;
        QueryButton.IsEnabled = true;
        Busy.IsVisible = false;
    }
}
