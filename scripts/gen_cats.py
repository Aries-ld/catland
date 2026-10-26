"""批量生成小猫动画（Meowa animate-run）。已有产物的任务自动跳过；结果清单写入 assets/art/cats/jobs.json。

用法：~/miniconda3/envs/catlands/bin/python scripts/gen_cats.py [--dry-run] [--parallel 3]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = Path.home() / ".agents/skills/game-assets/meowart_api.py"
BASE = ROOT / "assets/art/cats/base/v1"
OUT = ROOT / "assets/art/cats/anim"
JOBS_FILE = ROOT / "assets/art/cats/jobs.json"

CATS = ["orange", "white", "black", "calico", "tabby", "siamese", "tuxedo", "blue"]
FULL_SET = {"orange", "white", "black", "calico"}

# 动作：提示词、帧数、类型、四向留白（像素）。所有动作都从站姿开始、回到站姿，便于随机串接。
ACTIONS = {
    "walk": ("The cat walks to the right in place, a smooth looping walk cycle", 8, "walk", (2, 0, 4, 4)),
    "idle": ("The cat stands still, blinks slowly and gently swishes its tail", 8, "idle", (2, 0, 4, 4)),
    "groom": ("The cat sits down, licks its front paw to groom, then stands back up", 12, "other", (2, 0, 4, 4)),
    "stretch": ("The cat does a big stretch with front legs reaching forward and back raised, then returns to standing", 12, "other", (2, 0, 4, 10)),
    "hop": ("The cat makes a small playful hop in place and lands back", 8, "jump", (10, 0, 4, 4)),
    "nap": ("The cat lies down, curls up and naps while breathing gently, then gets back up", 16, "other", (2, 0, 6, 8)),
}


def jobs() -> list[dict]:
    out = []
    for i, cat in enumerate(CATS):
        for action in ACTIONS if cat in FULL_SET else ("walk", "idle"):
            out.append({"cat": cat, "index": i, "action": action})
    return out


def env() -> dict:
    e = dict(os.environ)
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            e[k.strip()] = v.strip().strip('"')
    return e


def done_dir(job: dict) -> Path | None:
    d = OUT / job["cat"] / job["action"]
    for f in d.glob("*/final_outputs.json"):
        if json.loads(f.read_text()).get("status") == "success":
            return f.parent
    return None


def run(job: dict, dry: bool) -> dict:
    existing = done_dir(job)
    if existing:
        return {**job, "status": "skipped", "dir": str(existing.relative_to(ROOT))}
    prompt, frames, kind, (top, down, left, right) = ACTIONS[job["action"]]
    cmd = [sys.executable, str(RUNNER), "animate-run",
           "--image-file", str(BASE / f"sprite_{job['index']:02d}.png"),
           "--prompt", prompt, "--output-frames", str(frames), "--output-format", "spritesheet",
           "--animation-type", kind,
           "--padding-top", str(top), "--padding-down", str(down), "--padding-left", str(left), "--padding-right", str(right),
           "--output-dir", str(OUT / job["cat"] / job["action"])]
    if dry:
        return {**job, "status": "dry-run", "cmd": " ".join(cmd[2:6])}
    t0 = time.time()
    p = subprocess.run(cmd, cwd=ROOT, env=env(), capture_output=True, text=True)
    d = done_dir(job)
    status = "success" if d else "failed"
    log = {**job, "status": status, "seconds": round(time.time() - t0)}
    if d:
        log["dir"] = str(d.relative_to(ROOT))
    else:
        log["error"] = (p.stdout + p.stderr)[-600:]
    print(json.dumps(log, ensure_ascii=False), flush=True)
    return log


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--parallel", type=int, default=3)
    a = ap.parse_args()
    js = jobs()
    print(f"{len(js)} jobs", flush=True)
    with ThreadPoolExecutor(max_workers=a.parallel) as ex:
        results = list(ex.map(lambda j: run(j, a.dry_run), js))
    if not a.dry_run:
        JOBS_FILE.write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print(json.dumps({s: sum(r["status"] == s for r in results) for s in {r["status"] for r in results}}), flush=True)


if __name__ == "__main__":
    main()
