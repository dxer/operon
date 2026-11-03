#!/usr/bin/env python3
"""Regenerate Android launcher icons from the Ø master artwork.

Outputs:
  * assets/icon/app_icon_android.png   rounded legacy icon (1024)
  * assets/icon/app_icon_foreground.png  adaptive foreground (transparent)
  * assets/icon/app_icon_monochrome.png  themed-icon layer (transparent)
  * android/app/src/main/res/drawable-*/ic_launcher_{foreground,monochrome}.png
  * android/app/src/main/res/mipmap-*/ic_launcher{,_round}.png
  * mipmap-anydpi-v26 XML + values/colors.xml

Requires Pillow. Run from the repository root.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/icon/app_icon.png"
ASSETS = ROOT / "assets/icon"
RES = ROOT / "android/app/src/main/res"

INK = (26, 28, 32, 255)  # #1A1C20 warm graphite
BONE = (242, 239, 232, 255)  # #F2EFE8

DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}


def glyph_layer(size: int, glyph_height_ratio: float, color=BONE) -> Image.Image:
    """Extract the Ø from the black master and place it on a transparent canvas."""
    source = Image.open(SRC).convert("L")

    # The master PNG carries faint compression noise in its black background;
    # clamp it out so the alpha bbox is the glyph, not the whole canvas.
    def clean(value: int) -> int:
        if value <= 24:
            return 0
        if value >= 200:
            return 255
        return round((value - 24) * 255 / (200 - 24))

    alpha = source.point(clean)
    bbox = alpha.getbbox()
    if bbox is None:
        raise SystemExit("master icon has no visible glyph")
    glyph = Image.new("RGBA", (bbox[2] - bbox[0], bbox[3] - bbox[1]), color)
    glyph.putalpha(alpha.crop(bbox))

    target_h = round(size * glyph_height_ratio)
    target_w = round(glyph.width * target_h / glyph.height)
    glyph = glyph.resize((target_w, target_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(
        glyph,
        ((size - target_w) // 2, (size - target_h) // 2),
    )
    return canvas


def rounded_background(size: int, radius_ratio: float) -> Image.Image:
    scale = 4
    large = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(large)
    draw.rounded_rectangle(
        (0, 0, size * scale - 1, size * scale - 1),
        radius=round(size * scale * radius_ratio),
        fill=INK,
    )
    return large.resize((size, size), Image.LANCZOS)


def circle_background(size: int) -> Image.Image:
    scale = 4
    large = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(large)
    draw.ellipse((0, 0, size * scale - 1, size * scale - 1), fill=INK)
    return large.resize((size, size), Image.LANCZOS)


def compose_legacy(size: int, radius_ratio: float, glyph_ratio: float) -> Image.Image:
    icon = rounded_background(size, radius_ratio)
    icon.alpha_composite(glyph_layer(size, glyph_ratio))
    return icon


def compose_round(size: int, glyph_ratio: float) -> Image.Image:
    icon = circle_background(size)
    icon.alpha_composite(glyph_layer(size, glyph_ratio))
    return icon


def main() -> None:
    # Full-resolution sources for future regeneration.
    compose_legacy(1024, 0.225, 0.56).save(ASSETS / "app_icon_android.png")
    glyph_layer(1024, 0.44).save(ASSETS / "app_icon_foreground.png")
    glyph_layer(1024, 0.48, color=(255, 255, 255, 255)).save(
        ASSETS / "app_icon_monochrome.png"
    )

    # Adaptive icon layers.
    for density, factor in DENSITIES.items():
        size = round(108 * factor)
        folder = RES / f"drawable-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        glyph_layer(size, 0.44).save(folder / "ic_launcher_foreground.png")
        glyph_layer(size, 0.48, color=(255, 255, 255, 255)).save(
            folder / "ic_launcher_monochrome.png"
        )

    # Legacy icons for API < 26 and launchers that ignore adaptive icons.
    for density, factor in DENSITIES.items():
        size = round(48 * factor)
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        compose_legacy(size, 0.225, 0.56).save(folder / "ic_launcher.png")
        compose_round(size, 0.50).save(folder / "ic_launcher_round.png")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
"""
    (anydpi / "ic_launcher.xml").write_text(adaptive)
    (anydpi / "ic_launcher_round.xml").write_text(adaptive)

    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">#1A1C20</color>\n'
        "</resources>\n"
    )

    print("icons written")


if __name__ == "__main__":
    main()
