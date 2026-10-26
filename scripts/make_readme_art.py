"""生成 README 用的 banner 与场景拼图（像素风，和 App 同一画风）。

输入：App 的实拍截图（scripts 外部用 catland-debug 拍好，放在 --shots 目录：s1.png … s9.png）
输出：assets/brand/banner.png、assets/brand/scenes.png

用法：~/miniconda3/envs/catlands/bin/python scripts/make_readme_art.py --shots /tmp
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets/brand"
CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"
ROUNDED = "/System/Library/Fonts/SFCompactRounded.ttf"


def island(path: Path, notch_w: int = 370, notch_h: int = 64) -> Image.Image:
    """从 App 窗口截图里裁出刘海区域，并把物理刘海涂黑（和真机看到的一样）。"""
    im = Image.open(path).convert("RGBA")
    a = im.getchannel("A")
    xs = [x for x in range(im.width) if a.getpixel((x, 2)) > 0]
    left, right = xs[0], xs[-1]
    col = [y for y in range(im.height) if a.getpixel((im.width // 2, y)) > 0]
    bottom = col[-1] + 1
    nl = (im.width - notch_w) // 2
    ImageDraw.Draw(im).rounded_rectangle((nl, -20, nl + notch_w, notch_h), radius=16, fill=(0, 0, 0, 255))
    return im.crop((left, 0, right + 1, bottom))


def night_sky(w: int, h: int, px: int = 8) -> Image.Image:
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    top, bottom = (16, 18, 42), (58, 40, 92)
    for y in range(0, h, px):
        k = y / h
        d.rectangle([0, y, w, y + px], fill=tuple(int(top[i] + (bottom[i] - top[i]) * k) for i in range(3)) + (255,))
    import random
    rnd = random.Random(7)
    for _ in range(38):
        x, y = rnd.randrange(0, w, px), rnd.randrange(0, int(h * 0.7), px)
        s = px // 2 if rnd.random() < 0.7 else px
        d.rectangle([x, y, x + s - 1, y + s - 1], fill=(255, 241, 200, rnd.choice([90, 150, 220])))
    # 城市剪影
    x, i = 0, 0
    heights, widths = [6, 10, 7, 13, 8, 11, 6, 12, 7, 9, 5, 14], [6, 5, 7, 4, 6, 5, 7, 4, 6, 5, 7, 4]
    while x < w:
        bw, bh = widths[i % len(widths)] * px, heights[i % len(heights)] * px
        d.rectangle([x, h - bh, x + bw - 1, h], fill=(14, 15, 36, 255))
        for wy in range(h - bh + px, h - px, px * 2):
            for wx in range(x + px // 2, x + bw - px, px * 2):
                if (wx // px * 7 + wy // px * 3 + i) % 4 == 0:
                    d.rectangle([wx, wy, wx + px // 2, wy + px // 2], fill=(255, 205, 120, 255))
        x += bw + px
        i += 1
    return img


def pixel_text(text: str, font_path: str, size: int, scale: int, color) -> Image.Image:
    """小字号渲染后按整数倍最近邻放大：得到和 App 一致的像素字。"""
    f = ImageFont.truetype(font_path, size)
    l, t, r, b = f.getbbox(text)
    img = Image.new("RGBA", (r - l + 2, b - t + 2), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((1 - l, 1 - t), text, font=f, fill=color)
    # 二值化 alpha，去掉抗锯齿，像素边缘更利落
    alpha = img.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    img.putalpha(alpha)
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def banner(shots: Path) -> None:
    W, H = 1600, 700
    img = night_sky(W, H)
    d = ImageDraw.Draw(img)
    # 屏幕顶边 + 刘海里的落地窗（实拍，放大 1.25 倍）
    d.rectangle([0, 0, W, 10], fill=(0, 0, 0, 255))
    isl = island(shots / "s9.png")
    isl = isl.resize((int(isl.width * 1.7), int(isl.height * 1.7)), Image.NEAREST)
    img.alpha_composite(isl, ((W - isl.width) // 2, 0))
    # 图标 + 像素标题 + 标语
    icon = Image.open(BRAND / "icon-1024.png").resize((168, 168), Image.LANCZOS)
    title = pixel_text("catland", ROUNDED, 20, 6, (255, 244, 230, 255))
    f_tag = ImageFont.truetype(CJK, 32)
    tag = "把小猫们装进你的刘海里 · 点一下就开刷"
    tag_w = int(d.textlength(tag, font=f_tag))
    text_w = max(title.width, tag_w)
    block_w = icon.width + 32 + text_w
    x0 = (W - block_w) // 2
    y0 = isl.height + 50
    img.alpha_composite(icon, (x0, y0))
    tx = x0 + icon.width + 32
    img.alpha_composite(title, (tx, y0 + 4))
    d.text((tx + 4, y0 + 4 + title.height + 14), tag, font=f_tag, fill=(255, 196, 214, 255))
    f_sub = ImageFont.truetype(CJK, 22)
    sub = "小红书 · B 站 · X · 抖音 · 快手 · 微博 · TikTok   一个刘海全装下"
    sw = d.textlength(sub, font=f_sub)
    d.text(((W - sw) // 2, y0 + icon.height + 40), sub, font=f_sub, fill=(200, 196, 230, 255))
    img.convert("RGB").save(BRAND / "banner.png", optimize=True)


def scenes(shots: Path) -> None:
    labels = ["上海 · 秋日午后", "傍晚 · 晚霞", "夜晚 · 城市灯火", "雨夜", "冬天 · 下雪", "春天 · 樱花雨", "流星雨（事件）", "新加坡 · 滨海湾灯光秀"]
    tiles = [island(shots / f"s{i}.png") for i in range(1, 9)]
    w = max(t.width for t in tiles)
    h = max(t.height for t in tiles)
    pad, label_h = 24, 40
    cols = 2
    rows = (len(tiles) + cols - 1) // cols
    W = cols * w + (cols + 1) * pad
    H = rows * (h + label_h) + (rows + 1) * pad
    img = Image.new("RGBA", (W, H), (18, 18, 28, 255))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(CJK, 24)
    for k, (t, lab) in enumerate(zip(tiles, labels)):
        x = pad + (k % cols) * (w + pad)
        y = pad + (k // cols) * (h + label_h + pad)
        img.alpha_composite(t, (x + (w - t.width) // 2, y))
        d.text((x + 6, y + h + 6), lab, font=f, fill=(220, 214, 240, 255))
    img = img.resize((W * 3 // 4, H * 3 // 4), Image.LANCZOS)
    img.convert("RGB").save(BRAND / "scenes.png", optimize=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", type=Path, default=Path("/tmp"))
    a = ap.parse_args()
    BRAND.mkdir(parents=True, exist_ok=True)
    banner(a.shots)
    scenes(a.shots)
    print("ok:", BRAND / "banner.png", BRAND / "scenes.png")
