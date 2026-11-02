"""Generates the ring textures in Media/ as 32-bit TGA (WoW reads TGA and BLP).

All textures are white with an alpha shape, so the addon can tint them with
SetVertexColor for each style. Run from the repo root: python scripts/make-media.py
"""
import math
import os
import struct

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media")


def smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def write_tga(name, size, alpha_at):
    """alpha_at(d) gets the distance from the centre, 0..1 at the edge."""
    pixels = bytearray()
    half = size / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x + 0.5 - half, y + 0.5 - half) / half
            a = max(0.0, min(1.0, alpha_at(d)))
            pixels += bytes((255, 255, 255, int(a * 255 + 0.5)))
    # Uncompressed true-colour, 32 bpp, 8 alpha bits, top-left origin.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header + pixels)


def band(centre, width, soft):
    """A ring of the given radius and width with soft edges."""
    def alpha(d):
        return 1 - smoothstep(width / 2, width / 2 + soft, abs(d - centre))
    return alpha


def main():
    os.makedirs(OUT, exist_ok=True)

    # Track the slots sit on: a bright line with a soft glow around it.
    line, glow = band(0.9, 0.012, 0.012), band(0.9, 0.0, 0.07)
    write_tga("track", 512, lambda d: max(line(d), 0.35 * glow(d)))

    # Soft light: halos, the light that runs along the track, the cast flash.
    write_tga("glow", 128, lambda d: (1 - smoothstep(0.0, 1.0, d)) ** 2)

    # Thin rim around each slot.
    write_tga("rim", 128, band(0.88, 0.05, 0.03))

    # Backdrop: dark in the middle, fading out well past the slots.
    write_tga("vignette", 256, lambda d: 0.85 * (1 - smoothstep(0.45, 1.0, d)))

    print("wrote", ", ".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    main()
