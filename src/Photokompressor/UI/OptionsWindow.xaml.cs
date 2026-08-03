using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Input;
using Photokompressor.Core;

namespace Photokompressor.UI;

public partial class OptionsWindow : Window
{
    private readonly ObservableCollection<string> _files = new();

    /// <summary>Suppresses the slider/text-box handlers while they mirror each other.</summary>
    private bool _sync;

    /// <summary>Empty would hide the "View the source" link rather than let it lie.</summary>
    private const string SourceUrl = "https://github.com/Anti-super-code/Photokompressor";

    private const string HomepageUrl = "https://antidot.gr";

    /// <summary>Ships beside the exe from the release package; absent in a dev build.</summary>
    private static string NoticesPath =>
        Path.Combine(AppContext.BaseDirectory, "THIRD-PARTY-NOTICES.md");

    public bool CompressStarted { get; private set; }

    public OptionsWindow(IEnumerable<string> files)
    {
        InitializeComponent();
        foreach (var f in files)
            _files.Add(f);

        _sync = true;
        LoadFrom(SettingsStore.Load());
        _sync = false;

        UpdateSelection();
        UpdateHints();

        SourceLink.Visibility = SourceUrl.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        LicencesLink.Visibility = File.Exists(NoticesPath) ? Visibility.Visible : Visibility.Collapsed;

        SourceInitialized += (_, _) => CursorPositioner.PlaceAtCursor(this, shadowMargin: 18);
        ContentRendered += (_, _) => Activate();
    }

    // ===== info screen =====

    private bool InfoShowing => InfoPanel.Visibility == Visibility.Visible;

    private void ShowInfo(bool show)
    {
        InfoPanel.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        BodyScroll.Visibility = show ? Visibility.Collapsed : Visibility.Visible;
        FooterBar.Visibility = show ? Visibility.Collapsed : Visibility.Visible;
        // The photo count belongs to the job, not to the about page.
        SubtitleRow.Visibility = show ? Visibility.Collapsed : Visibility.Visible;
    }

    private void OnInfoClicked(object sender, RoutedEventArgs e) => ShowInfo(true);

    private void OnBackToAppClicked(object sender, RoutedEventArgs e) => ShowInfo(false);

