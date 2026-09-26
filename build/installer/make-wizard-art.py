"""Renders the Inno Setup wizard images from the app's own icon colours and font.

    python build/installer/make-wizard-art.py

Writes wizard-large-*.png (the tall panel on the Welcome / Finished pages) and
wizard-small-*.png (the header badge on the interior pages) next to this script, one
file per DPI step. photokompressor.iss lists all of them; Inno picks the size the current
DPI wants and downsamples from there.

Same light ground (#EDF1F6), slate and coral as the app icon, and the icon's own mark - two
triangles squeezing a disc - so the installer looks like Photokompressor and not like
WinZip circa 1999.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BG_TOP = (0xF4, 0xF7, 0xFB)      # Theme.xaml Surface
BG_BOTTOM = (0xE2, 0xE8, 0xF0)   # Theme.xaml Sunken
SLATE = (74, 80, 89)             # the icon's triangles
CORAL = (232, 98, 81)            # the icon's disc
TEXT_HI = (0x13, 0x18, 0x20)     # Theme.xaml TextHi
TEXT_MID = (0x59, 0x64, 0x7A)    # Theme.xaml TextMid

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
FONT_DIR = REPO / "src" / "Photokompressor" / "Assets" / "Fonts"
ICON_PNG = REPO / "src" / "Photokompressor" / "Assets" / "photokompressor-source-1024.png"

# Inno shows these at 164x314 / 55x58 at 100% DPI; the rest are 150 / 200 / 250%.
LARGE_SIZES = [(164, 314), (246, 471), (328, 628), (410, 797)]
SMALL_SIZES = [(55, 58), (83, 86), (110, 116), (138, 140)]

SS = 4  # supersample: PIL has no antialiased primitives, so draw big and shrink.


def vertical_gradient(w: int, h: int) -> Image.Image:
    grad = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    return grad


def draw_mark(draw: ImageDraw.ImageDraw, cx: float, cy: float, width: float) -> None:
    """The icon's mark, `width` wide overall, centred on (cx, cy). Coordinates below are the
    icon's own 1024px layout: triangles at x 82..367 / 657..942, disc r150 at the middle."""
    k = width / 860
    def X(x): return cx + (x - 512) * k
    def Y(y): return cy + (y - 512) * k

    draw.polygon([(X(82), Y(402)), (X(82), Y(622)), (X(367), Y(512))], fill=SLATE)
    draw.polygon([(X(942), Y(402)), (X(942), Y(622)), (X(657), Y(512))], fill=SLATE)
    r = 150 * k
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=CORAL)


def render_large() -> Image.Image:
    base_w, base_h = LARGE_SIZES[-1]
    w, h = base_w * SS, base_h * SS

    img = vertical_gradient(w, h).convert("RGBA")
    draw = ImageDraw.Draw(img)

    pad = round(w * 0.10)
    draw_mark(draw, w / 2, h * 0.30, w - 2 * pad)

    # The wordmark is long; size it to the panel's text column rather than guessing.
    title_path = str(FONT_DIR / "FiraSansCondensed-SemiBold.ttf")
    title_size = round(w * 0.150)
    while draw.textlength("Photokompressor", font=ImageFont.truetype(title_path, title_size)) > w - 2 * pad:
        title_size -= 1
    title_font = ImageFont.truetype(title_path, title_size)
    sub_font = ImageFont.truetype(str(FONT_DIR / "FiraSansCondensed-Light.ttf"), round(w * 0.066))

    # Bottom-left stack: title over a two-line tagline.
    sub_lines = ["Smaller photos, straight", "from the right-click menu."]
    line_h = round(w * 0.066 * 1.35)
    sub_y = h - pad - line_h * len(sub_lines)
    for i, line in enumerate(sub_lines):
        draw.text((pad, sub_y + i * line_h), line, font=sub_font, fill=TEXT_MID)

    bbox = draw.textbbox((0, 0), "Photokompressor", font=title_font)
    draw.text((pad, sub_y - (bbox[3] - bbox[1]) - round(w * 0.06) - bbox[1]),
              "Photokompressor", font=title_font, fill=TEXT_HI)

    return img


def render_small() -> Image.Image:
    base = SMALL_SIZES[-1][1] * SS
    return Image.open(ICON_PNG).convert("RGBA").resize((base, base), Image.LANCZOS)


def save_steps(master: Image.Image, sizes, stem: str) -> None:
    for w, h in sizes:
        frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        scaled = master.resize((w, min(h, round(master.height * w / master.width))), Image.LANCZOS)
        frame.paste(scaled, (0, (h - scaled.height) // 2), scaled)
        out = HERE / f"{stem}-{w}.png"
        frame.save(out)
        print(f"wrote {out.relative_to(REPO)}  ({w}x{h})")


def main() -> None:
    save_steps(render_large(), LARGE_SIZES, "wizard-large")
    save_steps(render_small(), SMALL_SIZES, "wizard-small")


if __name__ == "__main__":
    main()
