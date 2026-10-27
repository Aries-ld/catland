"""生成 DMG 安装窗口的背景图（像素夜空风格，和 App / README 一致）：左边放 catland，右边放「应用程序」，中间一个箭头。
输出 1x 与 2x 两张，再用 tiffutil 合成多分辨率 TIFF（Retina 屏上清晰）。

用法：~/miniconda3/envs/catlands/bin/python packaging/make_dmg_background.py
"""
from __future__ import annotations

import random
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
W, H = 660, 400  # 与 dmg_settings.py 的窗口尺寸一致
CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def render(scale: int) -> Image.Image:
    w, h, px = W * scale, H * scale, 6 * scale
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    top, bottom = (24, 26, 56), (60, 44, 96)
    for y in range(0, h, px):
        k = y / h
        d.rectangle([0, y, w, y + px], fill=tuple(int(top[i] + (bottom[i] - top[i]) * k) for i in range(3)))
    rnd = random.Random(5)
    for _ in range(40):
        x, y = rnd.randrange(0, w, px), rnd.randrange(0, int(h * 0.42), px)
        if 36 * scale < y < 118 * scale and 110 * scale < x < 550 * scale:
            continue  # 文案区域不放星星
        s = px // 2 if rnd.random() < 0.7 else px
        d.rectangle([x, y, x + s - 1, y + s - 1], fill=(255, 241, 200))
    # 底部城市剪影 + 亮灯的窗
    x, i = 0, 0
    heights, widths = [5, 8, 6, 10, 7, 9, 5, 11, 6], [5, 4, 6, 4, 5, 4, 6, 4, 5]
    while x < w:
        bw, bh = widths[i % 9] * px, heights[i % 9] * px
        d.rectangle([x, h - bh, x + bw - 1, h], fill=(16, 17, 40))
        for wy in range(h - bh + px, h - px, px * 2):
            for wx in range(x + px // 2, x + bw - px, px * 2):
                if (wx // px * 5 + wy // px * 3 + i) % 4 == 0:
                    d.rectangle([wx, wy, wx + px // 2, wy + px // 2], fill=(255, 205, 120))
        x += bw + px
        i += 1
    # 中间的像素箭头（指向「应用程序」）
    cx, cy = w // 2, 190 * scale
    arrow = (255, 196, 214)
    # 箭杆：2 像素高的横条；箭头：逐列收窄的三角
    d.rectangle([cx - 9 * px, cy - px, cx + 3 * px - 1, cy + px - 1], fill=arrow)
    for k in range(5):
        half = 4 - k
        d.rectangle([cx + (3 + k) * px, cy - (half + 1) * px, cx + (4 + k) * px - 1, cy + (half + 1) * px - 1], fill=arrow)
    # 文案
    f = ImageFont.truetype(CJK, 22 * scale)
    tip = "把 catland 拖进「应用程序」就装好啦"
    d.text(((w - d.textlength(tip, font=f)) // 2, 52 * scale), tip, font=f, fill=(255, 244, 230))
    f2 = ImageFont.truetype(CJK, 13 * scale)
    sub = "装好后在「应用程序」里打开，刘海里会出现小猫 🐾"
    sub = sub.replace(" 🐾", "")
    d.text(((w - d.textlength(sub, font=f2)) // 2, 90 * scale), sub, font=f2, fill=(205, 198, 236))
    return img


def main() -> None:
    one, two = HERE / "dmg-background.png", HERE / "dmg-background@2x.png"
    render(1).save(one)
    render(2).save(two)
    subprocess.run(["tiffutil", "-cathidpicheck", str(one), str(two), "-out", str(HERE / "dmg-background.tiff")], check=True, capture_output=True)
    print("ok:", HERE / "dmg-background.tiff")


if __name__ == "__main__":
    main()
