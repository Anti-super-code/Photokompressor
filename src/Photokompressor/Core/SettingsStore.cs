using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Photokompressor.Core;

public static class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static string SettingsPath { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Photokompressor", "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                var json = File.ReadAllText(SettingsPath);
                var settings = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);
                if (settings != null)
                    return Sanitize(settings);
            }
        }
        catch
        {
            // Corrupt or unreadable settings fall back to defaults.
        }
        return new AppSettings();
    }

    public static void Save(AppSettings settings)
    {
        try
        {
            var dir = Path.GetDirectoryName(SettingsPath)!;
            Directory.CreateDirectory(dir);
            File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings, JsonOptions));
        }
        catch
        {
            // Settings persistence is best-effort; never block compression on it.
        }
    }

    private static AppSettings Sanitize(AppSettings s)
    {
        s.BoxWidth = Math.Clamp(s.BoxWidth, 16, 65500);
        s.BoxHeight = Math.Clamp(s.BoxHeight, 16, 65500);
        if (s.LocationMode == OutputLocationMode.CustomFolder && string.IsNullOrWhiteSpace(s.CustomFolder))
            s.LocationMode = OutputLocationMode.Subfolder;
        return s;
    }
}
