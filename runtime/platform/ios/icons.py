#!/usr/bin/env python3
"""Golden Abyss for iOS: the app icon at every size the bundle carries.

  python icons.py                     AppIcon.svg -> AppIcon/*.png (the drawn icon)
  python icons.py --from <png>        that image -> AppIcon/*.png (the game's own, from your copy)

The app's icon is the game's own: every Vita title carries one at sce_sys/icon0.png, and pack-ios.py takes it
from your copy at packaging time, the way pipeline/steam.py takes the game's art for a Steam shortcut. Nothing of
the game is in this repository, so the drawn AppIcon.svg is what the repository can hold, and what a smoke build
or a copy without an icon0.png falls back to.

Sizes are what iOS looks up (20/29/40/60 pt at @1x/@2x/@3x, and the 1024 the App Store wants), named as
Info.plist's CFBundleIcons names them. The SVG is rasterised once at 1024 by headless Chrome (or Edge, on
Windows); every size is then a filter over that image -- a browser window of 20 px is one Windows' headless
browser will not open.

Regenerate after editing AppIcon.svg. The PNGs are committed: packing an ipa needs no browser.
"""
import os
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "AppIcon")
SVG = os.path.join(HERE, "AppIcon.svg")
MASTER = 1024

# pixel size -> the names iOS asks for at that size (its own point grid: 20/29/40/60 pt, @2x and @3x)
SIZES = {
    1024: ["AppIcon-1024"],
    180: ["Icon-60@3x"],
    120: ["Icon-60@2x", "Icon-40@3x"],
    87: ["Icon-29@3x"],
    80: ["Icon-40@2x"],
    60: ["Icon-60", "Icon-20@3x"],
    58: ["Icon-29@2x"],
    40: ["Icon-40", "Icon-20@2x"],
    29: ["Icon-29"],
    20: ["Icon-20"],
}

BROWSERS = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]


def browser():
    import shutil
    for b in BROWSERS:
        if os.path.isfile(b):
            return b
    for name in ("google-chrome", "chromium", "chromium-browser", "microsoft-edge"):
        found = shutil.which(name)
        if found:
            return found
    sys.exit("no headless browser: install Chrome or Edge, or add one to BROWSERS in icons.py")


