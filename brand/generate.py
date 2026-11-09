"""Génère tous les visuels du logo ThibsDarts à partir de brand/logo-source.jpeg.

Usage (depuis la racine du repo) : python3 brand/generate.py
Dépendances : Pillow, cairosvg.
Pour une meilleure qualité, remplacer logo-source.jpeg par une version plus grande
(même dessin sur fond noir) et relancer.
"""
import io, json, os, re
from PIL import Image, ImageDraw, ImageFilter
import cairosvg

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'brand', 'logo-source.jpeg')
BETON = (0x12, 0x12, 0x14)
CREPUSCULE = (0xFF, 0x4D, 0x8D)
SUNSET = (0xFF, 0x7A, 0x2F)
WORDMARK_SVG = os.path.join(ROOT, 'brand', 'wordmark.svg')


def p(*parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def face_cutout(scale=3):
    """Tête détourée (fond noir retiré, contour noir gardé), agrandie."""
    im = Image.open(SRC).convert('RGB')
    im = im.resize((im.width * scale, im.height * scale), Image.LANCZOS)
    g = im.convert('L').point(lambda v: 0 if v < 40 else 255)
    ImageDraw.floodfill(g, (0, 0), 128)
    fg = g.point(lambda v: 0 if v == 128 else 255)
    fg = fg.filter(ImageFilter.MaxFilter(6 * scale + 1)).filter(ImageFilter.GaussianBlur(scale))
    im.putalpha(fg)
    return im.crop(fg.getbbox())


def fit(img, h):
    return img.resize((max(1, round(img.width * h / img.height)), h), Image.LANCZOS)


def wordmark(h):
    png = cairosvg.svg2png(url=WORDMARK_SVG, output_height=h * 4)
    return fit(Image.open(io.BytesIO(png)).convert('RGBA'), h)


def full_logo(face, h):
    """Tête + mot ThibsDarts, fond transparent."""
    f = fit(face, h)
    w = wordmark(round(h * 0.40))
    gap = round(h * 0.16)
    out = Image.new('RGBA', (f.width + gap + w.width, h), (0, 0, 0, 0))
    out.paste(f, (0, 0), f)
    out.paste(w, (f.width + gap, (h - w.height) // 2), w)
    return out


def glow(size, center, radius, color, alpha):
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    m = Image.new('L', size, 0)
    cx, cy = center
    ImageDraw.Draw(m).ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=alpha)
    m = m.filter(ImageFilter.GaussianBlur(radius * 0.45))
    layer.putalpha(m)
    solid = Image.new('RGBA', size, color + (255,))
    return Image.composite(solid, layer, m)


def background(w, h):
    bg = Image.new('RGBA', (w, h), BETON + (255,))
    bg.alpha_composite(glow((w, h), (w * 0.38, h * 0.62), min(w, h) * 0.42, CREPUSCULE, 70))
    bg.alpha_composite(glow((w, h), (w * 0.62, h * 0.40), min(w, h) * 0.38, SUNSET, 55))
    return bg


def icon(face, size, face_ratio=0.80):
    bg = background(size, size)
    f = fit(face, round(size * face_ratio))
    bg.alpha_composite(f, ((size - f.width) // 2, (size - f.height) // 2))
    return bg.convert('RGB')


def write_json(path, data):
    with open(path, 'w') as fh:
        json.dump(data, fh, indent=2)
        fh.write('\n')


def main():
    face = face_cutout()
    face.save(p('brand', 'logo-face.png'))
    full_logo(face, 512).save(p('brand', 'logo-full.png'))
    icon(face, 1024).save(p('brand', 'icon-1024.png'))

    # Pi hub (Flutter) : tête PNG + mot SVG, assemblés par widgets/logo.dart
    fit(face, 480).save(p('hub', 'assets', 'brand', 'logo-face.png'))
    with open(WORDMARK_SVG) as src, open(p('hub', 'assets', 'brand', 'logo-wordmark.svg'), 'w') as dst:
        dst.write(src.read())

    # Hub macOS (dev) : icônes d'app
    for s in (16, 32, 64, 128, 256, 512, 1024):
        icon(face, s * 2 if s < 64 else s).resize((s, s), Image.LANCZOS).save(
            p('hub', 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', f'app_icon_{s}.png'))

    # iOS + tvOS : logo complet (catalogue partagé)
    cat = p('ios', 'ThibsDarts', 'Resources', 'Assets.xcassets', 'x')[:-2]
    for k in (1, 2, 3):
        full_logo(face, 128 * k).save(os.path.join(cat, 'Logo.imageset', f'logo@{k}x.png'))

    # iOS : icône d'app (1024 unique, sans transparence)
    icon(face, 1024).save(p(cat, 'AppIcon.appiconset', 'icon-1024.png'))
    write_json(os.path.join(cat, 'AppIcon.appiconset', 'Contents.json'), {
        'images': [{'filename': 'icon-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
        'info': {'author': 'xcode', 'version': 1}})

    # tvOS : icône à calques (parallaxe) + Top Shelf
    tv = p('ios', 'TV', 'Assets.xcassets', 'x')[:-2]
    write_json(os.path.join(tv, 'Contents.json'), {'info': {'author': 'xcode', 'version': 1}})
    ba = os.path.join(tv, 'App Icon & Top Shelf Image.brandassets')
    stacks = [('App Icon', 'primary-app-icon', '400x240', (1, 2)),
              ('App Icon - App Store', 'primary-app-icon', '1280x768', (1,))]
    assets = []
    for name, role, size, scales in stacks:
        assets.append({'filename': f'{name}.imagestack', 'idiom': 'tv' if 'Store' not in name else 'tv-marketing',
                       'role': role, 'size': size})
        st = os.path.join(ba, f'{name}.imagestack')
        w, h = map(int, size.split('x'))
        layers = [('Front', 'front'), ('Back', 'back')]
        write_json(p(st, 'Contents.json'), {'layers': [{'filename': f'{n}.imagestacklayer'} for n, _ in layers],
                                            'info': {'author': 'xcode', 'version': 1}})
        for n, kind in layers:
            lay = os.path.join(st, f'{n}.imagestacklayer')
            write_json(p(lay, 'Contents.json'), {'info': {'author': 'xcode', 'version': 1}})
            imgs = []
            for k in scales:
                W, H = w * k, h * k
                if kind == 'back':
                    img = background(W, H).convert('RGB')
                else:
                    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                    f = fit(face, round(H * 0.78))
                    img.alpha_composite(f, ((W - f.width) // 2, (H - f.height) // 2))
                fn = f'{kind}@{k}x.png'
                img.save(p(lay, 'Content.imageset', fn))
                imgs.append({'filename': fn, 'idiom': 'tv', 'scale': f'{k}x'})
            write_json(os.path.join(lay, 'Content.imageset', 'Contents.json'),
                       {'images': imgs, 'info': {'author': 'xcode', 'version': 1}})
    for name, size in (('Top Shelf Image', '1920x720'), ('Top Shelf Image Wide', '2320x720')):
        role = 'top-shelf-image' if 'Wide' not in name else 'top-shelf-image-wide'
        assets.append({'filename': f'{name}.imageset', 'idiom': 'tv', 'role': role, 'size': size})
        w, h = map(int, size.split('x'))
        imgs = []
        for k in (1, 2):
            W, H = w * k, h * k
            img = background(W, H)
            lg = full_logo(face, round(H * 0.5))
            img.alpha_composite(lg, ((W - lg.width) // 2, (H - lg.height) // 2))
            fn = f'top@{k}x.png'
            img.convert('RGB').save(p(ba, f'{name}.imageset', fn))
            imgs.append({'filename': fn, 'idiom': 'tv', 'scale': f'{k}x'})
        write_json(os.path.join(ba, f'{name}.imageset', 'Contents.json'),
                   {'images': imgs, 'info': {'author': 'xcode', 'version': 1}})
    write_json(os.path.join(ba, 'Contents.json'), {'assets': assets, 'info': {'author': 'xcode', 'version': 1}})


if __name__ == '__main__':
    main()
