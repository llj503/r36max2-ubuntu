#!/usr/bin/env python3
"""r36-fbshot - save what is currently on the panel as a PNG.

Reads /dev/fb0 (the fbcon that drives the MIPI-DSI panel) and converts the raw
framebuffer to PNG using only the standard library, so it works on a minimal
rootfs without Pillow.

usage: r36-fbshot [out.png]
"""
import fcntl
import struct
import sys
import zlib

FBIOGET_VSCREENINFO = 0x4600
FBIOGET_FSCREENINFO = 0x4602


def write_png(path, width, height, rgb):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    stride = width * 3
    raw = bytearray()
    for y in range(height):
        raw.append(0)                     # filter type 0
        raw += rgb[y * stride:(y + 1) * stride]
    out = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(out)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/screen.png"
    with open("/dev/fb0", "rb", buffering=0) as fh:
        var = fh.read(0) if False else None
        vi = fcntl.ioctl(fh.fileno(), FBIOGET_VSCREENINFO, bytes(64))
        fi = fcntl.ioctl(fh.fileno(), FBIOGET_FSCREENINFO, bytes(64))
        (xres, yres, xres_v, yres_v, xoff, yoff, bpp, grayscale,
         ro, rl, rmsb, go, gl, gmsb, bo, bl, bmsb) = struct.unpack("<17I", vi[:68])
        smem_len = struct.unpack("<I", fi[24:28])[0]
        line_length = struct.unpack("<I", fi[48:52])[0]
        if line_length < xres * (bpp // 8):
            line_length = xres * (bpp // 8)
        fh.seek(0)
        data = fh.read(line_length * yres)
        if not data:
            # some drivers refuse read(); fall back to the whole buffer
            data = fh.read(smem_len or line_length * yres)

    shift_r, shift_g, shift_b = ro, go, bo
    mask_r = (1 << rl) - 1
    mask_g = (1 << gl) - 1
    mask_b = (1 << bl) - 1
    bytes_per_px = bpp // 8
    rgb = bytearray(xres * yres * 3)
    for y in range(yres):
        base = y * line_length
        for x in range(xres):
            off = base + x * bytes_per_px
            if bytes_per_px == 2:
                px = struct.unpack_from("<H", data, off)[0]
            elif bytes_per_px == 4:
                px = struct.unpack_from("<I", data, off)[0]
            elif bytes_per_px == 3:
                px = data[off] | (data[off + 1] << 8) | (data[off + 2] << 16)
            else:
                px = data[off]
            if grayscale:
                v = (px >> shift_r) & mask_r
                r = g = b = v * (255 // max(mask_r, 1))
            else:
                r = ((px >> shift_r) & mask_r) * (255 // max(mask_r, 1))
                g = ((px >> shift_g) & mask_g) * (255 // max(mask_g, 1))
                b = ((px >> shift_b) & mask_b) * (255 // max(mask_b, 1))
            o = (y * xres + x) * 3
            rgb[o] = min(r, 255)
            rgb[o + 1] = min(g, 255)
            rgb[o + 2] = min(b, 255)

    write_png(out, xres, yres, bytes(rgb))
    print("fb%d: %dx%d bpp=%d r%d/%d g%d/%d b%d/%d line_length=%d -> %s"
          % (0, xres, yres, bpp, ro, rl, go, gl, bo, bl, line_length, out))


if __name__ == "__main__":
    sys.exit(main() or 0)
