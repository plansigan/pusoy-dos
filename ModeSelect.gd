# ModeSelect.gd
# Pre-game mode picker, opened by the main menu's PLAY button.
# CASUAL adds a difficulty pick; RANKED derives difficulty from rank.

class_name ModeSelect
extends Control

const PANEL_SIZE = Vector2(560, 380)
const DIFFICULTY_NAMES = ["EASY", "MEDIUM", "HARD"]

var panel: Panel
var picking_difficulty: bool = false

static func open(parent: Control) -> ModeSelect:
	var menu = ModeSelect.new()
	parent.add_child(menu)
	return menu


func _ready() -> void:
	UIFactory.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


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

	if picking_difficulty:
		_build_difficulty_stage()
	else:
		_build_mode_stage()


# =============================================================
# STAGE 1 — pick a mode
# =============================================================

func _build_mode_stage() -> void:
	_add_title("SELECT MODE")

	_add_mode_button("CASUAL",
			"Practice freely. Pick your AI difficulty. No rating.",
			"", 74, _on_casual_pressed, false)
	_add_mode_button("RANKED",
			"Climb the ladder. AI difficulty scales with your rank.\nQuitting counts as a forfeit.",
			"Current: %s · %d rating" % [StatsManager.get_rank_name(), StatsManager.rating],
			174, _on_ranked_pressed, true)

	_add_back_button(_on_back_pressed)


func _add_mode_button(title: String, description: String, footer: String,
		y: float, handler: Callable, highlighted: bool) -> void:
	var btn = Button.new()
	btn.position = Vector2(30, y)
	btn.size = Vector2(PANEL_SIZE.x - 60, 88)
	UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected") if highlighted \
					else ThemeManager.get_color("border_soft"),
			ThemeManager.get_color("button_text"), 8, 2)
	btn.pressed.connect(handler)
	panel.add_child(btn)

	var name_label = UIFactory.make_label(title, 18,
			ThemeManager.get_color("button_text"), Vector2(0, 8))
	name_label.size = Vector2(btn.size.x, 24)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_child(name_label)

	var desc = UIFactory.make_label(description, 11,
			ThemeManager.get_color("text_muted"), Vector2(0, 34))
	desc.size = Vector2(btn.size.x, 32)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_child(desc)

	if footer != "":
		var foot = UIFactory.make_label(footer, 11,
				ThemeManager.get_color("status_color"), Vector2(0, 66))
		foot.size = Vector2(btn.size.x, 16)
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_child(foot)


func _on_casual_pressed() -> void:
	picking_difficulty = true
	_build()


func _on_ranked_pressed() -> void:
	GameSession.mode = GameSession.Mode.RANKED
	_start_game()


# =============================================================
# STAGE 2 — casual difficulty
# =============================================================

func _build_difficulty_stage() -> void:
	_add_title("CASUAL — AI DIFFICULTY")

	var btn_w = 150.0
	var spacing = 14.0
	var start_x = (PANEL_SIZE.x - (3 * btn_w + 2 * spacing)) / 2

	for i in 3:
		var selected = Settings.ai_difficulty == i
		var btn = Button.new()
		btn.text = DIFFICULTY_NAMES[i]
		btn.position = Vector2(start_x + i * (btn_w + spacing), 130)
		btn.size = Vector2(btn_w, 56)
		btn.add_theme_font_size_override("font_size", 14)
		UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
				ThemeManager.get_color("selected") if selected \
						else ThemeManager.get_color("border_soft"),
				ThemeManager.get_color("selected") if selected \
						else ThemeManager.get_color("button_text"),
				4, 3 if selected else 1)
		btn.pressed.connect(_on_difficulty_pressed.bind(i))
		panel.add_child(btn)

	var hint = UIFactory.make_label("pick one to start the game", 11,
			ThemeManager.get_color("text_muted"), Vector2(0, 200))
	hint.size = Vector2(PANEL_SIZE.x, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint)

	_add_back_button(_on_difficulty_back_pressed)


func _on_difficulty_pressed(difficulty: int) -> void:
	Settings.ai_difficulty = difficulty  # remembered as the casual default
	Settings.save_settings()
	GameSession.mode = GameSession.Mode.CASUAL
	GameSession.casual_difficulty = difficulty
	_start_game()


func _on_difficulty_back_pressed() -> void:
	picking_difficulty = false
	_build()


# =============================================================
# SHARED
# =============================================================

func _add_title(text: String) -> void:
	var title = UIFactory.make_label(text, 22,
			ThemeManager.get_color("status_color"), Vector2(0, 22))
	title.size = Vector2(PANEL_SIZE.x, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)


func _add_back_button(handler: Callable) -> void:
	var btn = Button.new()
	btn.text = "◀ BACK"
	btn.position = Vector2((PANEL_SIZE.x - 150) / 2, PANEL_SIZE.y - 68)
	btn.size = Vector2(150, 42)
	btn.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"))
	btn.pressed.connect(handler)
	panel.add_child(btn)


func _on_back_pressed() -> void:
	queue_free()


func _start_game() -> void:
	get_tree().change_scene_to_file("res://GameTable.tscn")
