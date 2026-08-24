using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.Windows;
using System.Windows.Input;
using Photokompressor.Core;

namespace Photokompressor.UI;

/// <summary>
/// The borderless panel that sits to the left of the main Options window,
/// listing the currently-selected photos as real thumbnails. Owned by the
/// main window (so WPF closes it automatically if that window closes) and
/// repositioned live as that window is dragged.
/// </summary>
public partial class GalleryTrayWindow : Window
{
    private const double Gap = 10;

    private readonly Window _owner;
    private readonly ObservableCollection<string> _files;
    private readonly ObservableCollection<GalleryFileRow> _rows = new();
    private readonly Action _onCloseRequested;

    public GalleryTrayWindow(Window owner, ObservableCollection<string> files, bool alwaysOnTop,
        Action onCloseRequested)
    {
        InitializeComponent();
        _owner = owner;
        _files = files;
        _onCloseRequested = onCloseRequested;

        Owner = owner;
        Topmost = alwaysOnTop;
        RowsScroll.MaxHeight = Math.Max(160, owner.Height - 130);
        RowList.ItemsSource = _rows;

        foreach (var path in _files)
            AddRow(path);
        _files.CollectionChanged += OnFilesChanged;

        Reposition();
        _owner.LocationChanged += OnOwnerLocationChanged;
        Closed += (_, _) =>
        {
            _files.CollectionChanged -= OnFilesChanged;
            _owner.LocationChanged -= OnOwnerLocationChanged;
        };
    }

    public void SetAlwaysOnTop(bool value) => Topmost = value;

    private void OnOwnerLocationChanged(object? sender, EventArgs e) => Reposition();

    private void Reposition()
    {
        Left = _owner.Left - Width - Gap;
        Top = _owner.Top;
    }

    private void OnFilesChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        switch (e.Action)
        {
            case NotifyCollectionChangedAction.Add:
                foreach (string path in e.NewItems!)
                    AddRow(path);
                break;
            case NotifyCollectionChangedAction.Remove:
                foreach (string path in e.OldItems!)
                {
                    var row = _rows.FirstOrDefault(r => r.Path == path);
                    if (row != null) _rows.Remove(row);
                }
                break;
            case NotifyCollectionChangedAction.Reset:
                _rows.Clear();
                break;
        }
    }

    private void AddRow(string path)
    {
        var row = new GalleryFileRow(path);
        _rows.Add(row);
        _ = LoadThumbnailAsync(row);
    }

    private async Task LoadThumbnailAsync(GalleryFileRow row)
    {
        var thumbnail = await ThumbnailLoader.LoadAsync(row.Path);
        row.Thumbnail = thumbnail;
    }

    private void OnRemoveClicked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: GalleryFileRow row })
            _files.Remove(row.Path);
    }

    private void OnCloseClicked(object sender, RoutedEventArgs e) => _onCloseRequested();

    private void OnChromeDrag(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        try { _owner.DragMove(); }
        catch (InvalidOperationException) { /* mouse released mid-drag */ }
    }
}
