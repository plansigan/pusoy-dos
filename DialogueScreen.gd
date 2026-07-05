# DialogueScreen.gd
# Visual-novel scene player for story intro/win/lose scenes and for the
# short modal mini-dialogues fired by match events.
#
# Line formats (from content JSON):
#   { "speaker": "<id>", "emotion": "smug", "text": "..." }
#   { "speaker": "player", "text": "..." }   -> silent "You", no portrait
#   { "pause": 1.0 }
#   { "narration": "..." }                   -> italic, centered, no portrait
#
# Click / Space / Enter: first press completes the current line's
# typewriter instantly, the next press advances.

class_name DialogueScreen
extends Control

const TYPE_CPS := 30.0   # typewriter characters per second

var _lines: Array = []
var _index: int = -1
var _on_done: Callable
var _modal: bool = false

var _typing: bool = false
var _full_text: String = ""
var _shown_chars: float = 0.0
var _paused: bool = false

# nodes
var portrait_holder: Control
var portrait_rect: TextureRect
var portrait_fallback: Panel
var portrait_initials: Label
var nameplate: Label
var text_panel: Panel
var text_label: Label
var narration_label: Label
var continue_hint: Label
var skip_button: Button


static func play(parent: Node, lines: Array, on_done: Callable,
		modal: bool = false, allow_skip: bool = true) -> DialogueScreen:
	var screen = DialogueScreen.new()
	screen._lines = lines
	screen._on_done = on_done
	screen._modal = modal
	parent.add_child(screen)
	screen._build(allow_skip)
	screen._advance()
	return screen


