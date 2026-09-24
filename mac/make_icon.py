# Generate Pterm.icns: "PTerm" in the PLATO font (from PTerm's own
# character tables in FrameCanvas.cpp), plasma orange on black.
# Usage: python3 make_icon.py path/to/FrameCanvas.cpp  (then iconutil)
import re, sys, zlib, struct
src = open(sys.argv[1]).read()
def table(name):
    body = src[src.index('const unsigned short %s[]' % name):]
    body = body[body.index('{') + 1:body.index('};')]
    v = [int(x, 16) for x in re.findall(r'0x[0-9a-fA-F]+', body)]
    return [v[i:i + 8] for i in range(0, len(v), 8)]
m0 = table('plato_m0'); m1 = table('plato_m1')
def glyph(c):
    if 'a' <= c <= 'z': return m0[1 + ord(c) - 97]
    if 'A' <= c <= 'Z': return m1[1 + ord(c) - 65]
    return [0] * 8
cols = []
for c in 'PTerm': cols += glyph(c)
W = 1024
img = bytearray(W * W * 4)
def px(x, y, r, g, b):
    o = (y * W + x) * 4; img[o:o + 4] = bytes((r, g, b, 255))
m, R = 100, 185                      # macOS icon body 824 px, rounded
for y in range(m, W - m):
    for x in range(m, W - m):
        dx = max(m + R - x, 0, x - (W - m - R - 1)); dy = max(m + R - y, 0, y - (W - m - R - 1))
        if dx * dx + dy * dy <= R * R: px(x, y, 8, 8, 8)
f = m + 60                           # orange frame
for t in range(6):
    for i in range(f, W - f):
        px(i, f + t, 255, 144, 0); px(i, W - f - 1 - t, 255, 144, 0)
        px(f + t, i, 255, 144, 0); px(W - f - 1 - t, i, 255, 144, 0)
pitch, dot = 15, 12                  # plasma dots
ox = (W - len(cols) * pitch) // 2; oy = (W - 16 * pitch) // 2 + 20
for cx, word in enumerate(cols):
    for bit in range(16):
        if word & (1 << bit):
            for yy in range(dot):
                for xx in range(dot):
                    px(ox + cx * pitch + xx, oy + (15 - bit) * pitch + yy, 255, 144, 0)
raw = b''.join(b'\x00' + bytes(img[y * W * 4:(y + 1) * W * 4]) for y in range(W))
ch = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
open('icon_1024.png', 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', W, W, 8, 6, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b''))
