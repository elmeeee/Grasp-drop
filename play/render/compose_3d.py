"""Compose Play store screenshots with a 3D look (perspective phone, shadows, floating cards).
Input: play/render/<scene>.png (1080x2400 UI renders). Output: play/screenshots/store/*.png (1080x2160)."""
import glob, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1080, 2160
BG = (10, 15, 26, 255)
PANEL = (17, 26, 43, 255)
RING = (26, 137, 228, 255)
WHITE = (237, 242, 250, 255)
MUTED = (135, 148, 173, 255)
BLUE = (26, 137, 228, 255)
GREEN = (34, 197, 94, 255)
FRAME = (5, 8, 15, 255)
EDGE = (46, 64, 102, 255)

def font(size, bold=False):
    path = "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf"
    return ImageFont.truetype(path, size)

def fit(text, start, bold, maxw):
    size = start
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    while size > 40 and probe.textlength(text, font=font(size, bold)) > maxw:
        size -= 2
    return font(size, bold)

def perspective_coeffs(src, dst):
    """Coefficients that map output (dst quad) back to input (src rect), for Image.transform."""
    A, b = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    return np.linalg.solve(np.array(A, float), np.array(b, float)).tolist()

def phone_layer(shot, sw, quad):
    """Phone (bezel + screen) drawn flat, then warped onto the full canvas with the given quad."""
    sh = int(shot.size[1] * sw / shot.size[0])
    bezel = 26
    fw, fh = sw + bezel * 2, sh + bezel * 2
    flat = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    ImageDraw.Draw(flat).rounded_rectangle([0, 0, fw - 1, fh - 1], radius=86, fill=FRAME, outline=EDGE, width=4)
    scr = shot.resize((sw, sh), Image.LANCZOS)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=62, fill=255)
    flat.paste(scr, (bezel, bezel), mask)
    # side highlight (glass sheen) as a thin light edge on the left
    ImageDraw.Draw(flat).rounded_rectangle([3, 3, fw - 4, fh - 4], radius=84, outline=(70, 92, 140, 255), width=2)
    src = [(0, 0), (fw, 0), (fw, fh), (0, fh)]
    coeffs = perspective_coeffs(src, quad)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    warped = flat.transform((W, H), Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    layer.alpha_composite(warped)
    return layer

def shadow_of(layer, offset=(34, 58), blur=38, alpha=170):
    a = layer.getchannel("A")
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shade = Image.new("RGBA", (W, H), (0, 0, 0, alpha))
    shadow.paste(shade, (0, 0), a)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(shadow, offset)
    return out

def card(text_lines, width, accent=BLUE, bar=None):
    """Floating UI card: flat panel, accent edge, text and an optional progress bar."""
    pad = 34
    h = pad * 2 + 46 * len(text_lines) + (34 if bar is not None else 0)
    img = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, width - 1, h - 1], radius=38, fill=PANEL, outline=EDGE, width=3)
    d.rounded_rectangle([0, 26, 10, h - 26], radius=5, fill=accent)
    y = pad
    for i, (t, bold, color, size) in enumerate(text_lines):
        d.text((pad + 16, y), t, font=font(size, bold), fill=color)
        y += size + 14
    if bar is not None:
        bw = width - pad * 2 - 16
        d.rounded_rectangle([pad + 16, y + 8, pad + 16 + bw, y + 22], radius=7, fill=(30, 44, 72, 255))
        d.rounded_rectangle([pad + 16, y + 8, pad + 16 + int(bw * bar), y + 22], radius=7, fill=accent)
    return img

