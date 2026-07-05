# CardUI.gd
# Visual card node. Pure display — input and fan positioning are
# handled by HandFan, which owns rotated hit detection.
class_name CardUI
extends Panel

const CARD_SIZE = Vector2(72, 100)

var card_data: Card = null
var is_selected: bool = false

# One stylebox per card, reused — selection only swaps its border color
var style: StyleBoxFlat
var corner_label: Label
var center_label: Label

func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = Vector2(CARD_SIZE.x / 2, CARD_SIZE.y)  # fan rotates around bottom-center
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	style = UIFactory.flat_style(ThemeManager.get_color("card_bg"), 4, 2,
			ThemeManager.get_color("card_border"))
	add_theme_stylebox_override("panel", style)

	# Top left rank + suit, stacked
	corner_label = UIFactory.make_label("", 14, Color.WHITE, Vector2(6, 4))
	corner_label.size = Vector2(36, 44)
	add_child(corner_label)

	# Center big suit
	center_label = UIFactory.make_label("", 32, Color.WHITE, Vector2(0, 30))
	center_label.size = Vector2(72, 50)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(center_label)


func setup(c: Card) -> void:
	card_data = c
	style.bg_color = ThemeManager.get_color("card_bg")
	var color = ThemeManager.get_suit_color(c.suit)
	corner_label.text = c.rank + "\n" + c.suit_symbol()
	corner_label.add_theme_color_override("font_color", color)
	center_label.text = c.suit_symbol()
	center_label.add_theme_color_override("font_color", color)


# Card back — used for cards flying to opponents during the deal
func setup_back() -> void:
	card_data = null
	style.bg_color = ThemeManager.get_color("card_back")
	corner_label.text = ""
	center_label.text = "❖"
	center_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))


# Border highlight only — the pop out of the fan is HandFan's job
func set_selected(value: bool) -> void:
	is_selected = value
	style.border_color = ThemeManager.get_color("selected") if is_selected \
			else ThemeManager.get_color("card_border")
