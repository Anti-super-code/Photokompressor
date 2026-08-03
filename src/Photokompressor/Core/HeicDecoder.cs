using ImageMagick;
using ImageMagick.Formats;
using NetVips;

namespace Photokompressor.Core;

/// <summary>
/// The bundled libvips Windows binaries cannot decode HEIC (H.265 patent licensing),
/// so iPhone photos are decoded with Magick.NET and handed to NetVips as a raw
/// RGB(A) buffer. Decode only — we never encode HEIC. Load also doubles as the
/// fallback for anything else libvips can't read (e.g. BMP).
/// </summary>
public static class HeicDecoder
{
    public static bool IsHeic(string path)
    {
        var ext = System.IO.Path.GetExtension(path);
        return ext.Equals(".heic", StringComparison.OrdinalIgnoreCase)
            || ext.Equals(".heif", StringComparison.OrdinalIgnoreCase);
    }

    public static bool IsSupported()
    {
        try
        {
            var format = MagickNET.SupportedFormats.FirstOrDefault(f => f.Format == MagickFormat.Heic);
            return format is { SupportsReading: true };
        }
        catch
        {
            return false;
        }
    }

    public static Image Load(string path)
    {
        using var magick = new MagickImage(path);
        magick.AutoOrient();

        // iPhone photos are commonly Display P3; convert to sRGB before the
        // profile is stripped so colors don't shift.
        if (magick.GetColorProfile() != null)
            magick.TransformColorSpace(ColorProfiles.SRGB);

        bool hasAlpha = magick.HasAlpha;
        var map = hasAlpha ? "RGBA" : "RGB";
        using var pixels = magick.GetPixelsUnsafe();
        var bytes = pixels.ToByteArray(map)
            ?? throw new InvalidOperationException("HEIC pixel export returned no data.");

        var image = Image.NewFromMemoryCopy<byte>(bytes, (int)magick.Width, (int)magick.Height,
            hasAlpha ? 4 : 3, Enums.BandFormat.Uchar);
        return image.Copy(interpretation: Enums.Interpretation.Srgb);
    }
}
