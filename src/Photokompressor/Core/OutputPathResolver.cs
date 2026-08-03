using System.IO;

namespace Photokompressor.Core;

/// <summary>
/// Resolves the final destination path for a compressed file, including collision
/// numbering that is safe under parallel batches (two inputs like a.png and a.jpg
/// can both map to a.jpg).
/// </summary>
public class OutputPathResolver
{
    private readonly HashSet<string> _reserved = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();

    /// <summary>
    /// When KeepOriginals is false the output goes next to the original with the
    /// original base name (in-place replace); location mode is ignored.
    /// </summary>
    public string Resolve(string inputPath, AppSettings settings)
    {
        var inputDir = Path.GetDirectoryName(inputPath) ?? "";
        var baseName = Path.GetFileNameWithoutExtension(inputPath);
        var ext = settings.ExtensionForFormat();

        string dir;
        string name;
        if (!settings.KeepOriginals)
        {
            dir = inputDir;
            name = baseName;
        }
        else
        {
            switch (settings.LocationMode)
            {
                case OutputLocationMode.Subfolder:
                    dir = Path.Combine(inputDir, AppSettings.SubfolderName);
                    name = baseName;
                    break;
                case OutputLocationMode.Suffix:
                    dir = inputDir;
                    name = baseName + AppSettings.SuffixText;
                    break;
                case OutputLocationMode.CustomFolder:
                default:
                    dir = settings.CustomFolder;
                    name = baseName;
                    break;
            }
        }

        lock (_gate)
        {
            var candidate = Path.Combine(dir, name + ext);
            var counter = 1;
            while (IsTaken(candidate, inputPath, settings))
            {
                candidate = Path.Combine(dir, $"{name} ({counter}){ext}");
                counter++;
            }
            _reserved.Add(candidate);
            return candidate;
        }
    }

    private bool IsTaken(string candidate, string inputPath, AppSettings settings)
    {
        if (_reserved.Contains(candidate))
            return true;
        // In replace mode the original file itself will be recycled, so landing on
        // the input path (e.g. photo.jpg -> photo.jpg) is not a collision.
        if (!settings.KeepOriginals && string.Equals(candidate, inputPath, StringComparison.OrdinalIgnoreCase))
            return false;
        return File.Exists(candidate);
    }
}
