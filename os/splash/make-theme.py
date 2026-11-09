#!/usr/bin/env python3
"""Genere le theme Plymouth ThibsDarts a partir de boot.gif et quotes.txt.

Usage : python3 os/splash/make-theme.py
Sortie : os/image/common/usr/share/plymouth/themes/thibsdarts/
Il faut Pillow. Les images sont dessinees pour l'ecran 1024x600 du Pi 4,
le script Plymouth les remet a l'echelle sur un autre ecran.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OUT = ROOT / "os/image/common/usr/share/plymouth/themes/thibsdarts"
FONT = ROOT / "hub/assets/fonts/Inter.ttf"

HEAD_H = 330  # hauteur de la tete sur un ecran de 600 px
BAR_W, BAR_H = 320, 8
ASPHALTE = (0x1E, 0x1F, 0x24)
SUNSET = (0xFF, 0x7A, 0x2F)
CREPUSCULE = (0xFF, 0x4D, 0x8D)
TEXTE = (0xF4, 0xF1, 0xEA)


def frames():
    gif = Image.open(HERE / "boot.gif")
    # Le GIF a un fond noir opaque : on garde la zone ou bouge la tete.
    box = None
    for i in range(gif.n_frames):
        gif.seek(i)
        mask = gif.convert("L").point(lambda v: 255 if v > 10 else 0)
        b = mask.getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    pad = 12
    box = (max(box[0] - pad, 0), max(box[1] - pad, 0), min(box[2] + pad, gif.width), min(box[3] + pad, gif.height))
    for i in range(gif.n_frames):
        gif.seek(i)
        img = gif.convert("RGB").crop(box)
        w = round(img.width * HEAD_H / img.height)
        img = img.resize((w, HEAD_H), Image.LANCZOS).quantize(256, dither=Image.Dither.NONE)
        img.info.pop("transparency", None)
        img.save(OUT / f"frame-{i:02d}.png", optimize=True)
    return gif.n_frames, gif.info.get("duration", 70)


def bar():
    track = Image.new("RGBA", (BAR_W, BAR_H))
    ImageDraw.Draw(track).rounded_rectangle((0, 0, BAR_W - 1, BAR_H - 1), BAR_H // 2, fill=ASPHALTE)
    track.save(OUT / "bar-track.png")
    # Le remplissage est etire en largeur par Plymouth : un degrade vertical reste propre.
    fill = Image.new("RGBA", (64, BAR_H))
    for x in range(64):
        t = x / 63
        c = tuple(round(SUNSET[k] + (CREPUSCULE[k] - SUNSET[k]) * t) for k in range(3))
        ImageDraw.Draw(fill).line((x, 0, x, BAR_H - 1), fill=c + (255,))
    fill.save(OUT / "bar-fill.png")


def quotes():
    font = ImageFont.truetype(str(FONT), 22)
    font.set_variation_by_axes([14, 500])  # Inter : taille optique 14, graisse 500
    lines = [l.strip() for l in (HERE / "quotes.txt").read_text(encoding="utf-8").splitlines() if l.strip()]
    for old in OUT.glob("quote-*.png"):
        old.unlink()
    for i, line in enumerate(lines):
        text = f"« {line} »"
        x0, y0, x1, y1 = font.getbbox(text)
        img = Image.new("RGBA", (x1 - x0 + 8, 34))
        ImageDraw.Draw(img).text((4 - x0, 4), text, font=font, fill=TEXTE + (255,))
        img.save(OUT / f"quote-{i:02d}.png", optimize=True)
    return len(lines)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("frame-*.png"):
        old.unlink()
    n, ms = frames()
    bar()
    q = quotes()
    script = (HERE / "thibsdarts.script.in").read_text(encoding="utf-8")
    script = script.replace("@FRAMES@", str(n)).replace("@FRAME_MS@", str(ms)).replace("@QUOTES@", str(q))
    (OUT / "thibsdarts.script").write_text(script, encoding="utf-8")
    (OUT / "thibsdarts.plymouth").write_text(
        "[Plymouth Theme]\n"
        "Name=ThibsDarts\n"
        "Description=Demarrage ThibsDarts : la tete de Thibs, une barre et ses phrases\n"
        "ModuleName=script\n\n"
        "[script]\n"
        "ImageDir=/usr/share/plymouth/themes/thibsdarts\n"
        "ScriptFile=/usr/share/plymouth/themes/thibsdarts/thibsdarts.script\n",
        encoding="utf-8",
    )
    print(f"{n} images, {q} phrases -> {OUT}")


if __name__ == "__main__":
    main()
