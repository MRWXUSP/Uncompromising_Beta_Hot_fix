# -*- coding: utf-8 -*-
"""
Generate the hotfix mod icon.

- background: Uncompromising Mode "beta" cover art
  (tools/um_beta_cover.png, extracted from UM's modicon and un-flipped)
- overlay: big Chinese title "热修补丁" with outline + shadow, like the
  reference workshop icon
- output: icon_source.png (authoring), modicon.tex (512x512 DXT5 + mips),
  modicon.xml, preview.png

IMPORTANT orientation note:
Klei's KTEX stores pixel rows bottom-up.  ktech/the autocompiler flip the
image when writing TEX, so a KTEX decoded top-down looks upside-down.
We therefore flip every mip vertically before DXT5 encoding; otherwise the
game shows the icon upside-down ("反的").
"""
import os
import struct

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_DIR = os.path.dirname(HERE)

COVER = os.path.join(HERE, "um_beta_cover.png")
HEADER = os.path.join(HERE, "ktex_header_512.bin")
SIZE = 512
MIPS = 10  # 512 -> 1
COVER_CROP = (0, 0, 824, 824)  # UM's modicon.xml crops this square

WHITE = (244, 242, 238)
INK = (10, 8, 10)
AMBER = (210, 150, 58)
MUTED = (205, 195, 185)

TEXT = "热修补丁"


def font(path, size):
    return ImageFont.truetype(path, size)


def fit_font(path, text, max_width, start_size, stroke_width=0):
    size = start_size
    while size > 24:
        f = font(path, size)
        box = f.getbbox(text, stroke_width=stroke_width)
        if box[2] - box[0] <= max_width:
            return f, size
        size -= 2
    return font(path, 24), 24


def make_icon():
    im = Image.open(COVER).convert("RGB").crop(COVER_CROP).resize((SIZE, SIZE), Image.LANCZOS)
    im = im.convert("RGBA")

    # subtle vignette so the overlaid text is readable in the corners
    vignette = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(vignette).ellipse((-160, -160, SIZE + 160, SIZE + 160), fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(110))
    dark = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    dark.putalpha(vignette.point(lambda v: int((255 - v) * 0.35)))
    im.alpha_composite(dark)

    cx, cy = SIZE // 2, 256
    f, fsize = fit_font(r"C:\Windows\Fonts\msyhbd.ttc", TEXT, 466, 110, stroke_width=8)

    # drop shadow
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.text((cx + 2, cy + 11), TEXT, font=f, fill=(0, 0, 0, 205), anchor="mm",
            stroke_width=11, stroke_fill=(0, 0, 0, 135))
    shadow = shadow.filter(ImageFilter.GaussianBlur(4))
    im.alpha_composite(shadow)

    # main text: white fill + dark outline
    d = ImageDraw.Draw(im)
    d.text((cx, cy), TEXT, font=f, fill=WHITE + (255,), anchor="mm",
           stroke_width=8, stroke_fill=INK + (255,))

    return im.convert("RGB"), fsize


def make_preview(icon):
    W, H = 1200, 600
    bg = Image.open(COVER).convert("RGB").resize((W, W), Image.LANCZOS).crop((0, 0, W, H))
    bg = bg.filter(ImageFilter.GaussianBlur(8)).convert("RGBA")
    overlay = Image.new("RGBA", (W, H), (8, 4, 4, 170))
    bg.alpha_composite(overlay)

    left = icon.resize((520, 520), Image.LANCZOS).convert("RGBA")
    bg.alpha_composite(left, (40, 40))

    d = ImageDraw.Draw(bg)
    x = 620
    d.text((x, 150), "永不妥协测试版", font=font(r"C:\Windows\Fonts\simhei.ttf", 46),
           fill=WHITE + (255,), anchor="lm")
    d.text((x, 210), "热修补丁", font=font(r"C:\Windows\Fonts\simhei.ttf", 46),
           fill=AMBER + (255,), anchor="lm")
    d.line((x, 258, 1140, 258), fill=(120, 60, 40, 200), width=3)
    d.text((x, 310), "Uncompromising Beta Hotfix", font=font(r"C:\Windows\Fonts\arialbd.ttf", 28),
           fill=WHITE + (255,), anchor="lm")
    d.text((x, 360), "递归 / 定时任务导致的内存泄漏热修", font=font(r"C:\Windows\Fonts\msyh.ttc", 24),
           fill=MUTED + (255,), anchor="lm")
    d.text((x, 400), "6 项修复可单独开关 · 服务端模组", font=font(r"C:\Windows\Fonts\msyh.ttc", 24),
           fill=MUTED + (255,), anchor="lm")
    return bg.convert("RGB")


