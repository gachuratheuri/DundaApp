"""Generate the canonical Tiketa launcher, splash, and favicon assets.

The geometry mirrors ``src/components/TiketaLogo.tsx``. Assets are rendered at
4x resolution and downsampled so the same mark remains crisp on every target.
Install the pinned renderer with
``python -m pip install -r scripts/requirements-brand-assets.txt``.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "images"
SUPERSAMPLE = 4

VOID = (8, 8, 10, 255)
VIOLET = (176, 38, 255, 255)
CYAN = (0, 240, 255, 255)
WHITE = (252, 252, 253, 255)


def scaled(value: float, factor: float) -> int:
    return round(value * factor)


def line(
    draw: ImageDraw.ImageDraw,
    points: list[tuple[float, float]],
    fill: tuple[int, int, int, int],
    width: float,
    factor: float,
) -> None:
    coordinates = [(scaled(x, factor), scaled(y, factor)) for x, y in points]
    draw.line(
        coordinates,
        fill=fill,
        width=max(1, scaled(width, factor)),
        joint="curve",
    )
    radius = scaled(width / 2, factor)
    for x, y in coordinates[0], coordinates[-1]:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def mascot_layer(
    canvas_size: int,
    *,
    monochrome: bool = False,
    safe_scale: float = 0.72,
) -> Image.Image:
    """Return a transparent, adaptive-icon-safe ticket mascot."""

    high_size = canvas_size * SUPERSAMPLE
    layer = Image.new("RGBA", (high_size, high_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    unit = high_size / 140 * safe_scale
    offset_x = (high_size - 100 * unit) / 2
    offset_y = (high_size - 140 * unit) / 2

    def point(x: float, y: float) -> tuple[float, float]:
        return ((offset_x + x * unit) / SUPERSAMPLE, (offset_y + y * unit) / SUPERSAMPLE)

    factor = SUPERSAMPLE
    mark_color = WHITE if monochrome else VIOLET

    # Limbs sit behind the ticket body and retain adaptive-mask clearance.
    line(draw, [point(42, 92), point(36, 124), point(29, 130)], mark_color, 6, factor)
    line(draw, [point(58, 92), point(64, 124), point(72, 129)], mark_color, 6, factor)
    line(draw, [point(29, 55), point(15, 64), point(8, 60)], mark_color, 6, factor)
    line(draw, [point(71, 54), point(84, 44), point(91, 34)], mark_color, 6, factor)

    x0, y0 = point(27, 18)
    x1, y1 = point(75, 98)
    body_box = (
        scaled(x0, factor),
        scaled(y0, factor),
        scaled(x1, factor),
        scaled(y1, factor),
    )
    draw.rounded_rectangle(body_box, radius=round(7 * unit), fill=mark_color)

    # Clearing alpha creates true ticket perforations for adaptive icons.
    notch_radius = 4.2 * unit
    for ticket_x in (38, 51, 64):
        for ticket_y in (18, 98):
            cx = offset_x + ticket_x * unit
            cy = offset_y + ticket_y * unit
            draw.ellipse(
                (
                    round(cx - notch_radius),
                    round(cy - notch_radius),
                    round(cx + notch_radius),
                    round(cy + notch_radius),
                ),
                fill=(0, 0, 0, 0),
            )

    if not monochrome:
        perforation_x0, perforation_y = point(34, 78)
        perforation_x1, _ = point(68, 78)
        dash_width = 4 * unit
        cursor = perforation_x0 * factor
        end = perforation_x1 * factor
        y = perforation_y * factor
        while cursor < end:
            draw.line(
                (round(cursor), round(y), round(min(cursor + dash_width, end)), round(y)),
                fill=CYAN,
                width=max(1, round(1.8 * unit)),
            )
            cursor += 7 * unit

        for eye_x in (42, 61):
            cx, cy = point(eye_x, 50)
            rx, ry = 8 * unit, 10 * unit
            draw.ellipse(
                (
                    round(cx * factor - rx),
                    round(cy * factor - ry),
                    round(cx * factor + rx),
                    round(cy * factor + ry),
                ),
                fill=WHITE,
            )
            pupil_x = cx * factor + 1.5 * unit
            pupil_y = cy * factor + 1.5 * unit
            pupil_r = 3.8 * unit
            draw.ellipse(
                (
                    round(pupil_x - pupil_r),
                    round(pupil_y - pupil_r),
                    round(pupil_x + pupil_r),
                    round(pupil_y + pupil_r),
                ),
                fill=VOID,
            )
            highlight_r = 1.1 * unit
            draw.ellipse(
                (
                    round(pupil_x + unit - highlight_r),
                    round(pupil_y - unit - highlight_r),
                    round(pupil_x + unit + highlight_r),
                    round(pupil_y - unit + highlight_r),
                ),
                fill=WHITE,
            )

    return layer.resize((canvas_size, canvas_size), Image.Resampling.LANCZOS)


def glow_background(size: int) -> Image.Image:
    base = Image.new("RGBA", (size, size), VOID)
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    radius = round(size * 0.42)
    centre = size // 2
    glow_draw.ellipse(
        (centre - radius, centre - radius, centre + radius, centre + radius),
        fill=(176, 38, 255, 120),
    )
    base.alpha_composite(glow.filter(ImageFilter.GaussianBlur(round(size * 0.15))))

    refraction = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    refraction_draw = ImageDraw.Draw(refraction)
    width = max(2, round(size * 0.018))
    refraction_draw.line(
        (-size * 0.05, size * 0.78, size * 1.05, size * 0.22),
        fill=(0, 240, 255, 75),
        width=width,
    )
    base.alpha_composite(
        refraction.filter(ImageFilter.GaussianBlur(max(1, width // 2)))
    )
    return base


def save_icon(
    filename: str,
    size: int,
    *,
    background: bool,
    monochrome: bool = False,
) -> None:
    canvas = (
        glow_background(size)
        if background
        else Image.new("RGBA", (size, size), (0, 0, 0, 0))
    )
    safe_scale = 0.78 if filename == "splash-icon.png" else 0.72
    canvas.alpha_composite(
        mascot_layer(size, monochrome=monochrome, safe_scale=safe_scale)
    )
    canvas.save(OUTPUT / filename, optimize=True)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    save_icon("icon.png", 1024, background=True)
    save_icon("splash-icon.png", 512, background=False)
    save_icon("favicon.png", 48, background=True)
    save_icon("android-icon-foreground.png", 512, background=False)
    save_icon("android-icon-monochrome.png", 432, background=False, monochrome=True)
    glow_background(512).save(OUTPUT / "android-icon-background.png", optimize=True)
    save_icon("brand-mark.png", 512, background=False)

    glow = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((96, 70, 416, 442), fill=(176, 38, 255, 120))
    glow.filter(ImageFilter.GaussianBlur(80)).save(
        OUTPUT / "logo-glow.png", optimize=True
    )


if __name__ == "__main__":
    main()
