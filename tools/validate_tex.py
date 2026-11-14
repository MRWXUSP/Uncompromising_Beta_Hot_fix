# -*- coding: utf-8 -*-
"""
Validate the generated KTEX:
  - parse mip table / sizes
  - decode mip0 (DXT5, as stored)
  - flip vertically -> this is what the game will actually display
  - compare that "game view" with the authoring PNG
"""
import struct
from PIL import Image

MOD = r"D:\zmh\Documents\repo\uncompromising\UncompromisingBetaHotfix"
TEX = MOD + r"\modicon.tex"
SRC = MOD + r"\tools\icon_source.png"
OUT_STORED = MOD + r"\tools\decoded_stored.png"   # raw stored orientation
OUT_GAME = MOD + r"\tools\decoded_gameview.png"   # flipped like the game shows

data = open(TEX, "rb").read()
assert data[:4] == b"KTEX"
mips = []
off = 8
while True:
    chunk = data[off:off + 10]
    if len(chunk) < 10:
        break
    w, h, stride = struct.unpack("<3H", chunk[:6])
    size = struct.unpack("<I", chunk[6:10])[0]
    if size != max(16, w * h):
        break
    mips.append((w, h, stride, size))
    off += 10
total = sum(m[3] for m in mips)
print("size", len(data), "header", off, "mips", len(mips), "mip sum", total)
assert len(data) == off + total

pos = off
payloads = []
for (w, h, stride, size) in mips:
    payloads.append(data[pos:pos + size])
    pos += size


def rgb565(c):
    r = (c >> 11) & 0x1F
    g = (c >> 5) & 0x3F
    b = c & 0x1F
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def decode_bc3(blob, w, h):
    img = Image.new("RGBA", (w, h))
    px = img.load()
    pos = 0
    for by in range(h // 4):
        for bx in range(w // 4):
            alpha = blob[pos:pos + 8]
            color = blob[pos + 8:pos + 16]
            pos += 16
            a0, a1 = alpha[0], alpha[1]
            if a0 > a1:
                pal_a = [a0, a1] + [int(round(((7 - i) * a0 + i * a1) / 7.0)) for i in range(1, 7)]
            else:
                pal_a = [a0, a1] + [int(round(((5 - i) * a0 + i * a1) / 5.0)) for i in range(1, 5)] + [0, 255]
            abits = int.from_bytes(alpha[2:8], "little")
            c0, c1, cbits = struct.unpack("<HHI", color)
            p0, p1 = rgb565(c0), rgb565(c1)
            if c0 > c1:
                pal_c = [p0, p1,
                         tuple((2 * p0[i] + p1[i]) // 3 for i in range(3)),
                         tuple((p0[i] + 2 * p1[i]) // 3 for i in range(3))]
            else:
                pal_c = [p0, p1, tuple((p0[i] + p1[i]) // 2 for i in range(3)), (0, 0, 0)]
            for i in range(16):
                x = bx * 4 + (i % 4)
                y = by * 4 + (i // 4)
                ai = (abits >> (3 * i)) & 7
                ci = (cbits >> (2 * i)) & 3
                px[x, y] = (pal_c[ci][0], pal_c[ci][1], pal_c[ci][2], pal_a[ai])
    return img


w0, h0 = mips[0][0], mips[0][1]
stored = decode_bc3(payloads[0], w0, h0)
stored.convert("RGB").save(OUT_STORED)
game = stored.transpose(Image.FLIP_TOP_BOTTOM)
game.convert("RGB").save(OUT_GAME)

src = Image.open(SRC).convert("RGB")
if src.size == game.size:
    serr = 0
    for y in range(0, h0, 6):
        for x in range(0, w0, 6):
            a = src.getpixel((x, y))
            b = game.getpixel((x, y))
            serr += abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
    print("game-view vs source sampled colour diff:", serr)
print("saved", OUT_STORED)
print("saved", OUT_GAME)
