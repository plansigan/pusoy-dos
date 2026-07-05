# UIFactory.gd
# Shared builders for the styleboxes and labels every screen was
# previously constructing by hand.

class_name UIFactory

static func flat_style(bg: Color, radius: int = 8, border_width: int = 0,
		border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	if border_width > 0:
		style.set_border_width_all(border_width)
		style.border_color = border_color
	return style


# Styles a button's normal/hover/pressed states so it doesn't fall back
# to Godot's default dark theme on interaction
static func style_button(btn: Button, bg: Color, border_color: Color, font_color: Color,
		radius: int = 4, border_width: int = 2) -> void:
	btn.add_theme_stylebox_override("normal", flat_style(bg, radius, border_width, border_color))
	btn.add_theme_stylebox_override("hover",
			flat_style(bg.lightened(0.08), radius, border_width, border_color.lightened(0.15)))
	btn.add_theme_stylebox_override("pressed",
			flat_style(bg.darkened(0.12), radius, border_width, border_color))
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.pressed.connect(func(): SoundManager.play("button_click"))


# Force a Control to fill the whole viewport. Our screen roots are
# small (40x40 in their .tscn) and everything is positioned absolutely,
# so overlays can't rely on anchors alone — size them explicitly.
static func fill_viewport(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if control.is_inside_tree():
		# Immediate size for same-frame reads; anchors keep it correct after
		control.set_deferred("size", control.get_viewport_rect().size)


static func make_label(text: String, font_size: int, color: Color,
		pos: Vector2 = Vector2.ZERO) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.position = pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
