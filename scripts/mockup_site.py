"""catland 官网设计稿（桌面端整页长图），只用于评审。素材在 docs/website/assets/（从 App 的离屏渲染导出）。

用法：~/miniconda3/envs/catlands/bin/python scripts/mockup_site.py
产物：docs/website/design-desktop.png（1440 宽，整页）、design-desktop-preview.png（缩小预览）
"""
from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
A = ROOT / "docs" / "website" / "assets"
OUT = ROOT / "docs" / "website"
W = 1440
SEC = 900
FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
PINK = (255, 92, 150)
INK = (236, 236, 245)
SUB = (160, 160, 185)


def f(size, bold=False):
    return ImageFont.truetype(FONT, size, index=2 if bold else 0)


def img(name, w=None, h=None, nearest=True):
    im = Image.open(A / name).convert("RGBA")
    b = im.getchannel("A").getbbox()
    if b: im = im.crop(b)
    if w and not h: h = int(im.height * w / im.width)
    if h and not w: w = int(im.width * h / im.height)
    if w: im = im.resize((w, h), Image.NEAREST if nearest else Image.LANCZOS)
    return im


def rounded(im, r):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], r, fill=255)
    out = im.copy(); out.putalpha(m); return out


def text(d, xy, s, size, color=INK, bold=False, anchor="la"):
    d.text(xy, s, font=f(size, bold), fill=color, anchor=anchor)


