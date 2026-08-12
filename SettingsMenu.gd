# SettingsMenu.gd
# Settings overlay — opens on top of MainMenu or GameTable, so BACK
# always returns to exactly where the player was.
#
# Usage:  SettingsMenu.open(self, _on_settings_closed)
# The callback receives one bool: whether the theme changed while open.

class_name SettingsMenu
extends Control

const PANEL_SIZE = Vector2(720, 500)

var on_close: Callable
var initial_theme: String
var panel: Panel

static func open(parent: Control, close_callback: Callable) -> SettingsMenu:
	var menu = SettingsMenu.new()
	menu.on_close = close_callback
	menu.initial_theme = ThemeManager.current_theme_key
	parent.add_child(menu)
	return menu


func _ready() -> void:
	UIFactory.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


# Rebuilt wholesale whenever a setting changes, so the overlay itself
# always renders in the current theme with current selections
func _build() -> void:
	for child in get_children():
		child.queue_free()

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	UIFactory.fill_viewport(dim)

	panel = Panel.new()
	panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 16))
	panel.size = PANEL_SIZE
	panel.position = get_viewport_rect().size / 2 - PANEL_SIZE / 2
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var title = UIFactory.make_label("SETTINGS", 26,
			ThemeManager.get_color("status_color"), Vector2(0, 20))
	title.size = Vector2(PANEL_SIZE.x, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	_build_theme_section()
	_build_sound_section()
	_build_pixel_section()
	_build_gameplay_section()
	_build_replay_tutorial_button()
	_build_back_button()


func _section_caption(text: String, y: float) -> void:
	panel.add_child(UIFactory.make_label(text, 12,
			ThemeManager.get_color("text_muted"), Vector2(28, y)))


# =============================================================
# THEME
# =============================================================

func _build_theme_section() -> void:
	_section_caption("THEME", 58)
	var themes = ThemeManager.get_theme_names()
	var card_w = 128.0
	var card_h = 92.0
	var spacing = 8.0
	var total = themes.size() * card_w + (themes.size() - 1) * spacing
	var start_x = (PANEL_SIZE.x - total) / 2

	for i in themes.size():
		var entry = themes[i]
		var selected = entry["key"] == ThemeManager.current_theme_key

		var btn = Button.new()
		btn.position = Vector2(start_x + i * (card_w + spacing), 78)
		btn.size = Vector2(card_w, card_h)
		UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
				ThemeManager.get_color("selected") if selected \
						else ThemeManager.get_color("border_soft"),
				ThemeManager.get_color("button_text"), 6, 3 if selected else 1)
		btn.pressed.connect(_on_theme_selected.bind(entry["key"]))
		panel.add_child(btn)

		# Long names get a deterministic line break (Godot's label
		# autowrap is unreliable for a manually-placed label). Anchored
		# into the fixed-size button so both lines stay centered.
		var display_name = entry["name"]
		if display_name.length() > 12:
			display_name = display_name.replace(" ", "\n")
		var name_label = UIFactory.make_label(display_name, 11,
				ThemeManager.get_color("button_text"))
		name_label.anchor_right = 1.0
		name_label.offset_left = 4
		name_label.offset_right = -4
		name_label.offset_top = 8
		name_label.offset_bottom = 48
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.add_child(name_label)

		# That theme's four suit colors as swatches
		var dot_size = 16.0
		var dot_x = (card_w - (4 * dot_size + 3 * 6.0)) / 2
		for s in 4:
			var dot = Panel.new()
			dot.position = Vector2(dot_x + s * (dot_size + 6.0), 60)
			dot.size = Vector2(dot_size, dot_size)
			dot.add_theme_stylebox_override("panel", UIFactory.flat_style(
					ThemeManager.THEMES[entry["key"]][ThemeManager.SUIT_KEYS[s]], 8))
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(dot)


func _on_theme_selected(theme_key: String) -> void:
	if theme_key == ThemeManager.current_theme_key:
		return
	ThemeManager.set_theme(theme_key)
	Settings.theme_key = theme_key
	Settings.save_settings()
	_build()


# =============================================================
# SOUND
# =============================================================

