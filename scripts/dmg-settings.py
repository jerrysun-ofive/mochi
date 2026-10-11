# dmgbuild settings. Invoke with: dmgbuild -s dmg-settings.py -D app=/path/Mochi.app -D root=<repo> Mochi out.dmg
# Window size and icon positions must match scripts/make-dmg-background.py.

import os.path

app = defines["app"]  # noqa: F821
root = defines["root"]  # noqa: F821
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]
icon = os.path.join(root, "Packaging", "AppIcon.icns")

background = os.path.join(root, "Packaging", "dmg-background.png")
# The window height includes the title bar and, when the user has it enabled, Finder's path bar.
window_rect = ((200, 140), (660, 480))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    app_name: (170, 196),
    "Applications": (490, 196),
}
