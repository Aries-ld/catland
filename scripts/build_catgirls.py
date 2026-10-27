"""把 Meowa 生成的猫娘动画（spritesheet）整理成 App 用的图集。

输入：assets/art/catgirls/anim/<角色>-<动作>/run1/
        result_output_transparent_output_urls_png.png（透明底 spritesheet）
        result_output_url.webp（用来读单帧尺寸和帧数）
输出：apps/macos/Resources/Catgirls/<角色>.png  每行一个动作、每列一帧，格子统一为 CELL×CELL
      apps/macos/Resources/Catgirls/catgirls.json  {"cell": 64, "characters": {"shushu": {"idle": {"row": 0, "frames": 8}, ...}}}

对齐：同一角色的所有动作按「脚底中点」对齐到格子底边中点，切换动作时人物不会跳动。
用法：~/miniconda3/envs/catlands/bin/python scripts/build_catgirls.py
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ANIM = ROOT / "assets/art/catgirls/anim"
OUT = ROOT / "apps/macos/Resources/Catgirls"
CELL = 64
CHARACTERS = {
    "shushu": ["idle", "walk", "sign"],
    "doudou": ["idle", "walk", "sign"],
    "bibi": ["idle", "walk", "sign"],
    "tietie": ["idle", "walk", "sign"],
    "box": ["idle", "pop"],
}


def frames_of(run: Path) -> list[Image.Image]:
    sheet = Image.open(run / "result_output_transparent_output_urls_png.png").convert("RGBA")
    meta = Image.open(run / "result_output_url.webp")
    fw, fh, n = meta.width, meta.height, getattr(meta, "n_frames", 1)
    cols = max(1, round(sheet.width / fw))
    return [sheet.crop(((i % cols) * fw, (i // cols) * fh, (i % cols + 1) * fw, (i // cols + 1) * fh)) for i in range(n)]


def foot_anchor(frames: list[Image.Image]) -> tuple[float, int]:
    """动作的锚点：首帧不透明区域的水平中心 + 所有帧里最低的不透明行（脚底）。"""
    box = frames[0].getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
    cx = (box[0] + box[2]) / 2 if box else frames[0].width / 2
    bottom = max((f.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox() or (0, 0, 0, f.height))[3] for f in frames)
    return cx, bottom


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    meta: dict = {"cell": CELL, "characters": {}}
    for name, anims in CHARACTERS.items():
        rows = []
        for anim in anims:
            run = ANIM / f"{name}-{anim}" / "run1"
            if not run.exists():
                print(f"skip {name}-{anim}: not generated yet")
                continue
            rows.append((anim, frames_of(run)))
        if not rows:
            continue
        cols = max(len(f) for _, f in rows)
        atlas = Image.new("RGBA", (cols * CELL, len(rows) * CELL), (0, 0, 0, 0))
        info = {}
        for r, (anim, frames) in enumerate(rows):
            cx, bottom = foot_anchor(frames)
            ox, oy = round(CELL / 2 - cx), CELL - 1 - bottom
            for c, f in enumerate(frames):
                cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
                cell.paste(f, (ox, oy), f)
                atlas.alpha_composite(cell, (c * CELL, r * CELL))
            info[anim] = {"row": r, "frames": len(frames)}
        atlas.save(OUT / f"{name}.png")
        meta["characters"][name] = info
        print(f"{name}: {', '.join(f'{a}×{v['frames']}' for a, v in info.items())}")
    (OUT / "catgirls.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    print("ok:", OUT)


if __name__ == "__main__":
    main()
