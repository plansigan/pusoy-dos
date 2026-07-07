# StatsScreen.gd
# Player stats overlay: ranked section (rating, rank, tier progress,
# W/L, streak), casual section, global records, and tagged history.

class_name StatsScreen
extends Control

const PANEL_SIZE = Vector2(720, 560)

var panel: Panel

static func open(parent: Control) -> StatsScreen:
	var screen = StatsScreen.new()
	parent.add_child(screen)
	return screen


func _ready() -> void:
	UIFactory.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


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

	var title = UIFactory.make_label("STATS", 24,
			ThemeManager.get_color("status_color"), Vector2(0, 16))
	title.size = Vector2(PANEL_SIZE.x, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	_build_ranked_section()
	_build_casual_section()
	_build_history_section()
	_build_back_button()


func _caption(text: String, y: float) -> void:
	panel.add_child(UIFactory.make_label(text, 12,
			ThemeManager.get_color("text_muted"), Vector2(32, y)))


func _line(text: String, y: float, color: Color) -> void:
	var label = UIFactory.make_label(text, 13, color, Vector2(48, y))
	label.size = Vector2(PANEL_SIZE.x - 96, 18)
	panel.add_child(label)


# =============================================================
# RANKED
# =============================================================

func _build_ranked_section() -> void:
	_caption("RANKED", 54)

	var rank_label = UIFactory.make_label(StatsManager.get_rank_name(), 20,
			ThemeManager.get_color("status_color"), Vector2(48, 74))
	panel.add_child(rank_label)

	var rating_label = UIFactory.make_label("%d rating" % StatsManager.rating, 14,
			ThemeManager.get_color("text_soft"), Vector2(PANEL_SIZE.x - 200, 78))
	rating_label.size = Vector2(152, 20)
	rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(rating_label)

	# Tier progress bar toward the next rank
	var bar_bg = Panel.new()
	bar_bg.position = Vector2(48, 106)
	bar_bg.size = Vector2(PANEL_SIZE.x - 96, 14)
	bar_bg.add_theme_stylebox_override("panel", UIFactory.flat_style(
			ThemeManager.get_color("table_bg"), 7, 1, ThemeManager.get_color("border_soft")))
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bar_bg)

	var next_threshold = StatsManager.next_rank_threshold()
	var progress = 1.0
	var progress_text = "MAX RANK"
	if next_threshold > 0:
		var current_min: int = StatsManager.RANKS[StatsManager.get_rank_index()]["min"]
		progress = float(StatsManager.rating - current_min) / float(next_threshold - current_min)
		progress_text = "%d / %d to %s" % [StatsManager.rating, next_threshold,
				StatsManager.RANKS[StatsManager.get_rank_index() + 1]["name"]]

	var fill = ColorRect.new()
	fill.color = ThemeManager.get_color("selected")
	fill.position = Vector2(2, 2)
	fill.size = Vector2(maxf(0.0, (bar_bg.size.x - 4) * clampf(progress, 0.0, 1.0)), 10)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(fill)

	var progress_label = UIFactory.make_label(progress_text, 10,
			ThemeManager.get_color("text_muted"), Vector2(48, 124))
	progress_label.size = Vector2(PANEL_SIZE.x - 96, 14)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(progress_label)

	var losses = StatsManager.ranked_games - StatsManager.ranked_wins
	_line("W %d — L %d  ·  win rate %s  ·  current streak %d" %
			[StatsManager.ranked_wins, losses,
			_percent(StatsManager.ranked_wins, StatsManager.ranked_games),
			StatsManager.streak],
			144, ThemeManager.get_color("text_soft"))


# =============================================================
# CASUAL + GLOBAL
# =============================================================

func _build_casual_section() -> void:
	_caption("CASUAL", 178)
	_line("games %d  ·  wins %d  ·  win rate %s" %
			[StatsManager.casual_games, StatsManager.casual_wins,
			_percent(StatsManager.casual_wins, StatsManager.casual_games)],
			198, ThemeManager.get_color("text_soft"))

	var fastest = "—" if StatsManager.fastest_win_turns == 0 \
			else "%d plays" % StatsManager.fastest_win_turns
	_line("combos played %d  ·  flawless wins %d  ·  fastest win %s" %
			[StatsManager.combos_played, StatsManager.flawless_wins, fastest],
			220, ThemeManager.get_color("text_muted"))


# =============================================================
# HISTORY
# =============================================================

func _build_history_section() -> void:
	_caption("MATCH HISTORY", 252)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(48, 272)
	scroll.size = Vector2(PANEL_SIZE.x - 96, 190)
	panel.add_child(scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	if StatsManager.match_history.is_empty():
		list.add_child(UIFactory.make_label("no matches yet — go play!", 12,
				ThemeManager.get_color("text_muted")))
		return

	for entry in StatsManager.match_history:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var mode_tag = UIFactory.make_label(str(entry["mode"]).to_upper(), 11,
				ThemeManager.get_color("text_muted"))
		mode_tag.custom_minimum_size = Vector2(70, 0)
		row.add_child(mode_tag)

		var result: String = entry["result"]
		var result_color: Color
		match result:
			"win": result_color = ThemeManager.get_color("clubs")
			"loss": result_color = ThemeManager.get_color("hearts")
			_: result_color = ThemeManager.get_color("text_muted")
		var result_label = UIFactory.make_label(result.to_upper(), 12, result_color)
		result_label.custom_minimum_size = Vector2(80, 0)
		row.add_child(result_label)

		var delta: int = entry["rating_delta"]
		var delta_text = "—" if entry["mode"] == "casual" else "%+d rating" % delta
		row.add_child(UIFactory.make_label(delta_text, 12,
				ThemeManager.get_color("text_soft")))

		list.add_child(row)


func _build_back_button() -> void:
	var achievements = Button.new()
	achievements.text = "🏆 Achievements"
	achievements.position = Vector2(PANEL_SIZE.x / 2 + 16, PANEL_SIZE.y - 66)
	achievements.size = Vector2(184, 42)
	achievements.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(achievements, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"))
	achievements.pressed.connect(func(): AchievementsScreen.open(get_parent()))
	panel.add_child(achievements)

	var btn = Button.new()
	btn.text = "◀ BACK"
	btn.position = Vector2(PANEL_SIZE.x / 2 - 200, PANEL_SIZE.y - 66)
	btn.size = Vector2(184, 42)
	btn.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected"), ThemeManager.get_color("button_text"))
	btn.pressed.connect(queue_free)
	panel.add_child(btn)


func _percent(wins: int, games: int) -> String:
	return "—" if games == 0 else "%d%%" % roundi(100.0 * wins / games)
