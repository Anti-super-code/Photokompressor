using System.IO;
using System.Windows;
using System.Windows.Threading;
using Photokompressor.Core;
using Photokompressor.UI;

namespace Photokompressor;

public partial class App : Application
{
    /// <summary>Sliding debounce: Explorer spawns one process per selected file within tens of ms.</summary>
    private static readonly TimeSpan DebounceInterval = TimeSpan.FromMilliseconds(300);
    private static readonly TimeSpan DebounceHardCap = TimeSpan.FromSeconds(2);

    private SingleInstance? _singleInstance;
    private readonly CancellationTokenSource _serverCts = new();
    private readonly List<string> _pendingFiles = new();
    private DispatcherTimer? _debounceTimer;
    private DateTime _firstArrivalUtc;
    private OptionsWindow? _openOptionsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var args = e.Args;

        if (args.Contains("--register"))
        {
            ShellRegistration.Register();
            Shutdown(0);
            return;
        }
        if (args.Contains("--unregister"))
        {
            ShellRegistration.Unregister();
            Shutdown(0);
            return;
        }
        if (args.Length > 0 && args[0] == "--cli")
        {
            Shutdown(CliRunner.Run(args.Skip(1).ToArray()));
            return;
        }

        CompressionEngine.ConfigureConcurrency(CompressionEngine.TaskDegreeOfParallelism);

        // GUI paths from here on: exit when the last window closes. The headless
        // paths above rely on explicit Shutdown() instead.
        ShutdownMode = ShutdownMode.OnLastWindowClose;

        var files = args.Where(File.Exists).Select(Path.GetFullPath).ToList();

        // One window, always — whether we were launched from Explorer's menu, from the
        // Start menu, or by a second copy of either while the first is still open.
        _singleInstance = new SingleInstance();
        if (!_singleInstance.TryBecomePrimary())
        {
            var payload = files.Count > 0 ? files : [FocusToken];
            if (SingleInstance.TrySendToPrimary(payload))
            {
                Shutdown(0);
                return;
            }
            // The primary died between mutex check and pipe connect — try to take over.
            _singleInstance.Dispose();
            _singleInstance = new SingleInstance();
            _singleInstance.TryBecomePrimary();
        }

        _ = _singleInstance.RunServerAsync(
            message => Dispatcher.BeginInvoke(() => OnPipeMessage(message)),
            _serverCts.Token);

        if (files.Count == 0)
        {
            ShowOptions([]);
            return;
        }

        foreach (var file in files)
            AddPendingFile(file);
    }

    /// <summary>
    /// The pipe carries file paths; this one reserved word means "you're already open,
    /// just come to the front" — sent when the app is launched again with no photos.
    /// </summary>
    private const string FocusToken = "--focus";

    private void OnPipeMessage(string message)
    {
        if (message == FocusToken)
        {
            var window = Windows.OfType<Window>().LastOrDefault(w => w.IsVisible);
            if (window == null)
                return;
            if (window.WindowState == WindowState.Minimized)
                window.WindowState = WindowState.Normal;
            window.Activate();
            return;
        }
        AddPendingFile(message);
    }

    private void AddPendingFile(string path)
    {
        if (_openOptionsWindow is { CompressStarted: false, IsLoaded: true })
        {
            _openOptionsWindow.AddFile(path);
            return;
        }

        if (_pendingFiles.Count == 0)
            _firstArrivalUtc = DateTime.UtcNow;
        if (!_pendingFiles.Contains(path, StringComparer.OrdinalIgnoreCase))
            _pendingFiles.Add(path);

        if (DateTime.UtcNow - _firstArrivalUtc >= DebounceHardCap)
        {
            ShowOptionsDialog();
            return;
        }

        if (_debounceTimer == null)
        {
            _debounceTimer = new DispatcherTimer { Interval = DebounceInterval };
            _debounceTimer.Tick += OnDebounceElapsed;
        }
        _debounceTimer.Stop();
        _debounceTimer.Start();
    }

    private void OnDebounceElapsed(object? sender, EventArgs e) => ShowOptionsDialog();

    private void ShowOptionsDialog()
    {
        if (_debounceTimer != null)
        {
            _debounceTimer.Stop();
            _debounceTimer.Tick -= OnDebounceElapsed;
            _debounceTimer = null;
        }

        if (_pendingFiles.Count == 0)
            return;

        ShowOptions(_pendingFiles.ToList());
        _pendingFiles.Clear();
    }

    private void ShowOptions(List<string> files)
    {
        var window = new OptionsWindow(files);
        _openOptionsWindow = window;
        window.Closed += (_, _) =>
        {
            if (ReferenceEquals(_openOptionsWindow, window))
                _openOptionsWindow = null;
        };
        window.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _serverCts.Cancel();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }
}
