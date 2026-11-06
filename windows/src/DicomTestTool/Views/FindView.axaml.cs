using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Threading;
using DicomTestTool.Controls;
using DicomTestTool.Core;
using DicomTestTool.ViewModels;
using FellowOakDicom;

namespace DicomTestTool.Views;

public enum QueryLevel { Patient, Study, Series, Image }

public sealed class FindRow(QueryLevel level, DicomDataset ds)
{
    public QueryLevel Level { get; } = level;
    public DicomDataset Dataset { get; } = ds;
    private string S(DicomTag t) => Dataset.GetSingleValueOrDefault(t, "");
    public string Name => DicomNames.FormatPN(S(DicomTag.PatientName));
    public string PatientId => S(DicomTag.PatientID);
    public string BirthDate => DicomNames.FormatDA(S(DicomTag.PatientBirthDate));
    public string Date => DicomNames.FormatDA(FirstNonEmpty(S(DicomTag.StudyDate), S(DicomTag.SeriesDate), S(DicomTag.ContentDate)));
    public string Modality => Dataset.TryGetValues<string>(DicomTag.ModalitiesInStudy, out var m) && m.Length > 0 ? string.Join("\\", m) : S(DicomTag.Modality);
    public string Accession => S(DicomTag.AccessionNumber);
    public string StudyUid => S(DicomTag.StudyInstanceUID);
    public string SeriesUid => S(DicomTag.SeriesInstanceUID);
    public string SopUid => S(DicomTag.SOPInstanceUID);
    public string Description => Level switch
    {
        QueryLevel.Patient => "",
        QueryLevel.Study => S(DicomTag.StudyDescription),
        QueryLevel.Series => $"#{S(DicomTag.SeriesNumber)} {S(DicomTag.SeriesDescription)}",
        _ => $"Bild {S(DicomTag.InstanceNumber)} – {DicomNames.SopClass(S(DicomTag.SOPClassUID))}",
    };
    public string Count => Level switch
    {
        QueryLevel.Patient => S(DicomTag.NumberOfPatientRelatedStudies),
        QueryLevel.Study => S(DicomTag.NumberOfStudyRelatedInstances),
        QueryLevel.Series => S(DicomTag.NumberOfSeriesRelatedInstances),
        _ => "",
    };
    private static string FirstNonEmpty(params string[] v) => v.FirstOrDefault(x => x.Length > 0) ?? "";
}

public partial class FindView : UserControl
{
    private readonly AppState _state = AppState.Shared;
    private readonly ObservableCollection<FindRow> _rows = [];
    private CancellationTokenSource? _cts;
    private bool IsStudyRoot => Model.SelectedIndex == 0;
    private QueryLevel CurrentLevel => Level.SelectedItem is QueryLevel l ? l : QueryLevel.Study;

    public FindView()
    {
        InitializeComponent();
        Grid.ItemsSource = _rows;
        Level.ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<QueryLevel>((l, _) => new TextBlock { Text = l.ToString().ToUpperInvariant() });
        Model.SelectionChanged += (_, _) => UpdateLevels();
        Level.SelectionChanged += (_, _) => UpdateFields();
        Grid.DoubleTapped += (_, _) => { if (Grid.SelectedItem is FindRow r) Drill(r); };
        Grid.ContextRequested += OnContext;
        Grid.SelectionChanged += (_, _) => UpdateButtons();
        MoveDest.Watermark = _state.ScpAe;
        UpdateLevels();
    }

    private void UpdateLevels()
    {
        var current = Level.SelectedItem as QueryLevel?;
        var levels = IsStudyRoot ? new[] { QueryLevel.Study, QueryLevel.Series, QueryLevel.Image } : Enum.GetValues<QueryLevel>();
        Level.ItemsSource = levels;
        Level.SelectedItem = current is { } c && levels.Contains(c) ? c : QueryLevel.Study;
        UpdateFields();
    }

    private void UpdateFields()
    {
        var l = CurrentLevel;
        StudyDate.IsVisible = AccessionBox.IsVisible = ModalityBox.IsVisible = l != QueryLevel.Patient;
        UidRow.IsVisible = l is QueryLevel.Series or QueryLevel.Image;
        SeriesUidBox.IsVisible = l == QueryLevel.Image;
        UpdateButtons();
    }

    private void UpdateButtons()
    {
        MoveButton.IsEnabled = Grid.SelectedItems.Count > 0 && _cts == null;
    }

    private string MoveTarget => string.IsNullOrWhiteSpace(MoveDest.Text) ? _state.ScpAe : MoveDest.Text.Trim();

