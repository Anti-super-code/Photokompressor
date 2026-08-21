using System.IO;
using NetVips;
using Photokompressor.Core;
using Image = NetVips.Image;

namespace Photokompressor.Tests;

/// <summary>
/// Integration tests that run the real NetVips pipeline on generated photos.
/// </summary>
public class EngineTests : IDisposable
{
    private readonly string _dir;

    public EngineTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "pk-engine-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_dir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_dir, recursive: true); } catch { }
    }

    /// <summary>Photo-like source: two gradients + gaussian noise, so it neither
    /// compresses to nothing nor defeats the codecs entirely.</summary>
    private string MakeSource(string name, int w = 4000, int h = 3000)
    {
        var path = Path.Combine(_dir, name);
        using var xyz = Image.Xyz(w, h);
        using var xg = xyz[0] * (255.0 / w);
        using var yg = xyz[1] * (255.0 / h);
        using var noise = Image.Gaussnoise(w, h, sigma: 25.0, mean: 128.0);
        using var joined = xg.Bandjoin(yg, noise);
        using var rgb = joined.Cast(Enums.BandFormat.Uchar);
        using var srgb = rgb.Copy(interpretation: Enums.Interpretation.Srgb);
        srgb.WriteToFile(path);
        return path;
    }

    [Theory]
    [InlineData(OutputFormat.Jpeg, QualityPreset.High)]
    [InlineData(OutputFormat.Jpeg, QualityPreset.Balanced)]
    [InlineData(OutputFormat.Jpeg, QualityPreset.Smallest)]
    [InlineData(OutputFormat.WebP, QualityPreset.High)]
    [InlineData(OutputFormat.WebP, QualityPreset.Balanced)]
    [InlineData(OutputFormat.WebP, QualityPreset.Smallest)]
    [InlineData(OutputFormat.Png, QualityPreset.Balanced)]
    [InlineData(OutputFormat.Png, QualityPreset.Smallest)]
    public void CompressesAndFitsBox(OutputFormat format, QualityPreset preset)
    {
        var source = MakeSource("src.png");
        var settings = new AppSettings
        {
            Format = format,
            Preset = preset,
            ResizeEnabled = true,
            BoxWidth = 1920,
            BoxHeight = 1920,
            LocationMode = OutputLocationMode.Subfolder,
        };

        var result = new CompressionEngine().CompressFile(source, settings);

        Assert.Equal(ResultStatus.Compressed, result.Status);
        Assert.NotNull(result.OutputPath);
        Assert.True(File.Exists(result.OutputPath));
        Assert.True(result.AfterBytes < result.BeforeBytes,
            $"{format}/{preset}: {result.AfterBytes} not smaller than {result.BeforeBytes}");

        using var output = Image.NewFromFile(result.OutputPath);
        Assert.True(output.Width <= 1920 && output.Height <= 1920);
        Assert.Equal(1920, Math.Max(output.Width, output.Height)); // aspect-preserving fit
    }

    [Fact]
    public void JpegPresetsAreOrderedBySize()
    {
        var source = MakeSource("ordered.png");
        long SizeFor(QualityPreset p)
        {
            var settings = new AppSettings
            {
                Format = OutputFormat.Jpeg,
                Preset = p,
                ResizeEnabled = true,
                BoxWidth = 1920,
                BoxHeight = 1920,
                LocationMode = OutputLocationMode.CustomFolder,
                CustomFolder = Path.Combine(_dir, p.ToString()),
            };
            var r = new CompressionEngine().CompressFile(source, settings);
            Assert.Equal(ResultStatus.Compressed, r.Status);
            return r.AfterBytes;
        }

        var high = SizeFor(QualityPreset.High);
        var balanced = SizeFor(QualityPreset.Balanced);
        var smallest = SizeFor(QualityPreset.Smallest);
        Assert.True(high > balanced, $"High {high} should exceed Balanced {balanced}");
        Assert.True(balanced > smallest, $"Balanced {balanced} should exceed Smallest {smallest}");
    }

    [Fact]
    public void NeverUpscales()
    {
        var source = MakeSource("small.png", 640, 480);
        var settings = new AppSettings
        {
            Format = OutputFormat.Jpeg,
            ResizeEnabled = true,
            BoxWidth = 4000,
            BoxHeight = 4000,
        };
        var result = new CompressionEngine().CompressFile(source, settings);
        Assert.Equal(ResultStatus.Compressed, result.Status);
        using var output = Image.NewFromFile(result.OutputPath!);
        Assert.Equal(640, output.Width);
        Assert.Equal(480, output.Height);
    }

    [Fact]
    public void BakesExifOrientationAndStripsMetadata()
    {
        // A landscape image tagged orientation=6 (rotate 90 CW) must come out
        // portrait with no orientation tag left.
        var source = Path.Combine(_dir, "rotated.jpg");
        using (var img = MakeVipsImage(1200, 800))
        {
            using var tagged = img.Mutate(m => m.Set(GValue.GIntType, "orientation", 6));
            tagged.Jpegsave(source, q: 90);
        }

        var settings = new AppSettings { Format = OutputFormat.Jpeg, ResizeEnabled = false };
        var result = new CompressionEngine().CompressFile(source, settings);
        Assert.Equal(ResultStatus.Compressed, result.Status);

        using var output = Image.NewFromFile(result.OutputPath!);
        Assert.Equal(800, output.Width);
        Assert.Equal(1200, output.Height);
        Assert.True(output.GetTypeOf("orientation") == 0
                    || output.Get("orientation") is int and 1,
            "orientation tag should be stripped or reset");
        Assert.Equal(0, (long)output.GetTypeOf("exif-data"));
    }

    private static Image MakeVipsImage(int w, int h)
    {
        using var xyz = Image.Xyz(w, h);
        using var xg = xyz[0] * (255.0 / w);
        using var yg = xyz[1] * (255.0 / h);
        using var noise = Image.Gaussnoise(w, h, sigma: 25.0, mean: 128.0);
        using var joined = xg.Bandjoin(yg, noise);
        using var rgb = joined.Cast(Enums.BandFormat.Uchar);
        return rgb.Copy(interpretation: Enums.Interpretation.Srgb);
    }

    [Fact]
    public void AlreadyTinyFileKeepsOriginal()
    {
        // A noisy JPEG converted to lossless PNG is always bigger, so the
        // engine must keep the original.
        var source = Path.Combine(_dir, "tiny.jpg");
        using (var img = MakeVipsImage(1000, 750))
            img.Jpegsave(source, q: 30);

        var settings = new AppSettings { Format = OutputFormat.Png, Preset = QualityPreset.High, ResizeEnabled = false };
        var result = new CompressionEngine().CompressFile(source, settings);

        Assert.Equal(ResultStatus.KeptOriginal, result.Status);
        Assert.True(File.Exists(source));
        Assert.Empty(Directory.GetFiles(Path.Combine(_dir, "Compressed")));
    }

    [Fact]
    public void ForceEvenIfLargerWritesTheBiggerFile()
    {
        var source = Path.Combine(_dir, "tiny2.jpg");
        using (var img = MakeVipsImage(1000, 750))
            img.Jpegsave(source, q: 30);

        var settings = new AppSettings { Format = OutputFormat.Png, Preset = QualityPreset.High, ResizeEnabled = false };
        var engine = new CompressionEngine();

        var normal = engine.CompressFile(source, settings);
        Assert.Equal(ResultStatus.KeptOriginal, normal.Status);
        Assert.Null(normal.OutputPath);

        var forced = engine.CompressFile(source, settings, forceEvenIfLarger: true);
        Assert.Equal(ResultStatus.Compressed, forced.Status);
        Assert.NotNull(forced.OutputPath);
        Assert.True(forced.AfterBytes >= forced.BeforeBytes);
        Assert.True(File.Exists(forced.OutputPath));
        Assert.Equal(forced.AfterBytes, new FileInfo(forced.OutputPath!).Length);
    }

    [Fact]
    public void SecondRunGetsNumberedName()
    {
        var source = MakeSource("dup.png", 800, 600);
        var settings = new AppSettings { Format = OutputFormat.Jpeg, ResizeEnabled = false };

        var first = new CompressionEngine().CompressFile(source, settings);
        var second = new CompressionEngine().CompressFile(source, settings);

        Assert.Equal(ResultStatus.Compressed, first.Status);
        Assert.Equal(ResultStatus.Compressed, second.Status);
        Assert.EndsWith("dup.jpg", first.OutputPath!);
        Assert.EndsWith("dup (1).jpg", second.OutputPath!);
    }

    [Fact]
    public void ReplaceModeSwapsFileInPlace()
    {
        var source = MakeSource("replace-me.png", 1600, 1200);
        var settings = new AppSettings
        {
            Format = OutputFormat.Jpeg,
            KeepOriginals = false,
            ResizeEnabled = false,
        };

        var result = new CompressionEngine().CompressFile(source, settings);

        Assert.Equal(ResultStatus.Compressed, result.Status);
        Assert.False(File.Exists(source), "original .png should be recycled");
        Assert.Equal(Path.Combine(_dir, "replace-me.jpg"), result.OutputPath);
        Assert.True(File.Exists(result.OutputPath));
    }

    [Fact]
    public void ReadOnlyOriginalCanBeReplaced()
    {
        var source = MakeSource("readonly.png", 800, 600);
        File.SetAttributes(source, FileAttributes.ReadOnly);
        try
        {
            var settings = new AppSettings { Format = OutputFormat.Jpeg, KeepOriginals = false, ResizeEnabled = false };
            var result = new CompressionEngine().CompressFile(source, settings);
            Assert.Equal(ResultStatus.Compressed, result.Status);
            Assert.False(File.Exists(source));
        }
        finally
        {
            if (File.Exists(source))
                File.SetAttributes(source, FileAttributes.Normal);
        }
    }

    [Fact]
    public void CorruptFileFailsGracefully()
    {
        var source = Path.Combine(_dir, "corrupt.jpg");
        File.WriteAllBytes(source, [0xFF, 0xD8, 0x00, 0x01, 0x02]);

        var result = new CompressionEngine().CompressFile(source, new AppSettings());
        Assert.Equal(ResultStatus.Failed, result.Status);
        Assert.NotNull(result.Note);
        Assert.True(File.Exists(source), "corrupt original must not be touched");
    }

    [Theory]
    [InlineData("src.tif")]
    [InlineData("src.gif")]
    [InlineData("src.webp")]
    public void OtherInputFormatsWork(string name)
    {
        var source = MakeSource(name, 1200, 900);
        var settings = new AppSettings { Format = OutputFormat.Jpeg, ResizeEnabled = false };
        var result = new CompressionEngine().CompressFile(source, settings);
        Assert.Equal(ResultStatus.Compressed, result.Status);
    }

    [Fact]
    public void BmpInputWorksViaMagickFallback()
    {
        var pngSource = MakeSource("bmp-src.png", 800, 600);
        var bmpSource = Path.Combine(_dir, "photo.bmp");
        using (var magick = new ImageMagick.MagickImage(pngSource))
            magick.Write(bmpSource, ImageMagick.MagickFormat.Bmp);

        var settings = new AppSettings { Format = OutputFormat.Jpeg, ResizeEnabled = false };
        var result = new CompressionEngine().CompressFile(bmpSource, settings);
        Assert.Equal(ResultStatus.Compressed, result.Status);
        using var output = Image.NewFromFile(result.OutputPath!);
        Assert.Equal(800, output.Width);
    }

    [Fact]
    public void MozjpegFlagsAreSupportedByBundledLibvips()
    {
        // The engine has a fallback for non-mozjpeg builds, but we expect the
        // bundled binaries to accept these flags — fail loudly if that changes.
        var path = Path.Combine(_dir, "moz.jpg");
        using var img = MakeVipsImage(200, 150);
        img.Jpegsave(path, q: 75, trellisQuant: true, overshootDeringing: true,
            optimizeScans: true, quantTable: 3, keep: Enums.ForeignKeep.None);
        Assert.True(new FileInfo(path).Length > 0);
    }

    [Fact]
    public void HeicDecodeDelegateIsPresent()
    {
        Assert.True(HeicDecoder.IsSupported(),
            "Magick.NET should ship with HEIC read support on Windows");
    }
}