def render(b, size, png):
    # (its own profile directory per shot: a shared one is locked by whatever ran before, and the browser waits on it)
    with tempfile.TemporaryDirectory() as profile:
        subprocess.run([b, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                        "--no-default-browser-check", "--disable-extensions", "--force-device-scale-factor=1",
                        f"--user-data-dir={profile}", f"--window-size={size},{size}", f"--screenshot={png}",
                        "file:///" + SVG.replace(os.sep, "/").lstrip("/")],
                       check=True, timeout=180, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def read_png(path):
    """a PNG as (width, height, RGBA bytes): 8-bit, not interlaced -- a screenshot's RGB/RGBA, or a Vita icon0's palette"""
    data = open(path, "rb").read()
    pos, idat, palette, w = 8, [], b"", 0
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or interlace or ctype not in (2, 3, 6):
                sys.exit(f"{path}: {depth}-bit colour type {ctype}, interlace {interlace}: not an 8-bit image")
        elif kind == b"PLTE":
            palette = body
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    ch = {2: 3, 3: 1, 6: 4}[ctype]
    raw, stride, prev, rows = zlib.decompress(b"".join(idat)), w * ch, bytearray(w * ch), []
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                line[i] = (line[i] + (((line[i - ch] if i >= ch else 0) + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b_, c = prev[i], (prev[i - ch] if i >= ch else 0)
                p = a + b_ - c
                pa, pb, pc = abs(p - a), abs(p - b_), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b_ if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    rgba = bytearray(w * h * 4)
    for y, line in enumerate(rows):
        for x in range(w):
            d = (y * w + x) * 4
            if ctype == 3:
                p = line[x] * 3
                rgba[d:d + 3] = palette[p:p + 3]
                rgba[d + 3] = 255
            else:
                s = x * ch
                rgba[d:d + 3] = line[s:s + 3]
                rgba[d + 3] = line[s + 3] if ch == 4 else 255
    return w, h, rgba


def square(w, h, rgba):
    """the middle square of an image, as icons are square and a Vita title's art is not"""
    s = min(w, h)
    if s == w == h:
        return w, h, rgba
    x0, y0 = (w - s) // 2, (h - s) // 2
    out = bytearray(s * s * 4)
    for y in range(s):
        a = ((y + y0) * w + x0) * 4
        out[y * s * 4:(y + 1) * s * 4] = rgba[a:a + s * 4]
    return s, s, out


def weights(src, dst):
    """per destination pixel, (source index, weight): the box it covers shrinking, the two it straddles growing"""
    out = []
    scale = src / dst
    for i in range(dst):
        if dst <= src:
            a, b, spans, j = i * scale, (i + 1) * scale, [], int(i * scale)
            while j < b and j < src:
                spans.append((j, min(b, j + 1) - max(a, j)))
                j += 1
            total = sum(k for _, k in spans)
            out.append([(j, k / total) for j, k in spans])
        else:
            f = (i + 0.5) * scale - 0.5
            j, t = int(f // 1), f - int(f // 1)
            j0, j1 = max(0, min(src - 1, j)), max(0, min(src - 1, j + 1))
            out.append([(j0, 1.0)] if j0 == j1 or t == 0 else [(j0, 1.0 - t), (j1, t)])
    return out


def resize(w, h, rgba, size):
    wx, wy = weights(w, size), weights(h, size)
    tmp = []
    for y in range(h):
        row, out = rgba[y * w * 4:(y + 1) * w * 4], [0.0] * (size * 4)
        if len(wx) == w:   # same width: nothing to do across
            tmp.append([float(v) for v in row])
            continue
        for x, spans in enumerate(wx):
            r = g = b = a = 0.0
            for sx, k in spans:
                s = sx * 4
                r += row[s] * k; g += row[s + 1] * k; b += row[s + 2] * k; a += row[s + 3] * k
            d = x * 4
            out[d], out[d + 1], out[d + 2], out[d + 3] = r, g, b, a
        tmp.append(out)
    acc = [0.0] * (size * size * 4)
    for y, spans in enumerate(wy):
        base = y * size * 4
        for sy, k in spans:
            row = tmp[sy]
            for i in range(size * 4):
                acc[base + i] += row[i] * k
    px = bytearray(len(acc))
    for i, v in enumerate(acc):
        px[i] = min(255, int(v + 0.5))
    return bytes(px)


def write_png(path, size, rgba):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)
    raw = b"".join(b"\x00" + rgba[y * size * 4:(y + 1) * size * 4] for y in range(size))
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n"
                           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 9))
                           + chunk(b"IEND", b""))


def write_set(outdir, w, h, rgba):
    """every size and name, from one square image (any size); the master is scaled up or down to 1024"""
    os.makedirs(outdir, exist_ok=True)
    base = rgba if w == MASTER else resize(w, h, rgba, MASTER)
    for size, names in sorted(SIZES.items(), reverse=True):
        px = base if size == MASTER else resize(MASTER, MASTER, base, size)
        for name in names:
            write_png(os.path.join(outdir, name + ".png"), size, px)
            print(f"  {name}.png  {size}x{size}")


def from_image(png, outdir=OUT):
    write_set(outdir, *square(*read_png(png)))


def main():
    if "--from" in sys.argv:
        from_image(sys.argv[sys.argv.index("--from") + 1])
    else:
        with tempfile.TemporaryDirectory() as tmp:
            shot = os.path.join(tmp, "master.png")
            render(browser(), MASTER, shot)
            w, h, rgba = read_png(shot)
            if (w, h) != (MASTER, MASTER):
                sys.exit(f"the browser wrote {w}x{h}, not {MASTER}x{MASTER}")
            write_set(OUT, w, h, rgba)
    print(f"{len(SIZES)} sizes -> {OUT}")


if __name__ == "__main__":
    main()
