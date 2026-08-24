using System.Globalization;

namespace Photokompressor.Core;

public static class FileSizeFormatting
{
    // Invariant, not current-culture: a comma-decimal locale would otherwise render
    // "5,0 MB" — same class of bug as the slider bubble's locale-formatted numbers.
    public static string For(long bytes) => bytes switch
    {
        >= 1024L * 1024 * 1024 =>
            (bytes / (1024.0 * 1024 * 1024)).ToString("0.00", CultureInfo.InvariantCulture) + " GB",
        >= 1024 * 1024 =>
            (bytes / (1024.0 * 1024)).ToString("0.0", CultureInfo.InvariantCulture) + " MB",
        >= 1024 =>
            (bytes / 1024.0).ToString("0", CultureInfo.InvariantCulture) + " KB",
        _ => $"{bytes} B",
    };
}
