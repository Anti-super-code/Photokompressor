using System.IO;
using System.Runtime.InteropServices;

namespace Photokompressor.Core;

public static class SafeReplace
{
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
    /// Sends a file to the Recycle Bin — never a hard delete — without showing any
    /// shell UI. Clears the read-only attribute first, which would otherwise fail it.
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
        RecycleOriginal(originalPath);
        File.SetAttributes(tempPath, FileAttributes.Normal);
        File.Move(tempPath, finalPath, overwrite: false);
    }
}
