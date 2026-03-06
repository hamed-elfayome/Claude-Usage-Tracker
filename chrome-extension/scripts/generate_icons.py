#!/usr/bin/env python3
"""
generate_icons.py — Create PNG icons for Claude Usage Tracker Chrome Extension.
Uses only Python stdlib (struct, zlib, math, os). No external dependencies.

Usage:
  python scripts/generate_icons.py
"""
import struct, zlib, math, os

# Colors
BG_DARK   = (18, 18, 32)         # #121220
BG_LIGHT  = (28, 28, 50)         # #1c1c32
ORANGE    = (249, 115, 22)        # #f97316 — Claude accent
ORANGE_DIM = (200, 90, 16)

def lerp_int(a, b, t):
    return int(a + (b - a) * max(0.0, min(1.0, t)))

def lerp_color(c1, c2, t):
    return tuple(lerp_int(a, b, t) for a, b in zip(c1, c2))

def write_png(path, width, height, rgba_rows):
    """Write a list of rows (each row = list of (r,g,b,a) tuples) as PNG."""
    def chunk(tag, data):
        payload = tag + data
        return struct.pack('>I', len(data)) + payload + struct.pack('>I', zlib.crc32(payload) & 0xFFFFFFFF)

    raw = b''.join(
        b'\x00' + b''.join(struct.pack('BBBB', *px) for px in row)
        for row in rgba_rows
    )
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)  # 6 = RGBA
    png = (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', ihdr)
        + chunk(b'IDAT', zlib.compress(raw, 9))
        + chunk(b'IEND', b'')
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(png)
    print(f'  {path}  ({width}x{height})')


def make_icon(size):
    """
    Design:
     - Dark circular background with subtle radial gradient
     - Orange "C" arc (like the letter C, opening to the right)
     - Anti-aliased edges
    """
    rows = []
    cx = cy = (size - 1) / 2
    outer_r = cx * 0.96          # circle radius
    arc_r   = outer_r * 0.54     # C arc radius
    arc_w   = outer_r * 0.20     # C stroke width

    for y in range(size):
        row = []
        for x in range(size):
            dx = x - cx
            dy = y - cy
            dist = math.sqrt(dx * dx + dy * dy)

            # --- circle mask with AA ---
            if dist > outer_r + 0.6:
                row.append((0, 0, 0, 0))
                continue

            circle_alpha = 255
            if dist > outer_r - 0.6:
                t = (outer_r + 0.6 - dist) / 1.2
                circle_alpha = int(255 * max(0.0, min(1.0, t)))

            # --- background gradient ---
            t_bg = dist / outer_r
            bg = lerp_color(BG_LIGHT, BG_DARK, t_bg * 0.5)

            # --- C arc ---
            angle_deg = math.degrees(math.atan2(dy, dx))  # -180..180
            arc_dist  = abs(dist - arc_r)
            in_stroke = arc_dist < arc_w / 2

            # C opening: right side, gap ≈ ±40°
            opening = abs(angle_deg) < 42

            if in_stroke and not opening:
                blend = 1.0 - (arc_dist / (arc_w / 2)) ** 2
                blend = max(0.0, blend)
                r = lerp_int(bg[0], ORANGE[0], blend)
                g = lerp_int(bg[1], ORANGE[1], blend)
                b = lerp_int(bg[2], ORANGE[2], blend)
            else:
                r, g, b = bg

            a = circle_alpha
            row.append((r, g, b, a))
        rows.append(row)
    return rows


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    icons_dir  = os.path.join(script_dir, '..', 'icons')

    print('Generating icons...')
    for size in [16, 32, 48, 128]:
        rows = make_icon(size)
        write_png(os.path.join(icons_dir, f'icon{size}.png'), size, size, rows)
    print('Done.')


if __name__ == '__main__':
    main()
