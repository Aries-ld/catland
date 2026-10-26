"""下载各平台官方 App 图标（App Store 公开接口），缩放为 128×128 PNG，供 App 内展示平台来源。

图标版权归各平台所有，仅用于标识内容来源（与 catbus 的免责声明一致）。
用法：~/miniconda3/envs/catlands/bin/python scripts/fetch_platform_icons.py
"""
from __future__ import annotations

import io
import json
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DST = ROOT / "apps/macos/Resources/PlatformIcons"

# 平台 id → (App Store 应用 id, 地区)
APPS = {
    "xhs": (741292507, "cn"),
    "douyin": (1142110895, "cn"),
    "bilibili": (736536022, "cn"),
    "kuaishou": (440948110, "cn"),
    "x": (333903271, "us"),
    "tiktok": (835599320, "us"),
    "weibo": (350962117, "cn"),
    "jd": (414245413, "cn"),
    "taobao": (387682726, "cn"),
    "xianyu": (510909506, "cn"),
}
SIZE = 128
# App Store 图标常换成节日 / 活动版（如 B 站联赛版、双 11 版）：这几个改用官网的常规图标。
WEB_OVERRIDES = {
    "bilibili": "https://i0.hdslb.com/bfs/static/jinkela/long/images/512.png",
    "jd": "https://storage.360buyimg.com/retail-mall/mall-common-component/favicon.ico",
    "taobao": "https://img.alicdn.com/tps/i3/T1OjaVFl4dXXa.JOZB-114-114.png",
}


def remove_web_ribbon(img: Image.Image) -> Image.Image:
    """B 站官网图标左上角有「WEB」斜角标：背景左右对称，用右上角对应像素填回（保留两侧都是白色文字的像素）。"""
    src = img.convert("RGBA")
    out = src.copy()
    s, px = src.load(), out.load()
    w = src.width
    k = w / 512
    white = lambda p: p[0] > 235 and p[1] > 225 and p[2] > 225
    for y in range(int(256 * k)):
        for x in range(int(256 * k)):
            d = (x + y) / k
            if d <= 215 or (d <= 330 and not white(s[x, y]) and not white(s[w - 1 - x, y])):
                px[x, y] = s[w - 1 - x, y]
    return out


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "catland-dev/0.1"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    sources = {}
    for pid, (app_id, country) in APPS.items():
        meta = json.loads(get(f"https://itunes.apple.com/lookup?id={app_id}&country={country}"))["results"][0]
        url = WEB_OVERRIDES.get(pid) or meta["artworkUrl512"].replace("512x512bb.jpg", "512x512bb.png")
        src = Image.open(io.BytesIO(get(url)))
        if src.format == "ICO":
            src = src.ico.getimage(max(src.ico.sizes()))
        if pid == "bilibili":
            src = remove_web_ribbon(src)
        img = src.convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
        img.save(DST / f"{pid}.png", optimize=True)
        sources[pid] = {"app": meta["trackName"], "appStoreId": app_id, "artwork": url}
        print(f"{pid:9} {meta['trackName']}")
    (DST / "SOURCES.json").write_text(json.dumps(sources, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
