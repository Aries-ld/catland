"""宣发图片：各平台需要的尺寸一次生成（中英文）。

素材准备（都来自 App 自己的渲染代码，不截屏、不用别人的内容）：
  1. 运行 App 后：apps/macos/build/catland-debug snapshots:/tmp/catland-snaps   （场景 + 竖版「刷到的内容」）
  2.              apps/macos/build/catland-debug film:/tmp/catland-film          （小岛动画逐帧）
  3. 小猫立绘：/tmp/cat_<花色>.png（16×12 像素猫放大 10 倍，见 docs/development.md「宣发素材」）
用法：~/miniconda3/envs/catlands/bin/python scripts/make_launch_kit.py
输出：assets/promo/
  how-<lang>-wide.png   1600×900   「它能干嘛」主视觉（X、即刻、V2EX、少数派头图）
  how-zh-tall.png       1080×1440  小红书第 2 张
  ph-1..4.png           1270×760   Product Hunt 展示图（英文）
  ph-thumb.png          240×240    Product Hunt 缩略图
  xhs-1..5.png          1080×1440  小红书图文
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from make_readme_art import CJK, CREAM, LAVENDER, PINK, backdrop, framed, pixel_text  # noqa: E402

SNAPS = Path("/tmp/catland-snaps")
FILM = Path("/tmp/catland-film")
OUT = ROOT / "assets/promo"
ICONS = ROOT / "apps/macos/Resources/PlatformIcons"

CATS = [  # 花色, 名字, 平台 id, 中文平台, 英文平台, 中文性格, 英文性格, 中文台词, 英文台词
    ("ragdoll", "薯薯", "xhs", "小红书", "Xiaohongshu", "精致又毒舌", "elegant, a little mean", "「老板画的饼，本小姐不吃」", "\u201cI don't eat my boss's pie in the sky.\u201d"),
    ("tuxedoBlack", "抖抖", "douyin", "抖音", "Douyin", "潮酷，什么梗都知道", "knows every meme", "「家人们谁懂啊，又上头了」", "\u201cOne more video. Really. Last one.\u201d"),
    ("calicoTV", "bibi", "bilibili", "B 站", "Bilibili", "傲娇，熬夜追番", "tsundere anime night owl", "「才、才不是想让你点我」", "\u201cI-it's not like I want you to click me.\u201d"),
    ("cowJacket", "铁铁", "kuaishou", "快手", "Kuaishou", "东北大姐，热心肠", "big-hearted big sister", "「老板画饼？大姐给你烙个真的」", "\u201cBoss promised you pie? I'll bake you a real one.\u201d"),
]
NAMES_EN = {"薯薯": "Shushu", "抖抖": "Doudou", "bibi": "Bibi", "铁铁": "Tietie"}


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(CJK, size)


def text_center(d: ImageDraw.ImageDraw, cx: int, y: int, t: str, f, fill) -> None:
    d.text((cx - d.textlength(t, font=f) // 2, y), t, font=f, fill=fill)


def rounded(im: Image.Image, r: int) -> Image.Image:
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=r, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def icon(pid: str, size: int) -> Image.Image:
    return rounded(Image.open(ICONS / f"{pid}.png").convert("RGBA").resize((size, size), Image.LANCZOS), size // 4)


def cat(skin: str, scale: float = 1.0) -> Image.Image:
    c = Image.open(f"/tmp/cat_{skin}.png").convert("RGBA")
    return c if scale == 1 else c.resize((int(c.width * scale), int(c.height * scale)), Image.NEAREST)


def cursor(size: int) -> Image.Image:
    """macOS 风格的鼠标箭头。"""
    s = size / 24
    pts = [(2, 1), (2, 19), (6.5, 15), (9.5, 22), (12.5, 20.8), (9.6, 14), (15.5, 14)]
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(x * s, y * s) for x, y in pts], fill=(255, 255, 255, 255), outline=(10, 10, 10, 255))
    d.line([(x * s, y * s) for x, y in pts + [pts[0]]], fill=(10, 10, 10, 255), width=max(1, int(1.6 * s)))
    return im


def island_strip(width: int) -> Image.Image:
    """真机悬停时的小岛（282×75pt，夜里的上海 + 四只猫 + 薯薯的气泡），中间叠上硬件刘海的黑块，底部圆角。"""
    f = Image.open(SNAPS / "island-hover.png").convert("RGBA")
    k = width / f.width
    im = f.resize((width, int(f.height * k)), Image.NEAREST)
    d = ImageDraw.Draw(im)
    nw, nh = int(180 / 282 * width), int(32 / 75 * im.height)
    nx = (width - nw) // 2
    d.rounded_rectangle([nx, -nh, nx + nw, nh], radius=int(nh * 0.45), fill=(0, 0, 0, 255))
    # 底部圆角（顶边贴着屏幕边缘）
    m = Image.new("L", im.size, 0)
    md = ImageDraw.Draw(m)
    r = max(8, int(14 * k))
    md.rounded_rectangle([0, -r, im.width - 1, im.height - 1], radius=r, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def heart(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill) -> None:
    d.ellipse([cx - r, cy - r * 0.7, cx, cy + r * 0.3], fill=fill)
    d.ellipse([cx, cy - r * 0.7, cx + r, cy + r * 0.3], fill=fill)
    d.polygon([(cx - r * 0.98, cy - r * 0.05), (cx + r * 0.98, cy - r * 0.05), (cx, cy + r * 0.95)], fill=fill)


def panel(w: int, h: int, feed: str, lang: str) -> Image.Image:
    """展开后的刷刷面板（简化重绘）：顶栏 + 一张卡片（我们自己的像素场景当内容）+ 来源标签 + 右侧按钮。"""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=w // 14, fill=(14, 14, 18, 255))
    pad = w // 24
    bar = int(h * 0.08)
    fs = font(max(12, w // 26))
    d.text((pad + 4, bar // 2 - fs.size // 2), "catland", font=fs, fill=(230, 230, 240))
    pill = "+ 连接 4" if lang == "zh" else "+ Connect 4"
    pw = d.textlength(pill, font=fs) + 24
    d.rounded_rectangle([w - pad - pw, bar // 2 - fs.size // 2 - 6, w - pad, bar // 2 + fs.size // 2 + 8], radius=14, fill=(40, 40, 50))
    d.text((w - pad - pw + 12, bar // 2 - fs.size // 2 - 1), pill, font=fs, fill=(220, 220, 235))
    # 卡片
    cw, ch = w - 2 * pad, h - bar - pad
    card = Image.open(SNAPS / f"{feed}.png").convert("RGBA")
    card = card.resize((cw, int(card.height * cw / card.width)), Image.LANCZOS)
    card = card.crop((0, max(0, card.height - ch), cw, max(ch, card.height)))
    shade = Image.new("RGBA", card.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for y in range(card.height // 2, card.height):
        sd.line([(0, y), (card.width, y)], fill=(0, 0, 0, int(170 * (y - card.height / 2) / (card.height / 2))))
    card = Image.alpha_composite(card, shade)
    im.alpha_composite(rounded(card, w // 20), (pad, bar))
    # 来源 + 作者 + 文案
    by = bar + ch - int(ch * 0.2)
    ic = icon("xhs" if feed.endswith("sakura") else "douyin", int(w * 0.075))
    im.alpha_composite(ic, (pad * 2, by))
    fb = font(max(12, w // 24))
    src = ("小红书 · 薯薯带回来的" if lang == "zh" else "Xiaohongshu · brought by Shushu") if feed.endswith("sakura") else ("抖音 · 抖抖带回来的" if lang == "zh" else "Douyin · brought by Doudou")
    d.text((pad * 2 + ic.width + 10, by + ic.height // 2 - fb.size // 2 - 2), src, font=fb, fill=(255, 255, 255))
    cap = ("樱花季，不出片等于白过" if lang == "zh" else "Cherry blossom season, finally") if feed.endswith("sakura") else ("今晚的花火大会，绝了" if lang == "zh" else "Tonight's fireworks were unreal")
    d.text((pad * 2, by + ic.height + 10), cap, font=font(max(11, w // 28)), fill=(235, 235, 240))
    # 右侧按钮：赞、收藏、评论
    bx = w - pad * 2 - int(w * 0.09)
    for k, (glyph, num) in enumerate([("♥", "2.3万" if lang == "zh" else "23k"), ("★", "收藏" if lang == "zh" else "Save"), ("…", "评论" if lang == "zh" else "Reply")]):
        y = by - int(ch * 0.36) + k * int(ch * 0.14)
        r = int(w * 0.045)
        d.ellipse([bx, y, bx + 2 * r, y + 2 * r], fill=(255, 255, 255, 40))
        g = font(int(r * 1.1))
        if glyph == "♥":
            heart(d, bx + r, y + r, r * 0.55, (255, 90, 120))
        else:
            d.text((bx + r - d.textlength(glyph, font=g) / 2, y + r - g.size * 0.62), glyph, font=g, fill=(255, 255, 255))
        sm = font(max(10, w // 34))
        d.text((bx + r - d.textlength(num, font=sm) / 2, y + 2 * r + 4), num, font=sm, fill=(230, 230, 235))
    # 进度条
    d.rectangle([pad, bar + ch - 3, pad + cw, bar + ch - 1], fill=(255, 255, 255, 60))
    d.rectangle([pad, bar + ch - 3, pad + int(cw * 0.38), bar + ch - 1], fill=(255, 107, 158, 255))
    return im


def how_wide(lang: str, W: int = 1600, H: int = 900) -> Image.Image:
    """横版主视觉：左边是屏幕顶上的小岛 + 展开的面板，右边是四步说明。"""
    img = backdrop(W, H, stars=40, avoid=[(0, 0, W, H)])
    d = ImageDraw.Draw(img)
    s = W / 1600
    title = "四只猫替你跑遍小红书、抖音、B 站、快手" if lang == "zh" else "Four cats fetch your feeds into the Dynamic Island"
    text_center(d, W // 2, int(44 * s), title, font(int(46 * s)), CREAM)
    # 屏幕：浅色的桌面 + 顶上的小岛
    sx, sy, sw, sh = int(60 * s), int(140 * s), int(900 * s), int(700 * s)
    d.rounded_rectangle([sx, sy, sx + sw, sy + sh], radius=int(26 * s), fill=(44, 46, 70), outline=(90, 92, 130), width=max(2, int(3 * s)))
    strip = island_strip(int(sw * 0.66))
    ix = sx + (sw - strip.width) // 2
    img.alpha_composite(strip, (ix, sy + int(3 * s)))
    img.alpha_composite(cursor(int(40 * s)), (ix + int(strip.width * 0.16), sy + strip.height - int(26 * s)))
    pw, ph = int(380 * s), int(sh - strip.height - 50 * s)
    p = panel(pw, ph, "feed-sakura", lang)
    img.alpha_composite(p, (sx + (sw - pw) // 2, sy + strip.height + int(30 * s)))
    # 四步
    steps = [
        ("1", "鼠标推到屏幕顶上", "猫们跟你打招呼，各说各的"),
        ("2", "点一下，小岛展开", "猫们带回来的东西都在这儿"),
        ("3", "几个平台混着刷", "轮着来，看过的不再出现"),
        ("4", "点别处，小岛收起", "老板来了按 Option + Esc"),
    ] if lang == "zh" else [
        ("1", "Nudge your mouse to the top", "the cats say hi, each in its own voice"),
        ("2", "Click, the island opens", "everything they brought back is here"),
        ("3", "Scroll several feeds as one", "mixed fairly, nothing repeats"),
        ("4", "Click away to hide it", "boss walking by? Option + Esc"),
    ]
    x0, y = sx + sw + int(60 * s), sy + int(40 * s)
    for n, head, sub in steps:
        r = int(26 * s)
        d.ellipse([x0, y, x0 + 2 * r, y + 2 * r], fill=PINK)
        fn = font(int(28 * s))
        d.text((x0 + r - d.textlength(n, font=fn) / 2, y + r - fn.size * 0.62), n, font=fn, fill=(40, 30, 50))
        d.text((x0 + 2 * r + int(18 * s), y - int(2 * s)), head, font=font(int(32 * s)), fill=CREAM)
        d.text((x0 + 2 * r + int(18 * s), y + int(44 * s)), sub, font=font(int(22 * s)), fill=LAVENDER)
        y += int(150 * s)
    foot = "开源 · 纯本地 · 不商用  github.com/Aries-ld/catland" if lang == "zh" else "Open source · fully local · github.com/Aries-ld/catland"
    text_center(d, sx + sw + (W - sx - sw) // 2, H - int(70 * s), foot, font(int(20 * s)), LAVENDER)
    return img


def how_tall() -> Image.Image:
    """竖版主视觉（小红书）：上面小岛，中间面板，下面四步。"""
    W, H = 1080, 1440
    img = backdrop(W, H, stars=40, avoid=[(0, 0, W, H)])
    d = ImageDraw.Draw(img)
    text_center(d, W // 2, 60, "它到底能干嘛？", font(56), CREAM)
    text_center(d, W // 2, 140, "四只猫替你跑遍小红书、抖音、B 站、快手", font(30), PINK)
    strip = island_strip(W - 120)
    img.alpha_composite(strip, (60, 220))
    img.alpha_composite(cursor(48), (60 + int(strip.width * 0.16), 220 + strip.height - 30))
    p = panel(470, 640, "feed-sakura", "zh")
    img.alpha_composite(p, ((W - 470) // 2, 220 + strip.height + 40))
    y = 220 + strip.height + 40 + 640 + 50
    steps = ["① 鼠标推到屏幕顶上，猫们跟你打招呼", "② 点一下，小岛展开，几个平台混着刷", "③ 点别处收起；老板来了按 Option + Esc"]
    for t in steps:
        text_center(d, W // 2, y, t, font(30), CREAM)
        y += 58
    return img


def cats_card(lang: str, W: int, H: int) -> Image.Image:
    img = backdrop(W, H, stars=40, avoid=[(0, 0, W, H)])
    d = ImageDraw.Draw(img)
    s = min(W / 1270, H / 760)
    title = "每只猫负责一个平台" if lang == "zh" else "One cat per feed"
    sub = "被平台限流的猫会趴下打盹，醒了再出门；登录过期的猫，暂时不在岛上" if lang == "zh" else "A rate-limited cat naps until it can go out again. Expired login? It stays home."
    text_center(d, W // 2, int(40 * s), title, font(int(44 * s)), CREAM)
    text_center(d, W // 2, int(104 * s), sub, font(int(22 * s)), LAVENDER)
    cw = W // 4
    for i, (skin, name, pid, zh, en, tzh, ten, qzh, qen) in enumerate(CATS):
        cx = i * cw + cw // 2
        c = cat(skin, 1.1 * s)
        img.alpha_composite(c, (cx - c.width // 2, int(190 * s)))
        ic = icon(pid, int(44 * s))
        img.alpha_composite(ic, (cx - ic.width // 2, int(190 * s) + c.height + int(18 * s)))
        y = int(190 * s) + c.height + int(76 * s)
        text_center(d, cx, y, name if lang == "zh" else NAMES_EN[name], font(int(34 * s)), CREAM)
        text_center(d, cx, y + int(48 * s), zh if lang == "zh" else en, font(int(22 * s)), PINK)
        text_center(d, cx, y + int(84 * s), tzh if lang == "zh" else ten, font(int(20 * s)), LAVENDER)
    return img


def world_card(lang: str, W: int, H: int) -> Image.Image:
    img = backdrop(W, H, stars=40, avoid=[(0, 0, W, H)])
    d = ImageDraw.Draw(img)
    s = min(W / 1270, H / 760)
    title = "岛上的天，和你那边一样" if lang == "zh" else "Same sky as yours"
    sub = "天色、晴雨、季节跟着你的城市；流星雨那晚，猫们会一起看窗外" if lang == "zh" else "Your city's time and weather, seasons, and meteor showers the cats watch with you"
    text_center(d, W // 2, int(36 * s), title, font(int(42 * s)), CREAM)
    text_center(d, W // 2, int(96 * s), sub, font(int(22 * s)), LAVENDER)
    tiles = ["beijing-dusk", "rain-night", "winter-snow", "event-meteor"]
    tw = (W - int(90 * s)) // 2
    for k, t in enumerate(tiles):
        im = Image.open(SNAPS / f"{t}.png").convert("RGBA")
        im = im.resize((tw - 20, int(im.height * (tw - 20) / im.width)), Image.LANCZOS)
        fr = framed(im, radius=12, border=4)
        img.alpha_composite(fr, (int(30 * s) + (k % 2) * (tw + int(10 * s)), int(150 * s) + (k // 2) * (fr.height + int(10 * s))))
    return img


def local_card(lang: str, W: int, H: int) -> Image.Image:
    img = backdrop(W, H, stars=60, avoid=[(0, 0, W, H)])
    d = ImageDraw.Draw(img)
    s = min(W / 1270, H / 760)
    ic = Image.open(ROOT / "assets/brand/icon-1024.png").resize((int(170 * s), int(170 * s)), Image.LANCZOS)
    img.alpha_composite(ic, (W // 2 - ic.width // 2, int(60 * s)))
    t = pixel_text("catland", 20, max(4, int(6 * s)), CREAM + (255,))
    img.alpha_composite(t, (W // 2 - t.width // 2, int(250 * s)))
    lines = ["没有服务器，不用注册账号", "点赞收藏只存在你自己的 Mac 上", "免费 · 开源 · 签名公证，双击就能打开"] if lang == "zh" else [
        "No server, no account, no tracking", "Likes and saves stay on your Mac", "Free and open source · signed & notarized"]
    y = int(400 * s)
    for k, l in enumerate(lines):
        text_center(d, W // 2, y, l, font(int(34 * s)), CREAM if k < 2 else PINK)
        y += int(62 * s)
    text_center(d, W // 2, H - int(80 * s), "github.com/Aries-ld/catland", font(int(28 * s)), LAVENDER)
    return img


def cats_tall() -> Image.Image:
    """小红书：四只猫各占一行，立绘 + 平台 + 性格 + 一句台词。"""
    W, H = 1080, 1440
    img = backdrop(W, H, stars=40, avoid=[(0, 0, W, H)])
    d = ImageDraw.Draw(img)
    text_center(d, W // 2, 70, "每只猫负责一个平台", font(52), CREAM)
    text_center(d, W // 2, 145, "接入哪个平台，它的猫就搬上岛", font(30), PINK)
    y = 230
    for skin, name, pid, zh, _en, tzh, _ten, qzh, _qen in CATS:
        c = cat(skin, 1.0)
        img.alpha_composite(c, (60, y + 6))
        ic = icon(pid, 46)
        img.alpha_composite(ic, (300, y + 10))
        d.text((360, y + 8), f"{name} · {zh}", font=font(40), fill=CREAM)
        d.text((300, y + 70), tzh, font=font(28), fill=LAVENDER)
        d.text((300, y + 112), qzh, font=font(32), fill=PINK)
        y += 250
    text_center(d, W // 2, 1250, "被平台限流的猫会趴下打盹，醒了再出门", font(28), LAVENDER)
    text_center(d, W // 2, 1300, "登录过期的猫，暂时不在岛上", font(28), LAVENDER)
    return img


def world_tall() -> Image.Image:
    W, H = 1080, 1440
    img = backdrop(W, H, stars=40, avoid=[(0, 0, W, H)])
    d = ImageDraw.Draw(img)
    text_center(d, W // 2, 70, "岛上的天，和你那边一样", font(52), CREAM)
    text_center(d, W // 2, 145, "天色、晴雨、季节都跟着你的城市走", font(30), PINK)
    y = 230
    for t, lab in [("beijing-dusk", "北京 · 傍晚"), ("rain-night", "雨夜"), ("winter-snow", "下雪"), ("event-meteor", "流星雨那晚，猫们一起看窗外")]:
        im = Image.open(SNAPS / f"{t}.png").convert("RGBA")
        im = im.resize((W - 120, int(im.height * (W - 120) / im.width)), Image.LANCZOS)
        fr = framed(im, radius=14, border=5)
        img.alpha_composite(fr, (36, y))
        d.text((70, y + fr.height - 6), lab, font=font(28), fill=CREAM)
        y += fr.height + 60
    return img


def local_tall() -> Image.Image:
    W, H = 1080, 1440
    img = backdrop(W, H, stars=60, avoid=[(40, 100, W - 40, 1380)])
    d = ImageDraw.Draw(img)
    ic = Image.open(ROOT / "assets/brand/icon-1024.png").resize((240, 240), Image.LANCZOS)
    img.alpha_composite(ic, ((W - 240) // 2, 150))
    t = pixel_text("catland", 22, 7, CREAM + (255,))
    img.alpha_composite(t, ((W - t.width) // 2, 430))
    text_center(d, W // 2, 610, "免费 · 开源 · 不商用", font(44), PINK)
    y = 740
    for l in ["没有服务器，不用注册账号", "点赞收藏只存在你自己的 Mac 上", "签名公证过，下载后双击就能打开", "老板来了，Option + Esc 一键收起"]:
        text_center(d, W // 2, y, l, font(34), CREAM)
        y += 72
    text_center(d, W // 2, 1110, "GitHub 搜 Aries-ld/catland", font(40), CREAM)
    text_center(d, W // 2, 1180, "macOS 14+ · Apple 芯片", font(28), LAVENDER)
    return img


def xhs_cover() -> Image.Image:
    W, H = 1080, 1440
    img = backdrop(W, H, stars=70, avoid=[(60, 120, W - 60, 420), (0, 440, W, H)])
    d = ImageDraw.Draw(img)
    text_center(d, W // 2, 150, "我在灵动岛里", font(64), CREAM)
    text_center(d, W // 2, 240, "养了四只猫", font(64), CREAM)
    text_center(d, W // 2, 350, "它们每天出门，把我爱看的东西叼回来", font(32), PINK)
    strip = island_strip(W - 80)
    img.alpha_composite(strip, (40, 480))
    y = 480 + strip.height + 80
    cw = W // 4
    for i, (skin, name, pid, *_rest) in enumerate(CATS):
        c = cat(skin, 0.75)
        img.alpha_composite(c, (i * cw + (cw - c.width) // 2, y))
        ic = icon(pid, 40)
        nm = font(30)
        tw = d.textlength(name, font=nm) + 48
        x = i * cw + (cw - tw) // 2
        img.alpha_composite(ic, (int(x), y + c.height + 14))
        d.text((x + 48, y + c.height + 16), name, font=nm, fill=CREAM)
    text_center(d, W // 2, 1330, "catland · 开源 · 纯本地 · Mac 免费下载", font(26), LAVENDER)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    how_wide("zh").convert("RGB").save(OUT / "how-zh-wide.png", optimize=True)
    how_wide("en").convert("RGB").save(OUT / "how-en-wide.png", optimize=True)
    how_tall().convert("RGB").save(OUT / "how-zh-tall.png", optimize=True)
    # Product Hunt（英文）
    how_wide("en", 1270, 760).convert("RGB").save(OUT / "ph-1.png", optimize=True)
    cats_card("en", 1270, 760).convert("RGB").save(OUT / "ph-2.png", optimize=True)
    world_card("en", 1270, 760).convert("RGB").save(OUT / "ph-3.png", optimize=True)
    local_card("en", 1270, 760).convert("RGB").save(OUT / "ph-4.png", optimize=True)
    Image.open(ROOT / "assets/brand/icon-1024.png").resize((240, 240), Image.LANCZOS).save(OUT / "ph-thumb.png")
    # 小红书（中文 3:4）
    xhs_cover().convert("RGB").save(OUT / "xhs-1.png", optimize=True)
    how_tall().convert("RGB").save(OUT / "xhs-2.png", optimize=True)
    cats_tall().convert("RGB").save(OUT / "xhs-3.png", optimize=True)
    world_tall().convert("RGB").save(OUT / "xhs-4.png", optimize=True)
    local_tall().convert("RGB").save(OUT / "xhs-5.png", optimize=True)
    # 中文横版（即刻 / 微博 / 朋友圈第二张）
    cats_card("zh", 1600, 900).convert("RGB").save(OUT / "cats-zh-wide.png", optimize=True)
    world_card("zh", 1600, 900).convert("RGB").save(OUT / "world-zh-wide.png", optimize=True)
    print("ok:", OUT)


if __name__ == "__main__":
    main()
