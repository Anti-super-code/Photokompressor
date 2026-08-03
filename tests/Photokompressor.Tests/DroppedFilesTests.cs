using System.IO;
using System.Windows;
using Photokompressor.UI;

namespace Photokompressor.Tests;

/// <summary>
/// Covers what a shell drop turns into. The OS-level wiring (AllowDrop + the
/// DragEnter/Drop handlers) can only be exercised by a real mouse, but this is
/// where the filtering and folder-expansion logic lives.
/// </summary>
public class DroppedFilesTests : IDisposable
{
    private readonly string _dir;

    public DroppedFilesTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "pk-drop-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_dir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_dir, recursive: true); } catch { }
    }

    private string Touch(string relativePath)
    {
        var path = Path.Combine(_dir, relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "x");
        return path;
    }

    private static DataObject Drop(params string[] paths) => new(DataFormats.FileDrop, paths);

    [Fact]
    public void KeepsSupportedImagesOnly()
    {
        var jpg = Touch("a.jpg");
        var heic = Touch("b.HEIC");
        var txt = Touch("notes.txt");
        var doc = Touch("thing.pdf");

        var result = DroppedFiles.Collect(Drop(jpg, heic, txt, doc));

        Assert.Equal(2, result.Count);
        Assert.Contains(jpg, result);
        Assert.Contains(heic, result);
    }

    [Fact]
    public void ExpandsFolderTopLevelOnly()
    {
        var top = Touch(Path.Combine("album", "one.jpg"));
        Touch(Path.Combine("album", "readme.txt"));
        Touch(Path.Combine("album", "nested", "deep.jpg"));

        var result = DroppedFiles.Collect(Drop(Path.Combine(_dir, "album")));

        Assert.Single(result);
        Assert.Contains(top, result);
    }

    [Fact]
    public void MixesLooseFilesAndFolders()
    {
        var loose = Touch("loose.png");
        Touch(Path.Combine("folder", "inside.webp"));

        var result = DroppedFiles.Collect(Drop(loose, Path.Combine(_dir, "folder")));

        Assert.Equal(2, result.Count);
        Assert.Contains(loose, result);
    }

    [Fact]
    public void EmptyWhenNothingUsable()
    {
        var txt = Touch("notes.txt");
        Assert.Empty(DroppedFiles.Collect(Drop(txt)));
        Assert.Empty(DroppedFiles.Collect(new DataObject(DataFormats.Text, "hello")));
    }

    [Fact]
    public void MissingPathsAreSkipped()
    {
        var result = DroppedFiles.Collect(Drop(Path.Combine(_dir, "gone.jpg")));
        Assert.Empty(result);
    }

    [Fact]
    public void LooksDroppableMatchesDragFeedback()
    {
        var jpg = Touch("a.jpg");
        var txt = Touch("notes.txt");
        Assert.True(DroppedFiles.LooksDroppable(Drop(jpg)));
        Assert.True(DroppedFiles.LooksDroppable(Drop(_dir)));
        Assert.False(DroppedFiles.LooksDroppable(Drop(txt)));
        Assert.False(DroppedFiles.LooksDroppable(new DataObject(DataFormats.Text, "hello")));
    }
}
