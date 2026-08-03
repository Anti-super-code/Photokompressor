using System.Collections.Concurrent;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace Photokompressor.Core;

public static class SafeReplace
{
    // ===================== can this file actually be recycled? =====================
    //
    // FOF_ALLOWUNDO is a request, not a promise. Windows silently deletes a file
    // outright — with no error and no way back — when the volume has no Recycle Bin
    // (network shares, most removable media), when the bin is switched off for that
    // volume or by policy, or when the file is bigger than the bin's quota. Replace
    // mode tells the user their originals are recoverable, so it has to establish
    // that up front instead of finding out afterwards, when the file is already gone.

    [StructLayout(LayoutKind.Sequential)]
    private struct SHQUERYRBINFO
    {
        public int cbSize;
        public long i64Size;
        public long i64NumItems;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHQueryRecycleBin(string pszRootPath, ref SHQUERYRBINFO pSHQueryRBInfo);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetVolumeNameForVolumeMountPoint(
        string lpszVolumeMountPoint, StringBuilder lpszVolumeName, int cchBufferLength);

    private const string PolicyKey = @"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer";
    private const string BitBucketKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume";

    /// <summary>Per-volume answer; the shell query is too slow to repeat for every file in a batch.</summary>
    private sealed record VolumeVerdict(bool CanRecycle, string Reason, long MaxBytes);

    private static readonly ConcurrentDictionary<string, VolumeVerdict> VolumeCache =
        new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// True when deleting <paramref name="path"/> would genuinely land it in the
    /// Recycle Bin. When false, <paramref name="reason"/> says why in words that can
    /// go straight into the results list.
    /// </summary>
    public static bool CanRecycle(string path, out string reason)
    {
        var fullPath = Path.GetFullPath(path);

        // UNC shares keep no bin of their own; deletes from them are permanent.
        if (fullPath.StartsWith(@"\\", StringComparison.Ordinal))
        {
            reason = "network locations have no Recycle Bin";
            return false;
        }

        var root = Path.GetPathRoot(fullPath);
        if (string.IsNullOrEmpty(root))
        {
            reason = "couldn't work out which drive this is on";
            return false;
        }

        var verdict = VolumeCache.GetOrAdd(root, InspectVolume);
        if (!verdict.CanRecycle)
        {
            reason = verdict.Reason;
            return false;
        }

        // A file larger than the bin's quota is destroyed rather than moved.
        if (verdict.MaxBytes > 0)
        {
            long length;
            try { length = new FileInfo(fullPath).Length; }
            catch (IOException) { reason = "couldn't measure the file"; return false; }
            catch (UnauthorizedAccessException) { reason = "couldn't measure the file"; return false; }

            if (length > verdict.MaxBytes)
            {
                reason = "it's larger than this drive's Recycle Bin allowance";
                return false;
            }
        }

        reason = "";
        return true;
    }

    private static VolumeVerdict InspectVolume(string root)
    {
        if (ReadDword(PolicyKey, "NoRecycleFiles") == 1)
            return new(false, "the Recycle Bin is switched off by policy", 0);

        long maxBytes = 0;
        if (VolumeSettingsKey(root) is { } volumeKey)
        {
            if (ReadDword(volumeKey, "NukeOnDelete") == 1)
                return new(false, "this drive is set to delete files immediately", 0);

            // Stored in MB. Absent means Windows picks a size we can't read, so we
            // simply don't apply a size test rather than guess one.
            if (ReadDword(volumeKey, "MaxCapacity") is > 0 and var megabytes)
                maxBytes = (long)megabytes * 1024 * 1024;
        }

        var info = new SHQUERYRBINFO { cbSize = Marshal.SizeOf<SHQUERYRBINFO>() };
        if (SHQueryRecycleBin(root, ref info) != 0)
            return new(false, "this drive has no Recycle Bin", 0);

        return new(true, "", maxBytes);
    }

