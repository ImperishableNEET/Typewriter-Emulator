"""Rebuild Hilda's specimen-derived optical atlases with Python and Pillow."""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "References/Hilda/Originals/20261126_010203.jpg"
DEST = ROOT / "GodivaStudio/machines/hilda"
SOURCE_SHA256 = "88346b5c45d4132d900902ea403e87c5337f0ba23e0bc9875e73bdf540fa62e4"
TEXT = "the quick brown fox jumps over the lazy dog"
CELL = (32, 52)
# EXIF-oriented source pixels. Both black lines lean up slightly to the right.
# Each tuple is (first character centre X, first baseline Y, pitch, rise per key).
LINES = ((148.0, 582.0, 39.10, 0.275), (146.3, 701.0, 39.15, 0.286))
# The specimen starts its number run with lowercase l (uppercase L below).
# The owner's keyboard photograph confirms a plus/equals key left of 2.
SYMBOL_LINES = (
    ("l234567890-¾½;¢,./ =", (1904.0, 571.0, 38.58, 0.0)),
    ("L\"#$%_&'()*!¼:@,.?+", (1905.0, 690.0, 38.70, 0.0)),
)


def optical_cell(page, line, index):
    x0, y0, pitch, rise = line
    x = x0 + index * pitch
    baseline = y0 - rise * index
    ratio = pitch / 30  # One clear pixel on either side of a full-pitch face.
    box = (x - 16 * ratio, baseline - 37 * ratio,
           x + 16 * ratio, baseline + 15 * ratio)
    # Estimate unprinted stock around the stroke. Closing fills narrow ink
    # traces without flattening the photograph's broad illumination gradient.
    neighborhood = page.crop((int(box[0]) - 12, int(box[1]) - 12,
                              int(box[2]) + 13, int(box[3]) + 13))
    stock = neighborhood.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
    stock = stock.filter(ImageFilter.GaussianBlur(3))
    density = ImageChops.subtract(stock, neighborhood)
    density = density.point(lambda v: max(0, min(255, (v - 17) * 1.52)))
    local_x = box[0] - int(box[0]) + 12
    local_y = box[1] - int(box[1]) + 12
    # Find the white gutter between adjacent faces. Some uppercase serifs
    # extend beyond the theoretical pitch boundary on this photograph.
    center = local_x + 16 * ratio
    for edge, left in ((center - pitch / 2, True), (center + pitch / 2, False)):
        def gutter_cost(column):
            strip = density.crop((column, int(local_y), column + 1, int(local_y + 51 * ratio)))
            return sum(strip.tobytes()) + 4 * abs(column - edge)
        cut = min(range(round(edge) - 4, round(edge) + 5), key=gutter_cost)
        density.paste(0, (0 if left else cut, 0, cut if left else density.width, density.height))
    return density.resize(CELL, Image.Resampling.LANCZOS,
                          (local_x, local_y, local_x + 32 * ratio, local_y + 52 * ratio))


def main():
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source specimen differs from the registered photograph")
    page = ImageOps.exif_transpose(Image.open(SOURCE)).convert("L")
    DEST.mkdir(parents=True, exist_ok=True)
    samples = {}
    for row, line in enumerate(LINES):
        for letter in "abcdefghijklmnopqrstuvwxyz":
            samples[letter.upper() if row else letter] = (line, TEXT.index(letter))
    for run, line in SYMBOL_LINES:
        for i, glyph in enumerate(run):
            if glyph != " ":
                samples.setdefault(glyph, (line, i))
    # A second faint diagonal crosses the first slash. Use the clean strike
    # at the end of the later black line, just below the two blank lines.
    samples["/"] = ((2540.0, 1888.0, 38.9, 0.0), 0)
    chars = {}
    alpha = Image.new("L", (13 * CELL[0], ((len(samples) + 12) // 13) * CELL[1]))
    contact = Image.new("L", alpha.size)
    for pos, (glyph, (line, index)) in enumerate(samples.items()):
        cell = optical_cell(page, line, index)
        if glyph == "&":
            # The preceding underscore crosses its pitch cell below baseline.
            cell.paste(0, (0, 41, CELL[0], CELL[1]))
        location = (pos % 13 * CELL[0], pos // 13 * CELL[1])
        chars[glyph] = list(location)
        alpha.paste(cell, location)
        # Carbon contact is a proxy. Close pinholes within an ink trace,
        # retaining the measured optical shape and its baseline.
        dent = cell.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
        contact.paste(ImageChops.lighter(cell, dent), location)
    for filename, mask in (("strikes.png", alpha), ("pressure.png", contact)):
        texture = Image.new("RGBA", mask.size, "white")
        texture.putalpha(mask)
        texture.save(DEST / filename)
    # Each identifier is one physical key. Its two faces share an articulated bar.
    # Writer uses +/- 1 step of normalized ribbon feed per hit for this rig.
    transport = [[p] + [0] * 14 + [-1, 1] for p in (0, 6000)]
    manifest = {
        "chars": chars, "keys": {}, "bars": {key: {} for key in "=234567890-¾QWERTYUIOP½ASDFGHJKL;¢ZXCVBNM,./"},
        "touch_rig": {"spring_work": [0, 0, 0, 0], "nominal_energy": 1},
        "ribbon_rig": {"transport": transport},
    }
    (DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
