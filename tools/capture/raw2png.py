#!/usr/bin/env python3
"""raw2png - convert a /dev/fb0 dump into a PNG (stdlib only).

usage: raw2png.py in.raw out.png W H [BPP] [LINE_LENGTH] [VISIBLE_H]
The RK3326 fbcon reports virtual_size=1024,1536 while only 768 lines are shown,
so VISIBLE_H defaults to H and the caller may pass the visible height separately.
"""
import struct
import sys
import zlib


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    inp, outp = sys.argv[1], sys.argv[2]
    W, H = int(sys.argv[3]), int(sys.argv[4])
    BPP = int(sys.argv[5]) if len(sys.argv) > 5 else 32
    LL = int(sys.argv[6]) if len(sys.argv) > 6 else W * (BPP // 8)
    VH = int(sys.argv[7]) if len(sys.argv) > 7 else H
    bytes_per_px = BPP // 8

    with open(inp, "rb") as fh:
        raw = fh.read(LL * VH)
    if len(raw) < LL * VH:
        print(f"warning: only {len(raw)} bytes for {LL * VH}", file=sys.stderr)

    rgb = bytearray(W * VH * 3)
    for y in range(VH):
        base = y * LL
        row = raw[base:base + W * bytes_per_px]
        if len(row) < W * bytes_per_px:
            row += bytes(W * bytes_per_px - len(row))
        dst = y * W * 3
        for x in range(W):
            o = x * bytes_per_px
            if bytes_per_px == 4:
                px = row[o] | (row[o + 1] << 8) | (row[o + 2] << 16) | (row[o + 3] << 24)
                r, g, b = (px >> 16) & 0xFF, (px >> 8) & 0xFF, px & 0xFF
            elif bytes_per_px == 2:
                px = row[o] | (row[o + 1] << 8)
                r = ((px >> 11) & 0x1F) << 3
                g = ((px >> 5) & 0x3F) << 2
                b = (px & 0x1F) << 3
            elif bytes_per_px == 3:
                r, g, b = row[o], row[o + 1], row[o + 2]
            else:
                r = g = b = row[o]
            rgb[dst + x * 3] = r
            rgb[dst + x * 3 + 1] = g
            rgb[dst + x * 3 + 2] = b

    def chunk(tag, data):
        body = tag + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    stride = W * 3
    rows = bytearray()
    for y in range(VH):
        rows.append(0)
        rows += rgb[y * stride:(y + 1) * stride]
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", W, VH, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(rows), 6))
           + chunk(b"IEND", b""))
    with open(outp, "wb") as fh:
        fh.write(png)
    print(f"{W}x{VH} bpp={BPP} ll={LL} -> {outp} ({len(png)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
