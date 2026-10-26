"""生成 catland 的品牌图标：白色圆角方块上的一只黑色线条猫爪。
猫爪图形来自 assets/brand/paw-source.png（透明底单色线稿），这里只负责改成黑色、平滑放大和排版：
  - App 图标 → apps/macos/Resources/AppIcon.icns、assets/brand/icon-1024.png
  - 菜单栏模板图（黑 + 透明，系统自动适配深浅色）→ apps/macos/Resources/MenuBarIcon.png / @2x

用法：~/miniconda3/envs/catlands/bin/python scripts/make_icons.py
"""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "apps/macos/Resources"
BRAND = ROOT / "assets/brand"
SOURCE = BRAND / "paw-source.png"

INK = (17, 17, 17)
PAPER = (255, 255, 255)


def paw_mask(size: int) -> Image.Image:
    """把线稿的形状提取成 size×size 的抗锯齿遮罩：先 8 倍放大并重新二值化（边缘更利落），再缩到目标尺寸。"""
    src = Image.open(SOURCE).convert("RGBA").getchannel("A")
    bbox = src.getbbox()
    src = src.crop(bbox)
    side = max(src.width, src.height)
    square = Image.new("L", (side, side), 0)
    square.paste(src, ((side - src.width) // 2, (side - src.height) // 2))
    big = square.resize((side * 8, side * 8), Image.BICUBIC).filter(ImageFilter.GaussianBlur(3))
    big = big.point(lambda v: 255 if v > 128 else 0)
    return big.resize((size, size), Image.LANCZOS)


def app_icon(size: int = 1024) -> Image.Image:
    # macOS 图标网格：主体 824×824 居中，圆角约 185，带轻微投影
    inset, body, radius = 100, 824, 185
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([inset, inset + 14, inset + body - 1, inset + body + 13], radius=radius, fill=(0, 0, 0, 90))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(14)))
    plate = Image.new("RGBA", (body, body), PAPER + (255,))
    paw = 560
    ink = Image.new("RGBA", (paw, paw), INK + (255,))
    off = (body - paw) // 2
    plate.paste(ink, (off, off + 8), paw_mask(paw))
    mask = Image.new("L", (body, body), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, body - 1, body - 1], radius=radius, fill=255)
    img.paste(plate, (inset, inset), mask)
    return img


def menubar_icon(pt: int, scale: int) -> Image.Image:
    size = pt * scale
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    img.paste(Image.new("RGBA", (size, size), (0, 0, 0, 255)), (0, 0), paw_mask(size))
    return img


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
                icon.resize((px, px), Image.LANCZOS).save(iconset / f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(RES / "AppIcon.icns")], check=True)
    menubar_icon(18, 1).save(RES / "MenuBarIcon.png")
    menubar_icon(18, 2).save(RES / "MenuBarIcon@2x.png")
    print("ok:", RES / "AppIcon.icns", BRAND / "icon-1024.png")


if __name__ == "__main__":
    main()
