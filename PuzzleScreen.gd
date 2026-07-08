# PuzzleScreen.gd
# Puzzle-select overlay, opened from the main menu. Locked / unlocked /
# solved states; selecting an unlocked puzzle drops straight into the
# handcrafted match (no intro dialogue).

class_name PuzzleScreen
extends Control

const PANEL_SIZE = Vector2(760, 560)
const ROW_HEIGHT = 96.0

var panel: Panel

static func open(parent: Control) -> PuzzleScreen:
	var screen = PuzzleScreen.new()
	parent.add_child(screen)
	return screen


func _ready() -> void:
	UIFactory.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Deep guard: bounce out if the feature is locked, whatever the path in.
	if not FeatureFlags.is_enabled("puzzles"):
		_bounce_to_menu()
		return
	ContentManager.load_all()
	_build()


func _bounce_to_menu() -> void:
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://MainMenu.tscn")
	else:
		queue_free()  # overlay case — reveal the menu underneath


func _build() -> void:
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

	var solved_count = ContentManager.puzzles_ordered.filter(
			func(p): return PuzzleManager.is_solved(String(p["id"]))).size()
	var title = UIFactory.make_label("PUZZLES  (%d / %d solved)" %
			[solved_count, ContentManager.puzzles_ordered.size()], 24,
			ThemeManager.get_color("status_color"), Vector2(0, 18))
	title.size = Vector2(PANEL_SIZE.x, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(30, 62)
	scroll.size = Vector2(PANEL_SIZE.x - 60, PANEL_SIZE.y - 138)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	if ContentManager.puzzles_ordered.is_empty():
		list.add_child(UIFactory.make_label("No puzzles yet.", 14,
				ThemeManager.get_color("text_muted")))
	for puzzle in ContentManager.puzzles_ordered:
		list.add_child(_make_puzzle_row(puzzle))

	_add_back_button()


func _make_puzzle_row(puzzle: Dictionary) -> Control:
	var id = String(puzzle["id"])
	var unlocked = PuzzleManager.is_unlocked(id)
	var solved = PuzzleManager.is_solved(id)

	var row = Panel.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var border = ThemeManager.get_color("selected") if unlocked and not solved \
			else ThemeManager.get_color("border_soft")
	row.add_theme_stylebox_override("panel", UIFactory.flat_style(
			ThemeManager.get_color("button_bg"), 8, 2, border))
	row.modulate.a = 1.0 if unlocked else 0.5

	row.add_child(UIFactory.make_label("Puzzle %d" % int(puzzle["order"]), 12,
			ThemeManager.get_color("text_muted"), Vector2(16, 10)))
	row.add_child(UIFactory.make_label(String(puzzle.get("title", id)), 20,
			ThemeManager.get_color("text_primary"), Vector2(16, 26)))
	row.add_child(UIFactory.make_label(String(puzzle.get("description", "")), 12,
			ThemeManager.get_color("text_soft"), Vector2(16, 56)))
	row.add_child(UIFactory.make_label(
			PuzzleManager.objective_text(puzzle.get("objective", {})), 11,
			ThemeManager.get_color("text_muted"), Vector2(16, 74)))

	if not unlocked:
		var lock = UIFactory.make_label("🔒 %s" % _lock_reason(puzzle), 12,
				ThemeManager.get_color("text_muted"), Vector2(PANEL_SIZE.x - 320, 40))
		lock.size = Vector2(226, 18)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(lock)
		return row

	if solved:
		var best = PuzzleManager.best_for(id)
		var check = UIFactory.make_label("✔ solved · best %d plays" % best, 12,
				ThemeManager.get_color("clubs"), Vector2(PANEL_SIZE.x - 320, 40))
		check.size = Vector2(226, 18)
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(check)

	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(_start_puzzle.bind(id))
	row.add_child(btn)
	return row


func _lock_reason(puzzle: Dictionary) -> String:
	var req = puzzle.get("unlock", {}).get("requires_puzzle", null)
	if req == null:
		return "Locked"
	var prev = ContentManager.get_puzzle(String(req))
	var title = prev.get("title", req) if not prev.is_empty() else req
	return "Solve \"%s\" first" % title


func _start_puzzle(puzzle_id: String) -> void:
	GameSession.mode = GameSession.Mode.PUZZLE
	GameSession.puzzle_id = puzzle_id
	# Capture the tree — this screen frees itself before the scene change
	var tree = get_tree()
	queue_free()
	tree.change_scene_to_file("res://GameTable.tscn")


func _add_back_button() -> void:
	var btn = Button.new()
	btn.text = "◀ BACK"
	btn.position = Vector2((PANEL_SIZE.x - 150) / 2, PANEL_SIZE.y - 60)
	btn.size = Vector2(150, 42)
	btn.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected"), ThemeManager.get_color("button_text"))
	btn.pressed.connect(queue_free)
	panel.add_child(btn)