    private static string T(TextBox b) => b.Text?.Trim() ?? "";

    private DicomDataset BuildQuery()
    {
        var level = CurrentLevel;
        var q = new DicomDataset { { DicomTag.QueryRetrieveLevel, level.ToString().ToUpperInvariant() } };
        if (T(PatName).Any(ch => ch > 127)) q.Add(DicomTag.SpecificCharacterSet, "ISO_IR 100");
        var birth = DicomDateInput.Normalize(BirthDate.Value, allowsRange: false);
        switch (level)
        {
            case QueryLevel.Patient:
                q.Add(DicomTag.PatientName, T(PatName)); q.Add(DicomTag.PatientID, T(PatId)); q.Add(DicomTag.PatientBirthDate, birth);
                q.Add(DicomTag.PatientSex, ""); q.Add(DicomTag.NumberOfPatientRelatedStudies, "");
                break;
            case QueryLevel.Study:
                q.Add(DicomTag.PatientName, T(PatName)); q.Add(DicomTag.PatientID, T(PatId)); q.Add(DicomTag.PatientBirthDate, birth);
                q.Add(DicomTag.PatientSex, "");
                q.Add(DicomTag.StudyDate, DicomDateInput.Normalize(StudyDate.Value, allowsRange: true)); q.Add(DicomTag.StudyTime, "");
                q.Add(DicomTag.AccessionNumber, T(Accession)); q.Add(DicomTag.ModalitiesInStudy, T(Modality).ToUpperInvariant());
                q.Add(DicomTag.StudyDescription, ""); q.Add(DicomTag.StudyID, ""); q.Add(DicomTag.ReferringPhysicianName, "");
                q.Add(DicomTag.StudyInstanceUID, T(StudyUid));
                q.Add(DicomTag.NumberOfStudyRelatedSeries, ""); q.Add(DicomTag.NumberOfStudyRelatedInstances, "");
                break;
            case QueryLevel.Series:
                if (!IsStudyRoot) q.Add(DicomTag.PatientID, T(PatId));
                q.Add(DicomTag.StudyInstanceUID, T(StudyUid));
                q.Add(DicomTag.SeriesInstanceUID, ""); q.Add(DicomTag.Modality, T(Modality).ToUpperInvariant()); q.Add(DicomTag.SeriesNumber, "");
                q.Add(DicomTag.SeriesDescription, ""); q.Add(DicomTag.SeriesDate, ""); q.Add(DicomTag.NumberOfSeriesRelatedInstances, "");
                break;
            case QueryLevel.Image:
                if (!IsStudyRoot) q.Add(DicomTag.PatientID, T(PatId));
                q.Add(DicomTag.StudyInstanceUID, T(StudyUid)); q.Add(DicomTag.SeriesInstanceUID, T(SeriesUid));
                q.Add(DicomTag.SOPInstanceUID, ""); q.Add(DicomTag.SOPClassUID, ""); q.Add(DicomTag.InstanceNumber, ""); q.Add(DicomTag.ContentDate, "");
                break;
        }
        return q;
    }

    private void OnFind(object? sender, RoutedEventArgs e) => _ = FindAsync();

    private async Task FindAsync()
    {
        if (_cts != null || _state.SelectedNode is not { } item) return;
        var level = CurrentLevel;
        if (level is QueryLevel.Series or QueryLevel.Image && T(StudyUid).Length == 0)
        {
            _state.Append("Find", $"Für die Ebene {level.ToString().ToUpperInvariant()} ist eine Study Instance UID nötig", error: true);
            return;
        }
        if (level == QueryLevel.Image && T(SeriesUid).Length == 0)
        {
            _state.Append("Find", "Für die Ebene IMAGE ist eine Series Instance UID nötig", error: true);
            return;
        }
        _rows.Clear();
        HitCount.Text = "0 Treffer";
        var q = BuildQuery();
        var sop = IsStudyRoot ? DicomNames.StudyRootFind : DicomNames.PatientRootFind;
        var cts = _cts = new CancellationTokenSource();
        SetBusy(true);
        try
        {
            await Task.Run(() => DicomScu.FindAsync(item.ToNode(), _state.ScuSettings, sop, q,
                ds => Dispatcher.UIThread.Post(() => { _rows.Add(new FindRow(level, ds)); HitCount.Text = $"{_rows.Count} Treffer"; }),
                _state.Logger("Find"), cts.Token));
        }
        catch (Exception ex)
        {
            _state.Append("Find", DicomErrors.Describe(ex), error: true);
        }
        _cts = null;
        SetBusy(false);
    }

