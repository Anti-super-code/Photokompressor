using System.IO;
using Photokompressor.Core;

namespace Photokompressor.Tests;

public class SettingsStoreTests : IDisposable
{
    private readonly string _tempDir;

    public SettingsStoreTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "pk-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempDir);
        SettingsStore.SettingsPath = Path.Combine(_tempDir, "settings.json");
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, recursive: true); } catch { }
    }

    [Fact]
    public void RoundTripsAllFields()
    {
        var s = new AppSettings
        {
            Format = OutputFormat.WebP,
            Preset = QualityPreset.Smallest,
            ResizeEnabled = false,
            BoxWidth = 800,
            BoxHeight = 600,
            KeepOriginals = false,
            LocationMode = OutputLocationMode.CustomFolder,
            CustomFolder = @"C:\Some\Folder",
        };
        SettingsStore.Save(s);
        var loaded = SettingsStore.Load();

        Assert.Equal(OutputFormat.WebP, loaded.Format);
        Assert.Equal(QualityPreset.Smallest, loaded.Preset);
        Assert.False(loaded.ResizeEnabled);
        Assert.Equal(800, loaded.BoxWidth);
        Assert.Equal(600, loaded.BoxHeight);
        Assert.False(loaded.KeepOriginals);
        Assert.Equal(OutputLocationMode.CustomFolder, loaded.LocationMode);
        Assert.Equal(@"C:\Some\Folder", loaded.CustomFolder);
    }

    [Fact]
    public void MissingFileGivesDefaults()
    {
        var loaded = SettingsStore.Load();
        Assert.Equal(OutputFormat.Jpeg, loaded.Format);
        Assert.Equal(QualityPreset.Balanced, loaded.Preset);
        Assert.True(loaded.KeepOriginals);
    }

    [Fact]
    public void CorruptFileGivesDefaults()
    {
        File.WriteAllText(SettingsStore.SettingsPath, "{not json!!");
        var loaded = SettingsStore.Load();
        Assert.Equal(OutputFormat.Jpeg, loaded.Format);
    }

    [Fact]
    public void CustomFolderModeWithoutFolderFallsBackToSubfolder()
    {
        SettingsStore.Save(new AppSettings
        {
            LocationMode = OutputLocationMode.CustomFolder,
            CustomFolder = "",
        });
        var loaded = SettingsStore.Load();
        Assert.Equal(OutputLocationMode.Subfolder, loaded.LocationMode);
    }
}

public class OutputPathResolverTests : IDisposable
{
    private readonly string _tempDir;

    public OutputPathResolverTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "pk-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, recursive: true); } catch { }
    }

    private string Input(string name)
    {
        var path = Path.Combine(_tempDir, name);
        File.WriteAllText(path, "x");
        return path;
    }

    [Fact]
    public void SubfolderMode()
    {
        var result = new OutputPathResolver().Resolve(Input("photo.png"),
            new AppSettings { Format = OutputFormat.Jpeg, LocationMode = OutputLocationMode.Subfolder });
        Assert.Equal(Path.Combine(_tempDir, "Compressed", "photo.jpg"), result);
    }

    [Fact]
    public void SuffixMode()
    {
        var result = new OutputPathResolver().Resolve(Input("photo.png"),
            new AppSettings { Format = OutputFormat.WebP, LocationMode = OutputLocationMode.Suffix });
        Assert.Equal(Path.Combine(_tempDir, "photo-compressed.webp"), result);
    }

    [Fact]
    public void CustomFolderMode()
    {
        var result = new OutputPathResolver().Resolve(Input("photo.png"),
            new AppSettings
            {
                Format = OutputFormat.Jpeg,
                LocationMode = OutputLocationMode.CustomFolder,
                CustomFolder = @"C:\Out",
            });
        Assert.Equal(@"C:\Out\photo.jpg", result);
    }

    [Fact]
    public void ReplaceModeIgnoresLocationAndLandsOnInputPath()
    {
        var input = Input("photo.jpg");
        var result = new OutputPathResolver().Resolve(input,
            new AppSettings
            {
                Format = OutputFormat.Jpeg,
                KeepOriginals = false,
                LocationMode = OutputLocationMode.Subfolder,
            });
        Assert.Equal(input, result);
    }

    [Fact]
    public void ReplaceModeChangesExtensionInPlace()
    {
        var input = Input("photo.heic");
        var result = new OutputPathResolver().Resolve(input,
            new AppSettings { Format = OutputFormat.Jpeg, KeepOriginals = false });
        Assert.Equal(Path.Combine(_tempDir, "photo.jpg"), result);
    }

    [Fact]
    public void TwoInputsMappingToSameNameGetNumbered()
    {
        var resolver = new OutputPathResolver();
        var settings = new AppSettings { Format = OutputFormat.Jpeg, LocationMode = OutputLocationMode.Subfolder };
        var first = resolver.Resolve(Input("a.png"), settings);
        var second = resolver.Resolve(Input("a.jpg"), settings);
        Assert.Equal(Path.Combine(_tempDir, "Compressed", "a.jpg"), first);
        Assert.Equal(Path.Combine(_tempDir, "Compressed", "a (1).jpg"), second);
    }

    [Fact]
    public void ExistingFileOnDiskGetsNumbered()
    {
        Directory.CreateDirectory(Path.Combine(_tempDir, "Compressed"));
        File.WriteAllText(Path.Combine(_tempDir, "Compressed", "photo.jpg"), "existing");
        var result = new OutputPathResolver().Resolve(Input("photo.png"),
            new AppSettings { Format = OutputFormat.Jpeg, LocationMode = OutputLocationMode.Subfolder });
        Assert.Equal(Path.Combine(_tempDir, "Compressed", "photo (1).jpg"), result);
    }
}

public class PresetTests
{
    [Fact]
    public void JpegQualityDecreasesWithPreset()
    {
        Assert.True(Presets.Jpeg(QualityPreset.High).Q > Presets.Jpeg(QualityPreset.Balanced).Q);
        Assert.True(Presets.Jpeg(QualityPreset.Balanced).Q > Presets.Jpeg(QualityPreset.Smallest).Q);
    }

    [Fact]
    public void PngHighIsLossless()
    {
        Assert.False(Presets.Png(QualityPreset.High).Palette);
        Assert.True(Presets.Png(QualityPreset.Balanced).Palette);
        Assert.True(Presets.Png(QualityPreset.Smallest).Palette);
    }

    [Fact]
    public void WebpQualityDecreasesWithPreset()
    {
        Assert.True(Presets.Webp(QualityPreset.High).Q > Presets.Webp(QualityPreset.Balanced).Q);
        Assert.True(Presets.Webp(QualityPreset.Balanced).Q > Presets.Webp(QualityPreset.Smallest).Q);
    }
}
