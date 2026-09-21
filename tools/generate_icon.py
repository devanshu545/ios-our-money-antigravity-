#!/usr/bin/env python3
"""Generates the OurMoney 1024x1024 app icon PNG using only the Python standard library.

Brand: dark graphite background (#121212 -> #1A1C1E vertical gradient), soft teal wallet
mark (#80CBC4) matching the Android launcher identity.
Output: OurMoney/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png
"""
import struct
import zlib
import os
import math

SIZE = 1024

# Colors
BG_TOP = (0x12, 0x12, 0x12)
BG_BOTTOM = (0x1A, 0x1C, 0x1E)
TEAL = (0x80, 0xCB, 0xC4)
TEAL_DIM = (0x00, 0x50, 0x49)


def lerp(a, b, t):
    return (int(a[0] + (b[0] - a[0]) * t),
            int(a[1] + (b[1] - a[1]) * t),
            int(a[2] + (b[2] - a[2]) * t))


def rounded_rect_contains(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    # Corner regions
    for ccx, ccy in ((x0 + r, y0 + r), (x1 - r, y0 + r), (x0 + r, y1 - r), (x1 - r, y1 - r)):
        in_corner_x = (x < x0 + r and ccx == x0 + r) or (x > x1 - r and ccx == x1 - r)
        in_corner_y = (y < y0 + r and ccy == y0 + r) or (y > y1 - r and ccy == y1 - r)
        if in_corner_x and in_corner_y:
            return (x - ccx) ** 2 + (y - ccy) ** 2 <= r * r
    return True


def render():
    cx, cy = SIZE / 2, SIZE / 2
    # Wallet body: rounded rectangle
    wx0, wy0, wx1, wy1 = cx - 300, cy - 200, cx + 300, cy + 220
    corner = 90
    # Card slot / flap: horizontal band
    flap_y = cy + 60
    flap_h = 90
    # Clasp circle
    clasp_r = 34
    clasp_cx = cx + 170
    clasp_cy = flap_y + flap_h / 2

    # Precompute per-row spans of the wallet body and flap for fast filling.
    body_rows = {}
    flap_rows = {}
    for y in range(SIZE):
        spans = []
        run_start = None
        for x in range(0, SIZE, 2):
            if rounded_rect_contains(x, y, wx0, wy0, wx1, wy1, corner):
                if run_start is None:
                    run_start = x
            else:
                if run_start is not None:
                    spans.append((run_start, x))
                    run_start = None
        if run_start is not None:
            spans.append((run_start, SIZE))
        if spans:
            body_rows[y] = spans

        spans = []
        run_start = None
        for x in range(int(wx0), int(wx1) + 1, 2):
            if rounded_rect_contains(x, y, wx0, flap_y, wx1, flap_y + flap_h, 28):
                if run_start is None:
                    run_start = x
            else:
                if run_start is not None:
                    spans.append((run_start, x))
                    run_start = None
        if run_start is not None:
            spans.append((run_start, int(wx1) + 1))
        if spans:
            flap_rows[y] = spans

    clasp_r_sq = clasp_r ** 2
    body_col_for_row = {}
    flap_col = lerp(TEAL_DIM, BG_TOP, 0.25)

    px = []
    for y in range(SIZE):
        t = y / (SIZE - 1)
        bg = lerp(BG_TOP, BG_BOTTOM, t)
        row = [bg] * SIZE

        if y in body_rows:
            if y not in body_col_for_row:
                tt = (y - wy0) / (wy1 - wy0)
                body_col_for_row[y] = lerp(TEAL, TEAL_DIM, tt * 0.35)
            col = body_col_for_row[y]
            for (sx, ex) in body_rows[y]:
                for x in range(max(0, sx - 1), min(SIZE, ex + 1)):
                    row[x] = col

        for (sx, ex) in flap_rows.get(y, []):
            for x in range(max(0, sx - 1), min(SIZE, ex + 1)):
                row[x] = flap_col

        if abs(y - clasp_cy) <= clasp_r:
            dx = int(math.sqrt(clasp_r_sq - (y - clasp_cy) ** 2))
            for x in range(max(0, int(clasp_cx) - dx), min(SIZE, int(clasp_cx) + dx + 1)):
                row[x] = bg

        px.append(row)

    return px


def write_png(path, px, size):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        c += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c

    raw = bytearray()
    for y in range(size):
        raw += b"\x00"
        row = px[y]
        for x in range(size):
            r, g, b = row[x]
            raw += bytes((r, g, b))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    out_dir = os.path.join(os.path.dirname(__file__), "..", "OurMoney", "Resources",
                           "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "AppIcon1024.png")
    img = render()
    write_png(out_path, img, SIZE)
    print(f"Wrote {out_path} ({os.path.getsize(out_path)} bytes)")
