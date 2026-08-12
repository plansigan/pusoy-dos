# HelpModal.gd
# "Mga Balidong Baraha" — a scrollable reference of every legal play,
# lowest to highest, with real (non-interactive) CardUI examples, plus
# rank- and suit-order strips. The suit strip reads the ACTIVE ruleset
# from RulesManager so it always matches how the current game scores.
#
# Opened from GameTable (the "?" button and the quit dialog). The caller
# is responsible for pausing its AI loop while this is open; the modal
# just reports back through on_close.

class_name HelpModal
extends Control

const PANEL_SIZE = Vector2(680, 588)
const MINI = Vector2(44, 62)

# name, short description, example card codes (lowest to highest)
const PLAYS = [
	{"name": "Single", "desc": "One card", "cards": ["7H"]},
	{"name": "Pair", "desc": "Two cards of the same number", "cards": ["7H", "7S"]},
	{"name": "Three of a Kind", "desc": "Three cards of the same number", "cards": ["9D", "9H", "9S"]},
	{"name": "Straight", "desc": "Five numbers in a row", "cards": ["4C", "5D", "6H", "7S", "8D"]},
	{"name": "Flush", "desc": "Five cards of the same suit", "cards": ["3H", "6H", "9H", "JH", "KH"]},
	{"name": "Full House", "desc": "Three of a kind plus a pair", "cards": ["QC", "QD", "QH", "5S", "5D"]},
	{"name": "Four of a Kind", "desc": "Four of the same number plus one", "cards": ["8C", "8D", "8H", "8S", "2D"]},
	{"name": "Straight Flush", "desc": "In a row and one suit, the strongest hand", "cards": ["5S", "6S", "7S", "8S", "9S"]},
]

var _on_close: Callable
var _dim: ColorRect
var _panel: Panel
var _closing := false


static func open(parent: Node, on_close: Callable = Callable()) -> HelpModal:
	var modal = HelpModal.new()
	modal._on_close = on_close
	parent.add_child(modal)
	return modal


func _ready() -> void:
	UIFactory.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 130
	_build()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	UIFactory.fill_viewport(_dim)
	_dim.gui_input.connect(_on_dim_input)

	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 16))
	_panel.size = PANEL_SIZE
	_panel.position = get_viewport_rect().size / 2 - PANEL_SIZE / 2
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var title = UIFactory.make_label("Valid Hands", 24,
			ThemeManager.get_color("status_color"), Vector2(0, 18))
	title.size = Vector2(PANEL_SIZE.x, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(title)

	var subtitle = UIFactory.make_label("from weakest to strongest", 12,
			ThemeManager.get_color("text_muted"), Vector2(0, 48))
	subtitle.size = Vector2(PANEL_SIZE.x, 18)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(subtitle)

	_add_close_button()

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(24, 76)
	scroll.size = Vector2(PANEL_SIZE.x - 48, PANEL_SIZE.y - 100)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for i in PLAYS.size():
		list.add_child(_make_play_row(i + 1, PLAYS[i]))

	list.add_child(_make_rank_strip())
	list.add_child(_make_suit_strip())

	# Tail spacer so the final strip clears the scroll clip edge cleanly
	var tail = Control.new()
	tail.custom_minimum_size = Vector2(0, 6)
	list.add_child(tail)

	# Standard modal entrance (dim fade + panel rise/settle)
	_dim.color.a = 0.7
	TransitionManager.open_modal(_dim, _panel)


func _add_close_button() -> void:
	var btn = Button.new()
	btn.text = "✕"
	btn.position = Vector2(PANEL_SIZE.x - 46, 14)
	btn.size = Vector2(32, 32)
	btn.add_theme_font_size_override("font_size", 16)
	UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"), 4, 1)
	btn.pressed.connect(_close)
	_panel.add_child(btn)


func _make_play_row(number: int, play: Dictionary) -> Control:
	var row = PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIFactory.flat_style(
			ThemeManager.get_color("button_bg"), 8, 1, ThemeManager.get_color("border_soft")))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	row.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var text_col = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.add_theme_constant_override("separation", 4)
	hbox.add_child(text_col)

	var name_label = UIFactory.make_label("%d.  %s" % [number, play["name"]], 16,
			ThemeManager.get_color("text_on_light_primary"))
	text_col.add_child(name_label)
	var desc_label = UIFactory.make_label(String(play["desc"]), 12,
			ThemeManager.get_color("text_on_light_secondary"))
	text_col.add_child(desc_label)

	var cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 4)
	cards.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(cards)
	for code in play["cards"]:
		cards.add_child(_mini_card(String(code)))

	return row


# A real CardUI, shrunk and made compact so the rank/suit stay legible.
func _mini_card(code: String) -> CardUI:
	var card = Card.from_code(code)
	var card_ui = CardUI.new()
	card_ui.custom_minimum_size = MINI
	card_ui.size = MINI
	card_ui.pivot_offset = MINI / 2
	if card != null:
		card_ui.setup(card)
	# Reflow the labels for the smaller face
	card_ui.corner_label.add_theme_font_size_override("font_size", 11)
	card_ui.corner_label.position = Vector2(4, 2)
	card_ui.corner_label.size = Vector2(22, 28)
	card_ui.center_label.add_theme_font_size_override("font_size", 20)
	card_ui.center_label.position = Vector2(0, 18)
	card_ui.center_label.size = Vector2(MINI.x, 30)
	return card_ui


func _make_rank_strip() -> Control:
	var box = _strip_panel()
	var v = box.get_child(0).get_child(0)  # margin -> vbox
	v.add_child(UIFactory.make_label("Rank order", 13,
			ThemeManager.get_color("text_on_light_primary")))
	var ranks = ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2"]
	v.add_child(UIFactory.make_label("  ".join(ranks), 15,
			ThemeManager.get_color("text_on_light_primary")))
	v.add_child(UIFactory.make_label("3 is the lowest,  2 is the highest", 11,
			ThemeManager.get_color("text_on_light_secondary")))
	return box


func _make_suit_strip() -> Control:
	var box = _strip_panel()
	var v = box.get_child(0).get_child(0)
	var ruleset_name = RulesManager.RANKING_NAMES[RulesManager.suit_ranking]
	v.add_child(UIFactory.make_label("Suit order (%s)" % ruleset_name, 13,
			ThemeManager.get_color("text_on_light_primary")))

	# Weakest → strongest under the active ruleset
	var order: Array = RulesManager.SUIT_ORDER[RulesManager.suit_ranking]
	var strip = HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	for i in order.size():
		var suit = order[i]
		var sym = UIFactory.make_label(Card.SUIT_SYMBOLS[suit], 22,
				ThemeManager.get_suit_color(suit))
		strip.add_child(sym)
		if i < order.size() - 1:
			strip.add_child(UIFactory.make_label("<", 16,
					ThemeManager.get_color("text_on_light_secondary")))
	v.add_child(strip)
	v.add_child(UIFactory.make_label("weak to strong (when the rank ties)", 11,
			ThemeManager.get_color("text_on_light_secondary")))
	return box


func _strip_panel() -> PanelContainer:
	var box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIFactory.flat_style(
			ThemeManager.get_color("button_bg"), 8, 1, ThemeManager.get_color("selected")))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	box.add_child(margin)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	margin.add_child(v)
	return box


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	# Guard against double-close (X + ESC + dim-click landing together)
	if _closing or not is_inside_tree():
		return
	_closing = true
	set_process_unhandled_key_input(false)
	var callback = _on_close
	TransitionManager.close_modal(_dim, _panel, func():
		if is_instance_valid(self):
			queue_free()
		if callback.is_valid():
			callback.call())
