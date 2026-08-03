using System.IO;
using System.Windows;
using Photokompressor.Core;

namespace Photokompressor.UI;

/// <summary>Turns an Explorer drop into the list of images the app can actually open.</summary>
public static class DroppedFiles
{
    public static bool IsSupported(string path) =>
        ShellRegistration.Extensions.Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase);

    /// <summary>Cheap check for drag feedback — never enumerates folder contents.</summary>
    public static bool LooksDroppable(IDataObject data) =>
        data.GetData(DataFormats.FileDrop) is string[] paths
        && paths.Any(p => IsSupported(p) || Directory.Exists(p));

    /// <summary>
    /// Files first, then the top level of any dropped folders — deliberately not
    /// recursive, so dropping a photo library doesn't silently queue thousands of files.
    /// </summary>
    public static List<string> Collect(IDataObject data)
    {
        var result = new List<string>();
        if (data.GetData(DataFormats.FileDrop) is not string[] paths)
            return result;

        foreach (var path in paths)
        {
            try
            {
                if (Directory.Exists(path))
                    result.AddRange(Directory.EnumerateFiles(path).Where(IsSupported));
                else if (File.Exists(path) && IsSupported(path))
                    result.Add(path);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                // Unreadable folder — just skip it rather than failing the whole drop.
            }
        }
        return result;
    }
}
