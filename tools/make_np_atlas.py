"""Atlas for the nameplates: bar frame, bar fill (white, tinted in game), blood bar frame/fill, end spark,
bounty skull, trader coins and for-hire crossed swords icons (drawn in colour, 32x32, shown at text height).

Regions are written to np_regions.lua next to the atlas. Usage: make_np_atlas.py out_dir
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

W, H = 128, 96
REGIONS = {
    "frame": (0, 0, 108, 13),
    "fill": (0, 16, 104, 9),
    "bframe": (0, 28, 108, 6),
    "bfill": (0, 36, 104, 4),
    "spark": (112, 16, 8, 9),
    "bounty": (0, 48, 32, 32),
    "trader": (32, 48, 32, 32),
    "hire": (64, 48, 32, 32),
}

S = 8  # icons are drawn 8 times bigger and scaled down for smooth edges


def frame(img: Image.Image, box: tuple[int, int, int, int], inner_alpha: int) -> None:
    x, y, w, h = box
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=2, fill=(0, 0, 0, 235))
    d.rounded_rectangle([x + 1, y + 1, x + w - 2, y + h - 2], radius=1, fill=(18, 16, 15, inner_alpha))
    # faint warm rim at the top edge and a darker bottom, like a recessed slot
    d.line([x + 2, y + 1, x + w - 3, y + 1], fill=(70, 62, 52, 150))
    d.line([x + 2, y + h - 2, x + w - 3, y + h - 2], fill=(6, 5, 5, 220))


def fill(img: Image.Image, box: tuple[int, int, int, int]) -> None:
    x, y, w, h = box
    px = img.load()
    for j in range(h):
        t = j / max(1, h - 1)
        v = 1.0 - 0.38 * t                       # light top, darker bottom
        if j == 0:
            v = 1.0
        a = 255
        for i in range(w):
            px[x + i, y + j] = (int(255 * v), int(255 * v), int(255 * v), a)
    gloss = Image.new("RGBA", (w, max(1, h // 2)), (255, 255, 255, 0))
    gd = ImageDraw.Draw(gloss)
    gd.rectangle([0, 0, w, h // 2], fill=(255, 255, 255, 46))
    img.alpha_composite(gloss, (x, y + 1))


def spark(img: Image.Image, box: tuple[int, int, int, int]) -> None:
    x, y, w, h = box
    s = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(s)
    d.rectangle([w // 2 - 1, 0, w // 2, h - 1], fill=(255, 255, 255, 255))
    s = s.filter(ImageFilter.GaussianBlur(1.1))
    core = ImageDraw.Draw(s)
    core.line([w // 2, 1, w // 2, h - 2], fill=(255, 255, 255, 255))
    img.alpha_composite(s, (x, y))


def skull(img: Image.Image, box: tuple[int, int, int, int]) -> None:
    x, y, w, h = box
    big = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    o = 2.2 * S                                             # dark outline width
    ivory, dark = (238, 226, 196, 255), (22, 14, 10, 255)

    def skull_shape(draw, grow, colour):
        # cranium and jaw
        draw.ellipse([4 * S - grow, 2.5 * S - grow, 28 * S + grow, 24 * S + grow], fill=colour)
        draw.rounded_rectangle([9 * S - grow, 19 * S - grow, 23 * S + grow, 29.5 * S + grow], radius=2 * S, fill=colour)
    skull_shape(d, o, dark)
    skull_shape(d, 0, ivory)
    # eyes, nose, teeth
    d.ellipse([8.5 * S, 11 * S, 14.5 * S, 18 * S], fill=dark)
    d.ellipse([17.5 * S, 11 * S, 23.5 * S, 18 * S], fill=dark)
    d.polygon([(16 * S, 18.5 * S), (14.2 * S, 22 * S), (17.8 * S, 22 * S)], fill=dark)
    for tx in (12.5, 16, 19.5):
        d.line([tx * S, 24.5 * S, tx * S, 29 * S], fill=dark, width=int(1.2 * S))
    # a warm shine on the forehead
    d.ellipse([10 * S, 5 * S, 17 * S, 9 * S], fill=(255, 250, 235, 255))
    img.alpha_composite(big.resize((w, h), Image.LANCZOS), (x, y))


def coins(img: Image.Image, box: tuple[int, int, int, int]) -> None:
    x, y, w, h = box
    big = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    dark, rim, face, shine = (40, 24, 6, 255), (176, 112, 22, 255), (246, 196, 64, 255), (255, 238, 150, 255)
    # a stack of three coins, then one coin standing in front
    for i, cy in enumerate((24, 19, 14)):
        d.ellipse([3 * S, (cy - 4.5) * S, 21 * S, (cy + 4.5) * S], fill=dark)
        d.ellipse([4.2 * S, (cy - 3.3) * S, 19.8 * S, (cy + 3.6) * S], fill=rim)
        d.ellipse([4.2 * S, (cy - 3.6) * S, 19.8 * S, (cy + 2.2) * S], fill=face)
    d.ellipse([13 * S, 9 * S, 31 * S, 27 * S], fill=dark)
    d.ellipse([14.4 * S, 10.4 * S, 29.6 * S, 25.6 * S], fill=rim)
    d.ellipse([15.8 * S, 11.8 * S, 28.2 * S, 24.2 * S], fill=face)
    d.arc([18 * S, 14 * S, 26 * S, 22 * S], start=40, end=320, fill=rim, width=int(1.8 * S))   # a "c" for cats
    d.ellipse([16.5 * S, 12.5 * S, 21 * S, 15.5 * S], fill=shine)
    img.alpha_composite(big.resize((w, h), Image.LANCZOS), (x, y))


def swords(img: Image.Image, box: tuple[int, int, int, int]) -> None:
    """Two crossed swords: someone you can hire."""
    x, y, w, h = box
    big = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    dark, steel, edge, guard, grip = (22, 16, 12, 255), (200, 208, 214, 255), (250, 252, 255, 255),         (196, 150, 52, 255), (120, 72, 36, 255)

    def sword(flip: bool) -> None:
        f = (lambda px, py: ((32 - px) * S, py * S)) if flip else (lambda px, py: (px * S, py * S))
        blade = [f(4, 3), f(7, 2.5), f(23, 18.5), f(20.5, 21)]
        d.polygon([f(3, 2), f(8, 1.5), f(24.5, 18.5), f(19.5, 22.5)], fill=dark)       # outline
        d.polygon(blade, fill=steel)
        d.line([f(5.5, 3.2), f(21.5, 19.2)], fill=edge, width=int(1.1 * S))           # shine along the blade
        d.line([f(17, 23.5), f(24.5, 16)], fill=dark, width=int(4.4 * S))             # cross guard
        d.line([f(17.6, 22.9), f(23.9, 16.6)], fill=guard, width=int(2.6 * S))
        d.line([f(21, 20), f(27.5, 26.5)], fill=dark, width=int(4.6 * S))             # grip
        d.line([f(21.6, 20.6), f(27, 26)], fill=grip, width=int(2.8 * S))
        cx = (29 if not flip else 3) * S
        d.ellipse([cx - 2.4 * S, 25.6 * S, cx + 2.4 * S, 30.4 * S], fill=dark)       # pommel
        d.ellipse([cx - 1.4 * S, 26.6 * S, cx + 1.4 * S, 29.4 * S], fill=guard)

    sword(False)
    sword(True)
    img.alpha_composite(big.resize((w, h), Image.LANCZOS), (x, y))


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    frame(img, REGIONS["frame"], 200)
    fill(img, REGIONS["fill"])
    frame(img, REGIONS["bframe"], 190)
    fill(img, REGIONS["bfill"])
    spark(img, REGIONS["spark"])
    skull(img, REGIONS["bounty"])
    coins(img, REGIONS["trader"])
    swords(img, REGIONS["hire"])
    img.save(out / "Nameplates_atlas.png")
    lines = ["-- generated by make_np_atlas.py", "local R = {"]
    for k, (x, y, w, h) in REGIONS.items():
        lines.append(f'    {k} = {{ x = {x}, y = {y}, w = {w}, h = {h} }},')
    lines.append("}")
    (out / "np_regions.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
    preview = img.resize((W * 6, H * 6), Image.NEAREST)
    bg = Image.new("RGBA", preview.size, (90, 120, 80, 255))
    bg.alpha_composite(preview)
    bg.convert("RGB").save(out / "atlas_preview.png")
    print("atlas written", out / "Nameplates_atlas.png")


if __name__ == "__main__":
    main()