def pill(d, box, fill, outline=None):
    d.rounded_rectangle(box, (box[3] - box[1]) // 2, fill=fill, outline=outline, width=2)


def shadow(canvas, im, xy, r=40, a=140):
    s = Image.new("RGBA", (im.width + r * 4, im.height + r * 4), (0, 0, 0, 0))
    ImageDraw.Draw(s).rounded_rectangle([r * 2, r * 2, r * 2 + im.width, r * 2 + im.height], 24, fill=(0, 0, 0, a))
    s = s.filter(ImageFilter.GaussianBlur(r))
    canvas.paste(s, (xy[0] - r * 2, xy[1] - r * 2 + 20), s)
    canvas.paste(im, xy, im)


def panel(content, w=400, h=720):
    """展开面板：顶栏 + 内容（圆角、深色描边）。"""
    p = Image.new("RGBA", (w, h), (12, 12, 18, 255))
    d = ImageDraw.Draw(p, "RGBA")
    text(d, (20, 16), "视频", 16, bold=True); text(d, (72, 16), "电商", 16, SUB)
    for i in range(4): d.ellipse([w - 150 + i * 32, 18, w - 134 + i * 32, 34], outline=(200, 200, 215), width=2)
    c = content.resize((w - 16, int(content.height * (w - 16) / content.width)), Image.LANCZOS) if content.width != w - 16 else content
    c = c.crop((0, 0, c.width, min(c.height, h - 60)))
    p.alpha_composite(rounded(c, 16), (8, 52))
    return rounded(p, 28)


def section_bg(canvas, y, h, top, bot):
    d = ImageDraw.Draw(canvas, "RGBA")
    for k in range(h):
        t = k / h
        d.line([(0, y + k), (W, y + k)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
    rng = random.Random(y)
    for _ in range(90):
        x, yy = rng.randrange(W), y + rng.randrange(h)
        a = rng.randrange(40, 160); s = rng.choice([2, 2, 3])
        d.rectangle([x, yy, x + s, yy + s], fill=(255, 255, 255, a))


def label(d, y, n, title, en):
    text(d, (120, y), f"{n:02d}", 18, PINK, bold=True)
    text(d, (120, y + 34), title, 52, bold=True)
    text(d, (120, y + 104), en, 20, SUB)


def build():
    secs = 10
    H = 120 + SEC * (secs - 1) + 700
    c = Image.new("RGB", (W, H), (10, 10, 22))  # RGB 画布：半透明填充才会和底色混合
    d = ImageDraw.Draw(c, "RGBA")

    # ── 1 首屏 ─────────────────────────────
    section_bg(c, 0, SEC + 120, (16, 14, 40), (44, 30, 70))
    # 屏幕顶部 + 刘海 + 小岛（真机比例）
    island = img("island-hover.png", w=620)
    shadow(c, island, (W // 2 - island.width // 2, 0), r=30, a=120)
    d.rounded_rectangle([W // 2 - 200, -30, W // 2 + 200, 64], 22, fill=(0, 0, 0, 255))
    d = ImageDraw.Draw(c, "RGBA")
    # 顶栏
    paw = img("cat_kitten.png", h=30)
    c.paste(paw, mask=paw, box=(40, 26)); text(d, (40 + paw.width + 10, 26), "catland", 24, bold=True)
    for i, t in enumerate(["功能", "下载", "GitHub"]): text(d, (W - 420 + i * 90, 30), t, 17, SUB)
    pill(d, (W - 150, 22, W - 40, 58), (255, 255, 255, 18), (255, 255, 255, 60)); text(d, (W - 95, 31), "中文 · EN", 15, INK, anchor="ma")
    # 标题
    text(d, (W // 2, 330), "在 Mac 刘海里，", 88, bold=True, anchor="ma")
    text(d, (W // 2, 440), "刷你常刷的 App", 88, PINK, bold=True, anchor="ma")
    text(d, (W // 2, 572), "小红书、抖音、B 站、快手，鼠标一推就开刷；四只猫替你把内容叼回来", 24, SUB, anchor="ma")
    text(d, (W // 2, 612), "Your favorite feeds, living in your MacBook notch.", 20, (130, 130, 160), anchor="ma")
    pill(d, (W // 2 - 300, 670, W // 2 - 20, 738), PINK); text(d, (W // 2 - 160, 690), "下载 macOS 版 · v1.0.2", 22, (30, 10, 24), bold=True, anchor="ma")
    pill(d, (W // 2 + 10, 670, W // 2 + 230, 738), (255, 255, 255, 20), (255, 255, 255, 70)); text(d, (W // 2 + 120, 690), "GitHub  Star", 22, INK, anchor="ma")
    for i, t in enumerate(["免费开源", "不用注册", "数据只在你的 Mac 上"]):
        text(d, (W // 2 - 260 + i * 220, 772), "• " + t, 17, SUB, anchor="ma")
    # 注释：鼠标移到刘海上
    text(d, (W // 2 + 340, 112), "← 鼠标移上来：小岛变大，猫打招呼", 16, (255, 200, 120))

    # ── 2 点一下就开刷（滚动固定段） ─────────
    y = 120 + SEC
    section_bg(c, y, SEC, (14, 12, 30), (20, 18, 40)); d = ImageDraw.Draw(c, "RGBA")
    label(d, y + 90, 2, "点一下就开刷", "One click and you're scrolling")
    p = panel(img("feed-sakura.png", nearest=False))
    p = p.resize((380, int(p.height * 380 / p.width)), Image.LANCZOS)
    shadow(c, p, (W - 620, y + 90))
    d = ImageDraw.Draw(c, "RGBA")
    steps = [("鼠标一推", "移到屏幕顶部，小岛就会探出来", False), ("点一下就刷", "面板从刘海里落下来，开始播放", True), ("四个平台混着来", "小红书、抖音、B 站、快手轮流出现", False)]
    for i, (t, s, on) in enumerate(steps):
        yy = y + 330 + i * 130
        d.rounded_rectangle([120, yy, 640, yy + 104], 18, fill=(255, 255, 255, 22 if on else 8), outline=PINK if on else None, width=2)
        text(d, (150, yy + 22), f"0{i + 1}  {t}", 26, INK if on else SUB, bold=on)
        text(d, (150, yy + 64), s, 17, SUB)
    d.line([(96, y + 330), (96, y + 720)], fill=(255, 255, 255, 40), width=3); d.line([(96, y + 460), (96, y + 560)], fill=PINK, width=3)
    text(d, (120, y + 760), "滚动时页面固定：面板展开、卡片一张张划过，右侧跟着换步骤", 15, (255, 200, 120))

    # ── 3 一次搜遍 ──────────────────────
    y = 120 + SEC * 2
    section_bg(c, y, SEC, (20, 18, 40), (30, 20, 50)); d = ImageDraw.Draw(c, "RGBA")
    label(d, y + 90, 3, "一次搜遍四个平台", "Search four apps at once")
    pill(d, (120, y + 260, 620, y + 316), (255, 255, 255, 26), PINK); text(d, (150, y + 274), "搜索  露营装备 |", 22, INK)
    cats = ["cat_ragdoll.png", "cat_tuxedoBlack.png", "cat_calicoTV.png", "cat_cowJacket.png"]
    names = ["薯薯 · 小红书", "抖抖 · 抖音", "bibi · B 站", "铁铁 · 快手"]
    for i, (cf, n) in enumerate(zip(cats, names)):
        cat = img(cf, h=60); c.paste(cat, mask=cat, box=(130 + i * 125, y + 370))
        text(d, (130 + i * 125 + cat.width // 2, y + 444), n, 13, SUB, anchor="ma")
        text(d, (130 + i * 125 + cat.width // 2, y + 466), "带回 10 条", 13, PINK, anchor="ma")
    text(d, (120, y + 530), "猫们分头出门，谁先回来谁先显示", 20, SUB)
    # 结果瀑布流：用 catland 自己的像素场景当封面（网站不放平台的真实内容）
    grid = Image.new("RGBA", (420, 700), (12, 12, 18, 255)); gd = ImageDraw.Draw(grid, "RGBA")
    scenes = ["autumn-afternoon.png", "event-fireworks.png", "dusk.png", "rain-night.png", "winter-snow.png", "event-lightshow.png", "event-meteor.png", "beijing-night.png"]
    heights = [0, 0]
    for i, sc in enumerate(scenes):
        col = 0 if heights[0] <= heights[1] else 1
        th = [150, 230, 190, 170][i % 4]
        tile = Image.open(A / sc).convert("RGBA")
        tile = tile.crop(((tile.width - int(tile.height * 196 / th)) // 2, 0, (tile.width + int(tile.height * 196 / th)) // 2, tile.height)).resize((196, th), Image.NEAREST)
        x, yy = 10 + col * 206, 10 + heights[col]
        grid.paste(rounded(tile, 12), (x, yy), rounded(tile, 12))
        gd.text((x, yy + th + 6), ["秋日露营清单", "江边看烟花", "傍晚的城市", "雨夜窗边", "第一场雪", "灯光秀机位", "流星雨攻略", "北京夜景"][i], font=f(13), fill=INK)
        heights[col] += th + 34
    shadow(c, rounded(grid, 24), (W - 600, y + 120))
    d = ImageDraw.Draw(c, "RGBA")
    text(d, (W - 600, y + 840), "结果以瀑布流一格格「落」下来", 15, (255, 200, 120))

    # ── 4 四只猫 ───────────────────────
    y = 120 + SEC * 3
    section_bg(c, y, SEC, (30, 20, 50), (24, 18, 44)); d = ImageDraw.Draw(c, "RGBA")
    label(d, y + 90, 4, "每个平台，住着一只猫", "A cat for every app")
    personas = [("薯薯", "小红书", "精致又毒舌的布偶猫", "本小姐挑的，都是好看的"), ("抖抖", "抖音", "什么梗都知道的黑猫", "家人们，这条必须看"),
                ("bibi", "B 站", "傲娇的三花夜猫子", "才、才不是特意等你"), ("铁铁", "快手", "穿花棉袄的东北奶牛猫", "老铁，整点好看的")]
    for i, (n, p_, desc, line) in enumerate(personas):
        x = 120 + i * 305
        d.rounded_rectangle([x, y + 280, x + 280, y + 700], 28, fill=(255, 255, 255, 14), outline=(255, 255, 255, 30), width=1)
        cat = img(cats[i], h=110); c.paste(cat, mask=cat, box=(x + 140 - cat.width // 2, y + 330))
        text(d, (x + 140, y + 470), n, 30, bold=True, anchor="ma"); text(d, (x + 140, y + 514), p_, 17, PINK, anchor="ma")
        text(d, (x + 140, y + 548), desc, 15, SUB, anchor="ma")
        d.rounded_rectangle([x + 24, y + 600, x + 256, y + 650], 14, fill=(255, 255, 255, 235))
        text(d, (x + 140, y + 614), line, 15, (40, 40, 50), anchor="ma")
    text(d, (120, y + 750), "悬停时猫会说话，跟访客的真实时间有关：半夜打开网站，它们会说「这么晚还没睡，辛苦啦」", 15, (255, 200, 120))

    # ── 5 窗外是你的城市 ─────────────────
    y = 120 + SEC * 4
    section_bg(c, y, SEC, (24, 18, 44), (8, 8, 20)); d = ImageDraw.Draw(c, "RGBA")
    label(d, y + 90, 5, "窗外，是你的城市", "Outside the window: your city")
    shots = [("city-shanghai-hover-day.png", "14:00"), ("city-shanghai-hover-night.png", "21:00")]
    for i, (fn, t) in enumerate(shots):
        im = img(fn, w=600, nearest=True)
        shadow(c, rounded(im, 20), (120 + i * 640, y + 300))
        d = ImageDraw.Draw(c, "RGBA"); text(d, (120 + i * 640, y + 300 + im.height + 20), f"上海 · {t}", 18, SUB)
    d.line([(120, y + 640), (W - 120, y + 640)], fill=(255, 255, 255, 50), width=4); d.ellipse([W // 2 + 180, y + 630, W // 2 + 200, y + 650], fill=PINK)
    text(d, (120, y + 670), "往下滑 = 时间在走：白天 → 傍晚 → 夜里，东方明珠亮灯、陆家嘴霓虹、江上夜游船", 16, (255, 200, 120))
    for i, t in enumerate(["上海", "北京", "新加坡"]):
        pill(d, (120 + i * 120, y + 730, 220 + i * 120, y + 770), PINK if i == 0 else (255, 255, 255, 20)); text(d, (170 + i * 120, y + 740), t, 16, (30, 10, 24) if i == 0 else INK, anchor="ma")

    # ── 6 老板来了 ──────────────────────
    y = 120 + SEC * 5
    section_bg(c, y, SEC, (8, 8, 20), (16, 12, 32)); d = ImageDraw.Draw(c, "RGBA")
    label(d, y + 90, 6, "老板来了？", "Boss walking by?")
    for i, (k, w) in enumerate([("Option", 220), ("Esc", 190)]):
        x = W // 2 - 220 + i * 240
        d.rounded_rectangle([x, y + 330, x + w, y + 480], 26, fill=(36, 36, 50), outline=(90, 90, 120), width=3)
        text(d, (x + w // 2, y + 372), k, 56, bold=True, anchor="ma")
    text(d, (W // 2, y + 540), "一键收起、视频暂停。现在按一下试试 ↓", 24, SUB, anchor="ma")
    d.rounded_rectangle([W // 2 - 160, y + 610, W // 2 + 160, y + 660], 22, fill=(0, 0, 0, 255))
    d.rounded_rectangle([W // 2 + 180, y + 610, W // 2 + 420, y + 660], 16, fill=(255, 255, 255, 235)); text(d, (W // 2 + 300, y + 624), "薯薯：嘘——", 17, (40, 40, 50), anchor="ma")
    text(d, (W // 2, y + 720), "访客在网页里真按下 Option + Esc，面板「嗖」地收回刘海", 15, (255, 200, 120), anchor="ma")

    # ── 7 猫猫也会累 ────────────────────
    y = 120 + SEC * 6
    section_bg(c, y, SEC, (16, 12, 32), (26, 20, 48)); d = ImageDraw.Draw(c, "RGBA")
    label(d, y + 90, 7, "猫猫也会累", "Even cats need a break")
    text(d, (120, y + 240), "每个平台的请求都有节奏，不容易被平台限流；", 20, SUB)
    text(d, (120, y + 274), "真要歇一会儿时，猫会告诉你还要等多久。", 20, SUB)
    pc = img("pause-cards-v2.png", w=1100, nearest=False)
    shadow(c, rounded(pc, 24), (W // 2 - 550, y + 340))

    # ── 8 只在你的 Mac 上 ─────────────────
    y = 120 + SEC * 7
    section_bg(c, y, SEC, (26, 20, 48), (14, 14, 30)); d = ImageDraw.Draw(c, "RGBA")
    label(d, y + 90, 8, "只在你的 Mac 上", "Nothing leaves your Mac")
    d.rounded_rectangle([120, y + 280, 700, y + 700], 30, fill=(255, 255, 255, 12), outline=(255, 255, 255, 50), width=2)
    text(d, (160, y + 310), "你的 Mac", 26, bold=True)
    for i, (t, s) in enumerate([("点赞 · 收藏 · 历史", "不回写原平台"), ("各平台登录状态", "重装也不用重新登录"), ("所在城市", "只发一个大概位置查天气")]):
        d.rounded_rectangle([160, y + 380 + i * 96, 660, y + 456 + i * 96], 16, fill=(255, 255, 255, 18))
        text(d, (190, y + 396 + i * 96), t, 20, INK, bold=True); text(d, (190, y + 426 + i * 96), s, 15, SUB)
    for i, t in enumerate(["小红书", "抖音", "B 站", "快手"]):
        yy = y + 330 + i * 90
        d.line([(700, y + 490), (900, yy + 20)], fill=(255, 255, 255, 70), width=2)
        pill(d, (900, yy, 1060, yy + 44), (255, 255, 255, 22)); text(d, (980, yy + 10), t, 17, INK, anchor="ma")
    d.rounded_rectangle([1130, y + 420, 1320, y + 560], 30, outline=(255, 90, 90), width=3)
    text(d, (1225, y + 452), "云端", 38, (255, 90, 90), bold=True, anchor="ma"); text(d, (1225, y + 515), "没有 catland 服务器", 15, (255, 140, 140), anchor="ma")
    d.line([(1140, y + 430), (1310, y + 550)], fill=(255, 90, 90), width=4)

    # ── 9 下载 ─────────────────────────
    y = 120 + SEC * 8
    section_bg(c, y, SEC + 700, (14, 14, 30), (40, 24, 60)); d = ImageDraw.Draw(c, "RGBA")
    cats_row = [img(x, h=70) for x in cats]
    for i, cat in enumerate(cats_row): c.paste(cat, mask=cat, box=(W // 2 - 210 + i * 110, y + 120))
    text(d, (W // 2, y + 230), "现在就把猫接回家", 64, bold=True, anchor="ma")
    text(d, (W // 2, y + 320), "Bring the cats home", 22, SUB, anchor="ma")
    pill(d, (W // 2 - 220, y + 390, W // 2 + 220, y + 470), PINK); text(d, (W // 2, y + 413), "下载 catland · v1.0.2", 26, (30, 10, 24), bold=True, anchor="ma")
    text(d, (W // 2, y + 500), "Apple 芯片 · macOS 14+ · 220 MB · 2026-10-29 发布（自动读取 GitHub 最新版）", 16, SUB, anchor="ma")
    d.rounded_rectangle([W // 2 - 420, y + 560, W // 2 + 420, y + 760], 22, fill=(255, 255, 255, 12))
    text(d, (W // 2 - 390, y + 582), "这一版更新了", 18, INK, bold=True)
    for i, t in enumerate(["想刷哪些平台自己选；搜索的猫可以勾选", "猫猫卡：刷太快时搬运进度，全都歇了就倒计时", "评论区重新设计：表情、楼中楼、图片评论去原帖看"]):
        text(d, (W // 2 - 390, y + 624 + i * 38), "·  " + t, 16, SUB)
    text(d, (W // 2 - 420, y + 820), "常见问题", 28, bold=True)
    for i, q in enumerate(["会不会被平台封号？", "安全吗？登录信息存在哪里？", "Intel 芯片的 Mac 能用吗？", "怎么卸载、彻底清除数据？", "为什么不上架 App Store？"]):
        yy = y + 880 + i * 72
        d.rounded_rectangle([W // 2 - 420, yy, W // 2 + 420, yy + 58], 16, fill=(255, 255, 255, 12))
        text(d, (W // 2 - 392, yy + 16), q, 18, INK); text(d, (W // 2 + 392, yy + 16), "+", 22, SUB, anchor="ra")
    text(d, (W // 2, H - 90), "catland · 免费开源 · 仅供学习研究 · 平台能力来自 catbus · GitHub", 15, (120, 120, 150), anchor="ma")
    return c


def main():
    page = build().convert("RGB")
    page.save(OUT / "design-desktop.png", optimize=True)
    page.resize((page.width // 3, page.height // 3), Image.LANCZOS).save(OUT / "design-desktop-preview.png")
    print(page.size)


if __name__ == "__main__":
    main()
