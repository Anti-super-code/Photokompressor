using System.IO;
using ImageMagick;
using NetVips;

namespace Photokompressor.Core;

public enum ResultStatus
{
    Compressed,
    KeptOriginal,
    Failed,
    Cancelled,
}

public record CompressionResult(
    string InputPath,
    string? OutputPath,
    long BeforeBytes,
    long AfterBytes,
    ResultStatus Status,
    string? Note);

public class CompressionEngine
{
    private readonly OutputPathResolver _resolver = new();

    /// <summary>Longest path the native codecs handle reliably; longer paths are bounced through %TEMP%.</summary>
    private const int MaxNativePathLength = 240;

    /// <summary>WebP hard format limit per side.</summary>
    private const int WebpMaxDimension = 16383;

    public static void ConfigureConcurrency(int taskDegreeOfParallelism)
    {
        NetVips.NetVips.Concurrency = Math.Max(2, Environment.ProcessorCount / taskDegreeOfParallelism);

        // libvips' operation cache holds decoded images — and keeps their source files
        // open — which blocks recycling the original in replace mode. Every file is
        // read exactly once here, so the cache buys nothing and only costs us locks.
        Cache.Max = 0;
    }

    public static int TaskDegreeOfParallelism => Math.Clamp(Environment.ProcessorCount / 2, 1, 4);

    public async Task RunBatchAsync(IReadOnlyList<string> files, AppSettings settings,
        IProgress<CompressionResult> progress, CancellationToken ct)
    {
        var frozen = settings.Clone();
        try
        {
            await Parallel.ForEachAsync(files,
                new ParallelOptions { MaxDegreeOfParallelism = TaskDegreeOfParallelism, CancellationToken = ct },
                (file, token) =>
                {
                    progress.Report(CompressFile(file, frozen, token));
                    return ValueTask.CompletedTask;
                });
        }
        catch (OperationCanceledException)
        {
            // Cancelled results for files that never started were already reported
            // by CompressFile's own token check; nothing further to do.
        }
    }

    public CompressionResult CompressFile(string inputPath, AppSettings settings, CancellationToken ct = default,
        bool forceEvenIfLarger = false)
    {
        long beforeBytes = 0;
        string? tempPath = null;
        var cleanup = new List<string>();
        try
        {
            if (ct.IsCancellationRequested)
                return new(inputPath, null, 0, 0, ResultStatus.Cancelled, null);

            var info = new FileInfo(inputPath);
            if (!info.Exists)
                return new(inputPath, null, 0, 0, ResultStatus.Failed, "File not found");
            beforeBytes = info.Length;

            // Replace mode is only safe where Windows will really hand the original
            // back. Checked before any work so nothing is compressed and thrown away.
            if (!settings.KeepOriginals && !SafeReplace.CanRecycle(inputPath, out var blocker))
            {
                return new(inputPath, null, beforeBytes, beforeBytes, ResultStatus.Failed,
                    $"Left alone — {blocker}. Switch on Keep originals to compress it.");
            }

            var finalPath = _resolver.Resolve(inputPath, settings);
            var destDir = Path.GetDirectoryName(finalPath)!;
            Directory.CreateDirectory(destDir);

            tempPath = Path.Combine(destDir, $".pk-tmp-{Guid.NewGuid():N}{settings.ExtensionForFormat()}");
            var nativeTempPath = tempPath;
            if (tempPath.Length > MaxNativePathLength)
            {
                nativeTempPath = Path.Combine(Path.GetTempPath(),
                    $"pk-out-{Guid.NewGuid():N}{settings.ExtensionForFormat()}");
            }

            var nativeInputPath = inputPath;
            if (inputPath.Length > MaxNativePathLength)
            {
                nativeInputPath = Path.Combine(Path.GetTempPath(),
                    $"pk-in-{Guid.NewGuid():N}{Path.GetExtension(inputPath)}");
                File.Copy(inputPath, nativeInputPath, overwrite: true);
                cleanup.Add(nativeInputPath);
            }

            string? note;
            using (var image = LoadPipeline(nativeInputPath, settings, out note))
            {
                Save(image, nativeTempPath, settings);
            }

            if (!ReferenceEquals(nativeTempPath, tempPath) && nativeTempPath != tempPath)
            {
                File.Move(nativeTempPath, tempPath);
            }
            try { File.SetAttributes(tempPath, File.GetAttributes(tempPath) | FileAttributes.Hidden); }
            catch { /* hidden temp is cosmetic */ }

            var afterBytes = new FileInfo(tempPath).Length;
            if (afterBytes <= 0)
                throw new InvalidOperationException("Output file is empty.");

            if (afterBytes >= beforeBytes && !forceEvenIfLarger)
            {
                File.Delete(tempPath);
                return new(inputPath, null, beforeBytes, beforeBytes, ResultStatus.KeptOriginal,
                    "Already smaller — kept original");
            }

            if (settings.KeepOriginals)
            {
                File.SetAttributes(tempPath, FileAttributes.Normal);
                File.Move(tempPath, finalPath, overwrite: false);
            }
            else
            {
                SafeReplace.PromoteTempOverOriginal(tempPath, inputPath, finalPath);
            }
            return new(inputPath, finalPath, beforeBytes, afterBytes, ResultStatus.Compressed, note);
        }
        catch (Exception ex)
        {
            TryDelete(tempPath);
            return new(inputPath, null, beforeBytes, 0, ResultStatus.Failed, FriendlyError(ex));
        }
        finally
        {
            foreach (var path in cleanup)
                TryDelete(path);
        }
    }

