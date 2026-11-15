# dmgbuild settings for Point.dmg. Run via ./make-dmg.sh
app = defines["app"]  # noqa: F821 (injected by dmgbuild)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # noqa: F821
window_rect = ((200, 120), (560, 340))
default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
background = defines["bg"]  # noqa: F821
hide_extensions = ["Point.app"]
icon_locations = {"Point.app": (150, 150), "Applications": (410, 150)}
