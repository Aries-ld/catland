"""v0.3 新手引导线框稿（高亮聚焦 + 气泡说明 + 下一步 / 跳过），只用于设计评审。

依赖同 scripts/mockups_v03.py（/tmp/catland-snaps、/tmp/cat_<花色>.png）。
用法：~/miniconda3/envs/catlands/bin/python scripts/mockups_onboarding.py → docs/design/v0.3-onboarding.png
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from mockups_v03 import (CARD, H, OUT, PINK, PLAT, S, SNAPS, SUB, TXT, W, cat, cover, f, icon, label, panel, rr,  # noqa: E402
                         sheet, text)

DARK = (20, 20, 28)


def header(d, img):
    """新版顶栏：视频 / 电商 + 右侧四个图标（搜索、收藏、连接、设置）。"""
    text(d, (22, 46), "视频", 14)
    rr(d, (27, 66, 41, 68), 1, fill=TXT)
    text(d, (64, 46), "电商", 14, (255, 255, 255, 80))
    for i, g in enumerate(["search", "heart", "person", "gear"]):
        x = 256 + i * 32
        cx, cy = x + 12, 58
        if g == "search":
            d.ellipse([(cx - 6) * S, (cy - 6) * S, (cx + 3) * S, (cy + 3) * S], outline=TXT, width=2 * S)
            d.line([(cx + 2) * S, (cy + 2) * S, (cx + 6) * S, (cy + 6) * S], fill=TXT, width=2 * S)
        elif g == "heart":
            rr(d, (cx - 6, cy - 6, cx + 6, cy + 6), 3, outline=TXT, width=2 * S)
        elif g == "person":
            d.ellipse([(cx - 3) * S, (cy - 7) * S, (cx + 3) * S, (cy - 1) * S], outline=TXT, width=2 * S)
            d.arc([(cx - 7) * S, (cy) * S, (cx + 7) * S, (cy + 12) * S], 180, 360, fill=TXT, width=2 * S)
        else:
            d.ellipse([(cx - 6) * S, (cy - 6) * S, (cx + 6) * S, (cy + 6) * S], outline=TXT, width=2 * S)
            d.ellipse([(cx - 2) * S, (cy - 2) * S, (cx + 2) * S, (cy + 2) * S], outline=TXT, width=2 * S)


def feed(img, d, name="event-sakura"):
    header(d, img)
    img.alpha_composite(cover(name, 384, 630), (8 * S, 82 * S))
    img.alpha_composite(icon("xhs", 20), (22 * S, 646 * S))
    text(d, (48, 648), "小红书 · @薯薯带回来的", 12)
    text(d, (22, 674), "樱花季，不出片等于白过", 12)
    for k, t in enumerate(["赞", "藏", "评", "音"]):
        y = 430 + k * 54
        d.ellipse([352 * S, y * S, 384 * S, (y + 32) * S], fill=(255, 255, 255, 60))
        text(d, (362, y + 8), t, 12)


def spotlight(img, box, r=14):
    """压暗整个面板，只留出 box 区域（圆角），外圈一道粉色光边。"""
    x0, y0, x1, y1 = box
    shade = Image.new("RGBA", img.size, (8, 8, 12, 185))
    m = Image.new("L", img.size, 255)
    ImageDraw.Draw(m).rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S, fill=0)
    shade.putalpha(Image.eval(m, lambda v: int(v * 185 / 255)))
    # 只在面板范围内压暗（面板外是透明的）
    panel_alpha = img.getchannel("A")
    a = Image.composite(shade.getchannel("A"), Image.new("L", img.size, 0), panel_alpha.point(lambda v: 255 if v > 0 else 0))
    shade.putalpha(a)
    img.alpha_composite(shade)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S, outline=PINK + (255,), width=3 * S)
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(2 * S)))
    img.alpha_composite(glow)


def bubble(img, box, arrow_x, arrow_up, cat_skin, title, body, step, total, last=False):
    """白色说明气泡：左边一只猫在讲，标题 + 说明 + 进度点 + 跳过 / 下一步。"""
    d = ImageDraw.Draw(img, "RGBA")
    x0, y0, x1, y1 = box
    rr(d, box, 14, fill=(255, 255, 255))
    if arrow_up:
        d.polygon([((arrow_x - 8) * S, y0 * S), (arrow_x * S, (y0 - 9) * S), ((arrow_x + 8) * S, y0 * S)], fill=(255, 255, 255))
    else:
        d.polygon([((arrow_x - 8) * S, y1 * S), (arrow_x * S, (y1 + 9) * S), ((arrow_x + 8) * S, y1 * S)], fill=(255, 255, 255))
    img.alpha_composite(cat(cat_skin, 46), ((x0 + 10) * S, (y0 + 12) * S))
    text(d, (x0 + 64, y0 + 12), title, 14, DARK)
    yy = y0 + 36
    for line in body.split("\n"):
        text(d, (x0 + 64, yy), line, 11, (90, 90, 105))
        yy += 18
    by = y1 - 32
    for k in range(total):
        cx = x0 + 18 + k * 12
        d.ellipse([(cx - 3) * S, (by + 10) * S, (cx + 3) * S, (by + 16) * S], fill=PINK if k == step else (210, 210, 220))
    text(d, (x1 - 128, by + 6), "跳过", 12, (140, 140, 155))
    rr(d, (x1 - 84, by, x1 - 12, by + 26), 13, fill=PINK)
    text(d, (x1 - 48, by + 5), "开刷" if last else "下一步", 12, (40, 20, 30), anchor="ma")


TOTAL = 5


def s0_island():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    # 屏幕顶部 + 小岛（箱箱）
    rr(d, (0, 0, 400, 300), 18, fill=(46, 50, 78))
    snap = Image.open(SNAPS / "island-hover.png").convert("RGBA")
    snap = snap.resize((300 * S, int(snap.height * 300 * S / snap.width)), Image.NEAREST)
    img.alpha_composite(snap, (50 * S, 0))
    rr(d, (106, -20, 294, 34), 12, fill=(0, 0, 0))
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([46 * S, -10 * S, 354 * S, 84 * S], radius=16 * S, outline=PINK + (255,), width=3 * S)
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(3 * S)))
    rr(d, (70, 104, 330, 186), 14, fill=(255, 255, 255))
    d.polygon([(192 * S, 104 * S), (200 * S, 94 * S), (208 * S, 104 * S)], fill=(255, 255, 255))
    img.alpha_composite(cat("kitten", 44), (80 * S, 118 * S))
    text(d, (134, 116), "我在这儿…点我一下", 14, DARK)
    text(d, (134, 140), "带你认识大家，30 秒就好", 11, (90, 90, 105))
    text(d, (134, 160), "不想看？点别处就行", 11, (150, 150, 165))
    d2 = ImageDraw.Draw(img, "RGBA")
    for i, l in enumerate(["· 第一次启动不弹窗，只在小岛下方冒一个气泡，", "  小岛轻轻发光提示", "· 鼠标移上去 / 点一下，展开进入引导", "· 定位权限等引导走完再问"]):
        text(d2, (20, 330 + i * 24), l, 13, (60, 60, 75))
    return label(img, "0 启动：小岛发光 + 气泡", "第一次打开不打断：小岛轻轻发光，下面冒一个气泡（箱箱在说话）。点一下展开进入引导；点别处就关掉，之后在设置里也能重新看。")


def s1_welcome():
    img, d = panel()
    img.alpha_composite(cat("kitten", 110), (145 * S, 74 * S))
    rr(d, (150, 146, 250, 172), 4, fill=(199, 148, 92))
    text(d, (200, 192), "把你常刷的 App 接回家", 19, anchor="ma")
    text(d, (200, 224), "接上后就能在这儿刷小红书、抖音、B 站、快手，还能一次搜遍", 11, SUB, anchor="ma")
    text(d, (200, 242), "登录信息只存在你的 Mac 上", 11, SUB, anchor="ma")
    for i, (pid, name, skin, cname) in enumerate(PLAT):
        x = 14 + (i % 2) * 190
        y = 276 + (i // 2) * 150
        rr(d, (x, y, x + 182, y + 140), 16, fill=CARD, outline=PINK if i == 0 else None, width=2 * S)
        img.alpha_composite(cat(skin, 70), ((x + 56) * S, (y + 12) * S))
        img.alpha_composite(icon(pid, 20), ((x + 16) * S, (y + 82) * S))
        text(d, (x + 42, y + 83), name, 14)
        text(d, (x + 16, y + 110), "扫码 10 秒" if pid != "douyin" else "官方页面登录", 11, SUB)
    rr(d, (14, 590, 386, 634), 22, fill=PINK)
    text(d, (200, 601), "先接小红书", 14, (30, 20, 30), anchor="ma")
    text(d, (200, 652), "跳过引导", 12, SUB, anchor="ma")
    return label(img, "① 欢迎：先接一个平台", "引导的第一步就是接平台（没有内容后面的都没意义）：四张卡片任选，默认小红书。登录留在面板里完成（抖音照旧开官方页面）。右下「跳过引导」随时可退。")


def s2_card():
    img, d = panel()
    feed(img, d)
    spotlight(img, (8, 82, 392, 712), 18)
    bubble(img, (40, 300, 360, 420), 200, False, "ragdoll", "上下滑，换一条", "触控板上下滑、滚轮、↑↓ 都行\n几个平台轮着来，看过的不会再出现", 0, TOTAL)
    return label(img, "② 高亮：内容卡片", "聚焦整张卡片，周围压暗。由第一只搬上岛的猫（这里是薯薯）讲解。用户真的滑一下，也会自动进入下一步。")


def s3_actions():
    img, d = panel()
    feed(img, d)
    spotlight(img, (344, 422, 392, 640), 22)
    bubble(img, (30, 470, 336, 590), 330, False, "ragdoll", "喜欢就点个赞", "点赞、收藏只存在你的 Mac 上\n不会同步回原平台，也不会被算法拿去", 1, TOTAL)
    return label(img, "③ 高亮：右侧按钮", "聚焦点赞 / 收藏 / 评论 / 静音，强调「只存在本机」这个和平台最大的不同。双击画面也能点赞。")


def s4_search():
    img, d = panel()
    feed(img, d)
    spotlight(img, (252, 44, 284, 72), 16)
    bubble(img, (60, 90, 340, 200), 268, True, "tuxedoBlack", "一次搜遍四个平台", "点放大镜或按 Cmd+F\n猫们会分头去各个平台帮你找", 2, TOTAL)
    return label(img, "④ 高亮：搜索", "聚焦顶栏放大镜（换成抖抖讲，四只猫轮流出场）。")


def s5_saved_connect():
    img, d = panel()
    feed(img, d)
    spotlight(img, (284, 44, 348, 72), 14)
    bubble(img, (50, 90, 350, 210), 316, True, "calicoTV", "收藏和更多平台在这里", "心形：你的点赞和收藏，点开直接在这里看\n人像：再接几个平台，猫就多几只", 3, TOTAL)
    return label(img, "⑤ 高亮：收藏 + 连接", "一次聚焦两个图标（相邻、都是「管理」类），减少步数。")


def s6_boss():
    img, d = panel()
    feed(img, d)
    spotlight(img, (0, 0, 0, 0), 1)
    bubble(img, (40, 280, 360, 410), 200, False, "cowJacket", "老板来了？Option+Esc", "一键收起小岛、暂停视频\n点小岛外面任何地方也能收起，随时回来接着刷", 4, TOTAL, last=True)
    return label(img, "⑥ 最后：老板键", "不高亮具体元素，只压暗；铁铁收尾。按钮变成「开刷」，点了引导结束、开始刷。")


def s7_settings():
    img, d = panel()
    text(d, (20, 46), "设置", 16)
    for i, (t, on) in enumerate([("默认静音", True), ("窗外天气", True), ("刘海下方的猫步道", True)]):
        y = 84 + i * 44
        rr(d, (14, y, 386, y + 36), 10, fill=CARD)
        text(d, (28, y + 9), t, 13)
        rr(d, (338, y + 9, 372, y + 27), 9, fill=PINK if on else (80, 80, 90))
    rr(d, (14, 230, 386, 270), 10, fill=CARD, outline=PINK, width=2 * S)
    text(d, (28, 241), "重新看一遍新手引导", 13)
    text(d, (360, 241), ">", 13, SUB)
    return label(img, "⑦ 设置里可以重看", "跳过之后想再看，设置里有「重新看一遍新手引导」。")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    frames = [s0_island(), s1_welcome(), s2_card(), s3_actions(), s4_search(), s5_saved_connect(), s6_boss(), s7_settings()]
    sheet(frames[:4], OUT / "v0.3-onboarding.png", "v0.3 新手引导（1/2）：启动 → 接平台 → 高亮讲解")
    sheet(frames[4:], OUT / "v0.3-onboarding-2.png", "v0.3 新手引导（2/2）：高亮讲解 → 结束 → 设置里重看")
    print("ok")


if __name__ == "__main__":
    main()
