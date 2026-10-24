class_name UIKit
extends RefCounted
## Shared look for every menu and panel: dark glass, thin borders, readable
## type at 1080p on a seven-inch screen.

const BG := Color(0.055, 0.062, 0.075, 0.90)
const BG_SOFT := Color(0.08, 0.09, 0.11, 0.78)
const BORDER := Color(0.42, 0.58, 0.62, 0.55)
const ACCENT := Color(0.62, 0.92, 0.82)
const WARN := Color(1.0, 0.72, 0.36)
const BAD := Color(1.0, 0.42, 0.38)
const TEXT := Color(0.90, 0.94, 0.96)
const TEXT_DIM := Color(0.62, 0.68, 0.72)
const FONT_BODY := 32
const FONT_SMALL := 24
const FONT_TITLE := 56


static func style_panel(bg: Color = BG, border: Color = BORDER, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


static func style_box(bg: Color, border: Color, radius: int = 8, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	node.add_theme_constant_override("outline_size", 3)
	return node


static func button(text: String, size: int = FONT_BODY) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	node.add_theme_color_override("font_focus_color", ACCENT)
	node.add_theme_stylebox_override("normal", style_box(Color(0.12, 0.14, 0.17, 0.95), Color(0.30, 0.38, 0.42, 0.9)))
	node.add_theme_stylebox_override("hover", style_box(Color(0.17, 0.21, 0.24, 0.98), BORDER))
	node.add_theme_stylebox_override("pressed", style_box(Color(0.22, 0.30, 0.31, 1.0), ACCENT))
	node.add_theme_stylebox_override("focus", style_box(Color(0.16, 0.20, 0.23, 1.0), ACCENT, 8, 3))
	node.add_theme_stylebox_override("disabled", style_box(Color(0.10, 0.10, 0.12, 0.7), Color(0.2, 0.22, 0.24, 0.6)))
	node.focus_mode = Control.FOCUS_ALL
	node.custom_minimum_size = Vector2(0, 58)
	return node


static func panel_container(bg: Color = BG, border: Color = BORDER) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style_panel(bg, border))
	return panel


static func vbox(separation: int = 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation: int = 10) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func separator() -> HSeparator:
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", style_box(Color(0, 0, 0, 0), Color(0.35, 0.45, 0.48, 0.6), 0, 1))
	line.custom_minimum_size = Vector2(0, 12)
	return line


static func progress_bar(color: Color = ACCENT) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.max_value = 1.0
	bar.step = 0.001
	bar.add_theme_stylebox_override("background", style_box(Color(0.08, 0.09, 0.1, 0.9), Color(0.25, 0.30, 0.33, 0.8), 7, 1))
	bar.add_theme_stylebox_override("fill", style_box(color, color, 7, 0))
	return bar


static func spacer(height: int = 12) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node


static func full_rect(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0


static func color_for_tone(tone: String) -> Color:
	match tone:
		"good", "clue":
			return ACCENT
		"bad":
			return BAD
		"warn":
			return WARN
		_:
			return TEXT
