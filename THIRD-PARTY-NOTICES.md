# Third-party notices

Photokompressor itself is MIT-licensed (see `LICENSE`). It ships with the components below,
each under its own licence. The verbatim licence texts are in the `licenses/` folder next to
this file; the summaries here are for orientation and the full texts govern.

## Components

| Component | Version | Licence | Verbatim text |
|---|---|---|---|
| libvips, and the libraries it bundles (mozjpeg, libwebp, libtiff, libpng, cgif, lcms, glib, pango, librsvg, libexif, fribidi, libarchive, libxml2, expat, highway, aom, libheif, libimagequant, zlib-ng and others) | 8.18.4 | LGPLv3 for libvips, glib, pango, librsvg, libexif, fribidi and proxy-libintl; permissive (BSD/MIT/zlib/IJG-style) for the rest | `licenses/libvips-and-bundled-libraries.md` |
| ImageMagick | 7.1.2-29 | ImageMagick licence (Apache-2.0-style; attribution required) | `licenses/imagemagick-and-libde265.txt` |
| libde265 (HEIC/HEVC decoding) | 1.1.1 | LGPLv3 | `licenses/imagemagick-and-libde265.txt` |
| Magick.NET | 14.16.0 | Apache-2.0 | `licenses/imagemagick-and-libde265.txt` |
| NetVips | 3.2.0 | MIT | https://github.com/kleisauke/net-vips |
| CommunityToolkit.Mvvm | 8.4.2 | MIT | https://github.com/CommunityToolkit/dotnet |
| Fira Sans Condensed | — | SIL Open Font License 1.1 | `licenses/fira-sans-condensed-OFL.txt` |
| .NET 8 Desktop Runtime | 8.x | MIT | https://github.com/dotnet/runtime |

`licenses/imagemagick-and-libde265.txt` contains the complete GNU Lesser General Public
License v3 and GNU General Public License v3 texts, which accompany the LGPL components as
those licences require.

## LGPL components — your right to modify and relink

libvips and libde265 are covered by the LGPLv3. You are entitled to modify them and use your
modified versions with this program.

libvips ships as an ordinary shared library, `libvips-42.dll`, sitting beside
`Photokompressor.exe`. Replacing that file with your own build is all that is required — no
relinking of Photokompressor is involved. libde265 is linked into `Magick.Native-Q8-x64.dll`,
which is likewise a replaceable DLL in the same folder.

Complete corresponding source for these components is published by their maintainers:

- libvips and its Windows build: https://github.com/libvips/libvips and
  https://github.com/kleisauke/libvips-packaging (tag matching version 8.18.4)
- ImageMagick, libde265 and the Magick.Native Windows build:
  https://github.com/dlemstra/Magick.NET and https://github.com/strukturag/libde265

If you would rather receive the corresponding source directly, write to chris@antidot.gr and
it will be provided.

## A note on HEIC

HEIC/HEIF photos are decoded through libde265, which implements HEVC. HEVC is covered by
patents administered by several licensing pools. Photokompressor decodes only — it never
encodes HEVC — and is distributed free of charge. Anyone redistributing this software, or
building a product on it, should form their own view on whether those patents apply to them.
