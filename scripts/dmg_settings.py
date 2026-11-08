# Einstellungen für dmgbuild (scripts/make_dmg.sh)
import os.path

app = defines.get("app", "build/Filmbibliothek.app")  # noqa: F821 (von dmgbuild bereitgestellt)
background = defines.get("background", "Resources/DMG/background.png")  # noqa: F821
readme = defines.get("readme", "docs/Installation – bitte lesen.txt")  # noqa: F821
app_name = os.path.basename(app)
readme_name = os.path.basename(readme)

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [app, readme]
symlinks = {"Applications": "/Applications"}
icon_locations = {app_name: (165, 200), "Applications": (495, 200), readme_name: (330, 300)}
window_rect = ((200, 120), (660, 400))
icon_size = 112
text_size = 12
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
