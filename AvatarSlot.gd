# AvatarSlot.gd
# One opponent's HUD: circular avatar (initials now, portrait later via
# set_portrait), a small fan of face-down mini cards, the card count,
# name, and a "thinking..." badge. Active player pulses gently.

class_name AvatarSlot
extends Control

const CIRCLE_SIZE = 56.0
const MINI_SIZE = Vector2(18, 26)

var circle_style: StyleBoxFlat
var initials_label: Label
var portrait_rect: TextureRect
var count_label: Label
var name_label: Label
var thinking_label: Label
var minis: Array = []

var idle_accent: Color        # border color when not the active player
var _pulse: Tween = null

func _init(display_name: String = "", initials: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(CIRCLE_SIZE / 2, CIRCLE_SIZE / 2)  # pulse around the circle
	idle_accent = ThemeManager.get_color("border_soft")

	# Circular avatar — a Panel with corner radius = half its size
	var circle = Panel.new()
	circle.size = Vector2(CIRCLE_SIZE, CIRCLE_SIZE)
	circle_style = UIFactory.flat_style(ThemeManager.get_color("panel_bg"),
			int(CIRCLE_SIZE / 2), 3, ThemeManager.get_color("border_soft"))
	circle.add_theme_stylebox_override("panel", circle_style)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(circle)

	# Placeholder initials — hidden once a portrait texture is set
	initials_label = UIFactory.make_label(initials, 17,
			ThemeManager.get_color("text_soft"))
	initials_label.size = Vector2(CIRCLE_SIZE, CIRCLE_SIZE)
	initials_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circle.add_child(initials_label)

	# Portrait slot for later (story mode pixel art goes here)
	portrait_rect = TextureRect.new()
	portrait_rect.position = Vector2(4, 4)
	portrait_rect.size = Vector2(CIRCLE_SIZE - 8, CIRCLE_SIZE - 8)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_SCALE
	portrait_rect.visible = false
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.add_child(portrait_rect)

	# Mini fan of face-down cards to the right of the circle
	for j in 3:
		var mini = Panel.new()
		mini.size = MINI_SIZE
		mini.position = Vector2(66 + j * 11, 16)
		mini.pivot_offset = Vector2(MINI_SIZE.x / 2, MINI_SIZE.y)
		mini.rotation_degrees = -12 + j * 12
		mini.add_theme_stylebox_override("panel", UIFactory.flat_style(
				ThemeManager.get_color("card_back"), 3, 1,
				ThemeManager.get_color("border_soft")))
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(mini)
		minis.append(mini)

	count_label = UIFactory.make_label("13", 22,
			ThemeManager.get_color("text_soft"), Vector2(108, 14))
	count_label.size = Vector2(40, 30)
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(count_label)

	name_label = UIFactory.make_label(display_name, 11,
			ThemeManager.get_color("text_soft"), Vector2(-22, 60))
	name_label.size = Vector2(100, 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(name_label)

	thinking_label = UIFactory.make_label("thinking...", 10,
			ThemeManager.get_color("status_color"), Vector2(-22, 77))
	thinking_label.size = Vector2(100, 14)
	thinking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thinking_label.visible = false
	add_child(thinking_label)


# Global center of the avatar circle — flight target for dealt cards,
# flight origin for cards this opponent plays
func global_circle_center() -> Vector2:
	return global_position + Vector2(CIRCLE_SIZE / 2, CIRCLE_SIZE / 2)


func set_portrait(texture: Texture2D) -> void:
	portrait_rect.texture = texture
	portrait_rect.visible = texture != null
	initials_label.visible = texture == null


# Story seats: relabel with a character's name/initials.
func set_identity(display_name: String, initials_text: String) -> void:
	name_label.text = display_name
	initials_label.text = initials_text


# A subtle accent (character theme_color) on the idle border — used to
# mark the rival seat.
func set_accent(color: Color) -> void:
	idle_accent = color
	if _pulse == null:  # only when not currently pulsing as active
		circle_style.border_color = color


func set_count(count: int) -> void:
	count_label.text = str(count)
	for j in minis.size():
		minis[j].visible = j < mini(3, count)


func set_thinking(value: bool) -> void:
	thinking_label.visible = value


func set_active(active: bool) -> void:
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	scale = Vector2.ONE

	var highlight = ThemeManager.get_color("status_color")
	circle_style.border_color = highlight if active else idle_accent

	if active:
		# Gentle breathing pulse on the circle + border glow
		_pulse = create_tween().set_loops()
		_pulse.tween_property(self, "scale", Vector2(1.06, 1.06), 0.45) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse.parallel().tween_property(circle_style, "border_color",
				highlight.lightened(0.35), 0.45)
		_pulse.chain().tween_property(self, "scale", Vector2.ONE, 0.45) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse.parallel().tween_property(circle_style, "border_color", highlight, 0.45)

	var text_color = highlight if active else ThemeManager.get_color("text_soft")
	name_label.add_theme_color_override("font_color", text_color)
	count_label.add_theme_color_override("font_color", text_color)
