"""下载各平台官方 App 图标（固定的干净版本），缩放为 128×128 PNG，供 App 内展示平台来源。

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

# 固定的「干净」图标地址：已人工确认没有节日 / 活动角标（双 11、联赛版等）。
# 不要改成动态取最新——App Store 图标会随活动更换。需要更新时，人工挑一个干净版本再替换这里。
PINNED = {
    "xhs": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/01/f5/1e/01f51e82-86bf-2056-0e8d-ba7efb3dca55/AppIcon-0-0-1x_U007epad-0-11-0-85-220.png/512x512bb.png",
    "douyin": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/56/0d/e6/560de620-6e7e-4679-43e4-689a52d71e4c/AppIcon-0-0-1x_U007emarketing-0-0-0-7-0-0-85-220.png/512x512bb.png",
    "bilibili": "https://i0.hdslb.com/bfs/static/jinkela/long/images/512.png",
    "kuaishou": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/e5/3e/b0/e53eb002-33fd-db94-75f9-459f2acff796/AppIcon-0-0-1x_U007emarketing-0-8-0-sRGB-85-220.png/512x512bb.png",
    "x": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/8a/c8/0d/8ac80d53-9d93-b659-94b3-6b7a87379b90/ProductionAppIcon-0-0-1x_U007emarketing-0-8-0-0-0-85-220.png/512x512bb.png",
    "tiktok": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/99/33/74/99337468-d03a-5efc-d436-67c0f4d918e1/TikTok_AppIcon26-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
    "weibo": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/0d/cb/53/0dcb5343-74eb-a65a-bb19-304fe55da537/WeiboAppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
    "jd": "https://storage.360buyimg.com/retail-mall/mall-common-component/favicon.ico",
    "taobao": "https://img.alicdn.com/tps/i3/T1OjaVFl4dXXa.JOZB-114-114.png",
    "xianyu": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/c1/e1/9f/c1e19fc8-8acb-9f5d-64fd-222a57b4c8a6/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png"
}
SIZE = 128


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
    for pid, url in PINNED.items():
        src = Image.open(io.BytesIO(get(url)))
        if src.format == "ICO":
            src = src.ico.getimage(max(src.ico.sizes()))
        if pid == "bilibili":
            src = remove_web_ribbon(src)
        src.convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS).save(DST / f"{pid}.png", optimize=True)
        print(pid)
    (DST / "SOURCES.json").write_text(json.dumps(PINNED, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
