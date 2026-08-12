# MainMenu.gd
extends Control

func _ready() -> void:
	# Load + validate story/character content once at boot so any bad
	# file is reported early (it never blocks the menu).
	ContentManager.load_all()
	await get_tree().process_frame
	_build_layout()
	# Returning from a finished story chapter / puzzle reopens that list
	# (only if the feature is still enabled).
	if GameSession.return_to_story:
		GameSession.return_to_story = false
		if FeatureFlags.is_enabled("story"):
			StoryScreen.open(self)
	elif GameSession.return_to_puzzles:
		GameSession.return_to_puzzles = false
		if FeatureFlags.is_enabled("puzzles"):
			PuzzleScreen.open(self)
	elif not Settings.tutorial_completed:
		# First launch: offer Lolo Carding's guided match. Its own entry
		# path — works even while Story is still feature-flagged off.
		_show_tutorial_prompt()


func _build_layout() -> void:
	var sw = get_viewport_rect().size.x
	var sh = get_viewport_rect().size.y

	_add_background(sw, sh)
	_add_corner_accents(sw, sh)
	_add_floating_suits(sw, sh)
	_add_title(sw, sh)
	_add_menu_buttons(sw, sh)
	_add_version_label(sw, sh)


func _add_background(sw: float, sh: float) -> void:
	var bg = ColorRect.new()
	bg.color = ThemeManager.get_color("table_bg")
	bg.size = Vector2(sw, sh)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _add_corner_accents(sw: float, sh: float) -> void:
	var size = 40
	var thickness = 3

	# Top-left — hearts color
	_add_corner_line(Vector2(0, 0), Vector2(size, 0), thickness, ThemeManager.get_color("hearts"))
	_add_corner_line(Vector2(0, 0), Vector2(0, size), thickness, ThemeManager.get_color("hearts"))

	# Top-right — spades color
	_add_corner_line(Vector2(sw - size, 0), Vector2(sw, 0), thickness, ThemeManager.get_color("spades"))
	_add_corner_line(Vector2(sw, 0), Vector2(sw, size), thickness, ThemeManager.get_color("spades"))

	# Bottom-left — diamonds color
	_add_corner_line(Vector2(0, sh - size), Vector2(0, sh), thickness, ThemeManager.get_color("diamonds"))
	_add_corner_line(Vector2(0, sh), Vector2(size, sh), thickness, ThemeManager.get_color("diamonds"))

	# Bottom-right — clubs color
	_add_corner_line(Vector2(sw - size, sh), Vector2(sw, sh), thickness, ThemeManager.get_color("clubs"))
	_add_corner_line(Vector2(sw, sh - size), Vector2(sw, sh), thickness, ThemeManager.get_color("clubs"))


func _add_corner_line(from: Vector2, to: Vector2, thickness: int, color: Color) -> void:
	var line = Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = thickness
	line.default_color = color
	add_child(line)


func _add_floating_suits(sw: float, sh: float) -> void:
	var suits = [
		{"suit": Card.Suit.HEARTS, "pos": Vector2(sw * 0.12, sh * 0.15), "rot": -15},
		{"suit": Card.Suit.SPADES, "pos": Vector2(sw * 0.82, sh * 0.18), "rot": 10},
		{"suit": Card.Suit.CLUBS, "pos": Vector2(sw * 0.08, sh * 0.78), "rot": 20},
		{"suit": Card.Suit.DIAMONDS, "pos": Vector2(sw * 0.85, sh * 0.75), "rot": -8},
	]
	for s in suits:
		var color: Color = ThemeManager.get_suit_color(s["suit"])
		color.a = 0.08
		var label = UIFactory.make_label(Card.SUIT_SYMBOLS[s["suit"]], 64, color, s["pos"])
		label.rotation_degrees = s["rot"]
		add_child(label)


func _add_title(sw: float, sh: float) -> void:
	var center_x = sw / 2

	var presents = UIFactory.make_label("·  presents  ·", 12, ThemeManager.get_color("text_muted"),
			Vector2(center_x - 60, sh * 0.18))
	presents.size = Vector2(120, 20)
	presents.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(presents)

	for i in 2:
		var base_y = sh * 0.21 + i * 50
		var title = UIFactory.make_label(["PUSOY", "DOS"][i], 48,
				ThemeManager.get_color("text_primary"),
				Vector2(center_x - 140, base_y))
		title.size = Vector2(280, 60)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(title)
		_start_title_float(title, base_y)

	var edition = UIFactory.make_label(
			"[ %s EDITION ]" % ThemeManager.current_theme_name().to_upper(), 11,
			ThemeManager.get_color("diamonds"), Vector2(center_x - 100, sh * 0.21 + 110))
	edition.size = Vector2(200, 20)
	edition.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(edition)