    private async void OnMove(object? sender, RoutedEventArgs e)
    {
        if (_cts != null || _state.SelectedNode is not { } item) return;
        var selected = Grid.SelectedItems.OfType<FindRow>().ToList();
        if (selected.Count == 0) return;
        if (IsStudyRoot && selected.Any(r => r.Level == QueryLevel.Patient)) return;
        var dest = MoveTarget;
        var studyRoot = IsStudyRoot;
        var sop = studyRoot ? DicomNames.StudyRootMove : DicomNames.PatientRootMove;
        var log = _state.Logger("Move");
        var cts = _cts = new CancellationTokenSource();
        SetBusy(true);
        foreach (var r in selected)
        {
            var q = new DicomDataset { { DicomTag.QueryRetrieveLevel, r.Level.ToString().ToUpperInvariant() } };
            if (!studyRoot || r.Level == QueryLevel.Patient) q.Add(DicomTag.PatientID, r.PatientId);
            if (r.Level != QueryLevel.Patient) q.Add(DicomTag.StudyInstanceUID, r.StudyUid);
            if (r.Level is QueryLevel.Series or QueryLevel.Image) q.Add(DicomTag.SeriesInstanceUID, r.SeriesUid);
            if (r.Level == QueryLevel.Image) q.Add(DicomTag.SOPInstanceUID, r.SopUid);
            try
            {
                await Task.Run(() => DicomScu.MoveAsync(item.ToNode(), _state.ScuSettings, sop, q, dest,
                    p => { if (DicomNames.IsPending(p.Status)) log($"  … {p.Completed} übertragen, {p.Remaining} verbleibend, {p.Failed} Fehler"); },
                    log, cts.Token));
            }
            catch (Exception ex)
            {
                _state.Append("Move", DicomErrors.Describe(ex), error: true);
                if (cts.IsCancellationRequested) break;
            }
        }
        _cts = null;
        SetBusy(false);
    }

    private void OnCancel(object? sender, RoutedEventArgs e) => _cts?.Cancel();

    private void SetBusy(bool busy)
    {
        // An indeterminate ProgressBar animates (and redraws) even while hidden – only switch it on while busy.
        Busy.IsVisible = Busy.IsIndeterminate = busy;
        CancelButton.IsVisible = busy;
        FindButton.IsVisible = !busy;
        UpdateButtons();
    }

    private void OnClearFields(object? sender, RoutedEventArgs e)
    {
        PatName.Text = PatId.Text = Accession.Text = Modality.Text = StudyUid.Text = SeriesUid.Text = "";
        BirthDate.Value = StudyDate.Value = "";
    }

    private void Drill(FindRow r)
    {
        switch (r.Level)
        {
            case QueryLevel.Patient: PatId.Text = r.PatientId; PatName.Text = ""; Level.SelectedItem = QueryLevel.Study; break;
            case QueryLevel.Study: StudyUid.Text = r.StudyUid; Level.SelectedItem = QueryLevel.Series; break;
            case QueryLevel.Series: StudyUid.Text = r.StudyUid; SeriesUid.Text = r.SeriesUid; Level.SelectedItem = QueryLevel.Image; break;
            default: ShowDetails(r); return;
        }
        _ = FindAsync();
    }

    private void ShowDetails(FindRow r) =>
        new DatasetWindow(r.Dataset, $"C-FIND-Antwort ({r.Level.ToString().ToUpperInvariant()})").ShowFor(this);

    private void OnContext(object? sender, ContextRequestedEventArgs e)
    {
        if (Grid.SelectedItem is not FindRow r) return;
        var menu = new ContextMenu();
        void Add(string header, Action a, bool enabled = true)
        {
            var mi = new MenuItem { Header = header, IsEnabled = enabled };
            mi.Click += (_, _) => a();
            menu.Items.Add(mi);
        }
        Add("Details …", () => ShowDetails(r));
        if (r.Level == QueryLevel.Patient) Add("Studien anzeigen", () => Drill(r));
        if (r.Level == QueryLevel.Study) Add("Serien anzeigen", () => Drill(r));
        if (r.Level == QueryLevel.Series) Add("Bilder anzeigen", () => Drill(r));
        Add($"C-MOVE an {MoveTarget}", () => OnMove(null, new RoutedEventArgs()), _cts == null);
        Add("UID kopieren", () => _ = Ui.CopyAsync(this, r.SopUid.Length > 0 ? r.SopUid : r.SeriesUid.Length > 0 ? r.SeriesUid : r.StudyUid));
        menu.Open(Grid);
        e.Handled = true;
    }
}
