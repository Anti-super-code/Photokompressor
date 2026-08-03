using CommunityToolkit.Mvvm.ComponentModel;

namespace Photokompressor.ViewModels;

/// <summary>Drives the row template in the progress window.</summary>
public partial class FileResultItem : ObservableObject
{
    public required string InputPath { get; init; }
    public required string FileName { get; init; }

    /// <summary>Size change ("612 KB → 153 KB") or, when that doesn't apply, the reason.</summary>
    [ObservableProperty] private string _detail = "Waiting…";

    /// <summary>Short badge text: savings percentage, or a status glyph.</summary>
    [ObservableProperty] private string _badge = "";

    /// <summary>Pending | Done | Kept | Failed | Cancelled — selects the badge styling.</summary>
    [ObservableProperty] private string _kind = "Pending";
}
