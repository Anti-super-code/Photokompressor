namespace Photokompressor.Core;

public enum OutputFormat
{
    Jpeg,
    WebP,
    Png,
}

public enum QualityPreset
{
    High,
    Balanced,
    Smallest,
}

public enum OutputLocationMode
{
    Subfolder,
    Suffix,
    CustomFolder,
}

public class AppSettings
{
    public OutputFormat Format { get; set; } = OutputFormat.Jpeg;
    public QualityPreset Preset { get; set; } = QualityPreset.Balanced;

    public bool ResizeEnabled { get; set; } = true;
    public int BoxWidth { get; set; } = 1920;
    public int BoxHeight { get; set; } = 1920;

    public bool KeepOriginals { get; set; } = true;

    /// <summary>Only applies when KeepOriginals is true; replace mode always writes in place.</summary>
    public OutputLocationMode LocationMode { get; set; } = OutputLocationMode.Subfolder;
    public string CustomFolder { get; set; } = "";

    public const string SubfolderName = "Compressed";
    public const string SuffixText = "-compressed";

    public string ExtensionForFormat() => Format switch
    {
        OutputFormat.Jpeg => ".jpg",
        OutputFormat.WebP => ".webp",
        OutputFormat.Png => ".png",
        _ => ".jpg",
    };

    public AppSettings Clone() => (AppSettings)MemberwiseClone();
}
