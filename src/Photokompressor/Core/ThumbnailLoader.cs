using System.IO;
using System.Windows.Media.Imaging;
using NetVips;

namespace Photokompressor.Core;

/// <summary>
/// Small preview thumbnails for the gallery tray — same decode path as the
/// compression pipeline (libvips, with the Magick.NET/HEIC bridge as a
/// fallback for formats libvips' Windows build can't read), but shrunk far
/// enough that decode cost is negligible even for a big batch of RAW-sized photos.
/// </summary>
public static class ThumbnailLoader
{
    public static Task<BitmapSource?> LoadAsync(string path, int maxPixels = 120) =>
        Task.Run(() =>
        {
            try
            {
                return Decode(path, maxPixels);
            }
            catch
            {
                // A bad/unreadable file just gets no thumbnail — the row still
                // shows its filename and size.
                return null;
            }
        });

    private static BitmapSource Decode(string path, int maxPixels)
    {
        Image thumb;
        if (HeicDecoder.IsHeic(path))
        {
            using var full = HeicDecoder.Load(path);
            thumb = full.ThumbnailImage(maxPixels, height: maxPixels, size: Enums.Size.Down);
        }
        else
        {
            try
            {
                thumb = Image.Thumbnail(path, maxPixels, height: maxPixels, size: Enums.Size.Down);
            }
            catch (VipsException)
            {
                using var full = HeicDecoder.Load(path);
                thumb = full.ThumbnailImage(maxPixels, height: maxPixels, size: Enums.Size.Down);
            }
        }

        byte[] bytes;
        using (thumb)
            bytes = thumb.PngsaveBuffer();

        using var ms = new MemoryStream(bytes);
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.StreamSource = ms;
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }
}
