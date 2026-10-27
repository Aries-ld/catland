"""生成 README 用的 banner 与场景拼图。

素材来自 App 的离屏渲染（和刘海里同一套表现层代码，但不截屏：没有物理刘海的黑块，画面干净）：
  1. 运行 App 后执行：apps/macos/build/catland-debug snapshots:/tmp/catland-snaps
  2. ~/miniconda3/envs/catlands/bin/python scripts/make_readme_art.py --snaps /tmp/catland-snaps
输出：assets/brand/banner.png、assets/brand/scenes.png
"""
from __future__ import annotations

import argparse
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets/brand"
CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"
ROUNDED = "/System/Library/Fonts/SFCompactRounded.ttf"

BG_TOP, BG_BOTTOM = (18, 20, 46), (52, 38, 86)
FRAME = (34, 28, 48)
CREAM = (255, 244, 230)
PINK = (255, 178, 204)
LAVENDER = (200, 194, 232)


def backdrop(w: int, h: int, px: int = 8, stars: int = 34, avoid: list[tuple[int, int, int, int]] | None = None) -> Image.Image:
    """像素色带的夜空 + 稀疏星星（每颗都是整像素块）；avoid 里的矩形区域（文字处）不放星星。"""
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(0, h, px):
        k = y / h
        d.rectangle([0, y, w, y + px], fill=tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * k) for i in range(3)) + (255,))
    rnd = random.Random(11)
    for _ in range(stars):
        x, y = rnd.randrange(0, w, px), rnd.randrange(0, h, px)
        if any(ax0 <= x <= ax1 and ay0 <= y <= ay1 for ax0, ay0, ax1, ay1 in (avoid or [])):
            continue
        s = px // 2 if rnd.random() < 0.75 else px
        d.rectangle([x, y, x + s - 1, y + s - 1], fill=(255, 241, 200, rnd.choice([70, 120, 190])))
    return img


def framed(scene: Image.Image, radius: int = 18, border: int = 6) -> Image.Image:
    """把场景装进圆角窗框，带一圈柔和投影。"""
    w, h = scene.width + border * 2, scene.height + border * 2
    pad = 24
    out = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", out.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([pad, pad + 8, pad + w, pad + h + 8], radius=radius, fill=(0, 0, 0, 120))
    out = Image.alpha_composite(out, shadow.filter(ImageFilter.GaussianBlur(10)))
    ImageDraw.Draw(out).rounded_rectangle([pad, pad, pad + w - 1, pad + h - 1], radius=radius, fill=FRAME + (255,))
    mask = Image.new("L", scene.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, scene.width - 1, scene.height - 1], radius=radius - border, fill=255)
    out.paste(scene, (pad + border, pad + border), mask)
    return out


def pixel_text(text: str, size: int, scale: int, color) -> Image.Image:
    """小字号渲染、二值化后按整数倍最近邻放大：和 App 一致的像素字。"""
    f = ImageFont.truetype(ROUNDED, size)
    l, t, r, b = f.getbbox(text)
    img = Image.new("RGBA", (r - l + 2, b - t + 2), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((1 - l, 1 - t), text, font=f, fill=color)
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v > 110 else 0))
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def banner(snaps: Path) -> None:
    W, H = 1600, 660
    hero = framed(Image.open(snaps / "hero.png").convert("RGBA"))
    text_top = 18 + hero.height
    img = backdrop(W, H, stars=40, avoid=[(260, text_top - 10, W - 260, H - 30)])
    d = ImageDraw.Draw(img)
    img.alpha_composite(hero, ((W - hero.width) // 2, 18))

    icon = Image.open(BRAND / "icon-1024.png").resize((150, 150), Image.LANCZOS)
    title = pixel_text("catland", 18, 6, CREAM + (255,))
    f_tag = ImageFont.truetype(CJK, 30)
    tag = "把小猫们装进你的刘海里 · 点一下就开刷"
    text_w = max(title.width, int(d.textlength(tag, font=f_tag)))
    x0 = (W - (icon.width + 30 + text_w)) // 2
    y0 = 18 + hero.height + 6
    img.alpha_composite(icon, (x0, y0))
    tx = x0 + icon.width + 30
    img.alpha_composite(title, (tx, y0 + 6))
    d.text((tx + 4, y0 + 6 + title.height + 12), tag, font=f_tag, fill=PINK)
    f_sub = ImageFont.truetype(CJK, 21)
    sub = "小红书 · 抖音 · Bilibili · 快手      纯本地 · 开源 · 不商用"
    d.text(((W - d.textlength(sub, font=f_sub)) // 2, y0 + icon.height + 24), sub, font=f_sub, fill=LAVENDER)
    img.convert("RGB").save(BRAND / "banner.png", optimize=True)


SCENES = [
    ("autumn-afternoon", "秋日午后 · 上海"), ("dusk", "傍晚 · 天色渐暗"),
    ("rain-night", "雨夜"), ("winter-snow", "冬天 · 下雪"),
    ("event-sakura", "事件 · 樱花雨"), ("event-meteor", "事件 · 流星雨"),
    ("event-fireworks", "事件 · 花火大会"), ("event-lightshow", "事件 · 滨海湾灯光秀"),
]


def scenes(snaps: Path) -> None:
    tiles = [(framed(Image.open(snaps / f"{name}.png").convert("RGBA"), radius=16, border=5), label) for name, label in SCENES]
    tw, th = tiles[0][0].width, tiles[0][0].height
    label_h, gap, margin = 50, 12, 28
    cols, rows = 2, (len(tiles) + 1) // 2
    W = margin * 2 + cols * tw + (cols - 1) * gap
    H = margin * 2 + rows * (th + label_h) + (rows - 1) * gap
    img = backdrop(W, H, stars=60)
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(CJK, 26)
    for k, (tile, label) in enumerate(tiles):
        x = margin + (k % cols) * (tw + gap)
        y = margin + (k // cols) * (th + label_h + gap)
        img.alpha_composite(tile, (x, y))
        lw = d.textlength(label, font=f)
        lx, ly = x + (tw - lw) // 2, y + th - 14
        pill = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(pill).rounded_rectangle([lx - 16, ly - 5, lx + lw + 16, ly + 36], radius=20, fill=(255, 255, 255, 34))
        img.alpha_composite(pill)
        d.text((lx, ly), label, font=f, fill=(240, 234, 252))
    img = img.resize((W // 2, H // 2), Image.LANCZOS)
    img.convert("RGB").save(BRAND / "scenes.png", optimize=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--snaps", type=Path, default=Path("/tmp/catland-snaps"))
    a = ap.parse_args()
    BRAND.mkdir(parents=True, exist_ok=True)
    banner(a.snaps)
    scenes(a.snaps)
    print("ok:", BRAND / "banner.png", BRAND / "scenes.png")
