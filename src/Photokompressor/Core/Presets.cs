namespace Photokompressor.Core;

public static class Presets
{
    public record JpegParams(int Q, bool ForceSubsampleOn);
    public record PngParams(bool Palette, int Q, double Dither, int Effort);
    public record WebpParams(int Q, int Effort, int AlphaQ);

    public static JpegParams Jpeg(QualityPreset preset) => preset switch
    {
        QualityPreset.High => new JpegParams(82, ForceSubsampleOn: false),
        QualityPreset.Balanced => new JpegParams(72, ForceSubsampleOn: true),
        QualityPreset.Smallest => new JpegParams(58, ForceSubsampleOn: true),
        _ => new JpegParams(72, true),
    };

    public static PngParams Png(QualityPreset preset) => preset switch
    {
        QualityPreset.High => new PngParams(Palette: false, Q: 100, Dither: 1.0, Effort: 7),
        QualityPreset.Balanced => new PngParams(Palette: true, Q: 90, Dither: 1.0, Effort: 7),
        QualityPreset.Smallest => new PngParams(Palette: true, Q: 65, Dither: 0.8, Effort: 10),
        _ => new PngParams(true, 90, 1.0, 7),
    };

    public static WebpParams Webp(QualityPreset preset) => preset switch
    {
        QualityPreset.High => new WebpParams(80, Effort: 4, AlphaQ: 90),
        QualityPreset.Balanced => new WebpParams(68, Effort: 5, AlphaQ: 85),
        QualityPreset.Smallest => new WebpParams(52, Effort: 6, AlphaQ: 80),
        _ => new WebpParams(68, 5, 85),
    };
}
