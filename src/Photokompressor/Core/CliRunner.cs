using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Photokompressor.Core;

/// <summary>
/// Hidden headless mode so the engine can be exercised and tested without UI:
/// Photokompressor.exe --cli file... [--format jpeg|webp|png] [--preset high|balanced|smallest]
///                     [--fit WxH] [--replace] [--suffix] [--outdir path] [--report results.json]
/// </summary>
public static class CliRunner
{
    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int dwProcessId);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static int Run(string[] args)
    {
        AttachConsole(-1);
        var files = new List<string>();
        var settings = new AppSettings { ResizeEnabled = false };
        string? reportPath = null;

        try
        {
            for (var i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--format": settings.Format = Enum.Parse<OutputFormat>(args[++i], ignoreCase: true); break;
                    case "--preset": settings.Preset = ParsePreset(args[++i]); break;
                    case "--fit":
                        var parts = args[++i].Split('x', 'X');
                        settings.ResizeEnabled = true;
                        settings.BoxWidth = int.Parse(parts[0]);
                        settings.BoxHeight = int.Parse(parts[1]);
                        break;
                    case "--replace": settings.KeepOriginals = false; break;
                    case "--suffix": settings.LocationMode = OutputLocationMode.Suffix; break;
                    case "--outdir":
                        settings.LocationMode = OutputLocationMode.CustomFolder;
                        settings.CustomFolder = Path.GetFullPath(args[++i]);
                        break;
                    case "--report": reportPath = Path.GetFullPath(args[++i]); break;
                    default: files.Add(Path.GetFullPath(args[i])); break;
                }
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Bad arguments: {ex.Message}");
            return 2;
        }

        CompressionEngine.ConfigureConcurrency(1);
        var engine = new CompressionEngine();
        var results = new List<CompressionResult>();
        foreach (var file in files)
        {
            var r = engine.CompressFile(file, settings);
            results.Add(r);
            Console.WriteLine($"{r.Status}: {r.InputPath} -> {r.OutputPath ?? "-"} " +
                              $"({r.BeforeBytes} -> {r.AfterBytes} bytes){(r.Note != null ? $" [{r.Note}]" : "")}");
        }

        if (reportPath != null)
            File.WriteAllText(reportPath, JsonSerializer.Serialize(results, JsonOptions));

        return results.Any(r => r.Status == ResultStatus.Failed) ? 1 : 0;
    }

    /// <summary>The smallest preset is labelled "Low" in the UI; accept either name.</summary>
    private static QualityPreset ParsePreset(string value) => value.ToLowerInvariant() switch
    {
        "low" or "smallest" => QualityPreset.Smallest,
        _ => Enum.Parse<QualityPreset>(value, ignoreCase: true),
    };
}
