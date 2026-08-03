# Photokompressor

Compress photos to a fraction of their size, straight from the Windows right-click menu.

Right-click one or many photos in Explorer → **Compress with Photokompressor** → an options
dialog pops up at your cursor → compressed copies appear with a per-file savings report.
Typical phone photos shrink 70–90 % with no visible quality loss at the Balanced preset.

## Features

- **Input:** JPEG, PNG, WebP, BMP, TIFF, GIF, and **HEIC/HEIF** (iPhone photos)
- **Output:** JPEG (mozjpeg), WebP, or PNG
- **Quality presets:** High / Balanced / Low — no fiddly sliders
- **Resize to fit** an optional W×H box (Lanczos3, never upscales, EXIF rotation baked in)
- **Keep originals** (to a `Compressed` subfolder, a `-compressed` suffix, or any folder) or
  **replace in place** — replaced originals go to the Recycle Bin, never hard-deleted
- Multi-select any number of files; one dialog handles the whole batch in parallel
- Metadata (EXIF/GPS) is stripped for extra savings and privacy; wide-gamut photos are
  converted to sRGB first so colors don't shift

## Look and feel

Custom borderless window: rounded card, drop shadow, all-caps hairline wordmark top-left,
large circular ✕ top-right, drag anywhere on the header. Controls are soft-shadowed
("neumorphic") — segmented pill pickers, toggle switches, and a size slider with a value
bubble that tracks the thumb.

Typography is **Fira Sans Condensed** (SIL Open Font License), the same family the Wind
Router app uses, embedded in the exe so it renders identically on any machine. WPF has no
letter-spacing property, so [Tracking.cs](src/Photokompressor/UI/Tracking.cs) provides an
attached `Tracking.Em` that rebuilds a TextBlock's runs with scaled spacers — the wordmark
uses 0.14em and section labels 0.1em, matching Wind Router's CSS.

To swap fonts: drop the new family's **static** `.ttf` weights into
`src/Photokompressor/Assets/Fonts` (the csproj globs them automatically) and change the
family name after the `#` in the `AppFont` resource at the top of
[Theme.xaml](src/Photokompressor/UI/Theme.xaml). Use static weights, not a
`Family[wght].ttf` variable font — WPF can't interpolate variable axes and will fake bold.

## Install

1. Build or grab the `publish` folder and copy it to `%LOCALAPPDATA%\Programs\Photokompressor`.
2. Run `Photokompressor.exe`, click the **i** button, and switch on **Right-click menu**
   (no admin needed — it writes only to HKCU).
3. Right-click any photo. On Windows 11 the entry lives under **Show more options** (Shift+F10).

Requires the .NET 8 Desktop Runtime (preinstalled on most machines; the app prompts to
download it otherwise).

The app has exactly one window. Launching the exe opens it with an empty queue; right-clicking
photos opens the same window with them loaded; and photos can be dragged onto it at any time.
A second launch hands its photos to the window already open rather than opening another.

## Disclaimer — please read before using replace mode

Photokompressor is provided **"as is", without warranty of any kind**, express or implied, and
**you use it entirely at your own risk**. The author accepts no responsibility or liability for
lost, deleted, corrupted or altered files, or for any other loss or damage arising from use of
this software. The full legal terms are in [LICENSE](LICENSE), and they govern.

That is the boilerplate. These are the specific things this app does that you should understand
before pointing it at photos you care about:

- **Compression discards image data on purpose.** Apart from the PNG *High* preset, output is
  not a bit-for-bit copy of the input, and the detail removed cannot be recovered from it. Every
  further pass compresses an already-compressed image and loses a little more.
- **Metadata is stripped.** EXIF, GPS coordinates, camera settings, captions and copyright fields
  are removed from output by design. Orientation is preserved by rotating the pixels; everything
  else is gone. Colour profiles are converted to sRGB, so wide-gamut originals lose gamut.
- **Replace mode deletes your originals.** With *Keep originals* switched off, the compressed
  file is written first, the original is then moved to the Recycle Bin, and the new file takes
  its place. The app refuses to run in this mode wherever Windows would delete permanently
  rather than recycle — network shares, drives with no Recycle Bin or with "don't move files to
  the Recycle Bin" set, and files above the bin's size allowance — but a Recycle Bin can still
  be emptied, and it is not a backup.
- **There is no undo inside the app**, and no versioning. Recovery means the Recycle Bin, or
  your own backup.

Keep an independent backup of any photo you cannot replace. Try a small batch first, with
*Keep originals* switched on, and check the results before trusting a large run.

## Licence

MIT — see [LICENSE](LICENSE).

## Third-party components

Photokompressor links these as separate native DLLs, so their copyleft does not reach this
repository's MIT-licensed code:

| Component | Via | Licence |
|---|---|---|
| libvips (with mozjpeg, libwebp, libtiff, libpng, lcms, glib, pango and others) | NetVips | LGPLv3, plus permissive licences per bundled library |
| ImageMagick and libde265 (HEIC/HEVC decode) | Magick.NET | ImageMagick licence; libde265 LGPLv3 |
| Fira Sans Condensed | embedded in the exe | SIL Open Font License 1.1 |
| CommunityToolkit.Mvvm, NetVips, .NET 8 | NuGet | MIT |

Distributed builds ship the full third-party notices next to the executable.

## Build

```bash
dotnet build                 # debug
dotnet test                  # unit + engine integration tests
dotnet publish src/Photokompressor -c Release -r win-x64 --self-contained false -o publish
```

## CLI (hidden, for scripting/testing)

```
Photokompressor.exe --cli <files...> [--format jpeg|webp|png] [--preset high|balanced|smallest]
                    [--fit 1920x1920] [--replace] [--suffix] [--outdir <path>] [--report out.json]
Photokompressor.exe --register | --unregister
```

## How it compresses

- **JPEG:** libvips built against **mozjpeg** — trellis quantisation, overshoot deringing,
  progressive scan optimisation, tuned quant tables (q82/72/58 by preset)
- **WebP:** smart subsampling, photo preset (q80/68/52)
- **PNG:** lossless at High; palette quantisation + dithering at Balanced/Smallest
- **HEIC:** decoded via Magick.NET (libvips can't ship HEIC decode on Windows), then the
  same pipeline
- If the recompressed file wouldn't be smaller than the original, the original is kept.
