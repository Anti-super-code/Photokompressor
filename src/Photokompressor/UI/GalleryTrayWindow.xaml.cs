using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
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

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint hWnd, out RECT lpRect);
    [DllImport("user32.dll")] private static extern nint MonitorFromWindow(nint hWnd, uint dwFlags);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(nint hmonitor, int dpiType, out uint dpiX, out uint dpiY);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint hWnd, nint hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

    private const uint MONITOR_DEFAULTTONEAREST = 2;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_NOACTIVATE = 0x0010;

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
        var selfHandle = new WindowInteropHelper(this).Handle;
        var ownerHandle = new WindowInteropHelper(_owner).Handle;
        if (selfHandle == 0 || ownerHandle == 0)
        {
            // Not yet realized (first call, from the constructor before Show) —
            // WPF's own DIP coordinates are all that's available at this point.
            Left = _owner.Left - Width - Gap;
            Top = _owner.Top;
            return;
        }

        // Once shown, reposition through Win32 in physical pixels instead: WPF's
        // Left/Top are expressed in whichever monitor's DPI *this* window last
        // rendered at, so mixing owner.Left into this.Left mid cross-monitor drag
        // can land the tray on the wrong scale and it stops tracking the owner.
        // GetWindowRect/SetWindowPos work in physical pixels for both windows,
        // sidestepping that — same trick as CursorPositioner.
        GetWindowRect(ownerHandle, out var ownerRect);
        GetWindowRect(selfHandle, out var selfRect);
        var width = selfRect.Right - selfRect.Left;

        uint dpiX = 96, dpiY = 96;
        try
        {
            var hMonitor = MonitorFromWindow(ownerHandle, MONITOR_DEFAULTTONEAREST);
            GetDpiForMonitor(hMonitor, 0 /* MDT_EFFECTIVE_DPI */, out dpiX, out dpiY);
        }
        catch { /* pre-8.1 fallback: assume 96 */ }
        var gapPx = (int)Math.Round(Gap * dpiX / 96.0);

        SetWindowPos(selfHandle, 0, ownerRect.Left - width - gapPx, ownerRect.Top,
            0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
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