def paste_card(canvas, img, xy, angle=0):
    rot = img.rotate(angle, resample=Image.BICUBIC, expand=True)
    sh = Image.new("RGBA", rot.size, (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", rot.size, (0, 0, 0, 170)), (0, 0), rot.getchannel("A"))
    sh = sh.filter(ImageFilter.GaussianBlur(26))
    canvas.alpha_composite(sh, (xy[0] + 16, xy[1] + 30))
    canvas.alpha_composite(rot, xy)

def orbit(canvas, cx, cy, rx, ry, rot_deg=-18, color=RING, width=3):
    """Flat elliptical orbit line, drawn on its own layer and rotated: reads as depth."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], outline=color, width=width)
    layer = layer.rotate(rot_deg, center=(cx, cy), resample=Image.BICUBIC)
    canvas.alpha_composite(layer)

def dot(canvas, cx, cy, r, color):
    ImageDraw.Draw(canvas).ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)

def base_canvas():
    canvas = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(canvas)
    # flat depth planes: large solid discs in slightly lighter navy (no gradient)
    d.ellipse([-260, 1180, 820, 2260], fill=(14, 22, 38, 255))
    d.ellipse([620, -180, 1300, 500], fill=(13, 20, 35, 255))
    orbit(canvas, 780, 1120, 520, 210, rot_deg=-22)
    orbit(canvas, 300, 900, 360, 130, rot_deg=14, width=2)
    for cx, cy, r in [(930, 760, 9), (150, 1500, 7), (860, 1600, 6)]:
        dot(canvas, cx, cy, r, BLUE)
    return canvas

def header(canvas, title, sub):
    canvas.alpha_composite(Image.open("Resources/Otter/otter-app-1024.png").convert("RGBA").resize((88, 88), Image.LANCZOS), (80, 60))
    d = ImageDraw.Draw(canvas)
    d.text((190, 88), "Otter", font=font(46, True), fill=WHITE)
    d.text((80, 196), title, font=fit(title, 84, True, 920), fill=WHITE)
    d.text((80, 302), sub, font=fit(sub, 38, False, 920), fill=MUTED)
    d.text((80, H - 84), "otterr.web.app", font=font(32), fill=MUTED)

def phone_scene(key, title, sub, quad, cards, sw=640):
    canvas = base_canvas()
    header(canvas, title, sub)
    shot = Image.open(f"play/render/{key}.png").convert("RGBA")
    layer = phone_layer(shot, sw, quad)
    canvas.alpha_composite(shadow_of(layer))
    canvas.alpha_composite(layer)
    for img, xy, angle in cards:
        paste_card(canvas, img, xy, angle)
    return canvas.convert("RGB")

# Phone quad (top-left, top-right, bottom-right, bottom-left) on the 1080x2160 canvas.
# Left edge is nearer to the viewer (taller), so the phone turns in 3D.
QUAD_TILT_LEFT = [(190, 420), (880, 500), (880, 1840), (190, 1950)]
QUAD_TILT_RIGHT = [(200, 500), (890, 410), (890, 1950), (200, 1840)]

SLIDES = [
  ("hero", "Your devices, one tap away", "Nearby devices show up on your Wi-Fi automatically", QUAD_TILT_LEFT,
     [(card([("Pixel 8", True, WHITE, 40), ("Nearby · Android", False, MUTED, 30)], 430, GREEN), (40, 1180), -4),
      (card([("Saldoo MacBook", True, WHITE, 40), ("Nearby · Mac", False, MUTED, 30)], 470, BLUE), (560, 1330), 3)]),
  ("live", "Watch every transfer live", "Progress, speed, and a notification while files move", QUAD_TILT_RIGHT,
     [(card([("holiday_beach.mp4", True, WHITE, 40), ("From Saldoo MacBook · 64%", False, MUTED, 30)], 520, GREEN, bar=0.64), (30, 1240), -5),
      (card([("vacation_photos.zip", True, WHITE, 36), ("To Pixel 8 · 40%", False, MUTED, 30)], 470, BLUE, bar=0.40), (590, 1430), 4)]),
  ("send", "Send several files at once", "Pick a device, choose everything you need, send", QUAD_TILT_LEFT,
     [(card([("3 devices nearby", True, WHITE, 40), ("Choose one to send to", False, MUTED, 30)], 470, BLUE), (580, 1260), 4)]),
  ("inbox", "Save photos to Gallery", "Received files wait in your Inbox until you decide", QUAD_TILT_RIGHT,
     [(card([("Saved to Gallery", True, WHITE, 40), ("Pictures/Otter/IMG_2044.jpg", False, MUTED, 30)], 500, GREEN), (30, 1300), -4)]),
  ("toast", "Know when files land", "Save to Gallery straight from the confirmation", QUAD_TILT_LEFT,
     [(card([("Batch received", True, WHITE, 40), ("3 of 3 files · 118 MB", False, MUTED, 30)], 470, GREEN), (580, 1300), 3)]),
  ("browser", "No app needed on the other side", "Open the address Otter shows in any browser", QUAD_TILT_RIGHT,
     [(card([("Open in any browser", True, WHITE, 40), ("http://192.168.1.50:7456", False, BLUE, 30)], 540, BLUE), (30, 1260), -4)]),
]

if __name__ == "__main__":
    os.makedirs("play/screenshots/store", exist_ok=True)
    for old in glob.glob("play/screenshots/store/*.png"):
        os.remove(old)
    for i, (key, title, sub, quad, cards) in enumerate(SLIDES, 1):
        img = phone_scene(key, title, sub, quad, cards)
        img.save(f"play/screenshots/store/0{i}-{key}.png", optimize=True)
        print("saved", i, key, img.size)
