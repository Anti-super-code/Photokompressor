using System.IO;
using Photokompressor.Core;

namespace Photokompressor.Tests;

/// <summary>
/// Guards the promise replace mode makes: an original is only ever deleted where
/// Windows will genuinely hand it back.
/// </summary>
public class SafeReplaceTests : IDisposable
{
    private readonly string _tempDir;

    public SafeReplaceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "pk-recycle-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, recursive: true); } catch { }
    }

    [Fact]
    public void OrdinaryLocalFileCanBeRecycled()
    {
        var path = Path.Combine(_tempDir, "photo.jpg");
        File.WriteAllBytes(path, new byte[64]);

        Assert.True(SafeReplace.CanRecycle(path, out var reason), reason);
        Assert.Equal("", reason);
    }

    [Fact]
    public void NetworkPathIsRefusedWithAReason()
    {
        // UNC shares keep no Recycle Bin, so a delete there is permanent.
        Assert.False(SafeReplace.CanRecycle(@"\\server\share\photo.jpg", out var reason));
        Assert.Contains("Recycle Bin", reason);
    }

    [Fact]
    public void PromotingOverAnUnrecyclableOriginalThrowsRatherThanDeleting()
    {
        var ex = Assert.Throws<IOException>(() =>
            SafeReplace.PromoteTempOverOriginal(
                Path.Combine(_tempDir, "temp.jpg"),
                @"\\server\share\photo.jpg",
                @"\\server\share\photo.jpg"));

        Assert.Contains("Can't recycle the original", ex.Message);
    }

    [Fact]
    public void RefusalReasonReadsAsPartOfASentence()
    {
        SafeReplace.CanRecycle(@"\\server\share\photo.jpg", out var reason);

        // It gets appended after an em dash in the results list, so it must not
        // arrive pre-capitalised or pre-punctuated.
        Assert.False(char.IsUpper(reason[0]));
        Assert.DoesNotContain(".", reason);
    }
}
