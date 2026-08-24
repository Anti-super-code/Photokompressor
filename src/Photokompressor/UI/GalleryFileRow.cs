using System.ComponentModel;
using System.IO;
using System.Windows.Media.Imaging;
using Photokompressor.Core;

namespace Photokompressor.UI;

/// <summary>One row in the gallery tray — the file path plus its lazily-loaded thumbnail.</summary>
public class GalleryFileRow : INotifyPropertyChanged
{
    public string Path { get; }
    public string FileName { get; }
    public string SizeText { get; }

    private BitmapSource? _thumbnail;
    public BitmapSource? Thumbnail
    {
        get => _thumbnail;
        set
        {
            _thumbnail = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Thumbnail)));
        }
    }

    public GalleryFileRow(string path)
    {
        Path = path;
        FileName = System.IO.Path.GetFileName(path);
        long bytes = 0;
        try { bytes = new FileInfo(path).Length; } catch { /* shown as 0 B, harmless */ }
        SizeText = FileSizeFormatting.For(bytes);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}
