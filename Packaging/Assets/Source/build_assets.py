"""Build app icon, volume icon, DMG background and docs icon from the generated sources."""
import shutil, subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageChops

root = Path(__file__).resolve().parents[3]
src = root / "Packaging/Assets/Source"

# ── App icon: macOS template, 824px squircle tile inside a 1024 canvas, soft drop shadow ──
def squircle_mask(size, n=5.0, ss=4):
    big = size * ss
    m = Image.new("L", (big, big), 0)
    px = m.load()
    r = big / 2
    for y in range(big):
        dy = abs((y + .5 - r) / r) ** n
        if dy >= 1: continue
        dx = (1 - dy) ** (1 / n) * r
        for x in range(int(r - dx), int(r + dx)):
            px[x, y] = 255
    return m.resize((size, size), Image.LANCZOS)

art = Image.open(src / "icon.png").convert("RGB")
tile_size, canvas = 824, 1024
off = (canvas - tile_size) // 2
z = 1.0  # the artwork is composed edge to edge
c = round(1024 / z); o = (1024 - c) // 2
tile = art.crop((o, o, o + c, o + c)).resize((tile_size, tile_size), Image.LANCZOS)
mask = squircle_mask(tile_size)
icon = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
sh = Image.new("L", (canvas, canvas), 0); sh.paste(mask, (off, off + 12))
sh = sh.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * .45))
shadow.putalpha(sh)
icon = Image.alpha_composite(icon, shadow)
t = tile.convert("RGBA"); t.putalpha(mask)
# faint top-edge highlight, as on system icons
inner = mask.filter(ImageFilter.GaussianBlur(1.5))
ring = ImageChops.subtract(mask, ImageChops.offset(inner, 0, 3))
hl = Image.new("RGBA", (tile_size, tile_size), (255, 255, 255, 0)); hl.putalpha(ring.point(lambda v: int(v * .22)))
t = Image.alpha_composite(t, hl)
icon.alpha_composite(t, (off, off))

assets = root / "Packaging/Assets"
icon.save(assets / "AppIcon.png")
for s in (16, 32, 64, 128, 256, 512):
    icon.resize((s, s), Image.LANCZOS).save(assets / f"AppIcon-{s}.png")
iconset = assets / "AppIcon.iconset"
for s in (16, 32, 128, 256, 512):
    icon.resize((s, s), Image.LANCZOS).save(iconset / f"icon_{s}x{s}.png")
    icon.resize((s * 2, s * 2), Image.LANCZOS).save(iconset / f"icon_{s}x{s}@2x.png")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", root / "Packaging/AppIcon.icns"], check=True)
shutil.copy(root / "Packaging/AppIcon.icns", root / "Packaging/dmg/VolumeIcon.icns")
icon.resize((512, 512), Image.LANCZOS).save(root / "docs/assets/tapthatmac-app-icon.png")

# ── DMG background: 660x400 window, app icon at (180,190), Applications at (480,190) ──
bg = Image.open(src / "dmg.png").convert("RGB")
origin = (450, 345)                      # calm centre of the spiral in the source
for scale_mult in (1, 2):
    W, H = 660 * scale_mult, 400 * scale_mult
    s = 1.8                              # source px per window pt
    left, top = origin[0] - 180 * s, origin[1] - 190 * s
    crop = bg.crop((round(left), round(top), round(left + 660 * s), round(top + 400 * s))).resize((W, H), Image.LANCZOS)
    crop = ImageEnhance.Brightness(crop).enhance(.9)
    # quiet the area under the Finder labels and Start Here
    veil = Image.new("L", (W, H), 0); d = ImageDraw.Draw(veil)
    k = scale_mult
    for cx, cy, w, h in ((180, 268, 150, 26), (480, 268, 150, 26), (330, 356, 160, 26)):
        d.rounded_rectangle(((cx - w / 2) * k, (cy - h / 2) * k, (cx + w / 2) * k, (cy + h / 2) * k), 13 * k, fill=150)
    veil = veil.filter(ImageFilter.GaussianBlur(12 * k))
    crop = Image.composite(Image.new("RGB", (W, H), (7, 9, 15)), crop, veil)
    # arrow between the two icons, drawn as one shape so nothing overlaps
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    y, x0, x1 = 190 * k, 302 * k, 358 * k
    t, hw, hl = 1.5 * k, 8 * k, 13 * k
    d.polygon(((x0, y - t), (x1 - hl, y - t), (x1 - hl, y - hw), (x1, y), (x1 - hl, y + hw), (x1 - hl, y + t), (x0, y + t)),
              fill=(238, 242, 246, 190))
    crop = Image.alpha_composite(crop.convert("RGBA"), layer).convert("RGB")
    name = "dmg_background.png" if k == 1 else "dmg_background@2x.png"
    crop.save(root / "Packaging/dmg" / name)
print("ok")