# A very slow, gentle vertical drift so the title feels alive without
# pulling the eye. Both title words share timing, so they move as one.
# The loop starts and ends on base_y, so it repeats seamlessly.
func _start_title_float(label: Label, base_y: float) -> void:
	var t = label.create_tween().set_loops()
	t.tween_property(label, "position:y", base_y - 3.0, 1.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(label, "position:y", base_y + 3.0, 2.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(label, "position:y", base_y, 1.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _add_menu_buttons(sw: float, sh: float) -> void:
	var center_x = sw / 2
	var btn_width = 240
	var btn_height = 40
	var spacing = 10
	var start_y = sh * 0.44

	var buttons_data = [
		{"text": "▶  PLAY", "highlighted": true, "callback": _on_play_pressed},
		{"text": "📖  STORY", "highlighted": false, "callback": _on_story_pressed, "feature": "story"},
		{"text": "🧩  PUZZLES", "highlighted": false, "callback": _on_puzzles_pressed, "feature": "puzzles"},
		{"text": "📊  STATS", "highlighted": false, "callback": _on_stats_pressed},
		{"text": "⚙  SETTINGS", "highlighted": false, "callback": _on_settings_pressed},
		{"text": "✕  QUIT", "highlighted": false, "callback": _on_quit_pressed},
	]

	for i in buttons_data.size():
		var data = buttons_data[i]
		var feature = String(data.get("feature", ""))
		var locked = feature != "" and not FeatureFlags.is_enabled(feature)

		var btn = Button.new()
		btn.text = data["text"]
		btn.position = Vector2(center_x - btn_width / 2, start_y + i * (btn_height + spacing))
		btn.size = Vector2(btn_width, btn_height)

		var border_color = ThemeManager.get_color("selected") if data["highlighted"] \
				else ThemeManager.get_color("border_soft")
		var font_color = ThemeManager.get_color("selected") if data["highlighted"] \
				else ThemeManager.get_color("button_text")
		UIFactory.style_button(btn, ThemeManager.get_color("button_bg"), border_color, font_color)
		btn.add_theme_font_size_override("font_size", 14)

		var delay = i * TransitionManager.STAGGER

		# Locked feature: dim the button (still clickable → toast) and tag it
		if locked:
			var tag = UIFactory.make_label("COMING SOON", 10,
					ThemeManager.get_color("status_color"),
					Vector2(btn.position.x + btn_width + 12, btn.position.y + 12))
			tag.size = Vector2(120, 16)
			add_child(tag)
			TransitionManager.fade_in(tag, delay, 1.0)

		add_child(btn)
		btn.pressed.connect(data["callback"])
		# Staggered slide-up + fade as the menu opens (locked buttons rest at 0.5)
		TransitionManager.fade_in(btn, delay, 0.5 if locked else 1.0)


func _add_version_label(sw: float, sh: float) -> void:
	var label = UIFactory.make_label("v0.1.0  ·  made with Godot 4", 10,
			ThemeManager.get_color("text_muted"), Vector2(sw / 2 - 100, sh - 30))
	label.size = Vector2(200, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_play_pressed() -> void:
	ModeSelect.open(self)


func _on_stats_pressed() -> void:
	StatsScreen.open(self)


func _on_story_pressed() -> void:
	if FeatureFlags.is_enabled("story"):
		StoryScreen.open(self)
	else:
		_show_toast("Story Mode is coming in a free update!")


func _on_puzzles_pressed() -> void:
	if FeatureFlags.is_enabled("puzzles"):
		PuzzleScreen.open(self)
	else:
		_show_toast("Puzzle Mode is coming in a free update!")


func _on_settings_pressed() -> void:
	SettingsMenu.open(self, _on_settings_closed)


func _on_settings_closed(theme_changed: bool) -> void:
	# No game is running here, so a new suit ranking can apply right away
	RulesManager.set_ranking(Settings.suit_ranking)
	if theme_changed:
		for child in get_children():
			child.queue_free()
		await get_tree().process_frame
		_build_layout()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _show_toast(text: String) -> void:
	var sw = get_viewport_rect().size.x
	var sh = get_viewport_rect().size.y
	var toast = UIFactory.make_label(text, 14, ThemeManager.get_color("status_color"),
			Vector2(sw / 2 - 210, sh * 0.85))
	toast.size = Vector2(420, 30)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast)

	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(toast):
		toast.queue_free()


# =============================================================
# FIRST-LAUNCH TUTORIAL PROMPT
# =============================================================

func _show_tutorial_prompt() -> void:
	var overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 60
	add_child(overlay)
	UIFactory.fill_viewport(overlay)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	UIFactory.fill_viewport(dim)

	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 16))
	panel.size = Vector2(480, 236)
	panel.position = get_viewport_rect().size / 2 - panel.size / 2
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(panel)

	var title = UIFactory.make_label("New here? 👋", 24,
			ThemeManager.get_color("status_color"), Vector2(0, 26))
	title.size = Vector2(panel.size.x, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var body = UIFactory.make_label(
			"Lolo Carding can show you how to play Pusoy Dos.",
			14, ThemeManager.get_color("text_soft"))
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 34
	body.offset_top = 72
	body.offset_right = -34
	body.offset_bottom = -84
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(body)

	var start = Button.new()
	start.text = "Teach me"
	start.position = Vector2(40, 172)
	start.size = Vector2(200, 46)
	start.add_theme_font_size_override("font_size", 14)
	UIFactory.style_button(start, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected"), ThemeManager.get_color("button_text"))
	start.pressed.connect(_start_tutorial)
	panel.add_child(start)

	var skip = Button.new()
	skip.text = "I know how"
	skip.position = Vector2(240, 172)
	skip.size = Vector2(200, 46)
	skip.add_theme_font_size_override("font_size", 14)
	UIFactory.style_button(skip, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"))
	skip.pressed.connect(_skip_tutorial.bind(overlay))
	panel.add_child(skip)


func _start_tutorial() -> void:
	GameSession.mode = GameSession.Mode.TUTORIAL
	TransitionManager.change_scene("res://GameTable.tscn")


func _skip_tutorial(overlay: Control) -> void:
	# Never auto-prompt again; the player can still replay from Settings.
	Settings.tutorial_completed = true
	Settings.save_settings()
	if is_instance_valid(overlay):
		overlay.queue_free()