# ---------------- DXT5 / BC3 encoder (same as before) ----------------

def rgb565(r, g, b):
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def unpack565(c):
    r = (c >> 11) & 0x1F
    g = (c >> 5) & 0x3F
    b = c & 0x1F
    return (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)


def encode_block(pixels):
    alphas = [p[3] for p in pixels]
    a_min, a_max = min(alphas), max(alphas)
    ab = bytearray()
    if a_min == a_max:
        ab += bytes([a_max, a_min]) + b"\x00\x00\x00\x00\x00\x00"
    else:
        ab += bytes([a_max, a_min])
        pal = [a_max, a_min]
        for i in range(1, 7):
            pal.append(int(round(a_max + (a_min - a_max) * i / 7.0)))
        bits = 0
        for i, a in enumerate(alphas):
            best = min(range(8), key=lambda k: abs(pal[k] - a))
            bits |= (best & 7) << (3 * i)
        ab += bits.to_bytes(6, "little")

    cols = [(p[0], p[1], p[2]) for p in pixels]
    rmin = min(c[0] for c in cols); rmax = max(c[0] for c in cols)
    gmin = min(c[1] for c in cols); gmax = max(c[1] for c in cols)
    bmin = min(c[2] for c in cols); bmax = max(c[2] for c in cols)
    c0 = rgb565(rmax, gmax, bmax)
    c1 = rgb565(rmin, gmin, bmin)
    if c0 < c1:
        c0, c1 = c1, c0
    p0 = unpack565(c0)
    p1 = unpack565(c1)
    if c0 == c1:
        pal_c = [p0, p0, p0, p0]
    else:
        pal_c = [p0, p1,
                 tuple((2 * p0[i] + p1[i]) // 3 for i in range(3)),
                 tuple((p0[i] + 2 * p1[i]) // 3 for i in range(3))]
    bits = 0
    for i, c in enumerate(cols):
        best = min(range(4), key=lambda k: (pal_c[k][0] - c[0]) ** 2 + (pal_c[k][1] - c[1]) ** 2 + (pal_c[k][2] - c[2]) ** 2)
        bits |= (best & 3) << (2 * i)
    return bytes(ab) + struct.pack("<HHI", c0, c1, bits)


def dxt5_image(img):
    img = img.convert("RGBA")
    w, h = img.size
    if w % 4 != 0 or h % 4 != 0:
        pw = (w + 3) // 4 * 4
        ph = (h + 3) // 4 * 4
        padded = Image.new("RGBA", (pw, ph), (0, 0, 0, 255))
        padded.paste(img, (0, 0))
        img = padded
        w, h = pw, ph
    px = img.load()
    out = bytearray()
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            block = []
            for y in range(4):
                for x in range(4):
                    block.append(px[bx + x, by + y])
            out += encode_block(block)
    return bytes(out)


def mip_chain(img, count):
    levels = [img]
    cur = img
    for _ in range(1, count):
        cur = cur.resize((max(1, cur.size[0] // 2), max(1, cur.size[1] // 2)), Image.LANCZOS)
        levels.append(cur)
    return levels


def main():
    icon, fsize = make_icon()
    icon.save(os.path.join(HERE, "icon_source.png"))
    print("icon text size:", fsize)

    # KTEX stores rows bottom-up: flip every mip before encoding
    levels = mip_chain(icon.convert("RGBA"), MIPS)
    data = b"".join(dxt5_image(lv.transpose(Image.FLIP_TOP_BOTTOM)) for lv in levels)

    header = open(HEADER, "rb").read()
    w, h = struct.unpack("<2H", header[8:12])
    assert (w, h) == (SIZE, SIZE), (w, h)
    tex = header + data
    open(os.path.join(MOD_DIR, "modicon.tex"), "wb").write(tex)

    xml = ('<Atlas><Texture filename="modicon.tex" />'
           '<Elements><Element name="modicon.tex" u1="0" u2="1" v1="0" v2="1" /></Elements></Atlas>')
    open(os.path.join(MOD_DIR, "modicon.xml"), "w", encoding="utf-8").write(xml)

    make_preview(icon).save(os.path.join(MOD_DIR, "preview.png"))

    print("tex size:", len(tex), "expected:", len(header) + 349552)
    print("wrote modicon.tex / modicon.xml / preview.png")


if __name__ == "__main__":
    main()