func _build(allow_skip: bool) -> void:
	UIFactory.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# A distinct darker backdrop so a story scene reads clearly as its
	# own screen, not the bright menu table. Modal events dim instead.
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72) if _modal else ThemeManager.get_color("table_bg").darkened(0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	UIFactory.fill_viewport(bg)

	if not _modal:
		# Faint oversized suit for flavor
		var accent = UIFactory.make_label("♠", 260, ThemeManager.get_color("status_color"))
		var accent_color = ThemeManager.get_color("status_color")
		accent_color.a = 0.06
		accent.add_theme_color_override("font_color", accent_color)
		accent.position = Vector2(BASE_W() - 300, 40)
		add_child(accent)

	# Portrait area (left-center)
	portrait_holder = Control.new()
	portrait_holder.position = Vector2(150, 70)
	portrait_holder.size = Vector2(300, 360)
	portrait_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait_holder)

	portrait_rect = TextureRect.new()
	portrait_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.visible = false
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(portrait_rect)

	# Fallback: a themed circle with initials when there's no art
	portrait_fallback = Panel.new()
	portrait_fallback.size = Vector2(200, 200)
	portrait_fallback.position = Vector2(50, 80)
	portrait_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(portrait_fallback)
	portrait_initials = UIFactory.make_label("", 64, ThemeManager.get_color("text_soft"))
	portrait_initials.size = Vector2(200, 200)
	portrait_initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_fallback.add_child(portrait_initials)

	# Nameplate
	nameplate = UIFactory.make_label("", 22, ThemeManager.get_color("status_color"),
			Vector2(90, 440))
	nameplate.size = Vector2(600, 28)
	add_child(nameplate)

	# Text box (bottom third)
	text_panel = Panel.new()
	text_panel.position = Vector2(80, 474)
	text_panel.size = Vector2(BASE_W() - 160, 150)
	text_panel.add_theme_stylebox_override("panel", UIFactory.flat_style(
			ThemeManager.get_color("panel_bg"), 12, 2, ThemeManager.get_color("border_soft")))
	text_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_panel)

	# Anchored into the fixed-size panel so autowrap has a real width to
	# wrap against (a free Label just grows to its text and overflows)
	text_label = UIFactory.make_label("", 17, ThemeManager.get_color("text_primary"))
	text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_label.offset_left = 24
	text_label.offset_top = 14
	text_label.offset_right = -24
	text_label.offset_bottom = -14
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_panel.add_child(text_label)

	# Narration reuses the text box area, centered
	narration_label = UIFactory.make_label("", 17, ThemeManager.get_color("text_secondary"))
	narration_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	narration_label.offset_left = 24
	narration_label.offset_top = 14
	narration_label.offset_right = -24
	narration_label.offset_bottom = -14
	narration_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	narration_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	narration_label.visible = false
	text_panel.add_child(narration_label)

	continue_hint = UIFactory.make_label("▸", 16, ThemeManager.get_color("text_muted"),
			Vector2(text_panel.size.x - 40, text_panel.size.y - 32))
	continue_hint.visible = false
	text_panel.add_child(continue_hint)

	if allow_skip:
		skip_button = Button.new()
		skip_button.text = "Skip ▸▸"
		skip_button.position = Vector2(BASE_W() - 130, 20)
		skip_button.size = Vector2(110, 34)
		skip_button.add_theme_font_size_override("font_size", 13)
		UIFactory.style_button(skip_button, ThemeManager.get_color("button_bg"),
				ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"), 4, 1)
		skip_button.pressed.connect(_on_skip)
		add_child(skip_button)


func BASE_W() -> float:
	return get_viewport_rect().size.x if is_inside_tree() else 1152.0


# =============================================================
# FLOW
# =============================================================

func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish()
		return

	var line = _lines[_index]

	if line.has("pause"):
		_show_blank()
		_run_pause(float(line["pause"]))
		return

	if line.has("narration"):
		_show_narration(String(line["narration"]))
		return

	# Dialogue / player line
	var speaker = String(line.get("speaker", ""))
	var emotion = String(line.get("emotion", "neutral"))
	var text = String(line.get("text", ""))
	if speaker == "player":
		_show_player_line(text)
	else:
		_show_character_line(speaker, emotion, text)


func _run_pause(seconds: float) -> void:
	_paused = true
	continue_hint.visible = false
	await get_tree().create_timer(maxf(0.1, seconds)).timeout
	if not is_inside_tree():
		return
	_paused = false
	_advance()


func _show_blank() -> void:
	_typing = false
	text_label.text = ""
	narration_label.visible = false
	nameplate.text = ""
	portrait_holder.visible = false


func _show_narration(text: String) -> void:
	portrait_holder.visible = false
	nameplate.text = ""
	text_label.visible = false
	narration_label.visible = true
	_begin_typing(narration_label, text)


func _show_player_line(text: String) -> void:
	portrait_holder.visible = false
	narration_label.visible = false
	text_label.visible = true
	nameplate.text = "You"
	nameplate.add_theme_color_override("font_color", ThemeManager.get_color("text_soft"))
	_begin_typing(text_label, text)


func _show_character_line(speaker_id: String, emotion: String, text: String) -> void:
	var character = ContentManager.get_character(speaker_id)
	narration_label.visible = false
	text_label.visible = true

	nameplate.text = String(character.get("display_name", speaker_id))
	nameplate.add_theme_color_override("font_color",
			ThemeManager.get_color(ContentManager.theme_color_key(character)))

	_show_portrait(character, emotion)
	_begin_typing(text_label, text)


func _show_portrait(character: Dictionary, emotion: String) -> void:
	portrait_holder.visible = true
	var path = ContentManager.portrait_path(character, emotion)
	if not path.is_empty() and ResourceLoader.exists(path):
		portrait_rect.texture = load(path)
		portrait_rect.visible = true
		portrait_fallback.visible = false
	else:
		# No art yet — themed circle with initials
		portrait_rect.visible = false
		portrait_fallback.visible = true
		var color = ThemeManager.get_color(ContentManager.theme_color_key(character))
		portrait_fallback.add_theme_stylebox_override("panel", UIFactory.flat_style(
				ThemeManager.get_color("panel_bg"), 100, 4, color))
		portrait_initials.text = ContentManager.initials(character)


# =============================================================
# TYPEWRITER
# =============================================================

func _begin_typing(label: Label, text: String) -> void:
	_typing = true
	_full_text = text
	_shown_chars = 0.0
	label.text = ""
	label.set_meta("typing_target", true)
	continue_hint.visible = false
	set_process(true)


func _process(delta: float) -> void:
	if not _typing:
		set_process(false)
		return
	_shown_chars += delta * TYPE_CPS
	var target = _active_label()
	if target == null:
		return
	if _shown_chars >= _full_text.length():
		target.text = _full_text
		_finish_typing()
	else:
		target.text = _full_text.substr(0, int(_shown_chars))


func _active_label() -> Label:
	if narration_label.visible:
		return narration_label
	return text_label


func _finish_typing() -> void:
	_typing = false
	set_process(false)
	continue_hint.visible = true


# =============================================================
# INPUT
# =============================================================

func _unhandled_input(event: InputEvent) -> void:
	if _paused:
		return
	var advance_pressed = event.is_action_pressed("ui_accept") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE) \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not advance_pressed:
		return
	get_viewport().set_input_as_handled()
	if _typing:
		# First press: finish the line instantly
		_active_label().text = _full_text
		_finish_typing()
	else:
		_advance()


func _on_skip() -> void:
	# Jump straight to the end of the scene
	_typing = false
	set_process(false)
	_finish()


func _finish() -> void:
	var callback = _on_done
	queue_free()
	if callback.is_valid():
		callback.call()