    /// <summary>Esc backs out of the info screen; only then does it close the window.</summary>
    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape && InfoShowing)
        {
            ShowInfo(false);
            e.Handled = true;
        }
    }

    private void OnSourceClicked(object sender, RoutedEventArgs e) => OpenExternal(SourceUrl);

    private void OnMadeByClicked(object sender, RoutedEventArgs e) => OpenExternal(HomepageUrl);

    private void OnLicencesClicked(object sender, RoutedEventArgs e) => OpenExternal(NoticesPath);

    private static void OpenExternal(string target)
    {
        if (string.IsNullOrWhiteSpace(target)) return;
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception)
        {
            // No browser, no handler for .md, or the user cancelled the "open with" prompt —
            // none of which is worth interrupting them over.
        }
    }

    // ===== Explorer integration =====

    private void OnShellToggled(object sender, RoutedEventArgs e)
    {
        if (_sync) return;
        try
        {
            if (ShellCheck.IsChecked == true)
                ShellRegistration.Register();
            else
                ShellRegistration.Unregister();
        }
        catch (Exception ex)
        {
            // Snap the switch back to what the registry actually says, and report in
            // place — the settings pane that holds ValidationText isn't on screen here.
            _sync = true;
            ShellCheck.IsChecked = ShellRegistration.IsRegistered();
            _sync = false;
            UpdateShellHint();
            ShellHint.Text = $"Couldn't update it — {ex.Message}";
            ShellHint.Foreground = (System.Windows.Media.Brush)FindResource("Danger");
            return;
        }
        UpdateShellHint();
    }

    private void UpdateShellHint()
    {
        ShellHint.Foreground = (System.Windows.Media.Brush)FindResource("TextLo");
        ShellHint.Text = ShellCheck.IsChecked == true
            ? "Compress straight from Explorer — right-click any photo"
            : "Add it to compress without opening this window";
    }

    /// <summary>Late arrivals from the pipe, or files dropped onto the open dialog.</summary>
    public void AddFile(string path)
    {
        if (CompressStarted) return;
        if (!_files.Contains(path, StringComparer.OrdinalIgnoreCase))
        {
            _files.Add(path);
            UpdateSelection();
        }
    }

    private void OnDeselectAllClicked(object sender, RoutedEventArgs e)
    {
        _files.Clear();
        UpdateSelection();
    }

    private void OnDragEnter(object sender, DragEventArgs e)
    {
        var droppable = !CompressStarted && DroppedFiles.LooksDroppable(e.Data);
        e.Effects = droppable ? DragDropEffects.Copy : DragDropEffects.None;
        if (droppable)
        {
            DropSubText.Text = _files.Count switch
            {
                0 => "JPEG · PNG · WebP · HEIC · BMP · TIFF · GIF",
                1 => "They'll be added to the 1 photo already queued",
                _ => $"They'll be added to the {_files.Count} photos already queued",
            };
            DropOverlay.Visibility = Visibility.Visible;
        }
        e.Handled = true;
    }

    private void OnDragLeave(object sender, DragEventArgs e) =>
        DropOverlay.Visibility = Visibility.Collapsed;

    private void OnDrop(object sender, DragEventArgs e)
    {
        DropOverlay.Visibility = Visibility.Collapsed;
        e.Handled = true;
        if (CompressStarted)
            return;

        // Dropping photos is a clear "get on with it" — leave the info screen behind.
        if (InfoShowing)
            ShowInfo(false);

        foreach (var file in DroppedFiles.Collect(e.Data))
            AddFile(Path.GetFullPath(file));
        Activate();
    }

    private void UpdateSelection()
    {
        SubtitleText.Text = _files.Count switch
        {
            0 => "No photos selected — drop some here",
            1 => "1 photo selected",
            _ => $"{_files.Count} photos selected",
        };
        // Nothing to deselect, and nothing to compress, when the queue is empty.
        DeselectButton.Visibility = _files.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        CompressButton.IsEnabled = _files.Count > 0;
    }

    private void LoadFrom(AppSettings s)
    {
        FmtJpeg.IsChecked = s.Format == OutputFormat.Jpeg;
        FmtWebp.IsChecked = s.Format == OutputFormat.WebP;
        FmtPng.IsChecked = s.Format == OutputFormat.Png;

        PresetHigh.IsChecked = s.Preset == QualityPreset.High;
        PresetBalanced.IsChecked = s.Preset == QualityPreset.Balanced;
        PresetSmallest.IsChecked = s.Preset == QualityPreset.Smallest;

        ResizeCheck.IsChecked = s.ResizeEnabled;
        // Boxes and slider share one range, so a setting saved under an older, wider
        // range can't leave the two showing different numbers.
        var width = ClampToSliderRange(s.BoxWidth);
        var height = ClampToSliderRange(s.BoxHeight);
        SizeSlider.Value = Math.Max(width, height);
        BoxWidthText.Text = width.ToString();
        BoxHeightText.Text = height.ToString();

        // Not persisted with the rest — the registry is the source of truth.
        ShellCheck.IsChecked = ShellRegistration.IsRegistered();
        UpdateShellHint();

        KeepCheck.IsChecked = s.KeepOriginals;
        LocSubfolder.IsChecked = s.LocationMode == OutputLocationMode.Subfolder;
        LocSuffix.IsChecked = s.LocationMode == OutputLocationMode.Suffix;
        LocCustom.IsChecked = s.LocationMode == OutputLocationMode.CustomFolder;
        CustomFolderText.Text = s.CustomFolder;
    }

    private AppSettings CollectSettings()
    {
        var s = new AppSettings
        {
            Format = FmtWebp.IsChecked == true ? OutputFormat.WebP
                   : FmtPng.IsChecked == true ? OutputFormat.Png
                   : OutputFormat.Jpeg,
            Preset = PresetHigh.IsChecked == true ? QualityPreset.High
                   : PresetSmallest.IsChecked == true ? QualityPreset.Smallest
                   : QualityPreset.Balanced,
            ResizeEnabled = ResizeCheck.IsChecked == true,
            KeepOriginals = KeepCheck.IsChecked == true,
            LocationMode = LocSuffix.IsChecked == true ? OutputLocationMode.Suffix
                         : LocCustom.IsChecked == true ? OutputLocationMode.CustomFolder
                         : OutputLocationMode.Subfolder,
            CustomFolder = CustomFolderText.Text,
        };
        if (int.TryParse(BoxWidthText.Text, out var w))
            s.BoxWidth = ClampToSliderRange(w);
        if (int.TryParse(BoxHeightText.Text, out var h))
            s.BoxHeight = ClampToSliderRange(h);
        return s;
    }

    /// <summary>The slider is the single source of truth for the allowed box size.</summary>
    private int ClampToSliderRange(int value) =>
        Math.Clamp(value, (int)SizeSlider.Minimum, (int)SizeSlider.Maximum);

    private void UpdateHints()
    {
        if (FormatHint == null) return;

        FormatHint.Text = FmtPng.IsChecked == true
            ? "Lossless — much larger for photos, ideal for graphics"
            : FmtWebp.IsChecked == true
                ? "Smallest files — great for web and storage"
                : "Best all-round choice for photos";

        PresetHint.Text = PresetHigh.IsChecked == true
            ? "Barely any loss — larger files"
            : PresetSmallest.IsChecked == true
                ? "Maximum savings — some softening"
                : "Recommended — big savings, no visible loss";

        var resize = ResizeCheck.IsChecked == true;
        SizeSlider.IsEnabled = resize;
        BoxWidthText.IsEnabled = BoxHeightText.IsEnabled = ChipRow.IsEnabled = resize;

        var keep = KeepCheck.IsChecked == true;
        KeepHint.Text = keep
            ? "Originals stay exactly where they are"
            : "Originals go to the Recycle Bin — recoverable";

        SaveToLabel.Opacity = keep ? 1.0 : 0.45;
        LocationTrack.IsEnabled = keep;
        BrowseButton.IsEnabled = keep && LocCustom.IsChecked == true;

        var showFolderBox = keep && LocCustom.IsChecked == true;
        CustomFolderText.Visibility = showFolderBox ? Visibility.Visible : Visibility.Hidden;
        LocationHint.Visibility = showFolderBox ? Visibility.Hidden : Visibility.Visible;
        LocationHint.Text = !keep
            ? "Compressed files take the originals' place"
            : LocSuffix.IsChecked == true
                ? "Next to each original, named “photo-compressed.jpg”"
                : "A “Compressed” folder next to each original";
    }

    private void OnFormatChanged(object sender, RoutedEventArgs e)
    {
        if (!_sync) UpdateHints();
    }

    private void OnPresetChanged(object sender, RoutedEventArgs e)
    {
        if (!_sync) UpdateHints();
    }

    private void OnResizeToggled(object sender, RoutedEventArgs e)
    {
        if (!_sync) UpdateHints();
    }

    private void OnKeepToggled(object sender, RoutedEventArgs e)
    {
        if (!_sync) UpdateHints();
    }

    private void OnLocationChanged(object sender, RoutedEventArgs e)
    {
        if (_sync) return;
        UpdateHints();
        if (LocCustom.IsChecked == true && string.IsNullOrWhiteSpace(CustomFolderText.Text))
            PickFolder();
    }

    private void OnSliderChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_sync || BoxWidthText == null) return;
        _sync = true;
        var value = ((int)e.NewValue).ToString();
        BoxWidthText.Text = value;
        BoxHeightText.Text = value;
        _sync = false;
    }

    private void OnSizeTextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        if (_sync) return;
        _sync = true;
        int.TryParse(BoxWidthText.Text, out var w);
        int.TryParse(BoxHeightText.Text, out var h);
        var longest = Math.Max(w, h);
        if (longest > 0)
            SizeSlider.Value = Math.Clamp(longest, SizeSlider.Minimum, SizeSlider.Maximum);
        _sync = false;
    }

    private void OnChipClicked(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button { Tag: string tag } && int.TryParse(tag, out var px))
            SizeSlider.Value = px;
    }

    private void OnDigitsOnly(object sender, TextCompositionEventArgs e) =>
        e.Handled = !e.Text.All(char.IsDigit);

    /// <summary>
    /// Moves the window from anywhere on the card that isn't an interactive control.
    /// Buttons, switches, sliders and text boxes handle the click themselves, so it
    /// never reaches here from one of those.
    /// </summary>
    private void OnChromeDrag(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        try { DragMove(); }
        catch (InvalidOperationException) { /* mouse released mid-drag */ }
    }

    private void OnBrowseClicked(object sender, RoutedEventArgs e) => PickFolder();

    private void PickFolder()
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { Title = "Choose output folder" };
        if (!string.IsNullOrWhiteSpace(CustomFolderText.Text) && Directory.Exists(CustomFolderText.Text))
            dialog.InitialDirectory = CustomFolderText.Text;
        if (dialog.ShowDialog(this) == true)
        {
            CustomFolderText.Text = dialog.FolderName;
            LocCustom.IsChecked = true;
            ValidationText.Visibility = Visibility.Collapsed;
            UpdateHints();
        }
    }

    private void OnCompressClicked(object sender, RoutedEventArgs e)
    {
        if (_files.Count == 0)
            return;

        var settings = CollectSettings();
        if (settings.KeepOriginals
            && settings.LocationMode == OutputLocationMode.CustomFolder
            && string.IsNullOrWhiteSpace(settings.CustomFolder))
        {
            ValidationText.Text = "Choose a destination folder first.";
            ValidationText.Visibility = Visibility.Visible;
            PickFolder();
            return;
        }

        SettingsStore.Save(settings);
        CompressStarted = true;

        var progress = new ProgressWindow(_files.ToList(), settings)
        {
            Left = Left,
            Top = Top,
        };
        progress.Show();
        Close();
    }

    /// <summary>
    /// Cancelling ends the session. This is the app's only window, so closing it is
    /// enough — ShutdownMode.OnLastWindowClose takes care of the process.
    /// </summary>
    private void OnCancelClicked(object sender, RoutedEventArgs e) => Close();
}
