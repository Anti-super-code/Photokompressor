using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Photokompressor.Core;

/// <summary>
/// Adds/removes the "Compress with Photokompressor" verb for each supported
/// image extension under HKCU (no admin). SystemFileAssociations fires no
/// matter which app owns the extension's default association.
/// </summary>
public static class ShellRegistration
{
    public const string VerbName = "Photokompressor";
    public const string MenuText = "Compress with Photokompressor";

    public static readonly string[] Extensions =
        [".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff", ".gif", ".heic", ".heif"];

    private const string BaseKey = @"Software\Classes\SystemFileAssociations";
    private const string ExplorerKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer";
    private const string MultiInvokePromptValueName = "MultipleInvokePromptMinimum";

    /// <summary>
    /// Explorer warns/blocks multi-invoke verbs once selection size exceeds this
    /// (default 15). We raise it so large photo batches don't get silently cut off.
    /// </summary>
    private const int MultiInvokePromptMinimum = 1000;

    [DllImport("shell32.dll")]
    private static extern void SHChangeNotify(int wEventId, uint uFlags, nint dwItem1, nint dwItem2);

    private const int SHCNE_ASSOCCHANGED = 0x08000000;
    private const uint SHCNF_IDLIST = 0x0000;

    public static void Register()
    {
        var exePath = Environment.ProcessPath
            ?? throw new InvalidOperationException("Cannot determine the application path.");

        foreach (var ext in Extensions)
        {
            using var verbKey = Registry.CurrentUser.CreateSubKey($@"{BaseKey}\{ext}\shell\{VerbName}");
            verbKey.SetValue("", MenuText);
            verbKey.SetValue("Icon", $"\"{exePath}\",0");
            // Document model: Explorer launches one process per selected file (what
            // SingleInstance.cs's pipe-accumulator is built for). Player model looks
            // tempting for "unlimited" selections but silently caps around 100 items
            // and only ever passes the first file through %1 above that.
            verbKey.SetValue("MultiSelectModel", "Document");
            using var commandKey = verbKey.CreateSubKey("command");
            commandKey.SetValue("", $"\"{exePath}\" \"%1\"");
        }
        RaiseMultiInvokePromptMinimum();
        NotifyShell();
    }

    public static void Unregister()
    {
        foreach (var ext in Extensions)
        {
            try
            {
                Registry.CurrentUser.DeleteSubKeyTree($@"{BaseKey}\{ext}\shell\{VerbName}", throwOnMissingSubKey: false);
            }
            catch { /* key may not exist */ }
        }
        NotifyShell();
    }

    public static bool IsRegistered()
    {
        using var key = Registry.CurrentUser.OpenSubKey($@"{BaseKey}\.jpg\shell\{VerbName}\command");
        return key?.GetValue("") is string;
    }

    private static void NotifyShell() => SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, 0, 0);

    /// <summary>
    /// Only raises the value, never lowers it — the user (or another app) may already
    /// have it set higher. Takes effect after Explorer restarts (sign-out or explorer.exe
    /// relaunch); there's no notification for this one like SHChangeNotify above.
    /// </summary>
    private static void RaiseMultiInvokePromptMinimum()
    {
        using var key = Registry.CurrentUser.CreateSubKey(ExplorerKey);
        var current = key.GetValue(MultiInvokePromptValueName);
        if (current is not int existing || existing < MultiInvokePromptMinimum)
            key.SetValue(MultiInvokePromptValueName, MultiInvokePromptMinimum, RegistryValueKind.DWord);
    }
}
