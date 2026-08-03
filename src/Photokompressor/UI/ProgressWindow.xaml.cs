using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Input;
using Photokompressor.Core;
using Photokompressor.ViewModels;

namespace Photokompressor.UI;

public partial class ProgressWindow : Window
{
    private readonly List<string> _files;
    private readonly AppSettings _settings;
    private readonly CancellationTokenSource _cts = new();
    private readonly ObservableCollection<FileResultItem> _items = new();
    private readonly Dictionary<string, FileResultItem> _byPath;
    private long _totalBefore;
    private long _totalAfter;
    private int _doneCount;
    private bool _finished;
    private bool _closeRequested;
    private string? _firstOutputDir;

    public ProgressWindow(List<string> files, AppSettings settings)
    {
        InitializeComponent();
        _files = files;
        _settings = settings;
        foreach (var f in files)
        {
            _items.Add(new FileResultItem
            {
                InputPath = f,
                FileName = Path.GetFileName(f),
            });
        }
        _byPath = _items.ToDictionary(i => i.InputPath, StringComparer.OrdinalIgnoreCase);
        ResultsList.ItemsSource = _items;
        OverallProgress.Maximum = files.Count;
        UpdateCount();
        Loaded += OnLoaded;
        Closing += OnClosing;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        var engine = new CompressionEngine();
        var progress = new Progress<CompressionResult>(OnResult);
        try
        {
            await Task.Run(() => engine.RunBatchAsync(_files, _settings, progress, _cts.Token));
        }
        catch (OperationCanceledException)
        {
            // handled below: unprocessed rows become "Cancelled"
        }
        Finish();
    }

    private void OnResult(CompressionResult result)
    {
        if (!_byPath.TryGetValue(result.InputPath, out var item))
            return;

        _doneCount++;
        switch (result.Status)
        {
            case ResultStatus.Compressed:
                item.Detail = $"{FormatSize(result.BeforeBytes)} → {FormatSize(result.AfterBytes)}"
                              + (result.Note is { } note ? $"  ·  {note}" : "");
                item.Badge = $"−{100 - (int)Math.Round(100.0 * result.AfterBytes / result.BeforeBytes)}%";
                item.Kind = "Done";
                _totalBefore += result.BeforeBytes;
                _totalAfter += result.AfterBytes;
                _firstOutputDir ??= Path.GetDirectoryName(result.OutputPath);
                break;
            case ResultStatus.KeptOriginal:
                item.Detail = result.Note ?? "Already smaller — kept original";
                item.Badge = "kept";
                item.Kind = "Kept";
                break;
            case ResultStatus.Cancelled:
                item.Detail = "Cancelled";
                item.Badge = "—";
                item.Kind = "Cancelled";
                break;
            default:
                item.Detail = result.Note ?? "Failed";
                item.Badge = "failed";
                item.Kind = "Failed";
                break;
        }
        OverallProgress.Value = _doneCount;
        UpdateCount();
        UpdateTotals();
    }

    private void Finish()
    {
        _finished = true;
        if (_closeRequested)
        {
            Close();
            return;
        }
        foreach (var item in _items.Where(i => i.Kind == "Pending"))
        {
            item.Detail = "Cancelled";
            item.Badge = "—";
            item.Kind = "Cancelled";
        }
        OverallProgress.Value = OverallProgress.Maximum;
        CancelButton.Content = "Done";
        CancelButton.IsEnabled = true;
        OpenFolderButton.IsEnabled = _firstOutputDir != null;
        BackButton.IsEnabled = true;
        Tracking.SetText(TitleText, "FINISHED");
        UpdateCount();
        UpdateTotals();
    }

    private void UpdateCount() =>
        CountText.Text = _finished
            ? $"{_doneCount} of {_files.Count} processed"
            : $"{_doneCount} of {_files.Count}…";

    private void UpdateTotals()
    {
        if (_totalBefore <= 0)
        {
            TotalsText.Text = _finished ? "Nothing to save here" : "";
            return;
        }
        var pct = 100 - (int)Math.Round(100.0 * _totalAfter / _totalBefore);
        TotalsText.Text = $"{FormatSize(_totalBefore)} → {FormatSize(_totalAfter)}   −{pct}%";
    }

    private void OnCancelClicked(object sender, RoutedEventArgs e)
    {
        if (_finished)
        {
            Close();
            return;
        }
        _cts.Cancel();
        CancelButton.IsEnabled = false;
        CancelButton.Content = "Cancelling…";
        Tracking.SetText(TitleText, "CANCELLING");
    }

    private void OnClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (_finished)
            return;
        // Let the in-flight files wind down; Finish() closes the window afterwards.
        _closeRequested = true;
        _cts.Cancel();
        e.Cancel = true;
    }

    /// <summary>
    /// Moves the window from anywhere on the card that isn't an interactive control.
    /// Buttons and the scrollbar handle the click themselves, so it never reaches here
    /// from one of those.
    /// </summary>
    private void OnChromeDrag(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        try { DragMove(); }
        catch (InvalidOperationException) { /* mouse released mid-drag */ }
    }

    /// <summary>
    /// Returns to the options dialog with an empty queue — a finished batch starts
    /// fresh rather than silently carrying the same photos forward.
    /// </summary>
    private void OnBackClicked(object sender, RoutedEventArgs e)
    {
        new OptionsWindow(Array.Empty<string>()) { Left = Left, Top = Top }.Show();
        Close();
    }

    private void OnOpenFolderClicked(object sender, RoutedEventArgs e)
    {
        if (_firstOutputDir != null && Directory.Exists(_firstOutputDir))
            Process.Start("explorer.exe", $"\"{_firstOutputDir}\"");
    }

    private static string FormatSize(long bytes) => bytes switch
    {
        >= 1024 * 1024 => $"{bytes / (1024.0 * 1024.0):0.0} MB",
        >= 1024 => $"{bytes / 1024.0:0} KB",
        _ => $"{bytes} B",
    };
}
