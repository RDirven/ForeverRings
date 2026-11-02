"""Renders an approximate preview of the ring animation outside WoW.

Uses the real textures in Media/ and the same sizes and timings as
Display.lua. Icons are placeholders. Writes dist/ring-preview.gif and
dist/ring-preview-classic.png. Run from the repo root: python scripts/preview.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "Media")
OUT = os.path.join(ROOT, "dist")

# Same numbers as Display.lua
RADIUS, ICON = 120, 46
TRACK_RADIUS = RADIUS - 36
TRACK = TRACK_RADIUS * 2 / 0.9
OUTER = (RADIUS + ICON) * 2
POINTER_RADIUS = 52
OPEN_TIME, STAGGER, SELECT_SCALE = 0.22, 0.02, 1.22
PING_TIME, FLASH_TIME, IDLE_SPEED = 0.3, 0.35, 40
COLORS = {"clean": (0.35, 0.75, 1.0), "classic": (1.0, 0.82, 0.25)}

SIZE = 440
FPS = 30
SLOTS = [  # placeholder icons for the default Main ring
    ("Food", (0.85, 0.55, 0.25)), ("Mounts", (0.55, 0.4, 0.3)), ("Bag", (0.6, 0.35, 0.7)),
    ("Quest", (0.95, 0.8, 0.2)), ("Markers", (0.85, 0.2, 0.2)), ("Tools", (0.45, 0.5, 0.55)),
    ("Settings", (0.5, 0.55, 0.65)),
]


def load(name):
    img = Image.open(os.path.join(MEDIA, name + ".tga")).convert("RGBA")
    return np.asarray(img).astype(np.float32) / 255


TEX = {n: load(n) for n in ("track", "glow", "rim", "vignette")}


def resized(tex, size, rotation=0.0):
    img = Image.fromarray((tex * 255).astype(np.uint8), "RGBA")
    if rotation:
        img = img.rotate(math.degrees(rotation), resample=Image.BICUBIC)
    size = max(1, int(round(size)))
    return np.asarray(img.resize((size, size), Image.BICUBIC)).astype(np.float32) / 255


def draw(canvas, tex, cx, cy, size, color=(1, 1, 1), alpha=1.0, add=False, rotation=0.0):
    if alpha <= 0 or size < 1:
        return
    t = resized(tex, size, rotation)
    h, w = t.shape[:2]
    x0, y0 = int(round(cx - w / 2)), int(round(cy - h / 2))
    x1, y1 = max(x0, 0), max(y0, 0)
    x2, y2 = min(x0 + w, SIZE), min(y0 + h, SIZE)
    if x1 >= x2 or y1 >= y2:
        return
    part = t[y1 - y0:y2 - y0, x1 - x0:x2 - x0]
    a = part[..., 3:4] * alpha
    rgb = part[..., :3] * np.array(color, dtype=np.float32)
    region = canvas[y1:y2, x1:x2]
    if add:
        region += rgb * a
    else:
        region[:] = region * (1 - a) + rgb * a
    np.clip(region, 0, 1, out=region)


def icon_texture(color, letter):
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = tuple(int(v * 255) for v in color)
    dark = tuple(int(v * 140) for v in color)
    d.ellipse((0, 0, 127, 127), fill=dark)
    d.ellipse((10, 10, 117, 117), fill=c)
    font = ImageFont.load_default(size=56)
    d.text((64, 66), letter, fill=(255, 255, 255, 235), font=font, anchor="mm")
    return np.asarray(img).astype(np.float32) / 255


ICONS = [icon_texture(c, n[0]) for n, c in SLOTS]


def scene():
    """A blurry 'game world' behind the ring."""
    y = np.linspace(0, 1, SIZE)[:, None, None]
    x = np.linspace(0, 1, SIZE)[None, :, None]
    sky = np.array([0.38, 0.55, 0.72], np.float32)
    ground = np.array([0.28, 0.36, 0.2], np.float32)
    mix = np.clip((y - 0.35) * 2.5, 0, 1)
    img = sky * (1 - mix) + ground * mix
    img = img + 0.05 * np.sin(x * 9 + y * 4)
    return np.broadcast_to(img, (SIZE, SIZE, 3)).astype(np.float32).copy()


def ease_out(p):
    return 1 - (1 - min(max(p, 0), 1)) ** 3


def ease_out_back(p):
    p = min(max(p, 0), 1)
    c = 1.7
    return 1 + (c + 1) * (p - 1) ** 3 + c * (p - 1) ** 2


def on_circle(angle, radius):
    rad = math.radians(angle)
    return SIZE / 2 + math.sin(rad) * radius, SIZE / 2 - math.cos(rad) * radius


def render(state, style="clean"):
    color = COLORS[style]
    canvas = scene()
    open_ = ease_out(state["age"] / OPEN_TIME)
    c = SIZE / 2

    # Draw at reduced opacity while opening: blend toward the scene afterwards.
    ring = canvas.copy()
    draw(ring, TEX["vignette"], c, c, OUTER * (1.15 + 0.25 * open_), (0, 0, 0))
    draw(ring, TEX["track"], c, c, TRACK * (0.85 + 0.15 * open_), color, rotation=math.radians(50 * (1 - open_)))
    sel = state["selected"]
    draw(ring, TEX["glow"], c, c, 150, color, 0.35 if sel else 0.15, add=True)
    light_alpha = 0.9 if sel else 0.35 + 0.15 * math.sin(state["time"] * 2)
    lx, ly = on_circle(state["light"], TRACK_RADIUS)
    draw(ring, TEX["glow"], lx, ly, 90, color, light_alpha, add=True)
    if sel:
        px, py = on_circle(state["light"], POINTER_RADIUS)
        draw(ring, TEX["glow"], px, py, 12, color, 1)

    n = len(SLOTS)
    pulse = 0.75 + 0.25 * math.sin(state["time"] * 5)
    for i in range(n):
        on = sel == i + 1
        p = ease_out_back((state["age"] - i * STAGGER) / OPEN_TIME)
        angle = i * 360 / n
        x, y = on_circle(angle, RADIUS * (0.5 + 0.5 * p))
        scale = state["scales"][i] * (0.5 + 0.5 * p)
        alpha = min(max(p, 0), 1) * (0.65 if sel and not on else 1)
        if on:
            draw(ring, TEX["glow"], x, y, ICON * 2.4 * scale, color, pulse * alpha, add=True)
        draw(ring, ICONS[i], x, y, ICON * scale, alpha=alpha)
        if style == "clean":
            rim_color, rim_alpha = (color, 1) if on else ((1, 1, 1), 0.3)
            draw(ring, TEX["rim"], x, y, (ICON + 10) * scale, rim_color, rim_alpha * alpha)
        else:
            draw(ring, TEX["rim"], x, y, (ICON + 12) * scale, (0.55, 0.45, 0.3), alpha)
        ping = min(max(state["pings"][i] / PING_TIME, 0), 1)
        if ping < 1:
            draw(ring, TEX["rim"], x, y, (ICON + 10) * scale * (1 + 0.7 * ping), color, (1 - ping) * 0.9, add=True)

    canvas = canvas * (1 - open_) + ring * open_ if state["shown"] else canvas

    if state["flash"] is not None:
        f = min(state["flash"] / FLASH_TIME, 1)
        if f < 1:
            fs = 1 + 0.5 * ease_out(f)
            draw(canvas, TEX["glow"], c, c, ICON * 4 * fs, color, 1 - f, add=True)
            draw(canvas, ICONS[state["flash_icon"]], c, c, ICON * 1.4 * fs, alpha=1 - f)

    img = Image.fromarray((canvas * 255).astype(np.uint8), "RGB")
    if state["shown"]:
        d = ImageDraw.Draw(img)
        title = SLOTS[sel - 1][0] if sel else "Main"
        d.text((c, c - 2), title, fill=(255, 255, 255), font=ImageFont.load_default(size=17), anchor="mm")
        d.text((c, c + 18), "A select  ·  B close", fill=(150, 150, 150), font=ImageFont.load_default(size=11), anchor="mm")
    return img


def simulate():
    """Open, idle a moment, aim at a few slots, then use one."""
    script = [(0.0, None), (0.6, 1), (1.1, 2), (1.6, 4), (2.2, "use")]
    dt = 1 / FPS
    state = {"age": 0.0, "time": 0.0, "selected": None, "light": 0.0, "shown": True,
             "scales": [1.0] * len(SLOTS), "pings": [PING_TIME] * len(SLOTS), "flash": None, "flash_icon": 0}
    frames, t = [], 0.0
    while t < 2.8:
        for at, action in script:
            if abs(t - at) < dt / 2:
                if action == "use":
                    state["shown"], state["flash"], state["flash_icon"] = False, 0.0, state["selected"] - 1
                elif action is not None:
                    state["selected"] = action
                    state["pings"][action - 1] = 0.0
        sel = state["selected"]
        if sel:
            target = (sel - 1) * 360 / len(SLOTS)
            diff = (target - state["light"] + 180) % 360 - 180
            state["light"] += diff * min(1, dt * 20)
        else:
            state["light"] = (state["light"] + IDLE_SPEED * dt) % 360
        for i in range(len(SLOTS)):
            goal = SELECT_SCALE if sel == i + 1 else 1
            state["scales"][i] += (goal - state["scales"][i]) * min(1, dt * 14)
            state["pings"][i] += dt
        if state["flash"] is not None:
            state["flash"] += dt
        frames.append(render(state))
        state["age"] += dt
        state["time"] += dt
        t += dt
    return frames


def main():
    os.makedirs(OUT, exist_ok=True)
    frames = simulate()
    gif = os.path.join(OUT, "ring-preview.gif")
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=int(1000 / FPS), loop=0)
    frames[40].save(os.path.join(OUT, "ring-preview-clean.png"))

    still = {"age": 1.0, "time": 1.0, "selected": 3, "light": 3 * 360 / 7 - 360 / 7, "shown": True,
             "scales": [1, 1, SELECT_SCALE, 1, 1, 1, 1], "pings": [PING_TIME] * 7, "flash": None, "flash_icon": 0}
    still["light"] = 2 * 360 / 7
    render(still, "classic").save(os.path.join(OUT, "ring-preview-classic.png"))
    print("wrote", gif)


if __name__ == "__main__":
    main()