    /// <summary>Maps a drive root to its per-volume Recycle Bin settings key, which is keyed by volume GUID.</summary>
    private static string? VolumeSettingsKey(string root)
    {
        try
        {
            var mountPoint = root.EndsWith('\\') ? root : root + '\\';
            var buffer = new StringBuilder(64);
            if (!GetVolumeNameForVolumeMountPoint(mountPoint, buffer, buffer.Capacity))
                return null;

            // Comes back as \\?\Volume{xxxxxxxx-xxxx-...}\
            var name = buffer.ToString();
            var open = name.IndexOf('{');
            var close = name.IndexOf('}');
            if (open < 0 || close <= open)
                return null;

            return $@"{BitBucketKey}\{name[open..(close + 1)]}";
        }
        catch
        {
            return null;   // an unreadable volume just means we skip these extra checks
        }
    }

    private static int? ReadDword(string subKey, string name)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(subKey);
            return key?.GetValue(name) as int?;
        }
        catch
        {
            return null;
        }
    }

    // ===================== the replace itself =====================

    // Microsoft.VisualBasic's FileSystem.DeleteFile is the usual way to reach the
    // Recycle Bin, but its .NET (Core) implementation fails with "The specified path
    // is invalid", and it pops modal shell dialogs mid-batch that the user then has to
    // dismiss per file. Calling the shell directly fixes both: it is silent, and it
    // hands back an error code we can report in our own results list.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd;
        [MarshalAs(UnmanagedType.U4)] public int wFunc;
        public string pFrom;
        public string? pTo;
        public short fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string? lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT lpFileOp);

    private const int FO_DELETE = 0x0003;
    private const short FOF_SILENT = 0x0004;
    private const short FOF_NOCONFIRMATION = 0x0010;
    private const short FOF_ALLOWUNDO = 0x0040;      // this is what routes to the Recycle Bin
    private const short FOF_NOERRORUI = 0x0400;

    private const int DE_OPCANCELLED = 0x75;
    private const int DE_ACCESSDENIEDSRC = 0x78;
    private const int DE_INVALIDFILES = 0x7C;
    private const int ERROR_SHARING_VIOLATION = 32;

    /// <summary>
    /// Sends a file to the Recycle Bin without showing any shell UI. Clears the
    /// read-only attribute first, which would otherwise fail it. Call
    /// <see cref="CanRecycle"/> beforehand: this cannot tell a recycle from a
    /// permanent delete after the fact, because the shell reports both as success.
    /// </summary>
    public static void RecycleOriginal(string path)
    {
        var attributes = File.GetAttributes(path);
        if (attributes.HasFlag(FileAttributes.ReadOnly))
            File.SetAttributes(path, attributes & ~FileAttributes.ReadOnly);

        var operation = new SHFILEOPSTRUCT
        {
            wFunc = FO_DELETE,
            // pFrom is a double-null-terminated list, even for a single file.
            pFrom = path + '\0' + '\0',
            fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI,
        };

        var result = SHFileOperation(ref operation);
        if (result != 0 || operation.fAnyOperationsAborted)
            throw new IOException(DescribeShellError(result), result);

        // The shell reports success even when nothing happened in some edge cases,
        // so confirm the original is actually gone before the caller renames over it.
        if (File.Exists(path))
            throw new IOException("Couldn't move the original to the Recycle Bin.");
    }

    private static string DescribeShellError(int code) => code switch
    {
        DE_OPCANCELLED => "Recycling the original was cancelled",
        ERROR_SHARING_VIOLATION or DE_ACCESSDENIEDSRC => "Original is open in another program",
        DE_INVALIDFILES => "Windows rejected the original's path",
        0 => "Recycling the original was aborted",
        _ => $"Couldn't recycle the original (shell error 0x{code:X})",
    };

    /// <summary>
    /// Moves a finished temp file into its final place, recycling the original
    /// first. The original's extension may differ from the output's (heic -> jpg),
    /// so this cannot use File.Replace.
    /// </summary>
    public static void PromoteTempOverOriginal(string tempPath, string originalPath, string finalPath)
    {
        // Belt and braces: the caller checks this before doing any work, but nothing
        // here may ever destroy an original that Windows can't hand back.
        if (!CanRecycle(originalPath, out var blocker))
            throw new IOException($"Can't recycle the original — {blocker}.");

        RecycleOriginal(originalPath);
        File.SetAttributes(tempPath, FileAttributes.Normal);
        File.Move(tempPath, finalPath, overwrite: false);
    }
}