func _build_sound_section() -> void:
	_section_caption("SOUND", 184)
	var y = 204.0

	var toggle = Button.new()
	toggle.text = "SOUND: ON" if Settings.sound_enabled else "SOUND: OFF"
	toggle.position = Vector2(104, y)
	toggle.size = Vector2(150, 40)
	toggle.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(toggle, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected") if Settings.sound_enabled \
					else ThemeManager.get_color("border_soft"),
			ThemeManager.get_color("button_text"), 4,
			3 if Settings.sound_enabled else 1)
	toggle.pressed.connect(_on_sound_toggled)
	panel.add_child(toggle)

	var minus = Button.new()
	minus.text = "−"
	minus.position = Vector2(296, y)
	minus.size = Vector2(40, 40)
	UIFactory.style_button(minus, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"))
	minus.pressed.connect(_on_volume_changed.bind(-0.1))
	panel.add_child(minus)

	var blocks = roundi(Settings.volume * 10)
	var bar = UIFactory.make_label(
			"▮".repeat(blocks) + "▯".repeat(10 - blocks), 14,
			ThemeManager.get_color("status_color"), Vector2(348, y))
	bar.size = Vector2(220, 40)
	bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(bar)

	var plus = Button.new()
	plus.text = "+"
	plus.position = Vector2(576, y)
	plus.size = Vector2(40, 40)
	UIFactory.style_button(plus, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"))
	plus.pressed.connect(_on_volume_changed.bind(0.1))
	panel.add_child(plus)


func _on_sound_toggled() -> void:
	Settings.sound_enabled = not Settings.sound_enabled
	SoundManager.set_enabled(Settings.sound_enabled)
	Settings.save_settings()
	_build()


func _on_volume_changed(delta: float) -> void:
	Settings.volume = clampf(Settings.volume + delta, 0.0, 1.0)
	SoundManager.set_volume(Settings.volume)
	Settings.save_settings()
	SoundManager.play("card_play")  # audible feedback at the new volume
	_build()


# =============================================================
# PIXEL FX
# =============================================================

func _build_pixel_section() -> void:
	_section_caption("PIXEL FX", 256)
	var btn_w = 130.0
	var spacing = 12.0
	var start_x = (PANEL_SIZE.x - (4 * btn_w + 3 * spacing)) / 2

	for i in 4:
		var selected = Settings.pixel_level == i
		var btn = Button.new()
		btn.text = PixelFilter.LEVEL_NAMES[i]
		btn.position = Vector2(start_x + i * (btn_w + spacing), 276)
		btn.size = Vector2(btn_w, 40)
		btn.add_theme_font_size_override("font_size", 13)
		UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
				ThemeManager.get_color("selected") if selected \
						else ThemeManager.get_color("border_soft"),
				ThemeManager.get_color("selected") if selected \
						else ThemeManager.get_color("button_text"),
				4, 3 if selected else 1)
		btn.pressed.connect(_on_pixel_level_selected.bind(i))
		panel.add_child(btn)


func _on_pixel_level_selected(level: int) -> void:
	Settings.pixel_level = level
	Settings.save_settings()
	PixelFilter.apply_level(level)  # takes effect immediately, overlay included
	_build()


# =============================================================
# GAMEPLAY
# =============================================================

func _build_gameplay_section() -> void:
	_section_caption("GAMEPLAY", 328)
	var y = 348.0
	var btn_w = 170.0
	var spacing = 12.0
	var start_x = (PANEL_SIZE.x - (3 * btn_w + 2 * spacing)) / 2

	var hints = Button.new()
	hints.text = "HINTS: ON" if Settings.show_hints else "HINTS: OFF"
	hints.position = Vector2(start_x, y)
	hints.size = Vector2(btn_w, 40)
	hints.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(hints, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected") if Settings.show_hints \
					else ThemeManager.get_color("border_soft"),
			ThemeManager.get_color("button_text"), 4,
			3 if Settings.show_hints else 1)
	hints.pressed.connect(_on_hints_toggled)
	panel.add_child(hints)

	# Suit ranking: Filipino (2♦ high) vs Big Two (2♠ high)
	for i in 2:
		var selected = Settings.suit_ranking == i
		var btn = Button.new()
		btn.text = RulesManager.RANKING_NAMES[i]
		btn.position = Vector2(start_x + (i + 1) * (btn_w + spacing), y)
		btn.size = Vector2(btn_w, 40)
		btn.add_theme_font_size_override("font_size", 12)
		UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
				ThemeManager.get_color("selected") if selected \
						else ThemeManager.get_color("border_soft"),
				ThemeManager.get_color("selected") if selected \
						else ThemeManager.get_color("button_text"),
				4, 3 if selected else 1)
		btn.pressed.connect(_on_ranking_selected.bind(i))
		panel.add_child(btn)

	# A ranking picked mid-game is only applied when the next game starts
	if RulesManager.suit_ranking != Settings.suit_ranking:
		var note = UIFactory.make_label("suit ranking applies to the next game", 11,
				ThemeManager.get_color("status_color"), Vector2(0, 392))
		note.size = Vector2(PANEL_SIZE.x, 14)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(note)


func _on_hints_toggled() -> void:
	Settings.show_hints = not Settings.show_hints
	Settings.save_settings()
	_build()


func _on_ranking_selected(value: int) -> void:
	Settings.suit_ranking = value
	Settings.save_settings()
	_build()


# =============================================================
# BACK
# =============================================================

func _build_replay_tutorial_button() -> void:
	var btn = Button.new()
	btn.text = "↺ Replay Tutorial"
	btn.position = Vector2(40, 418)
	btn.size = Vector2(196, 44)
	btn.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"))
	btn.pressed.connect(_on_replay_tutorial)
	panel.add_child(btn)


func _on_replay_tutorial() -> void:
	# Works whether Settings was opened over the menu or a live game — the
	# scene swap replaces whatever is underneath with a fresh tutorial match.
	GameSession.mode = GameSession.Mode.TUTORIAL
	TransitionManager.change_scene("res://GameTable.tscn")


func _build_back_button() -> void:
	var btn = Button.new()
	btn.text = "◀ BACK"
	btn.position = Vector2((PANEL_SIZE.x - 160) / 2, 418)
	btn.size = Vector2(160, 44)
	btn.add_theme_font_size_override("font_size", 14)
	UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected"), ThemeManager.get_color("button_text"))
	btn.pressed.connect(_on_back)
	panel.add_child(btn)


func _on_back() -> void:
	var theme_changed = ThemeManager.current_theme_key != initial_theme
	var callback = on_close
	queue_free()
	if callback.is_valid():
		callback.call(theme_changed)
