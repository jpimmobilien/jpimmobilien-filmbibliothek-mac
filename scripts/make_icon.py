#!/usr/bin/env python3
"""App-Symbol und DMG-Hintergrund der Filmbibliothek erzeugen (Pillow).

    python3 scripts/make_icon.py      → Resources/AppIcon-1024.png, Resources/AppIcon.icns,
                                        Resources/DMG/background.png, Resources/DMG/background@2x.png

Gestaltung: macOS-Squircle mit tiefem Indigo-Verlauf und weichen Lichtinseln (wie das App-Fenster),
darauf eine Glas-Linse mit Filmstreifen-Ring und einem hellen Wiedergabe-Dreieck.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Resources")
S = 1024


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def squircle_mask(size, inset, radius_factor=0.225):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    box = (inset, inset, size - inset, size - inset)
    r = int((size - 2 * inset) * radius_factor)
    d.rounded_rectangle(box, radius=r, fill=255)
    return m


def radial(size, center, radius, color, alpha):
    layer = Image.new("RGBA", (size, size), color + (0,))
    a = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(a)
    steps = 60
    for i in range(steps, 0, -1):
        r = radius * i / steps
        v = int(alpha * (1 - i / steps) ** 1.6)
        d.ellipse((center[0] - r, center[1] - r, center[0] + r, center[1] + r), fill=v)
    layer.putalpha(a)
    return layer


def make_icon():
    inset = 100
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Hintergrund-Verlauf (diagonal)
    grad = Image.new("RGBA", (S, S))
    top, mid, bot = (40, 52, 110), (28, 22, 70), (12, 16, 34)
    px = grad.load()
    for y in range(S):
        for x in range(S):
            t = (x * 0.35 + y * 0.65) / S
            c = lerp(top, mid, t / 0.55) if t < 0.55 else lerp(mid, bot, (t - 0.55) / 0.45)
            px[x, y] = c + (255,)
    grad = Image.alpha_composite(grad, radial(S, (240, 180), 520, (110, 90, 255), 150))
    grad = Image.alpha_composite(grad, radial(S, (860, 300), 460, (40, 170, 200), 110))
    grad = Image.alpha_composite(grad, radial(S, (420, 960), 520, (170, 60, 200), 120))
    mask = squircle_mask(S, inset)
    base.paste(grad, (0, 0), mask)

    # Lichtkante oben
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ed = ImageDraw.Draw(edge)
    r = int((S - 2 * inset) * 0.225)
    ed.rounded_rectangle((inset + 2, inset + 2, S - inset - 2, S - inset - 2), radius=r, outline=(255, 255, 255, 70), width=4)
    fade = Image.new("L", (S, S), 0)
    fd = ImageDraw.Draw(fade)
    for y in range(S):
        fd.line([(0, y), (S, y)], fill=int(255 * max(0, 1 - (y - inset) / 520)))
    edge.putalpha(ImageChops.multiply(edge.split()[3], fade))
    base = Image.alpha_composite(base, edge)

    cx, cy = S // 2, S // 2 + 10
    # Glas-Linse
    lens_r = 300
    lens = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lens)
    ld.ellipse((cx - lens_r, cy - lens_r, cx + lens_r, cy + lens_r), fill=(175, 190, 255, 46), outline=(255, 255, 255, 110), width=5)
    # Filmstreifen-Ring: Perforationen
    ring_r = lens_r - 48
    for i in range(24):
        a = 2 * math.pi * i / 24
        x, y = cx + ring_r * math.cos(a), cy + ring_r * math.sin(a)
        w, h = 30, 20
        box = Image.new("RGBA", (60, 60), (0, 0, 0, 0))
        bd = ImageDraw.Draw(box)
        bd.rounded_rectangle((30 - w / 2, 30 - h / 2, 30 + w / 2, 30 + h / 2), radius=6, fill=(255, 255, 255, 120))
        box = box.rotate(-math.degrees(a), resample=Image.BICUBIC)
        lens.alpha_composite(box, (int(x - 30), int(y - 30)))
    # Glanz oben in der Linse
    sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse((cx - lens_r + 40, cy - lens_r + 20, cx + lens_r - 40, cy - 20), fill=(255, 255, 255, 40))
    sheen = sheen.filter(ImageFilter.GaussianBlur(28))
    lens = Image.alpha_composite(lens, sheen)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((cx - lens_r, cy - lens_r + 30, cx + lens_r, cy + lens_r + 30), fill=(0, 0, 0, 55))
    shadow = shadow.filter(ImageFilter.GaussianBlur(36))
    base = Image.alpha_composite(base, shadow)
    base = Image.alpha_composite(base, lens)

    # Wiedergabe-Dreieck mit leichtem Verlauf
    tri = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(tri)
    h = 250
    pts = [(cx - h * 0.40, cy - h * 0.55), (cx - h * 0.40, cy + h * 0.55), (cx + h * 0.62, cy)]
    td.polygon(pts, fill=(255, 255, 255, 255))
    tri = tri.filter(ImageFilter.GaussianBlur(1.2))
    tg = Image.new("RGBA", (S, S))
    tp = tg.load()
    for y in range(S):
        c = lerp((255, 255, 255), (196, 210, 255), max(0, min(1, (y - (cy - h * 0.55)) / (h * 1.1))))
        for x in range(S):
            tp[x, y] = c + (255,)
    tri_col = Image.composite(tg, Image.new("RGBA", (S, S), (0, 0, 0, 0)), tri.split()[3])
    glow = tri.filter(ImageFilter.GaussianBlur(30))
    glow = Image.composite(Image.new("RGBA", (S, S), (130, 160, 255, 200)), Image.new("RGBA", (S, S), (0, 0, 0, 0)), glow.split()[3])
    base = Image.alpha_composite(base, glow)
    base = Image.alpha_composite(base, tri_col)

    # außerhalb der Squircle-Form transparent lassen
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(base, (0, 0), squircle_mask(S, inset - 1))
    # weicher Schatten der Kachel (macOS-Stil)
    drop = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(drop).rounded_rectangle((inset, inset + 16, S - inset, S - inset + 16), radius=r, fill=(0, 0, 0, 110))
    drop = drop.filter(ImageFilter.GaussianBlur(22))
    final = Image.alpha_composite(drop, out)
    final.save(os.path.join(RES, "AppIcon-1024.png"))
    final.save(os.path.join(RES, "AppIcon.icns"), sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    return final


def make_dmg_background(icon):
    for scale, name in ((1, "background.png"), (2, "background@2x.png")):
        w, h = 660 * scale, 400 * scale
        bg = Image.new("RGBA", (w, h))
        px = bg.load()
        a, b, c = (32, 20, 52), (22, 14, 36), (12, 10, 18)
        for y in range(h):
            for x in range(w):
                t = (x * 0.4 + y * 0.6) / max(w, h) * 1.4
                col = lerp(a, b, min(1, t / 0.6)) if t < 0.6 else lerp(b, c, min(1, (t - 0.6) / 0.6))
                px[x, y] = col + (255,)
        bg = Image.alpha_composite(bg, radial(w, (int(w * 0.15), int(h * 0.05)), int(w * 0.6), (100, 85, 240), 120).resize((w, h)) if False else bg)
        glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse((-w * 0.2, -h * 0.6, w * 0.6, h * 0.5), fill=(150, 90, 240, 70))
        gd.ellipse((w * 0.55, -h * 0.4, w * 1.3, h * 0.6), fill=(200, 80, 170, 45))
        glow = glow.filter(ImageFilter.GaussianBlur(60 * scale))
        bg = Image.alpha_composite(bg, glow)
        d = ImageDraw.Draw(bg)
        # Pfeil von der App zum Programme-Ordner
        y = 200 * scale
        d.line([(250 * scale, y), (410 * scale, y)], fill=(255, 255, 255, 120), width=3 * scale)
        d.polygon([(410 * scale, y - 10 * scale), (428 * scale, y), (410 * scale, y + 10 * scale)], fill=(255, 255, 255, 120))
        try:
            from PIL import ImageFont
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22 * scale)
            small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13 * scale)
            d.text((w / 2, 52 * scale), "Filmbibliothek", font=font, fill=(255, 255, 255, 235), anchor="mm")
            d.text((w / 2, 335 * scale), "Zum Installieren die App auf „Applications“ (Programme) ziehen", font=small, fill=(232, 222, 255, 200), anchor="mm")
            d.text((w / 2, 357 * scale), "Erster Start ohne Apple-Beglaubigung: siehe „Installation – bitte lesen.txt“", font=small, fill=(214, 200, 245, 160), anchor="mm")
        except Exception as e:  # Schrift fehlt: ohne Text
            print("Hinweis:", e)
        bg.convert("RGB").save(os.path.join(RES, "DMG", name))


def icon_from_source(path):
    """App-Symbol aus der Vorlage (Resources/AppIcon-Quelle.png, Symbol auf weißem Grund): Hintergrund von den
    Ecken aus freistellen, Saum entfernen, nach Apple-Raster (824 px Körper auf 1024 px) mit weichem Schatten setzen."""
    src = Image.open(path).convert("RGBA")
    w, h = src.size
    mark = src.convert("RGB")
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(mark, seed, (255, 0, 255), thresh=40)
    mp = mark.load()
    mask = Image.new("L", (w, h), 0)
    mk = mask.load()
    for y in range(h):
        for x in range(w):
            mk[x, y] = 0 if mp[x, y] == (255, 0, 255) else 255
    mask = mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.1))
    body = src.copy()
    body.putalpha(mask)
    body = body.crop(mask.getbbox())
    side = max(body.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(body, ((side - body.size[0]) // 2, (side - body.size[1]) // 2))
    b = sq.resize((824, 824), Image.LANCZOS)
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    sh = Image.new("RGBA", (824, 824), (40, 10, 80, 0))
    sh.putalpha(b.split()[3].point(lambda a: int(a * 0.32)))
    shadow.paste(sh, (100, 112), sh)
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(b, (100, 100))
    canvas.save(os.path.join(RES, "AppIcon-1024.png"))
    canvas.save(os.path.join(RES, "AppIcon.icns"), sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    return canvas


if __name__ == "__main__":
    os.makedirs(os.path.join(RES, "DMG"), exist_ok=True)
    source = os.path.join(RES, "AppIcon-Quelle.png")
    icon = icon_from_source(source) if os.path.exists(source) else make_icon()
    make_dmg_background(icon)
    print("ok")
