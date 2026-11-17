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


def write_wedge(name, size, n, i, inner=0.30, outer=0.98, gap_px=5, samples=4):
    """A pizza slice, anti-aliased by averaging samples x samples points per
    pixel. The gap between slices is the same width all along (gap_px)."""
    import numpy as np

    half = size / 2
    offsets = (np.arange(samples) + 0.5) / samples
    xs = (np.arange(size)[:, None] + offsets[None, :]).reshape(-1) - half
    px, py = np.meshgrid(xs, xs)  # rows are y, columns x, in sub-pixels
    d = np.hypot(px, py) / half
    inside = (d >= inner) & (d <= outer)
    if n > 1:
        # Distance to the slice's centre line, in pixels, must stay within the
        # slice's half angle minus half the gap.
        centre = np.radians((i - 1) * 360.0 / n)
        dir_x, dir_y = np.sin(centre), -np.cos(centre)  # up is -y in the image
        along = px * dir_x + py * dir_y
        across = np.abs(px * dir_y - py * dir_x)
        half_angle = np.pi / n
        inside &= along > 0
        inside &= across * np.cos(half_angle) <= along * np.sin(half_angle) - gap_px / 2 * size / 256
    a = inside.reshape(size, samples, size, samples).mean(axis=(1, 3))
    alpha = (a * 255 + 0.5).astype(np.uint8)
    pixels = np.zeros((size, size, 4), dtype=np.uint8)
    pixels[..., :3] = 255
    pixels[..., 3] = alpha
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    # TGA stores BGRA; white is the same either way.
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header + pixels.tobytes())


def write_ring(name, size, k, count, inner=0.30, outer=0.98, samples=4, from_centre=False):
    """From the crust inward over k of count steps: ring 1 is the crust, ring
    count the whole slice. They overlap, so lit rings make one solid area.
    from_centre: the same, growing from the centre outward."""
    import numpy as np

    if from_centre:
        r_in, outer = inner, inner + k * (outer - inner) / count
    else:
        r_in = outer - k * (outer - inner) / count
    half = size / 2
    offsets = (np.arange(samples) + 0.5) / samples
    xs = (np.arange(size)[:, None] + offsets[None, :]).reshape(-1) - half
    px, py = np.meshgrid(xs, xs)
    d = np.hypot(px, py) / half
    a = ((d >= r_in) & (d <= outer)).reshape(size, samples, size, samples).mean(axis=(1, 3))
    pixels = np.zeros((size, size, 4), dtype=np.uint8)
    pixels[..., :3] = 255
    pixels[..., 3] = (a * 255 + 0.5).astype(np.uint8)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header + pixels.tobytes())


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

    # Party ring: one pizza slice per member, for 1 to 5 members. Slice i of n
    # points at (i - 1) * 360 / n degrees, clockwise from up, like the slots.
    # A hole in the middle leaves room for the ring's title.
    for n in range(1, 6):
        for i in range(1, n + 1):
            write_wedge("wedge%d_%d" % (n, i), 256, n, i)
    for k in range(1, 13):
        write_ring("ring%d" % k, 256, k, 12)
        write_ring("ringc%d" % k, 256, k, 12, from_centre=True)

    print("wrote", ", ".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    main()
