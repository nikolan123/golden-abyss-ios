# a dump to a PNG, so a phone's UI can be looked at without a PPM viewer (stdlib only: zlib)
import sys, struct, zlib
def ppm_to_png(src, dst):
    d = open(src, 'rb').read()
    parts = d.split(b'\n', 3)
    if parts[0] != b'P6': raise SystemExit(f'{src}: not a P6 PPM')
    w, h = map(int, parts[1].split())
    px = parts[3][: w * h * 3]
    rows = b''.join(b'\x00' + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def chunk(tag, body):
        return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')
    open(dst, 'wb').write(png)
    print(f'{dst}: {w}x{h}, {len(png)} bytes')
for src in sys.argv[1:]:
    ppm_to_png(src, src[:-4] + '.png')
