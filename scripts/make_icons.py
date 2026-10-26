"""生成 catland 的品牌图标（手绘像素风，与 App 内小猫 / 场景同一风格）：
  - App 图标：夜色圆角方块 + 星星 + 底部城市剪影 + 一只奶白色猫爪（粉色肉垫）
    → apps/macos/Resources/AppIcon.icns、assets/brand/icon-1024.png
  - 菜单栏图标：单只猫爪的模板图（黑 + 透明，系统自动适配深浅色）
    → apps/macos/Resources/MenuBarIcon.png / MenuBarIcon@2x.png

用法：~/miniconda3/envs/catlands/bin/python scripts/make_icons.py
"""
from __future__ import annotations

import math
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "apps/macos/Resources"
BRAND = ROOT / "assets/brand"

CREAM = (255, 244, 230, 255)
PINK = (255, 143, 177, 255)
OUTLINE = (42, 30, 46, 255)


def paw_grid(n: int = 20) -> list[list[str]]:
    """在 n×n 网格上画猫爪：' ' 空、'C' 奶白、'P' 粉色肉垫、'O' 描边。"""
    g = [[" "] * n for _ in range(n)]
    s = n / 20

    def ellipse(cx, cy, rx, ry, ch):
        for y in range(n):
            for x in range(n):
                if ((x + 0.5 - cx * s) / (rx * s)) ** 2 + ((y + 0.5 - cy * s) / (ry * s)) ** 2 <= 1:
                    g[y][x] = ch

    # 四个趾头与掌垫之间留出空隙，轮廓才像猫爪
    toes = [(3.1, 8.7, 2.0, 2.1), (7.4, 5.2, 2.1, 2.2), (12.6, 5.2, 2.1, 2.2), (16.9, 8.7, 2.0, 2.1)]
    ellipse(10, 14.6, 4.9, 3.9, "C")
    ellipse(7.2, 13.4, 2.4, 2.4, "C")
    ellipse(12.8, 13.4, 2.4, 2.4, "C")
    for cx, cy, rx, ry in toes:
        ellipse(cx, cy, rx, ry, "C")
    ellipse(10, 15.0, 2.9, 2.2, "P")
    for cx, cy, rx, ry in toes:
        ellipse(cx, cy + 0.3, rx * 0.55, ry * 0.5, "P")
    # 描边：紧贴实心像素的空格
    out = [row[:] for row in g]
    for y in range(n):
        for x in range(n):
            if g[y][x] != " ":
                continue
            if any(0 <= y + dy < n and 0 <= x + dx < n and g[y + dy][x + dx] != " " for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = "O"
    return out


def app_icon(size: int = 1024) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # macOS 图标网格：主体 824×824 居中，圆角约 185
    inset, body = 100, 824
    radius = 185
    bg = Image.new("RGBA", (body, body))
    d = ImageDraw.Draw(bg)
    top, bottom = (27, 31, 66), (74, 50, 108)
    px = 16  # 背景也走像素块：每 16px 一行色带
    for y in range(0, body, px):
        k = y / body
        col = tuple(int(top[i] + (bottom[i] - top[i]) * k) for i in range(3)) + (255,)
        d.rectangle([0, y, body, y + px], fill=col)
    # 星星
    for (sx, sy, big) in [(120, 110, 1), (650, 90, 0), (720, 210, 1), (90, 300, 0), (560, 160, 0), (300, 70, 0), (760, 380, 0)]:
        s = 24 if big else 16
        d.rectangle([sx, sy, sx + s - 1, sy + s - 1], fill=(255, 241, 200, 255))
    # 底部城市剪影 + 亮着的窗
    x = 0
    heights = [5, 8, 6, 11, 7, 9, 5, 10, 6, 8, 5]
    widths = [5, 4, 6, 4, 5, 4, 6, 3, 5, 4, 6]
    i = 0
    while x < body:
        w, h = widths[i % len(widths)] * px, heights[i % len(heights)] * px
        d.rectangle([x, body - h, x + w - 1, body], fill=(20, 22, 48, 255))
        for wy in range(body - h + px, body - px, px * 2):
            for wx in range(x + px // 2, x + w - px, px * 2):
                if (wx // px + wy // px + i) % 3 == 0:
                    d.rectangle([wx, wy, wx + px // 2, wy + px // 2], fill=(255, 210, 120, 255))
        x += w + px
        i += 1
    # 猫爪：20×20 网格，每格 28px
    g = paw_grid(20)
    cell = 28
    ox, oy = (body - 20 * cell) // 2, (body - 20 * cell) // 2 - 40
    colors = {"C": CREAM, "P": PINK, "O": OUTLINE}
    for yy, row in enumerate(g):
        for xx, ch in enumerate(row):
            if ch in colors:
                d.rectangle([ox + xx * cell, oy + yy * cell, ox + (xx + 1) * cell - 1, oy + (yy + 1) * cell - 1], fill=colors[ch])
    # 圆角遮罩
    mask = Image.new("L", (body, body), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, body - 1, body - 1], radius=radius, fill=255)
    img.paste(bg, (inset, inset), mask)
    # 轻微投影
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([inset, inset + 12, inset + body - 1, inset + body + 11], radius=radius, fill=(0, 0, 0, 70))
    return Image.alpha_composite(shadow, img)


def menubar_icon(pt: int, scale: int) -> Image.Image:
    """菜单栏模板图：只用黑色 + 透明，系统按深浅色自动着色。"""
    n = 20
    g = paw_grid(n)
    size = pt * scale
    work = n * 2 * scale  # 先按整数格画大图，再缩到目标尺寸
    img = Image.new("RGBA", (work, work), (0, 0, 0, 0))
    cell = work / n
    d = ImageDraw.Draw(img)
    for y, row in enumerate(g):
        for x, ch in enumerate(row):
            if ch in ("C", "P"):
                # 肉垫挖空一点，模板图里也看得出「肉垫」
                alpha = 255 if ch == "C" else 110
                d.rectangle([math.floor(x * cell), math.floor(y * cell), math.ceil((x + 1) * cell) - 1, math.ceil((y + 1) * cell) - 1], fill=(0, 0, 0, alpha))
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    BRAND.mkdir(parents=True, exist_ok=True)
    icon = app_icon()
    icon.save(BRAND / "icon-1024.png")
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for base in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = base * scale
                name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
                icon.resize((px, px), Image.LANCZOS if px < 512 else Image.NEAREST).save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(RES / "AppIcon.icns")], check=True)
    menubar_icon(18, 1).save(RES / "MenuBarIcon.png")
    menubar_icon(18, 2).save(RES / "MenuBarIcon@2x.png")
    print("ok:", RES / "AppIcon.icns", BRAND / "icon-1024.png")


if __name__ == "__main__":
    main()
