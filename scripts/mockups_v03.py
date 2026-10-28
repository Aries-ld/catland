"""v0.3 界面线框稿：跨平台搜索 + 新手引导（只用于设计评审，不进 App）。

依赖：/tmp/catland-snaps（catland-debug snapshots:/tmp/catland-snaps）与 /tmp/cat_<花色>.png。
用法：~/miniconda3/envs/catlands/bin/python scripts/mockups_v03.py → docs/design/v0.3-search.png、v0.3-onboarding.png
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from make_readme_art import CJK  # noqa: E402

S = 2  # 2 倍图
W, H = 400 * S, 720 * S
SNAPS = Path("/tmp/catland-snaps")
ICONS = ROOT / "apps/macos/Resources/PlatformIcons"
OUT = ROOT / "docs/design"
BG = (8, 8, 10)
CARD = (24, 24, 30)
LINE = (255, 255, 255, 30)
TXT = (240, 240, 245)
SUB = (150, 150, 165)
PINK = (255, 107, 158)
PLAT = [("xhs", "小红书", "ragdoll", "薯薯"), ("douyin", "抖音", "tuxedoBlack", "抖抖"), ("bilibili", "B 站", "calicoTV", "bibi"), ("kuaishou", "快手", "cowJacket", "铁铁")]


def f(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(CJK, size * S)


def rr(d, box, r, **kw):
    """圆角矩形；半透明填充先画在透明层上再叠加（RGBA 图上直接画会把底色替换成半透明，而不是混合）。"""
    fill = kw.get("fill")
    if fill is not None and len(fill) == 4 and fill[3] < 255:
        base = d._image
        layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle([v * S for v in box], radius=r * S, **kw)
        base.alpha_composite(layer)
        return
    d.rounded_rectangle([v * S for v in box], radius=r * S, **kw)


def text(d, xy, t, size, fill=TXT, anchor="la"):
    d.text((xy[0] * S, xy[1] * S), t, font=f(size), fill=fill, anchor=anchor)


def icon(pid: str, size: int) -> Image.Image:
    im = Image.open(ICONS / f"{pid}.png").convert("RGBA").resize((size * S, size * S), Image.LANCZOS)
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=im.width // 4, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def cat(skin: str, w: int) -> Image.Image:
    c = Image.open(f"/tmp/cat_{skin}.png").convert("RGBA")
    return c.resize((w * S, int(c.height * w * S / c.width)), Image.NEAREST)


def cover(name: str, w: int, h: int) -> Image.Image:
    im = Image.open(SNAPS / f"{name}.png").convert("RGBA")
    k = max(w * S / im.width, h * S / im.height)
    im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)
    x = (im.width - w * S) // 2
    im = im.crop((x, im.height - h * S, x + w * S, im.height))
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=8 * S, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def panel() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    rr(d, (0, 0, 400, 720), 24, fill=BG)
    # 刘海
    rr(d, (110, -20, 290, 32), 12, fill=(0, 0, 0))
    return img, d


def header_tabs(d, search_active=False):
    text(d, (22, 46), "视频", 14)
    rr(d, (27, 66, 41, 68), 1, fill=TXT)
    text(d, (64, 46), "电商", 14, (255, 255, 255, 80))
    # 右侧：搜索（新增）、收藏、连接、设置
    x = 230
    rr(d, (x, 44, x + 28, 72), 14, fill=(255, 255, 255, 40) if search_active else (0, 0, 0, 0))
    d.ellipse([(x + 8) * S, (50) * S, (x + 18) * S, (60) * S], outline=PINK if not search_active else TXT, width=2 * S)
    d.line([(x + 17) * S, (59) * S, (x + 21) * S, (63) * S], fill=PINK if not search_active else TXT, width=2 * S)
    text(d, (x + 36, 50), "收藏", 11, SUB)
    rr(d, (x + 62, 46, x + 120, 70), 12, fill=(255, 255, 255, 30))
    text(d, (x + 70, 50), "+ 连接 4", 11)
    text(d, (x + 128, 50), "≡", 13, SUB)


def search_bar(d, query="", focused=True):
    rr(d, (14, 42, 330, 74), 16, fill=(40, 40, 48), outline=PINK if focused else None, width=S)
    d.ellipse([26 * S, 51 * S, 36 * S, 61 * S], outline=SUB, width=2 * S)
    d.line([35 * S, 60 * S, 39 * S, 64 * S], fill=SUB, width=2 * S)
    text(d, (46, 49), query or "一次搜遍小红书、抖音、B 站、快手", 13, TXT if query else SUB)
    if query:
        text(d, (312, 49), "×", 12, SUB)
    text(d, (342, 49), "取消", 13, SUB)


def chips(d, y, active="全部", status=None):
    x = 14
    items = [("全部", None)] + [(n, p) for p, n, *_ in PLAT]
    for name, pid in items:
        st = (status or {}).get(pid)
        label = name + (f" {st}" if st else "")
        w = int(d.textlength(label, font=f(11)) / S) + (30 if pid else 20)
        on = name == active
        rr(d, (x, y, x + w, y + 24), 12, fill=(255, 255, 255) if on else (255, 255, 255, 26))
        if pid:
            img_icon = icon(pid, 14)
            d._image.alpha_composite(img_icon, ((x + 6) * S, (y + 5) * S))
        text(d, (x + (24 if pid else 10), y + 5), label, 11, (20, 20, 25) if on else TXT)
        x += w + 6


def label(img, title: str, note: str) -> Image.Image:
    """加上方标题和下方说明。"""
    out = Image.new("RGBA", (W + 40 * S, H + 200 * S), (238, 238, 243, 255))
    d = ImageDraw.Draw(out)
    d.text((20 * S, 14 * S), title, font=f(17), fill=(30, 30, 40))
    out.alpha_composite(img, (20 * S, 48 * S))
    y = 48 * S + H + 12 * S
    fn = f(12)
    for para in note.split("\n"):
        line = ""
        for ch in para:
            if d.textlength(line + ch, font=fn) > W:
                d.text((20 * S, y), line, font=fn, fill=(70, 70, 85)); y += 20 * S; line = ""
            line += ch
        d.text((20 * S, y), line, font=fn, fill=(70, 70, 85)); y += 20 * S
    return out


# ---------------- 搜索 ----------------

def s1_entry():
    img, d = panel()
    header_tabs(d)
    # 推荐流卡片
    img.alpha_composite(cover("feed-fireworks", 384, 630), (8 * S, 82 * S))
    # 气泡提示（第一次出现）
    rr(d, (150, 80, 296, 108), 10, fill=(255, 255, 255))
    d.polygon([(242 * S, 80 * S), (248 * S, 72 * S), (254 * S, 80 * S)], fill=(255, 255, 255))
    text(d, (160, 86), "新：一次搜遍四个平台", 12, (30, 30, 40))
    return label(img, "① 入口：顶栏放大镜（Cmd+F）", "顶栏右侧新增放大镜，和抖音 / 小红书右上角搜索的位置一致；快捷键 Cmd+F。\n第一次升级后冒一次提示气泡，之后不再打扰。\n刘海悬停时也可以直接按 Cmd+F：小岛展开并进入搜索。")


def s2_empty():
    img, d = panel()
    search_bar(d)
    chips(d, 86)
    text(d, (16, 128), "最近搜索", 13, SUB)
    text(d, (340, 128), "清空", 12, SUB)
    x, y = 16, 152
    for k in ["露营装备", "MacBook 贴膜", "上海周末去哪", "原神 新角色"]:
        w = int(d.textlength(k, font=f(12)) / S) + 22
        if x + w > 384:
            x, y = 16, y + 34
        rr(d, (x, y, x + w, y + 26), 13, fill=(255, 255, 255, 22))
        text(d, (x + 11, y + 5), k, 12)
        x += w + 8
    text(d, (16, 236), "猫们会去这些地方帮你找", 13, SUB)
    for i, (pid, name, skin, cname) in enumerate(PLAT):
        y = 264 + i * 58
        rr(d, (14, y, 386, y + 48), 12, fill=CARD)
        img.alpha_composite(cat(skin, 44), (22 * S, (y + 6) * S))
        img.alpha_composite(icon(pid, 18), (76 * S, (y + 15) * S))
        text(d, (102, y + 14), f"{cname} · {name}", 13)
        text(d, (300, y + 15), "已连接" if pid != "kuaishou" else "按关键词", 11, SUB)
    text(d, (16, 520), "回车开始搜索 · 不会边打字边搜（少请求、防风控）", 11, SUB)
    return label(img, "② 搜索页（刚打开）", "顶栏变成搜索框，推荐流暂停；下面是平台筛选：全部 / 单个平台，只列出已连接的。\n最近搜索只存在本机，可清空。按回车才搜，不做边打字边搜。")


def s3_searching():
    img, d = panel()
    search_bar(d, "露营装备", focused=False)
    chips(d, 86, status={"xhs": "12", "douyin": "…", "bilibili": "8", "kuaishou": "休息"})
    # 猫们出门找
    rr(d, (14, 124, 386, 214), 14, fill=CARD)
    text(d, (28, 136), "猫们出门帮你找了…", 13)
    for i, (pid, name, skin, cname) in enumerate(PLAT):
        x = 28 + i * 88
        c = cat(skin, 40)
        img.alpha_composite(c, (x * S, 158 * S))
        st = {"xhs": "带回 12 条", "douyin": "在找…", "bilibili": "带回 8 条", "kuaishou": "在打盹"}[pid]
        text(d, (x + 2, 194), st, 10, PINK if "带回" in st else SUB)
    # 骨架
    for k in range(4):
        x = 14 + (k % 2) * 190
        y = 226 + (k // 2) * 250
        img.alpha_composite(cover(["event-sakura", "winter-snow", "beijing-dusk", "rain-night"][k], 182, 180), (x * S, y * S))
        rr(d, (x, y + 186, x + 150, y + 198), 4, fill=(255, 255, 255, 25))
        rr(d, (x, y + 204, x + 90, y + 214), 4, fill=(255, 255, 255, 18))
    return label(img, "③ 搜索中：猫们出门找", "每只猫去自己的平台搜，谁先回来谁的结果先上（不用等最慢的）。\n筛选条上显示每个平台带回多少条；被限流的平台显示「休息」并悄悄跳过，不报错。")


def s4_results():
    img, d = panel()
    search_bar(d, "露营装备", focused=False)
    chips(d, 86, status={"xhs": "12", "douyin": "10", "bilibili": "8", "kuaishou": "休息"})
    covers = ["event-sakura", "winter-snow", "beijing-dusk", "rain-night", "feed-fireworks", "autumn-afternoon"]
    heights = [190, 150, 150, 190, 170, 170]
    plats = ["xhs", "douyin", "bilibili", "xhs", "douyin", "bilibili"]
    titles = ["新手露营装备清单｜一次买齐", "周末露营 vlog", "千元露营装备横评", "露营灯怎么选？", "雨天露营也能很舒服", "装备党的极简露营"]
    ys = [124, 124]
    for k in range(6):
        col = 0 if ys[0] <= ys[1] else 1
        x, y = 14 + col * 190, ys[col]
        h = heights[k]
        if y + h > 712:
            continue
        img.alpha_composite(cover(covers[k], 182, h), (x * S, y * S))
        img.alpha_composite(icon(plats[k], 18), ((x + 6) * S, (y + 6) * S))
        if plats[k] != "xhs":
            rr(d, (x + 140, y + h - 22, x + 176, y + h - 6), 6, fill=(0, 0, 0, 150))
            text(d, (x + 145, y + h - 21), "3:24", 10)
        text(d, (x + 2, y + h + 6), titles[k], 12)
        text(d, (x + 2, y + h + 26), "赞 2.3万", 10, SUB)
        ys[col] = y + h + 50
    return label(img, "④ 结果：两列封面瀑布流", "按平台轮流混排（和推荐流一样，同一平台最多连着 3 条）；封面左上角是平台图标，视频右下角是时长。\n滑到底自动加载下一页（每个平台再取一页）。点「小红书」等筛选只看一个平台。")


def s5_player():
    img, d = panel()
    rr(d, (14, 42, 120, 72), 15, fill=(255, 255, 255, 30))
    text(d, (24, 48), "< 露营装备", 13)
    text(d, (318, 48), "3 / 30", 12, SUB)
    img.alpha_composite(cover("event-sakura", 384, 630), (8 * S, 82 * S))
    img.alpha_composite(icon("xhs", 22), (22 * S, 640 * S))
    text(d, (52, 642), "小红书 · 薯薯带回来的", 13)
    text(d, (22, 670), "新手露营装备清单｜一次买齐", 13)
    return label(img, "⑤ 点开：和推荐流同一套播放卡片", "点任意结果，进入和推荐流一样的竖向卡片，上下划在搜索结果里切换（点赞、收藏、评论都一样）。\n左上「< 关键词」或 Esc 回到瀑布流，停在刚才的位置；再按「取消」回到推荐流，接着刚才那条播。")


# ---------------- 新手引导 ----------------

def o0_island():
    img = Image.new("RGBA", (W, 150 * S), (40, 44, 70, 255))
    d = ImageDraw.Draw(img, "RGBA")
    snap = Image.open(SNAPS / "island-hover.png").convert("RGBA")
    snap = snap.resize((W - 40 * S, int(snap.height * (W - 40 * S) / snap.width)), Image.NEAREST)
    img.alpha_composite(snap, (20 * S, 0))
    rr(d, (110, -20, 290, 26), 10, fill=(0, 0, 0))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(img, (0, 0))
    d2 = ImageDraw.Draw(out, "RGBA")
    text(d2, (20, 180), "第一次启动：", 14, (30, 30, 40))
    for i, l in enumerate(["· 小岛里只有纸箱里的箱箱，轻轻蹦两下吸引注意", "· 气泡：「箱箱：点我一下…带你认识大家」", "· 鼠标移上去、点一下 → 展开新手引导", "· 定位权限不在启动时弹，等引导走完再问"]):
        text(d2, (20, 210 + i * 26), l, 13, (60, 60, 75))
    return label(out, "0 启动：箱箱在小岛里等你", "第一次打开不弹任何窗口，只让箱箱在小岛里招手；用户自己点进来，不打断手头的事。")


def o1_welcome():
    img, d = panel()
    box = cat("kitten", 120)
    img.alpha_composite(box, (140 * S, 80 * S))
    rr(d, (150, 156, 250, 186), 4, fill=(199, 148, 92))
    text(d, (200, 206), "在 Mac 顶上刷你常刷的 App", 19, anchor="ma")
    text(d, (200, 238), "接上平台，就能在这儿刷小红书、抖音、B 站、快手，还能一次搜遍", 11, SUB, anchor="ma")
    text(d, (200, 256), "登录信息只存在你的 Mac 上", 11, SUB, anchor="ma")
    for i, (pid, name, skin, cname) in enumerate(PLAT):
        x = 14 + (i % 2) * 190
        y = 290 + (i // 2) * 150
        rr(d, (x, y, x + 182, y + 140), 16, fill=CARD)
        img.alpha_composite(cat(skin, 70), ((x + 56) * S, (y + 12) * S))
        img.alpha_composite(icon(pid, 20), ((x + 16) * S, (y + 82) * S))
        text(d, (x + 42, y + 83), name, 14)
        text(d, (x + 16, y + 110), f"{cname}去{name}帮你搬", 11, SUB)
    rr(d, (14, 600, 386, 644), 22, fill=PINK)
    text(d, (200, 611), "先接一个试试（扫码 10 秒）", 14, (30, 20, 30), anchor="ma")
    text(d, (200, 660), "稍后再说", 12, SUB, anchor="ma")
    return label(img, "① 欢迎页：先讲清能干嘛，再选平台", "替代现在的「还没有连接任何平台」空状态：一句话价值 + 四张平台卡（每张带它的猫）。\n点卡片直接进入该平台登录；大按钮默认选第一个（小红书）。")


def o2_qr():
    img, d = panel()
    text(d, (22, 48), "< 返回", 13, SUB)
    img.alpha_composite(cat("ragdoll", 90), (155 * S, 80 * S))
    text(d, (200, 160), "薯薯准备出门去小红书", 16, anchor="ma")
    text(d, (200, 186), "打开小红书 App，扫一扫下面的二维码", 12, SUB, anchor="ma")
    rr(d, (100, 214, 300, 414), 12, fill=(255, 255, 255))
    import random
    rnd = random.Random(3)
    for yy in range(18):
        for xx in range(18):
            if rnd.random() < 0.45 or (xx < 5 and yy < 5) or (xx > 12 and yy < 5) or (xx < 5 and yy > 12):
                d.rectangle([(110 + xx * 10) * S, (224 + yy * 10) * S, (118 + xx * 10) * S, (232 + yy * 10) * S], fill=(20, 20, 25))
    text(d, (200, 432), "二维码 2 分钟内有效 · 过期自动刷新", 11, SUB, anchor="ma")
    rr(d, (60, 470, 340, 500), 15, fill=(255, 255, 255, 22))
    text(d, (200, 476), "抖音：在官方登录页扫码 / 验证码", 11, SUB, anchor="ma")
    return label(img, "② 登录：留在引导里完成", "复用现有的扫码 / 网页登录流程，但嵌在引导页里，不跳到「连接」浮层。\n抖音照旧打开官方登录窗口；登录完成后自动回到这里。")


def o3_done():
    img, d = panel()
    img.alpha_composite(cat("kitten", 90), (80 * S, 120 * S))
    img.alpha_composite(cat("ragdoll", 110), (200 * S, 110 * S))
    text(d, (110, 104), "开心", 14, PINK)
    text(d, (200, 230), "薯薯搬上岛啦！", 20, anchor="ma")
    text(d, (200, 262), "她已经去小红书帮你搬第一批内容了", 12, SUB, anchor="ma")
    rr(d, (14, 300, 386, 344), 22, fill=PINK)
    text(d, (200, 311), "开刷", 15, (30, 20, 30), anchor="ma")
    rr(d, (14, 356, 386, 396), 20, fill=(255, 255, 255, 26))
    text(d, (200, 366), "再接一个平台", 13, anchor="ma")
    text(d, (200, 430), "接得越多，刷到的越杂、越不腻", 11, SUB, anchor="ma")
    return label(img, "③ 成功：箱箱蹦一下，第一只猫登场", "和小岛里的登场动画呼应（箱箱开心地蹦一下、薯薯走上岛）。\n后台已在预取第一批内容，点「开刷」时首条基本已就绪。")


def o4_tips():
    img, d = panel()
    header_tabs(d)
    img.alpha_composite(cover("event-sakura", 384, 630), (8 * S, 82 * S))
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.rounded_rectangle([40 * S, 470 * S, 360 * S, 640 * S], radius=18 * S, fill=(10, 10, 14, 220))
    img.alpha_composite(ov)
    tips = [("1", "上下滑 / 滚轮：换一条"), ("2", "双击：点赞（只存在本机）"), ("3", "Cmd+F：一次搜遍四个平台"), ("4", "Option+Esc：老板来了，一键收起")]
    for i, (g, t) in enumerate(tips):
        text(d, (62, 486 + i * 34), g, 15, PINK)
        text(d, (92, 487 + i * 34), t, 13)
    text(d, (200, 650), "划一下就消失", 11, SUB, anchor="ma")
    return label(img, "④ 第一次刷：四条操作提示", "只在第一次进入推荐流时出现，半透明浮在底部，用户划一下或点一下就消失，以后不再出现。")


def sheet(frames: list[Image.Image], path: Path, title: str) -> None:
    w = sum(fr.width for fr in frames) + 20 * S * (len(frames) + 1)
    h = max(fr.height for fr in frames) + 80 * S
    out = Image.new("RGB", (w, h), (238, 238, 243))
    d = ImageDraw.Draw(out)
    d.text((20 * S, 20 * S), title, font=f(22), fill=(20, 20, 30))
    x = 20 * S
    for fr in frames:
        out.paste(fr, (x, 70 * S), fr)
        x += fr.width + 20 * S
    out = out.resize((out.width // 2, out.height // 2), Image.LANCZOS)
    out.save(path, optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sheet([s1_entry(), s2_empty(), s3_searching(), s4_results(), s5_player()], OUT / "v0.3-search.png", "v0.3 跨平台搜索")
    sheet([o0_island(), o1_welcome(), o2_qr(), o3_done(), o4_tips()], OUT / "v0.3-onboarding.png", "v0.3 新手引导")
    print("ok")


if __name__ == "__main__":
    main()
