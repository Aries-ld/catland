"""把 Meowa 生成的小猫动画打包进 App：校验 → 复制透明精灵表 → 写清单 cats.json。

输出：apps/macos/Resources/Cats/<cat>/<action>.png + apps/macos/Resources/Cats/cats.json
校验（不通过的动画不入库）：帧数与尺寸一致、有透明通道、每帧非空、角色没有贴到画布边缘被裁切。
预览：/tmp/cats_contact.png（每只猫一行，8 倍最近邻放大，用于人工审美把关）。

用法：~/miniconda3/envs/catlands/bin/python scripts/pack_cats.py
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/art/cats/anim"
DST = ROOT / "apps/macos/Resources/Cats"

# 与 gen_cats.py 的 ACTIONS 保持一致：帧数、四向留白（上、下、左、右）
ACTIONS = {
    "walk": (8, (2, 0, 4, 4)),
    "idle": (8, (2, 0, 4, 4)),
    "groom": (12, (2, 0, 4, 4)),
    "stretch": (12, (2, 0, 4, 10)),
    "hop": (8, (10, 0, 4, 4)),
    "nap": (16, (2, 0, 6, 8)),
}
SOURCE_SIZE = 32


def frames_of(sheet: Image.Image, fw: int, fh: int, n: int) -> list[Image.Image]:
    cols = sheet.width // fw
    return [sheet.crop(((i % cols) * fw, (i // cols) * fh, (i % cols + 1) * fw, (i // cols + 1) * fh)) for i in range(n)]


def check(frames: list[Image.Image]) -> list[str]:
    problems = []
    for i, f in enumerate(frames):
        bbox = f.getchannel("A").getbbox()
        if not bbox:
            problems.append(f"frame {i} empty")
            continue
        if bbox[0] == 0 or bbox[2] == f.width or bbox[1] == 0:
            problems.append(f"frame {i} touches edge {bbox}")
    return problems


def main() -> None:
    if DST.exists():
        shutil.rmtree(DST)
    DST.mkdir(parents=True)
    manifest: dict = {"sourceSize": SOURCE_SIZE, "cats": {}}
    rows = []
    for cat_dir in sorted(p for p in SRC.iterdir() if p.is_dir()):
        cat = cat_dir.name
        for action, (n, (top, down, left, right)) in ACTIONS.items():
            done = [f for f in (cat_dir / action).glob("*/final_outputs.json") if json.loads(f.read_text()).get("status") == "success"]
            if not done:
                continue
            job = done[0].parent
            sheet = Image.open(next(job.glob("*transparent*png*.png"))).convert("RGBA")
            gif = Image.open(next(job.glob("*.gif")))
            fw, fh = gif.size
            expected = (SOURCE_SIZE + left + right, SOURCE_SIZE + top + down)
            frames = frames_of(sheet, fw, fh, n)
            problems = ([] if (fw, fh) == expected else [f"frame size {fw}x{fh} != {expected}"]) + check(frames)
            # 贴边只警告（伸懒腰、跳跃可能轻微触边），尺寸 / 空帧不符直接拒收。
            fatal = [p for p in problems if "touches" not in p]
            status = "REJECT" if fatal else ("WARN" if problems else "ok")
            print(f"{status:6} {cat:8} {action:8} {fw}x{fh} x{n} {'; '.join(problems)}")
            if fatal:
                continue
            (DST / cat).mkdir(exist_ok=True)
            sheet.save(DST / cat / f"{action}.png", optimize=True)
            manifest["cats"].setdefault(cat, {})[action] = {
                "file": f"{cat}/{action}.png", "frameWidth": fw, "frameHeight": fh, "columns": sheet.width // fw, "frames": n,
                # 源图（32×32 站姿）在帧内的左上角位置：用于对齐脚底锚点。
                "originX": left, "originY": top,
            }
            rows.append((cat, action, frames))
    (DST / "cats.json").write_text(json.dumps(manifest, indent=2))
    preview(rows)
    print(f"packed {sum(len(v) for v in manifest['cats'].values())} animations for {len(manifest['cats'])} cats → {DST.relative_to(ROOT)}")


def preview(rows) -> None:
    if not rows:
        return
    s = 4
    cell = 48 * s
    cats = sorted({r[0] for r in rows})
    actions = list(ACTIONS)
    sheet = Image.new("RGBA", (cell * len(actions), cell * len(cats)), (36, 36, 42, 255))
    for cat, action, frames in rows:
        f = frames[len(frames) // 3]
        big = f.resize((f.width * s, f.height * s), Image.NEAREST)
        sheet.alpha_composite(big, (actions.index(action) * cell, cats.index(cat) * cell))
    sheet.save("/tmp/cats_contact.png")


if __name__ == "__main__":
    main()
