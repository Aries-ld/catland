# dmgbuild 的配置：DMG 打开后的安装窗口（背景图、图标位置、卷图标）。
# 由 scripts/package-dmg.sh 调用：dmgbuild -s packaging/dmg_settings.py -D app=<Catland.app 路径> "catland" <输出.dmg>
import os.path

application = defines.get("app", "Catland.app")  # noqa: F821  (dmgbuild 注入 defines)
appname = os.path.basename(application)
here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else "packaging"

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
size = None

files = [application]
symlinks = {"Applications": "/Applications"}
hide_extension = [appname]

icon = os.path.join(application, "Contents/Resources/AppIcon.icns")  # 挂载后卷的图标
background = os.path.join(here, "dmg-background.tiff")

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 160), (660, 400))
default_view = "icon-view"
show_icon_preview = False
arrange_by = None
icon_size = 112
text_size = 13
icon_locations = {appname: (170, 196), "Applications": (490, 196)}
