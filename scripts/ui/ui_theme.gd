extends RefCounted
## Shared look for every menu and HUD element.

const ACCENT := Color(0.98, 0.72, 0.25)
const TEXT := Color(0.96, 0.95, 0.92)
const MUTED := Color(0.72, 0.74, 0.8)
const PANEL := Color(0.11, 0.12, 0.18, 0.92)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", TEXT)
	theme.set_constant("outline_size", "Label", 0)

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, 16, 22))

	theme.set_stylebox("normal", "Button", _box(Color(0.24, 0.27, 0.38), 10, 12))
	theme.set_stylebox("hover", "Button", _box(Color(0.32, 0.36, 0.5), 10, 12))
	theme.set_stylebox("pressed", "Button", _box(ACCENT.darkened(0.2), 10, 12))
	theme.set_stylebox("disabled", "Button", _box(Color(0.2, 0.21, 0.26), 10, 12))
	theme.set_stylebox("focus", "Button", _outline())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color(1, 1, 1))
	theme.set_color("font_pressed_color", "Button", Color(0.1, 0.1, 0.12))
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))

	theme.set_stylebox("normal", "LineEdit", _box(Color(0.06, 0.07, 0.1), 8, 10))
	theme.set_stylebox("focus", "LineEdit", _outline())
	theme.set_color("font_color", "LineEdit", TEXT)

	var bar_bg := _box(Color(0.06, 0.07, 0.1, 0.9), 8, 0)
	var bar_fill := _box(Color(0.4, 0.85, 0.45), 8, 0)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	return theme


static func _box(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin * 0.6
	box.content_margin_bottom = margin * 0.6
	return box


static func _outline() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	return box


static func label(text: String, size := 20, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func outlined(text: String, size := 22, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l