    private static Image LoadPipeline(string path, AppSettings settings, out string? note)
    {
        note = null;
        // Size.Down never upscales, so a huge box is a no-op resize that still
        // gives us auto-rotation and ICC handling from the same code path.
        var boxW = settings.ResizeEnabled ? settings.BoxWidth : 5_000_000;
        var boxH = settings.ResizeEnabled ? settings.BoxHeight : 5_000_000;

        Image image;
        if (HeicDecoder.IsHeic(path))
        {
            image = LoadViaMagick(path, settings, boxW, boxH);
        }
        else
        {
            try
            {
                image = Image.Thumbnail(path, boxW, height: boxH, size: Enums.Size.Down, outputProfile: "srgb");
            }
            catch (VipsException)
            {
                // libvips' Windows build lacks some loaders (BMP among them);
                // ImageMagick reads far more, so give it a shot before failing.
                image = LoadViaMagick(path, settings, boxW, boxH);
            }
        }

        try
        {
            if (image.GetTypeOf("n-pages") != 0 && image.Get("n-pages") is int pages && pages > 1)
                note = "Animated input — first frame only";
        }
        catch { /* metadata probe is best-effort */ }

        if (settings.Format == OutputFormat.WebP
            && (image.Width > WebpMaxDimension || image.Height > WebpMaxDimension))
        {
            var shrunk = image.ThumbnailImage(WebpMaxDimension, height: WebpMaxDimension, size: Enums.Size.Down);
            image.Dispose();
            image = shrunk;
            note = note == null ? "Reduced to WebP's 16383 px limit" : note + "; reduced to WebP's 16383 px limit";
        }
        return image;
    }

    private static Image LoadViaMagick(string path, AppSettings settings, int boxW, int boxH)
    {
        var full = HeicDecoder.Load(path);
        if (!settings.ResizeEnabled)
            return full;
        var resized = full.ThumbnailImage(boxW, height: boxH, size: Enums.Size.Down);
        full.Dispose();
        return resized;
    }

    private static void Save(Image image, string tempPath, AppSettings settings)
    {
        switch (settings.Format)
        {
            case OutputFormat.Jpeg:
            {
                var p = Presets.Jpeg(settings.Preset);
                var subsample = p.ForceSubsampleOn ? Enums.ForeignSubsample.On : Enums.ForeignSubsample.Auto;
                var flat = image.HasAlpha() ? image.Flatten(background: [255.0, 255.0, 255.0]) : image;
                try
                {
                    try
                    {
                        flat.Jpegsave(tempPath, q: p.Q, subsampleMode: subsample,
                            optimizeCoding: true, interlace: true, trellisQuant: true,
                            overshootDeringing: true, optimizeScans: true, quantTable: 3,
                            keep: Enums.ForeignKeep.None);
                    }
                    catch (VipsException)
                    {
                        // Bundled libvips without mozjpeg: retry with baseline flags.
                        TryDelete(tempPath);
                        flat.Jpegsave(tempPath, q: p.Q, subsampleMode: subsample,
                            optimizeCoding: true, interlace: true,
                            keep: Enums.ForeignKeep.None);
                    }
                }
                finally
                {
                    if (!ReferenceEquals(flat, image))
                        flat.Dispose();
                }
                break;
            }
            case OutputFormat.Png:
            {
                var p = Presets.Png(settings.Preset);
                if (p.Palette)
                {
                    image.Pngsave(tempPath, compression: 9, palette: true, q: p.Q,
                        dither: p.Dither, effort: p.Effort, keep: Enums.ForeignKeep.None);
                }
                else
                {
                    image.Pngsave(tempPath, compression: 9, keep: Enums.ForeignKeep.None);
                }
                break;
            }
            case OutputFormat.WebP:
            {
                var p = Presets.Webp(settings.Preset);
                image.Webpsave(tempPath, q: p.Q, effort: p.Effort, smartSubsample: true,
                    alphaQ: p.AlphaQ, preset: Enums.ForeignWebpPreset.Photo,
                    keep: Enums.ForeignKeep.None);
                break;
            }
        }
    }

    private static string FriendlyError(Exception ex) => ex switch
    {
        VipsException => "Couldn't read or convert this file",
        MagickException => "Couldn't read this file",
        UnauthorizedAccessException => "Access denied",
        IOException io when (io.HResult & 0xFFFF) == 32 => "File is in use by another program",
        IOException io when (io.HResult & 0xFFFF) == 112 => "Disk full",
        _ => ex.Message,
    };

    private static void TryDelete(string? path)
    {
        if (path == null) return;
        try { if (File.Exists(path)) File.Delete(path); }
        catch { /* cleanup is best-effort */ }
    }
}
