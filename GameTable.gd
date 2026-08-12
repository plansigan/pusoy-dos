# GameTable.gd
# UI controller — layout, input, refresh, animations, win screen.
# The player's hand is a HandFan; opponents are AvatarSlots.

extends Control

const BASE_W = 1152.0
const BASE_H = 648.0

const CARD_SIZE_HAND = Vector2(72, 95)
const CARD_SIZE_MINI = Vector2(52, 72)

const DEAL_STAGGER = 0.045      # delay between each card leaving the deck
const DEAL_FLIGHT_TIME = 0.25   # how long one dealt card flies
const PLAY_FLY_TIME = 0.32      # how long played cards fly to the table

# --- State ---
var game_manager: GameManager
var ai_player: AIPlayer
var is_ai_turn: bool = false
var is_dealing: bool = false
var ai_chain_running: bool = false   # an AI turn loop is already awaiting
var win_screen_shown: bool = false
var hand_custom_order: bool = false  # manual drag order active until re-sorted
var match_recorded: bool = false     # rating/stats recorded exactly once per game
var human_plays: int = 0             # successful human plays this game
var ui_locked: bool = false          # a modal dialog is open — AI loop waits
var quit_dialog: Control = null

# --- Story mode state (empty/ignored in casual & ranked) ---
var story_chapter: Dictionary = {}
var seat_char_ids: Array = []        # index by player id; [0]=player (unused)
var turn_counter: int = 0
var last_bark_turn: int = -99
var bark_once: Dictionary = {}       # "charid:trigger" -> true
var event_fired: Array = []          # per match_event, once-guard
var table_cleared_count: int = 0

# --- Puzzle mode state ---
var puzzle: Dictionary = {}
var puzzle_solved_this_run: bool = false
var puzzle_new_best: bool = false
var objective_label: Label
var _win_rating_countup: Dictionary = {}  # {from,to,rank} for the WinScreen tally

# --- UI refs ---
var avatars: Array = []              # [AvatarSlot, AvatarSlot, AvatarSlot] for P2-P4
var hand_fan: HandFan
var table_history_container: VBoxContainer
var table_scroll: ScrollContainer
var last_play_panel: Panel           # the "last play" box (raised in tutorial)
var last_play_card_container: VBoxContainer
var last_play_player_label: Label
var play_button: Button
var pass_button: Button
var status_label: Label
var _status_tween: Tween        # active status-label crossfade, if any
var menu_button: Button
var settings_button: Button
var sort_button: Button
var help_button: Button
var buttons_row: HBoxContainer      # Pass/Play row (raised during tutorial highlights)
var drop_zone: DropZone
var _help_modal: HelpModal = null

# --- Tutorial mode state (only used when GameSession.mode == TUTORIAL) ---
signal _tut_step_signal              # emitted when the player clears the current step
var _tut_active: bool = false        # guided tutorial running
var _tut_free_play: bool = false     # final step — normal play/AI resumed
var _tut_step_index: int = 0
var _tut_awaiting: bool = false      # driver is blocked waiting on the player
var _tut_required: Dictionary = {}   # current step's required-action descriptor
var _tut_allowed_cards: Array = []   # Card refs the fan is locked to this step
var _tut_dim: ColorRect = null       # spotlight dim behind raised targets
var _tut_bubble: Panel = null        # persistent Lolo instruction panel
var _tut_raised: Array = []          # [{node,z}] originals to restore after a highlight
var _tut_last_correct_ms: int = 0    # throttle for Lolo's correction bubbles


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# We must intercept window close to record ranked forfeits
	get_tree().set_auto_accept_quit(false)
	await get_tree().process_frame
	_build_layout()
	_start_game()


func _exit_tree() -> void:
	get_tree().set_auto_accept_quit(true)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	# Closing the window mid-ranked-game is a forfeit; the synchronous
	# save inside record_forfeit() completes before we quit
	if GameSession.mode == GameSession.Mode.RANKED and game_manager != null \
			and not game_manager.game_over and not match_recorded:
		match_recorded = true
		StatsManager.record_forfeit()
	get_tree().quit()


func _start_game() -> void:
	# A ranking chosen mid-game only takes effect here, on the next game
	RulesManager.set_ranking(Settings.suit_ranking)
	game_manager = GameManager.new()

	# Story chapters and puzzles deal a fixed layout instead of shuffling
	var preset: Array = []
	if GameSession.mode == GameSession.Mode.STORY:
		story_chapter = ContentManager.get_chapter(GameSession.story_chapter_id)
		preset = ContentManager.deal_to_hands(story_chapter)
	elif GameSession.mode == GameSession.Mode.PUZZLE:
		puzzle = ContentManager.get_puzzle(GameSession.puzzle_id)
		preset = ContentManager.deal_to_hands(puzzle)
	elif GameSession.mode == GameSession.Mode.TUTORIAL:
		preset = ContentManager.deal_to_hands(ContentManager.get_tutorial())
	game_manager.setup_game(preset)
	_apply_sort()

	ai_player = AIPlayer.new(game_manager)
	match GameSession.mode:
		GameSession.Mode.RANKED:
			# snapshotted from the CURRENT rank — a rank change mid-game
			# never affects the game being played
			ai_player.difficulty = StatsManager.ranked_difficulty()
		GameSession.Mode.STORY:
			_setup_story_ai()
		GameSession.Mode.PUZZLE:
			ai_player.difficulty = ContentManager.puzzle_ai_difficulty(puzzle)
			# Puzzles must be reproducible: EASY opponents otherwise pass/misplay
			# at random, so a solved line might not replay.
			ai_player.deterministic = true
		GameSession.Mode.TUTORIAL:
			_setup_tutorial_ai()
		_:
			ai_player.difficulty = GameSession.casual_difficulty

	puzzle_solved_this_run = false
	puzzle_new_best = false
	if GameSession.mode == GameSession.Mode.PUZZLE and not puzzle.is_empty():
		objective_label.text = PuzzleManager.objective_text(puzzle.get("objective", {}))
		objective_label.visible = true

	win_screen_shown = false
	match_recorded = false
	human_plays = 0
	ai_chain_running = false   # defensive: GameTable is reused across Play Again
	_reset_tutorial_state()
	_connect_buttons()
	if GameSession.mode == GameSession.Mode.STORY or GameSession.mode == GameSession.Mode.TUTORIAL:
		_apply_story_seats()
	await _deal_cards_animated()
	if not is_inside_tree():
		return
	_refresh_all()
	if GameSession.mode == GameSession.Mode.TUTORIAL:
		_tut_begin()


func _connect_buttons() -> void:
	play_button.pressed.connect(_on_play_pressed)
	pass_button.pressed.connect(_on_pass_pressed)


# =============================================================
# LAYOUT
# =============================================================

func _build_layout() -> void:
	var sw = BASE_W
	var sh = BASE_H

	_add_background(sw, sh)
	_add_avatars(sw)
	_add_center_area(sw, sh)
	_add_emote_bar(sw, sh)
	_add_hand_fan(sw, sh)
	_add_buttons(sw, sh)
	_add_status_label(sw, sh)
	_add_menu_button(sh)
	_add_settings_button(sh)
	_add_help_button(sh)
	_add_sort_button(sw, sh)
	_add_objective_banner(sw)


func _add_background(sw: float, sh: float) -> void:
	var bg = ColorRect.new()
	bg.color = ThemeManager.get_color("table_bg")
	bg.position = Vector2.ZERO
	bg.size = Vector2(sw, sh)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _add_avatars(sw: float) -> void:
	var centers = [0.25, 0.5, 0.75]
	for i in 3:
		var avatar = AvatarSlot.new("Player %d" % (i + 2), "P%d" % (i + 2))
		avatar.position = Vector2(sw * centers[i] - 60, 14)
		add_child(avatar)
		avatars.append(avatar)


func _add_center_area(sw: float, sh: float) -> void:
	var top = 130.0
	var center_h = sh - top - 256  # below avatars, above emote bar + fan
	var padding = 10.0

	# Last play panel (left third)
	var last_play_w = sw * 0.28
	var last_play = _make_panel(ThemeManager.get_color("panel_bg"))
	last_play.position = Vector2(padding, top)
	last_play.size = Vector2(last_play_w, center_h)
	add_child(last_play)
	last_play_panel = last_play
	last_play.add_child(_make_caption("last play"))

	last_play_player_label = UIFactory.make_label("", 12,
			ThemeManager.get_color("status_color"), Vector2(0, center_h - 24))
	last_play_player_label.size = Vector2(last_play_w, 20)
	last_play_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	last_play.add_child(last_play_player_label)

	last_play_card_container = VBoxContainer.new()
	last_play_card_container.position = Vector2(0, 28)
	last_play_card_container.size = Vector2(last_play_w, center_h - 56)
	last_play_card_container.alignment = BoxContainer.ALIGNMENT_CENTER
	last_play_card_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	last_play.add_child(last_play_card_container)

	# Drop zone highlight — dashed border around the last-play area,
	# visible only while drag-playing cards
	drop_zone = DropZone.new()
	drop_zone.position = last_play.position - Vector2(4, 4)
	drop_zone.size = last_play.size + Vector2(8, 8)
	drop_zone.visible = false
	drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drop_zone)

	# History panel (right portion)
	var history_x = padding + last_play_w + padding
	var history_w = sw - history_x - padding
	var history = _make_panel(ThemeManager.get_color("panel_bg"))
	history.position = Vector2(history_x, top)
	history.size = Vector2(history_w, center_h)
	add_child(history)
	history.add_child(_make_caption("play history"))

	table_scroll = ScrollContainer.new()
	table_scroll.position = Vector2(8, 28)
	table_scroll.size = Vector2(history_w - 16, center_h - 36)
	table_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history.add_child(table_scroll)

	table_history_container = VBoxContainer.new()
	table_history_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_history_container.add_theme_constant_override("separation", 4)
	table_history_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table_scroll.add_child(table_history_container)


func _add_emote_bar(sw: float, sh: float) -> void:
	var emotes = ["😤", "👏", "😂", "🔥", "😎", "💀", "🤙"]
	var bar = _make_panel(ThemeManager.get_color("panel_bg"))
	bar.position = Vector2(10, sh - 250.0)
	bar.size = Vector2(sw - 20, 36)
	add_child(bar)

	var hbox = HBoxContainer.new()
	hbox.position = Vector2(sw / 2 - 180, 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	bar.add_child(hbox)

	var react_label = UIFactory.make_label("react:", 12, ThemeManager.get_color("text_muted"))
	hbox.add_child(react_label)

	for emote in emotes:
		var btn = Button.new()
		btn.text = emote
		btn.flat = true
		btn.custom_minimum_size = Vector2(32, 28)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func(): SoundManager.play("button_click"))
		btn.pressed.connect(_on_emote_pressed.bind(emote, btn))
		hbox.add_child(btn)


func _add_hand_fan(sw: float, sh: float) -> void:
	hand_fan = HandFan.new()
	hand_fan.position = Vector2(sw / 2, sh - 64)  # bottom-center baseline of the arc
	add_child(hand_fan)
	hand_fan.card_double_clicked.connect(_on_card_double_clicked)
	hand_fan.order_changed.connect(_on_hand_reordered)
	hand_fan.play_drag_started.connect(_on_play_drag_started)
	hand_fan.play_drag_moved.connect(_on_play_drag_moved)
	hand_fan.play_drag_ended.connect(_on_play_drag_ended)
	hand_fan.play_dropped.connect(_on_play_dropped)
	hand_fan.illegal_card_tapped.connect(_on_illegal_card_tapped)


func _add_buttons(sw: float, sh: float) -> void:
	var row = HBoxContainer.new()
	row.position = Vector2(sw / 2 - 120, sh - 40)
	row.size = Vector2(240, 32)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	buttons_row = row

	var button_size = Vector2(110, 30)

	pass_button = Button.new()
	pass_button.text = "Pass"
	pass_button.custom_minimum_size = button_size
	UIFactory.style_button(pass_button, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"))
	row.add_child(pass_button)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	play_button = Button.new()
	play_button.text = "Play"
	play_button.custom_minimum_size = button_size
	UIFactory.style_button(play_button, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected"), ThemeManager.get_color("button_text"))
	row.add_child(play_button)


func _add_status_label(sw: float, sh: float) -> void:
	status_label = UIFactory.make_label("Your turn!", 14,
			ThemeManager.get_color("status_color"), Vector2(sw / 2 - 80, sh - 206))
	status_label.size = Vector2(160, 20)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.pivot_offset = status_label.size / 2  # for the turn pulse
	add_child(status_label)


func _add_menu_button(sh: float) -> void:
	menu_button = Button.new()
	menu_button.text = "☰ Menu"
	menu_button.position = Vector2(10, sh - 36)
	menu_button.custom_minimum_size = Vector2(70, 28)
	menu_button.add_theme_font_size_override("font_size", 12)
	UIFactory.style_button(menu_button, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"), 4, 1)
	add_child(menu_button)
	menu_button.pressed.connect(_on_menu_pressed)


func _add_settings_button(sh: float) -> void:
	settings_button = Button.new()
	settings_button.text = "⚙ Settings"
	settings_button.position = Vector2(86, sh - 36)
	settings_button.custom_minimum_size = Vector2(92, 28)
	settings_button.add_theme_font_size_override("font_size", 12)
	UIFactory.style_button(settings_button, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"), 4, 1)
	add_child(settings_button)
	settings_button.pressed.connect(_on_settings_pressed)


func _add_help_button(sh: float) -> void:
	help_button = Button.new()
	help_button.text = "?"
	help_button.position = Vector2(184, sh - 36)
	help_button.custom_minimum_size = Vector2(34, 28)
	help_button.add_theme_font_size_override("font_size", 14)
	UIFactory.style_button(help_button, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"), 4, 1)
	add_child(help_button)
	help_button.pressed.connect(_on_help_pressed)


func _add_sort_button(sw: float, sh: float) -> void:
	sort_button = Button.new()
	sort_button.text = _sort_button_text()
	sort_button.position = Vector2(sw - 122, sh - 36)
	sort_button.custom_minimum_size = Vector2(112, 28)
	sort_button.add_theme_font_size_override("font_size", 12)
	UIFactory.style_button(sort_button, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"), 4, 1)
	add_child(sort_button)
	sort_button.pressed.connect(_on_sort_pressed)


func _sort_button_text() -> String:
	return "Sort: Suit" if Settings.sort_mode == "suit" else "Sort: Rank"


func _on_sort_pressed() -> void:
	if is_dealing:
		return
	# After a manual reorder the first press restores the shown sort;
	# otherwise it toggles between the two modes
	if not hand_custom_order:
		Settings.sort_mode = "suit" if Settings.sort_mode == "rank" else "rank"
		Settings.save_settings()
	sort_button.text = _sort_button_text()
	_apply_sort()
	hand_fan.sync(game_manager.players[0].hand, hand_fan.input_enabled)
	_apply_hints()


# Sorts the actual hand array — the fan renders hand order directly
func _apply_sort() -> void:
	hand_custom_order = false
	var hand = game_manager.players[0].hand
	var sorted = hand.duplicate()
	if Settings.sort_mode == "suit":
		# Group by suit in the active ranking's order (weakest suit first)
		sorted.sort_custom(func(a, b):
			if a.suit != b.suit:
				return a.suit_value() < b.suit_value()
			return a.rank_value() < b.rank_value()
		)
	else:
		sorted = Card.sort_cards(sorted)
	hand.assign(sorted)


func _on_hand_reordered(cards: Array) -> void:
	game_manager.players[0].hand.assign(cards)
	hand_custom_order = true


# Puzzle objective, shown between the avatars and the table panels
func _add_objective_banner(sw: float) -> void:
	objective_label = UIFactory.make_label("", 12,
			ThemeManager.get_color("status_color"), Vector2(sw / 2 - 280, 108))
	objective_label.size = Vector2(560, 18)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.visible = false
	add_child(objective_label)


func _on_menu_pressed() -> void:
	if quit_dialog != null:
		return
	# Finished games can be left freely
	if game_manager == null or game_manager.game_over or match_recorded:
		TransitionManager.change_scene("res://MainMenu.tscn")
		return
	_open_quit_dialog()


func _open_quit_dialog() -> void:
	ui_locked = true
	hand_fan.set_input_enabled(false)
	var ranked = GameSession.mode == GameSession.Mode.RANKED

	quit_dialog = Control.new()
	quit_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	quit_dialog.z_index = 120
	add_child(quit_dialog)
	UIFactory.fill_viewport(quit_dialog)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	quit_dialog.add_child(dim)
	UIFactory.fill_viewport(dim)

	var panel_h = 200.0 if ranked else 160.0
	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 12))
	panel.size = Vector2(470, panel_h)
	panel.position = get_viewport_rect().size / 2 - panel.size / 2
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	quit_dialog.add_child(panel)

	var quit_title = "Quit game?"
	match GameSession.mode:
		GameSession.Mode.RANKED: quit_title = "⚠ Quit ranked game?"
		GameSession.Mode.STORY: quit_title = "Quit chapter?"
		GameSession.Mode.PUZZLE: quit_title = "Quit puzzle?"
		GameSession.Mode.TUTORIAL: quit_title = "Quit tutorial?"
	var title = UIFactory.make_label(quit_title,
			18, ThemeManager.get_color("status_color"), Vector2(0, 22))
	title.size = Vector2(panel.size.x, 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	# "?" Help, reachable from the pause dialog too (opens above it)
	var help = Button.new()
	help.text = "?"
	help.position = Vector2(panel.size.x - 44, 12)
	help.size = Vector2(32, 32)
	help.add_theme_font_size_override("font_size", 14)
	UIFactory.style_button(help, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"), 4, 1)
	help.pressed.connect(_open_help.bind(quit_dialog))
	panel.add_child(help)

	if ranked:
		var body = UIFactory.make_label(
				"This counts as a forfeit. You'll lose 10 rating\nand your streak (current streak: %d)."
				% StatsManager.streak,
				12, ThemeManager.get_color("text_soft"), Vector2(0, 58))
		body.size = Vector2(panel.size.x, 40)
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(body)

	var button_y = panel_h - 62
	var keep = Button.new()
	keep.text = "Keep playing"
	keep.position = Vector2(46, button_y)
	keep.size = Vector2(180, 42)
	keep.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(keep, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected"), ThemeManager.get_color("button_text"))
	keep.pressed.connect(_close_quit_dialog)
	panel.add_child(keep)

	var quit = Button.new()
	quit.text = "Forfeit and quit" if ranked else "Quit"
	quit.position = Vector2(244, button_y)
	quit.size = Vector2(180, 42)
	quit.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(quit, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("hearts") if ranked \
					else ThemeManager.get_color("border_soft"),
			ThemeManager.get_color("button_text"))
	quit.pressed.connect(_confirm_quit)
	panel.add_child(quit)


func _close_quit_dialog() -> void:
	if quit_dialog != null:
		quit_dialog.queue_free()
		quit_dialog = null
	ui_locked = false
	hand_fan.set_input_enabled(
			not is_ai_turn and not is_dealing and not game_manager.game_over)


func _confirm_quit() -> void:
	# Ranked: leaving an unfinished game is always a forfeit.
	# Casual & story: free — nothing is recorded (story chapter just
	# stays incomplete).
	if GameSession.mode == GameSession.Mode.RANKED and not match_recorded \
			and not game_manager.game_over:
		match_recorded = true
		StatsManager.record_forfeit()
	if GameSession.mode == GameSession.Mode.STORY:
		GameSession.return_to_story = true
	elif GameSession.mode == GameSession.Mode.PUZZLE:
		GameSession.return_to_puzzles = true
	TransitionManager.change_scene("res://MainMenu.tscn")


func _on_settings_pressed() -> void:
	hand_fan.set_input_enabled(false)
	SettingsMenu.open(self, _on_settings_closed)


func _on_settings_closed(theme_changed: bool) -> void:
	if theme_changed:
		_rebuild_after_theme_change()
	else:
		hand_fan.set_input_enabled(
				not is_ai_turn and not is_dealing and not game_manager.game_over)


# --- Help modal (combos reference) ---

func _on_help_pressed() -> void:
	_open_help(self)


# `over` lets the quit dialog open Help on top of itself.
func _open_help(over: Node) -> void:
	if _help_modal != null and is_instance_valid(_help_modal):
		return
	ui_locked = true                       # the AI loop waits while Help is open
	hand_fan.set_input_enabled(false)
	_help_modal = HelpModal.open(over, _on_help_closed)


func _on_help_closed() -> void:
	_help_modal = null
	# Keep the loop paused if the quit dialog is still underneath.
	if quit_dialog == null:
		ui_locked = false
	# Tutorial: closing Help is what completes the "open the Help" step.
	if _tut_active and _tut_awaiting and String(_tut_required.get("type", "")) == "help":
		_tut_step_signal.emit()
		return
	# Normal play: restore hand input for the current turn state. During a
	# guided tutorial step the step owns hand input, so leave it untouched.
	if not _tut_guided() and game_manager != null and not game_manager.game_over \
			and quit_dialog == null:
		hand_fan.set_input_enabled(not is_ai_turn and not is_dealing)


func _tut_guided() -> bool:
	return _tut_active and not _tut_free_play


# Rebuild every UI node in the new theme while keeping the game state
func _rebuild_after_theme_change() -> void:
	for child in get_children():
		child.queue_free()
	avatars.clear()
	await get_tree().process_frame
	_build_layout()
	_connect_buttons()
	_refresh_all()


# =============================================================
# HELPERS
# =============================================================

func _make_panel(color: Color) -> Panel:
	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel", UIFactory.flat_style(color, 8))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


# Small dim caption in a panel's top-left corner
func _make_caption(text: String) -> Label:
	return UIFactory.make_label(text, 11, ThemeManager.get_color("text_muted"), Vector2(10, 6))


func _make_card(card: Card, card_size := CARD_SIZE_HAND) -> CardUI:
	var card_ui = CardUI.new()
	card_ui.custom_minimum_size = card_size
	card_ui.size = card_size
	card_ui.pivot_offset = Vector2(card_size.x / 2, card_size.y)
	card_ui.setup(card)
	return card_ui


# =============================================================
# DEAL ANIMATION
# =============================================================

func _deal_cards_animated() -> void:
	is_dealing = true
	play_button.disabled = true
	pass_button.disabled = true
	settings_button.disabled = true
	sort_button.disabled = true
	_set_status("Dealing...")

	# Counters start at zero and tick up as cards arrive
	for i in 3:
		avatars[i].set_count(0)

	# Build the fan as invisible placeholders so every card's final
	# slot position AND rotation are known before anything flies
	var placeholders = hand_fan.build_hidden(game_manager.players[0].hand)
	await get_tree().process_frame
	if not is_inside_tree():
		return

	var deck_pos = Vector2(BASE_W / 2 - CARD_SIZE_HAND.x / 2, BASE_H / 2 - 150)

	# Round-robin like a real deal: one card to each player, 13 rounds
	for round_i in 13:
		_fly_card_to_hand(placeholders[round_i], deck_pos)
		for opp_i in 3:
			await get_tree().create_timer(DEAL_STAGGER).timeout
			if not is_inside_tree():
				return
			_fly_card_back_to_opponent(opp_i, deck_pos, round_i + 1)
		await get_tree().create_timer(DEAL_STAGGER).timeout
		if not is_inside_tree():
			return

	# Let the last flights land
	await get_tree().create_timer(DEAL_FLIGHT_TIME).timeout
	if not is_inside_tree():
		return
	is_dealing = false
	play_button.disabled = false
	settings_button.disabled = false
	sort_button.disabled = false
	_update_pass_button()


# Face-up card flies from the deck into its fan slot, rotating into place
func _fly_card_to_hand(placeholder: CardUI, from_pos: Vector2) -> void:
	SoundManager.play("card_deal")
	var proxy = _make_card(placeholder.card_data)
	proxy.position = from_pos
	add_child(proxy)

	var tween = create_tween().set_parallel(true)
	tween.tween_property(proxy, "global_position", placeholder.global_position,
			DEAL_FLIGHT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(proxy, "rotation", placeholder.rotation, DEAL_FLIGHT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func():
		placeholder.modulate.a = 1.0
		proxy.queue_free()
	)


# Face-down card flies to an opponent's avatar, shrinking as it goes,
# then bumps their card counter
func _fly_card_back_to_opponent(opp_i: int, from_pos: Vector2, new_count: int) -> void:
	SoundManager.play("card_deal")
	var proxy = CardUI.new()
	proxy.setup_back()
	proxy.position = from_pos
	proxy.pivot_offset = proxy.size / 2
	add_child(proxy)

	var target = avatars[opp_i].global_circle_center() - proxy.size / 2

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(proxy, "global_position", target, DEAL_FLIGHT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(proxy, "scale", Vector2(0.3, 0.3), DEAL_FLIGHT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(proxy, "modulate:a", 0.2, DEAL_FLIGHT_TIME)
	tween.chain().tween_callback(func():
		avatars[opp_i].set_count(new_count)
		proxy.queue_free()
	)


# =============================================================
# PLAY / CLEAR ANIMATIONS
# =============================================================

# Cards fly from their origin(s) to the last-play area with a slight
# arc, settling their rotation on the way. origins holds one position
# per card (human, from the fan) or a single point (AI, from avatar).
func _animate_play(origins: Array, cards: Array) -> void:
	var n = cards.size()
	if n == 0:
		return
	var target_center = last_play_card_container.get_global_rect().get_center()
	var total_w = n * CARD_SIZE_MINI.x + (n - 1) * 4

	for i in n:
		var proxy = _make_card(cards[i], CARD_SIZE_MINI)
		proxy.pivot_offset = CARD_SIZE_MINI / 2
		proxy.rotation = randf_range(-0.2, 0.2)
		add_child(proxy)
		var origin: Vector2 = origins[i] if i < origins.size() else origins[0]
		proxy.global_position = origin

		var dest = target_center + Vector2(
				-total_w / 2 + i * (CARD_SIZE_MINI.x + 4), -CARD_SIZE_MINI.y / 2)
		var mid = origin.lerp(dest, 0.5) + Vector2(0, -46)  # slight arc

		var flight = create_tween()
		flight.tween_property(proxy, "global_position", mid, PLAY_FLY_TIME * 0.5) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(i * 0.05)
		flight.tween_property(proxy, "global_position", dest, PLAY_FLY_TIME * 0.5) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		flight.tween_callback(proxy.queue_free)

		var settle = create_tween()
		settle.tween_property(proxy, "rotation", 0.0, PLAY_FLY_TIME).set_delay(i * 0.05)

	await get_tree().create_timer(PLAY_FLY_TIME + 0.05 * n + 0.02).timeout


# Last-play cards fade out and slide away when the table clears
func _animate_table_clear() -> void:
	for child in last_play_card_container.get_children():
		var gp = child.global_position
		last_play_card_container.remove_child(child)
		add_child(child)
		child.global_position = gp
		var tween = create_tween().set_parallel(true)
		tween.tween_property(child, "global_position", gp + Vector2(90, 24), 0.3) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(child, "modulate:a", 0.0, 0.3)
		tween.chain().tween_callback(child.queue_free)


# =============================================================
# REFRESH
# =============================================================

func _refresh_all() -> void:
	_refresh_table()
	_refresh_hand()
	_update_avatars()


func _refresh_hand() -> void:
	if game_manager.game_over:
		hand_fan.sync(game_manager.players[0].hand, false)
		hand_fan.apply_hints({})
		_update_status()
		return

	var current = game_manager.get_current_player()
	hand_fan.sync(game_manager.players[0].hand, current.id == 0)
	_update_pass_button()

	if current.id != 0:
		hand_fan.apply_hints({})
		is_ai_turn = true
		_update_status()
		if _tut_guided():
			return  # the tutorial driver runs the opponents itself
		if ai_chain_running:
			return  # a rebuild refreshed mid-chain — don't start a second loop
		await get_tree().create_timer(randf_range(0.4, 0.9)).timeout
		if ai_chain_running:
			return
		if not game_manager.game_over:
			await _run_ai_turns()
	else:
		var returning_to_player = is_ai_turn
		is_ai_turn = false
		_apply_hints()
		_update_status()
		if returning_to_player:
			_pulse_status()


func _pulse_status() -> void:
	var tween = create_tween()
	tween.tween_property(status_label, "scale", Vector2(1.15, 1.15), 0.15) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(status_label, "scale", Vector2.ONE, 0.15) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# Swap the status text with a quick crossfade instead of an instant change.
# Routing every status change through here keeps the alpha tween single-owner
# (no racing fades), and it always resolves back to full opacity.
func _set_status(text: String) -> void:
	if not is_instance_valid(status_label):
		return
	if status_label.visible and status_label.text == text:
		return
	status_label.visible = true
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
	_status_tween = create_tween()
	_status_tween.tween_property(status_label, "modulate:a", 0.0, 0.08) \
			.set_trans(Tween.TRANS_SINE)
	_status_tween.tween_callback(func(): status_label.text = text)
	_status_tween.tween_property(status_label, "modulate:a", 1.0, 0.08) \
			.set_trans(Tween.TRANS_SINE)


func _update_pass_button() -> void:
	# Passing is illegal on an empty table — the leader must play
	pass_button.disabled = is_dealing or game_manager.table_cards.is_empty()


# Dim cards that can't help beat the current table
func _apply_hints() -> void:
	if _tut_guided():
		hand_fan.apply_hints({})   # tutorial uses its own selectable lock, not hints
		return
	var relevant = Settings.show_hints \
			and not is_ai_turn and not is_dealing \
			and not game_manager.game_over \
			and not game_manager.table_cards.is_empty() \
			and game_manager.get_current_player().id == 0
	hand_fan.apply_hints(_compute_playable() if relevant else {})


func _compute_playable() -> Dictionary:
	var playable = {}
	var hand: Array = game_manager.players[0].hand
	var table: Array = game_manager.table_cards
	match table.size():
		1:
			for card in hand:
				if HandEvaluator.can_beat(table, [card]):
					playable[card] = true
		2, 3:
			var by_rank = {}
			for card in hand:
				if not by_rank.has(card.rank):
					by_rank[card.rank] = []
				by_rank[card.rank].append(card)
			for rank in by_rank:
				var group: Array = by_rank[rank]
				if group.size() >= table.size() \
						and HandEvaluator.can_beat(table, group.slice(0, table.size())):
					for card in group:
						playable[card] = true
		5:
			_mark_five_card_playable(hand, 0, [], table, playable)
	return playable


# Marks every card that appears in at least one beating five-card combo
func _mark_five_card_playable(hand: Array, start: int, combo: Array,
		table: Array, playable: Dictionary) -> void:
	if combo.size() == 5:
		if HandEvaluator.can_beat(table, combo):
			for card in combo:
				playable[card] = true
		return
	for i in range(start, hand.size()):
		combo.append(hand[i])
		_mark_five_card_playable(hand, i + 1, combo, table, playable)
		combo.pop_back()


func _refresh_table() -> void:
	# Clear history
	for child in table_history_container.get_children():
		child.queue_free()

	# Clear last play
	for child in last_play_card_container.get_children():
		child.queue_free()
	last_play_player_label.text = ""

	# Rebuild history
	for entry in game_manager.play_history:
		if entry["cards"].is_empty():
			var divider = UIFactory.make_label("── table cleared ──", 11,
					ThemeManager.get_color("text_muted"))
			table_history_container.add_child(divider)
			continue

		var row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 4)

		var name_label = UIFactory.make_label(entry["player"] + ":", 12,
				ThemeManager.get_color("status_color"))
		name_label.custom_minimum_size = Vector2(72, 0)
		row.add_child(name_label)

		for card in entry["cards"]:
			row.add_child(_make_card(card, CARD_SIZE_MINI))

		table_history_container.add_child(row)

	# Show last play big on the left
	if not game_manager.play_history.is_empty():
		var last = game_manager.play_history.back()
		if not last["cards"].is_empty():
			last_play_player_label.text = last["player"]
			var hbox = HBoxContainer.new()
			hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_theme_constant_override("separation", 4)
			hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			for card in last["cards"]:
				hbox.add_child(_make_card(card, CARD_SIZE_MINI))
			last_play_card_container.add_child(hbox)

	await get_tree().process_frame
	table_scroll.scroll_vertical = int(table_scroll.get_v_scroll_bar().max_value)


func _update_avatars() -> void:
	var current = game_manager.get_current_player()
	for i in 3:
		var player = game_manager.players[i + 1]
		var is_active = current.id == player.id
		avatars[i].set_count(player.hand.size())
		avatars[i].set_active(is_active)
		avatars[i].set_thinking(is_active and is_ai_turn)


func _update_status() -> void:
	_update_objective_banner()
	if game_manager.game_over:
		status_label.visible = false
		_show_win_screen(game_manager.winner.name)
		return
	var current = game_manager.get_current_player()
	_set_status("Your turn!" if current.id == 0 else _display_name(current.id) + " is thinking...")


func _update_objective_banner() -> void:
	if GameSession.mode != GameSession.Mode.PUZZLE or puzzle.is_empty():
		return
	var objective = puzzle.get("objective", {})
	var text = PuzzleManager.objective_text(objective)
	if String(objective.get("type", "win")) == "win_in":
		text += "  (%d used)" % human_plays
	objective_label.text = text


# =============================================================
# INPUT
# =============================================================

func _on_play_pressed() -> void:
	if is_ai_turn or is_dealing:
		return
	if _tut_guided():
		_tut_handle_play(hand_fan.get_selected())
		return
	var selected = hand_fan.get_selected()
	if selected.is_empty():
		_set_status("Select cards first!")
		return

	# Capture flight origins before the fan reflows
	var origins = []
	for card in selected:
		origins.append(hand_fan.global_origin_of(card))

	if game_manager.try_play(selected):
		await _commit_human_play(origins, selected)
	else:
		hand_fan.shake(selected)
		_set_status("Invalid play. Try again!")


# Shared post-play flow for button, double-click, and drag-drop plays
func _commit_human_play(origins: Array, cards: Array) -> void:
	human_plays += 1
	if cards.size() >= 2 and GameSession.mode != GameSession.Mode.TUTORIAL:
		StatsManager.record_combo()
	SoundManager.play("card_play")
	hand_fan.sync(game_manager.players[0].hand, false)
	_update_avatars()
	_update_pass_button()
	await _animate_play(origins, cards)
	if not is_inside_tree():
		return
	_refresh_table()
	await _after_turn(0, true, false, cards, -1)
	if not is_inside_tree():
		return
	_refresh_hand()
	_update_status()


# Double-click plays a card immediately if it's a legal single
func _on_card_double_clicked(card: Card) -> void:
	if is_ai_turn or is_dealing:
		return
	if _tut_guided():
		_tut_handle_play([card])
		return
	var origins = [hand_fan.global_origin_of(card)]
	if game_manager.try_play([card]):
		await _commit_human_play(origins, [card])
	else:
		hand_fan.shake([card])
		_set_status("Can't play that as a single!")


# --- drag-to-play plumbing ---

func _on_play_drag_started() -> void:
	drop_zone.visible = true


func _on_play_drag_moved(global_pos: Vector2) -> void:
	drop_zone.set_hovered(drop_zone.get_global_rect().has_point(global_pos))


func _on_play_drag_ended() -> void:
	drop_zone.visible = false


func _on_play_dropped(cards: Array, global_pos: Vector2) -> void:
	drop_zone.visible = false
	if is_ai_turn or is_dealing or cards.is_empty():
		hand_fan.return_play_drag()
		return
	if _tut_guided():
		hand_fan.return_play_drag()   # settle cards, then validate the attempt
		_tut_handle_play(cards)
		return
	if not drop_zone.get_global_rect().has_point(global_pos):
		# Dropped outside the zone — cards glide home, selection kept
		hand_fan.return_play_drag()
		return

	var origins = []
	for card in cards:
		origins.append(hand_fan.global_origin_of(card))
	if game_manager.try_play(cards):
		await _commit_human_play(origins, cards)
	else:
		hand_fan.return_play_drag()
		hand_fan.shake(cards)
		_set_status("Invalid play. Try again!")


func _on_pass_pressed() -> void:
	if is_ai_turn or is_dealing:
		return
	if _tut_guided():
		_tut_handle_pass()
		return
	if game_manager.table_cards.is_empty():
		_set_status("Can't pass. You must play!")
		return
	game_manager.try_pass()
	var cleared = game_manager.table_cards.is_empty()
	SoundManager.play("table_clear" if cleared else "pass")
	hand_fan.clear_selection()
	if cleared:
		_animate_table_clear()
	_refresh_table()
	_update_avatars()
	await get_tree().process_frame
	await _after_turn(0, false, cleared, [], -1)
	if not is_inside_tree():
		return
	_refresh_hand()


func _on_emote_pressed(emote: String, source_btn: Button) -> void:
	# Spawn centered above the clicked button, drifting up as it fades
	var popup = UIFactory.make_label(emote, 28, Color.WHITE)
	popup.size = Vector2(40, 32)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.z_index = 100  # above fanned cards and panels
	add_child(popup)
	var btn_center = source_btn.global_position + source_btn.size / 2
	popup.global_position = btn_center + Vector2(-popup.size.x / 2, -50 - popup.size.y)

	var tween = create_tween().set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 60.0, 1.5)
	tween.tween_property(popup, "modulate:a", 0.0, 1.5)
	tween.chain().tween_callback(func():
		if is_instance_valid(popup):
			popup.queue_free()
	)


# =============================================================
# AI TURN LOOP
# =============================================================

func _run_ai_turns() -> void:
	if ai_chain_running:
		return  # re-entrancy guard: a loop is already driving the AI
	ai_chain_running = true
	while not game_manager.game_over:
		# Modal dialog open — hold the AI until it closes
		while ui_locked:
			await get_tree().create_timer(0.15).timeout
			if not is_inside_tree():
				return
		var current = game_manager.get_current_player()
		if current.id == 0:
			break

		_update_status()
		_update_avatars()
		var prev_owner = game_manager.last_player_index
		var table_had_cards = not game_manager.table_cards.is_empty()
		var played = ai_player.take_turn(current)
		var played_cards: Array = game_manager.play_history.back()["cards"] if played else []
		var table_cleared = table_had_cards and game_manager.table_cards.is_empty()

		# "ipit": an ally just beat the rival's table-topping play
		var ipit_victim = -1
		if played and prev_owner == ai_player.rival_id and prev_owner != current.id \
				and ai_player.role_by_id.get(current.id, AIPlayer.Role.NEUTRAL) == AIPlayer.Role.ALLY:
			ipit_victim = prev_owner

		if played:
			SoundManager.play("card_play")
			await _animate_play(
					[avatars[current.id - 1].global_circle_center()], played_cards)
			if not is_inside_tree():
				return
		elif table_cleared:
			SoundManager.play("table_clear")
			_animate_table_clear()
		else:
			SoundManager.play("pass")
		_refresh_table()
		_update_avatars()
		await get_tree().process_frame

		await _after_turn(current.id, played, table_cleared, played_cards, ipit_victim)
		if not is_inside_tree():
			return

		if game_manager.game_over:
			break

		# Variable pause so the AI feels like it's thinking
		await get_tree().create_timer(randf_range(0.4, 0.9)).timeout

	ai_chain_running = false
	is_ai_turn = false
	_refresh_hand()
	_update_status()
	_update_avatars()


# =============================================================
# WIN SCREEN
# =============================================================

func _show_win_screen(winner_name: String) -> void:
	if win_screen_shown:
		return
	win_screen_shown = true
	SoundManager.play("win")
	# Record immediately (synchronous save) so even closing the window
	# during the win moment can't lose the result
	var summary = _record_result()

	# Celebratory pop on the winning cards
	for child in last_play_card_container.get_children():
		child.pivot_offset = child.size / 2
		var pop = create_tween()
		pop.tween_property(child, "scale", Vector2(1.18, 1.18), 0.18) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(child, "scale", Vector2.ONE, 0.2)

	# Dim the table underneath
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	UIFactory.fill_viewport(dim)
	create_tween().tween_property(dim, "color:a", 0.4, 0.4)

	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	if GameSession.mode == GameSession.Mode.TUTORIAL:
		_show_tutorial_end()
		return
	if GameSession.mode == GameSession.Mode.STORY:
		_show_story_end()
		return
	if GameSession.mode == GameSession.Mode.PUZZLE:
		_show_puzzle_end()
		return
	WinScreen.show(self, winner_name, Callable(self, "_on_play_again_pressed"),
			Callable(self, "_on_win_to_menu"), summary, _win_rating_countup)


# Record the finished game exactly once; returns WinScreen summary lines
func _record_result() -> Array:
	if match_recorded:
		return []
	match_recorded = true
	_win_rating_countup = {}
	# The tutorial is practice — never touch stats, rating, or achievements.
	if GameSession.mode == GameSession.Mode.TUTORIAL:
		return []
	var human_won = game_manager.winner.id == 0
	var flawless = human_won and _is_flawless_win()
	var sf_finish = human_won and _finished_with_straight_flush()
	var lines: Array = []

	match GameSession.mode:
		GameSession.Mode.STORY:
			StatsManager.record_story(human_won, flawless, human_plays)
			if human_won:
				StoryManager.complete_chapter(GameSession.story_chapter_id)
			# story shows its own end screen — no summary lines
		GameSession.Mode.PUZZLE:
			var final_type = _play_type_name(game_manager.play_history.back()["cards"])
			puzzle_solved_this_run = PuzzleManager.objective_met(
					puzzle.get("objective", {}), human_won, human_plays, final_type)
			if puzzle_solved_this_run:
				puzzle_new_best = PuzzleManager.mark_solved(String(puzzle["id"]), human_plays)
			StatsManager.save()  # persist global records (combos) touched mid-game
		GameSession.Mode.RANKED:
			var old_rating = StatsManager.rating
			if human_won:
				var breakdown = StatsManager.record_ranked_win(flawless, sf_finish, human_plays)
				for entry in breakdown:
					lines.append("%+d  %s" % [entry["delta"], entry["label"]])
			else:
				var delta = StatsManager.record_ranked_loss()
				lines.append("%+d  ranked loss" % delta)
			# The final "Rating N · Rank" line is rendered by WinScreen as an
			# animated count-up from the pre-match value, so it's not a static line.
			_win_rating_countup = {
				"from": old_rating,
				"to": StatsManager.rating,
				"rank": StatsManager.get_rank_name(),
			}
		_:
			StatsManager.record_casual(human_won, flawless, human_plays)
			lines = ["Casual match, no rating change"]

	# Achievements check AFTER all stats/progression updates, every mode
	var newly = AchievementManager.evaluate({
		"straight_flush_finish": human_won and sf_finish,
	})
	_show_achievement_toasts(newly)
	return lines


# Flawless: every opponent still holds 10+ cards
func _is_flawless_win() -> bool:
	for i in range(1, GameManager.PLAYER_COUNT):
		if game_manager.players[i].hand.size() < 10:
			return false
	return true


func _finished_with_straight_flush() -> bool:
	var last = game_manager.play_history.back()
	return last["cards"].size() == 5 \
			and HandEvaluator.get_play_type(last["cards"]) == HandEvaluator.PlayType.STRAIGHT_FLUSH


func _on_play_again_pressed() -> void:
	for child in get_children():
		child.queue_free()
	avatars.clear()
	is_ai_turn = false
	hand_custom_order = false
	await get_tree().process_frame
	_build_layout()
	_start_game()


# Leave to the menu from the win screen. The game is already over and the
# result was recorded once in _record_result, so this path records nothing
# and needs no forfeit or confirm dialog.
func _on_win_to_menu() -> void:
	TransitionManager.change_scene("res://MainMenu.tscn")


# =============================================================
# STORY MODE
# =============================================================

func _setup_story_ai() -> void:
	var seats = story_chapter.get("seats", {})
	seat_char_ids = ["", _seat_char_id(seats, "rival"),
			_seat_char_id(seats, "seat3"), _seat_char_id(seats, "seat4")]
	ai_player.rival_id = 1
	ai_player.difficulty_by_id = {}
	ai_player.role_by_id = {}
	for i in [1, 2, 3]:
		var character = ContentManager.get_character(seat_char_ids[i])
		ai_player.difficulty_by_id[i] = ContentManager.ai_difficulty(character)
		ai_player.role_by_id[i] = _seat_role(seats, i)

	turn_counter = 0
	last_bark_turn = -99
	bark_once = {}
	table_cleared_count = 0
	event_fired = []
	event_fired.resize(story_chapter.get("match_events", []).size())
	event_fired.fill(false)


func _apply_story_seats() -> void:
	for i in 3:
		var idx = i + 1
		var character = ContentManager.get_character(seat_char_ids[idx])
		avatars[i].set_identity(String(character.get("display_name", "?")),
				ContentManager.initials(character))
		if idx == 1:  # rival accent
			avatars[i].set_accent(ThemeManager.get_color(ContentManager.theme_color_key(character)))


func _seat_char_id(seats: Dictionary, key: String) -> String:
	var value = seats.get(key, "")
	if value is Dictionary:
		return String(value.get("character", ""))
	return String(value)


func _seat_role(seats: Dictionary, index: int) -> int:
	if index <= 1:
		return AIPlayer.Role.NEUTRAL   # rival is a plain opponent
	var seat = seats.get("seat%d" % (index + 1), {})  # index 2 -> seat3, 3 -> seat4
	if seat is Dictionary:
		return _role_from_string(String(seat.get("role", "neutral")))
	return AIPlayer.Role.NEUTRAL


func _role_from_string(role: String) -> int:
	match role:
		"ally": return AIPlayer.Role.ALLY
		"rival2": return AIPlayer.Role.RIVAL2
		_: return AIPlayer.Role.NEUTRAL


func _seat_index(key: String) -> int:
	match key:
		"rival": return 1
		"seat3": return 2
		"seat4": return 3
	return -1


func _display_name(index: int) -> String:
	var named = GameSession.mode == GameSession.Mode.STORY \
			or GameSession.mode == GameSession.Mode.TUTORIAL
	if named and index >= 1 and index < seat_char_ids.size():
		return String(ContentManager.get_character(seat_char_ids[index]).get("display_name", ""))
	return game_manager.players[index].name


# Runs after every turn in story mode: fires match events (blocking
# modal) then a bark (non-blocking). A no-op in casual/ranked.
func _after_turn(actor_index: int, played: bool, table_cleared: bool,
		played_cards: Array, ipit_victim: int) -> void:
	if GameSession.mode != GameSession.Mode.STORY:
		return
	turn_counter += 1
	if table_cleared:
		table_cleared_count += 1

	var event = _check_match_events(actor_index, played_cards, table_cleared)
	if not event.is_empty():
		_trigger_match_event(event)   # in-game popup, non-blocking

	_evaluate_barks(actor_index, played_cards, table_cleared, ipit_victim)


# --- match events ---

func _check_match_events(actor_index: int, played_cards: Array, table_cleared: bool) -> Dictionary:
	var events = story_chapter.get("match_events", [])
	for i in events.size():
		if i < event_fired.size() and event_fired[i]:
			continue
		var ev = events[i]
		if _event_matches(ev.get("trigger", {}), actor_index, played_cards, table_cleared):
			if ev.get("once", true) and i < event_fired.size():
				event_fired[i] = true
			return ev
	return {}


func _event_matches(trigger: Dictionary, actor_index: int, played_cards: Array,
		table_cleared: bool) -> bool:
	var value = int(trigger.get("value", 0))
	match String(trigger.get("type", "")):
		"player_cards_left":
			return game_manager.players[0].hand.size() <= value
		"rival_cards_left":
			return game_manager.players[1].hand.size() <= value
		"turn_number":
			return turn_counter >= value
		"player_played_combo":
			return actor_index == 0 and _play_type_name(played_cards) == String(trigger.get("value", ""))
		"table_cleared_count":
			return table_cleared_count >= value
	return false


func _play_type_name(cards: Array) -> String:
	if cards.is_empty():
		return ""
	return HandEvaluator.PlayType.keys()[HandEvaluator.get_play_type(cards)]


# Match events play as non-blocking in-game speech bubbles near the
# speaker (like barks) rather than a full-screen dialog takeover. The
# actions (e.g. set_role) apply immediately at the dramatic beat.
func _trigger_match_event(ev: Dictionary) -> void:
	for action in ev.get("actions", []):
		if action.has("set_role"):
			var sr = action["set_role"]
			var idx = _seat_index(String(sr.get("seat", "")))
			if idx >= 1:
				ai_player.role_by_id[idx] = _role_from_string(String(sr.get("role", "neutral")))
	_play_event_bubbles(ev.get("lines", []).duplicate())


# Fire-and-forget: each event line pops as a speech bubble in turn.
func _play_event_bubbles(lines: Array) -> void:
	for line in lines:
		if not is_inside_tree():
			return
		var speaker = String(line.get("speaker", ""))
		_show_speech_bubble(_speaker_seat_index(speaker), String(line.get("text", "")),
				_speaker_accent(speaker), 3.0)
		await get_tree().create_timer(2.4).timeout


func _speaker_seat_index(speaker_id: String) -> int:
	if speaker_id == "player":
		return 0
	for i in [1, 2, 3]:
		if seat_char_ids[i] == speaker_id:
			return i
	return -1


func _speaker_accent(speaker_id: String) -> Color:
	if speaker_id.is_empty() or speaker_id == "player":
		return ThemeManager.get_color("status_color")
	return ThemeManager.get_color(
			ContentManager.theme_color_key(ContentManager.get_character(speaker_id)))


# --- barks ---

func _evaluate_barks(actor_index: int, played_cards: Array, table_cleared: bool,
		ipit_victim: int) -> void:
	# got_ipit is the highest-priority reaction
	if ipit_victim >= 1 and _maybe_bark(ipit_victim, "got_ipit", false):
		return
	# the actor is about to win
	if actor_index >= 1 and game_manager.players[actor_index].hand.size() <= 1 \
			and _maybe_bark(actor_index, "self_winning_soon", true):
		return
	# the actor played a five-card combo
	if actor_index >= 1 and played_cards.size() == 5 \
			and _maybe_bark(actor_index, "played_big_combo", false):
		return
	# the human is running low — the first character with a line reacts
	if game_manager.players[0].hand.size() <= 3:
		for idx in [1, 2, 3]:
			if _maybe_bark(idx, "player_low_cards", true):
				return
	# an AI is running low
	for idx in [1, 2, 3]:
		if game_manager.players[idx].hand.size() <= 3 and _maybe_bark(idx, "self_low_cards", true):
			return
	# the table just cleared — its new leader reacts
	if table_cleared and game_manager.current_player_index >= 1:
		_maybe_bark(game_manager.current_player_index, "table_cleared", false)


# Respects the global 1-bark-per-2-turns cooldown and per-trigger once
# flags. Returns true if a bark was shown.
func _maybe_bark(seat_index: int, trigger: String, once: bool) -> bool:
	if turn_counter - last_bark_turn < 2:
		return false
	var char_id = seat_char_ids[seat_index]
	var character = ContentManager.get_character(char_id)
	var pool = ContentManager.bark_lines(character, trigger)
	if pool.is_empty():
		return false
	var key = char_id + ":" + trigger
	if once and bark_once.has(key):
		return false
	if once:
		bark_once[key] = true
	last_bark_turn = turn_counter
	_show_speech_bubble(seat_index, String(pool[randi() % pool.size()]),
			ThemeManager.get_color(ContentManager.theme_color_key(character)), 2.6)
	return true


# Shared speech bubble for barks and match events. The label is anchored
# into the fixed-size bubble so autowrap actually wraps (a free Label
# grows to its text and overflows); the bubble auto-heights to the text.
# seat_index 1-3 -> near that avatar; 0 or -1 -> above the player's hand.
func _show_speech_bubble(seat_index: int, text: String, accent: Color, duration: float) -> void:
	var width = 244.0
	var est_lines = maxi(1, ceili(text.length() / 30.0))
	var height = 22.0 + est_lines * 19.0
	var anchor := Vector2(BASE_W / 2, BASE_H - 244)  # default: above the hand
	if seat_index >= 1 and seat_index <= 3:
		anchor = avatars[seat_index - 1].global_circle_center() + Vector2(0, 42)

	var bubble = Panel.new()
	bubble.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 8, 2, accent))
	bubble.size = Vector2(width, height)
	bubble.z_index = 95
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.position = Vector2(
			clampf(anchor.x - width / 2, 8, BASE_W - width - 8),
			clampf(anchor.y, 88, BASE_H - height - 56))
	add_child(bubble)

	var label = UIFactory.make_label(text, 13, ThemeManager.get_color("text_primary"))
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 8
	label.offset_top = 5
	label.offset_right = -8
	label.offset_bottom = -5
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble.add_child(label)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(bubble, "position:y", bubble.position.y - 28.0, duration)
	tween.tween_property(bubble, "modulate:a", 0.0, duration).set_delay(duration * 0.55)
	tween.set_parallel(false)
	tween.tween_callback(func():
		if is_instance_valid(bubble):
			bubble.queue_free()
	)


# --- story end flow ---

func _show_story_end() -> void:
	var human_won = game_manager.winner.id == 0
	var scene = story_chapter.get("scenes", {}).get("win" if human_won else "lose", [])
	if scene.is_empty():
		_show_story_end_panel(human_won)
	else:
		DialogueScreen.play(self, scene, _on_story_scene_done.bind(human_won), false, true)


func _on_story_scene_done(won: bool) -> void:
	_show_story_end_panel(won)


func _show_story_end_panel(won: bool) -> void:
	var overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 135
	add_child(overlay)
	UIFactory.fill_viewport(overlay)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	UIFactory.fill_viewport(dim)

	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 16))
	panel.size = Vector2(440, 210)
	panel.position = get_viewport_rect().size / 2 - panel.size / 2
	overlay.add_child(panel)

	var title = UIFactory.make_label("You Win! 🎉" if won else "You Lost... 😅", 26,
			ThemeManager.get_color("status_color"), Vector2(0, 28))
	title.size = Vector2(panel.size.x, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var chapter_label = UIFactory.make_label(String(story_chapter.get("title", "")), 14,
			ThemeManager.get_color("text_soft"), Vector2(0, 72))
	chapter_label.size = Vector2(panel.size.x, 20)
	chapter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(chapter_label)

	var retry = story_chapter.get("on_lose", {}).get("retry", true)
	if won:
		_story_end_button(panel, "▸  Continue", Vector2((panel.size.x - 190) / 2, 140), _return_to_story)
	elif retry:
		_story_end_button(panel, "Retry", Vector2(46, 140), _retry_story)
		_story_end_button(panel, "Back", Vector2(234, 140), _return_to_story)
	else:
		_story_end_button(panel, "Back", Vector2((panel.size.x - 190) / 2, 140), _return_to_story)


func _story_end_button(parent: Control, text: String, pos: Vector2, handler: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.position = pos
	btn.size = Vector2(160, 44)
	btn.add_theme_font_size_override("font_size", 13)
	UIFactory.style_button(btn, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected"), ThemeManager.get_color("button_text"))
	btn.pressed.connect(handler)
	parent.add_child(btn)


func _retry_story() -> void:
	GameSession.story_skip_intro = true
	_on_play_again_pressed()


func _return_to_story() -> void:
	GameSession.return_to_story = true
	TransitionManager.change_scene("res://MainMenu.tscn")


# =============================================================
# PUZZLE MODE — end panel + achievement toasts
# =============================================================

func _show_puzzle_end() -> void:
	var overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 135
	add_child(overlay)
	UIFactory.fill_viewport(overlay)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	UIFactory.fill_viewport(dim)

	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 16))
	panel.size = Vector2(460, 226)
	panel.position = get_viewport_rect().size / 2 - panel.size / 2
	overlay.add_child(panel)

	var title = UIFactory.make_label(
			"Puzzle Solved! 🧩" if puzzle_solved_this_run else "Puzzle Failed 😅", 26,
			ThemeManager.get_color("status_color"), Vector2(0, 26))
	title.size = Vector2(panel.size.x, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var detail_text: String
	if puzzle_solved_this_run:
		detail_text = "Cleared in %d plays" % human_plays
		if puzzle_new_best:
			detail_text += ", new best!"
	elif game_manager.winner != null and game_manager.winner.id == 0:
		detail_text = "You won the round, but missed the objective."
	else:
		detail_text = "You lost the round. Study the deal and try again."

	var subtitle = UIFactory.make_label(String(puzzle.get("title", "")), 14,
			ThemeManager.get_color("text_soft"), Vector2(0, 70))
	subtitle.size = Vector2(panel.size.x, 20)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subtitle)

	var detail = UIFactory.make_label(detail_text, 12,
			ThemeManager.get_color("text_muted"), Vector2(0, 96))
	detail.size = Vector2(panel.size.x, 18)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(detail)

	if puzzle_solved_this_run:
		var next_id = _next_puzzle_id()
		if next_id != "":
			_story_end_button(panel, "▸  Next Puzzle", Vector2(46, 156),
					_start_next_puzzle.bind(next_id))
			_story_end_button(panel, "Back", Vector2(234, 156), _return_to_puzzles)
		else:
			_story_end_button(panel, "Back", Vector2((panel.size.x - 160) / 2, 156),
					_return_to_puzzles)
	else:
		_story_end_button(panel, "Retry", Vector2(46, 156), _on_play_again_pressed)
		_story_end_button(panel, "Back", Vector2(234, 156), _return_to_puzzles)


# Next puzzle in order that is unlocked (solving this one usually
# unlocks it), or "" when this was the last one
func _next_puzzle_id() -> String:
	var found_current = false
	for entry in ContentManager.puzzles_ordered:
		if found_current and PuzzleManager.is_unlocked(String(entry["id"])):
			return String(entry["id"])
		if String(entry["id"]) == String(puzzle.get("id", "")):
			found_current = true
	return ""


func _start_next_puzzle(next_id: String) -> void:
	GameSession.puzzle_id = next_id
	_on_play_again_pressed()  # rebuild + restart reads the new id


func _return_to_puzzles() -> void:
	GameSession.return_to_puzzles = true
	TransitionManager.change_scene("res://MainMenu.tscn")


# Slide-in toasts, top-right, one per newly unlocked achievement
func _show_achievement_toasts(unlocked: Array) -> void:
	for i in unlocked.size():
		_spawn_achievement_toast(unlocked[i], i)


func _spawn_achievement_toast(achievement: Dictionary, index: int) -> void:
	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel", UIFactory.flat_style(
			ThemeManager.get_color("panel_bg"), 10, 2, ThemeManager.get_color("selected")))
	panel.size = Vector2(300, 58)
	panel.position = Vector2(BASE_W, 88 + index * 68)  # starts offscreen right
	panel.z_index = 110
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var icon = UIFactory.make_label(String(achievement.get("icon", "🏆")), 24,
			Color.WHITE, Vector2(12, 12))
	panel.add_child(icon)
	panel.add_child(UIFactory.make_label("Achievement unlocked!", 10,
			ThemeManager.get_color("text_muted"), Vector2(52, 8)))
	panel.add_child(UIFactory.make_label(String(achievement.get("name", "")), 14,
			ThemeManager.get_color("status_color"), Vector2(52, 26)))

	var tween = create_tween()
	tween.tween_interval(0.15 + index * 0.35)
	tween.tween_callback(func(): SoundManager.play("card_play"))
	tween.tween_property(panel, "position:x", BASE_W - 312.0, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.8)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func():
		if is_instance_valid(panel):
			panel.queue_free()
	)


# =============================================================
# TUTORIAL MODE — guided first match taught by Lolo Carding
#
# The driver walks TutorialManager.STEPS. For each step it (1) arranges the
# board — scripting the opponents or resetting to a player lead — then
# (2) shows Lolo's persistent instruction, spotlights the target, and locks
# the hand to just the cards that step needs. Player input is gated against
# the step's requirement; the wrong move gets a gentle correction and no
# state change, so the tutorial can never soft-lock. The last step removes
# the locks and hands off to the normal AI loop (EASY + deterministic).
# =============================================================

func _reset_tutorial_state() -> void:
	_tut_active = false
	_tut_free_play = false
	_tut_step_index = 0
	_tut_awaiting = false
	_tut_required = {}
	_tut_allowed_cards = []
	_tut_raised = []       # the nodes themselves are freed on rebuild
	_tut_dim = null
	_tut_bubble = null


func _setup_tutorial_ai() -> void:
	var seats = ContentManager.get_tutorial().get("seats", {})
	seat_char_ids = ["", _seat_char_id(seats, "rival"),
			_seat_char_id(seats, "seat3"), _seat_char_id(seats, "seat4")]
	ai_player.rival_id = 1
	ai_player.difficulty = AIPlayer.Difficulty.EASY
	ai_player.deterministic = true    # fully predictable for teaching
	ai_player.difficulty_by_id = {}
	ai_player.role_by_id = {}


func _tut_begin() -> void:
	_tut_active = true
	_tut_free_play = false
	_tut_dim = ColorRect.new()
	_tut_dim.color = Color(0, 0, 0, 0.0)
	_tut_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE   # visual only; locks gate input
	_tut_dim.z_index = 80
	add_child(_tut_dim)
	UIFactory.fill_viewport(_tut_dim)
	create_tween().tween_property(_tut_dim, "color:a", 0.6, 0.25)
	_tut_run()


func _tut_run() -> void:
	for i in range(TutorialManager.count()):
		_tut_step_index = i
		var step = TutorialManager.step(i)
		await _tut_setup(step)
		if not is_inside_tree():
			return
		if String(step["require"]["type"]) == "free":
			_tut_enter_free_play(step)
			return
		_tut_present(step)
		_tut_awaiting = true
		await _tut_step_signal
		_tut_awaiting = false
		if not is_inside_tree():
			return


# Arrange the board so the upcoming step's action is exactly achievable.
func _tut_setup(step: Dictionary) -> void:
	match String(step["id"]):
		"beat":
			# One opponent tops the 3♣, the rest yield → player follows a single
			await _tut_opponents([{"do": "beat_lowest"}, {"do": "pass"}, {"do": "pass"}])
		"pass":
			# Lolo drops the 2♦ (the boss card) over the player's 2♠ → unbeatable
			await _tut_opponents([{"do": "play_code", "code": "2D"}, {"do": "pass"}, {"do": "pass"}])
		"pair":
			# Player just passed; hand the fresh lead back to them
			_tut_reset_to_player_lead()
		"straight", "help":
			# Nobody can top the player's lead → table clears back to the player
			await _tut_opponents([{"do": "pass"}, {"do": "pass"}, {"do": "pass"}])
		# "lead3c" and "free" need no board setup


# Run the scripted opponents in turn order until control returns to the player.
func _tut_opponents(plans: Array) -> void:
	for plan in plans:
		if not is_inside_tree() or game_manager.game_over:
			return
		if game_manager.current_player_index == 0:
			return
		await _tut_opponent_move(game_manager.current_player_index, plan)
		if not is_inside_tree():
			return
		await get_tree().create_timer(0.5).timeout


func _tut_opponent_move(pid: int, plan: Dictionary) -> void:
	is_ai_turn = true
	_update_status()
	_update_avatars()
	await get_tree().create_timer(0.45).timeout
	if not is_inside_tree():
		return
	var table_had = not game_manager.table_cards.is_empty()
	var cards = _tut_pick_cards(pid, plan)
	var played = false
	if cards.is_empty():
		game_manager.try_pass()
	else:
		played = game_manager.try_play(cards)
		if not played:
			game_manager.try_pass()   # safety: never stall
	var played_cards: Array = game_manager.play_history.back()["cards"] if played else []
	var table_cleared = table_had and game_manager.table_cards.is_empty()
	if played:
		SoundManager.play("card_play")
		await _animate_play([avatars[pid - 1].global_circle_center()], played_cards)
		if not is_inside_tree():
			return
	elif table_cleared:
		SoundManager.play("table_clear")
		_animate_table_clear()
	else:
		SoundManager.play("pass")
	_refresh_table()
	_update_avatars()


func _tut_pick_cards(pid: int, plan: Dictionary) -> Array:
	var hand: Array = game_manager.players[pid].hand
	var table: Array = game_manager.table_cards
	match String(plan.get("do", "pass")):
		"pass":
			return []
		"lead_lowest":
			return [Card.sort_cards(hand)[0]]
		"beat_lowest":
			for card in Card.sort_cards(hand):
				if HandEvaluator.can_beat(table, [card]):
					return [card]
			return []
		"play_code":
			var code = String(plan.get("code", ""))
			for card in hand:
				if _card_code(card) == code \
						and (table.is_empty() or HandEvaluator.can_beat(table, [card])):
					return [card]
			return []
	return []


# Narrated hand-back of the lead after the player passes (step 3 → 4).
func _tut_reset_to_player_lead() -> void:
	game_manager.table_cards = []
	game_manager.last_player_index = 0
	game_manager.current_player_index = 0
	game_manager.pass_count = 0
	game_manager.play_history.append({"player": "---", "cards": []})
	is_ai_turn = false
	hand_fan.sync(game_manager.players[0].hand, false)
	_refresh_table()
	_update_avatars()


# --- present a step: instruction bubble + input lock + spotlight ---

func _tut_present(step: Dictionary) -> void:
	_tut_show_bubble(String(step["text"]))
	_tut_apply_lock(step)
	_tut_apply_highlight(String(step["highlight"]))


func _tut_apply_lock(step: Dictionary) -> void:
	var req: Dictionary = step["require"]
	var rtype = String(req["type"])
	_tut_required = req
	is_ai_turn = false
	hand_fan.clear_selection()
	match rtype:
		"play_exact", "play_pair", "play_straight":
			_tut_allowed_cards = _tut_resolve_cards(req.get("cards", []))
			hand_fan.set_input_enabled(true)
			hand_fan.set_selectable(_tut_allowed_cards)
			play_button.disabled = false
			pass_button.disabled = true
		"pass":
			_tut_allowed_cards = []
			hand_fan.set_input_enabled(true)
			hand_fan.set_selectable([])       # nothing selectable — only Pass
			play_button.disabled = true
			pass_button.disabled = false
		"help":
			_tut_allowed_cards = []
			hand_fan.set_input_enabled(true)
			hand_fan.set_selectable([])
			play_button.disabled = true
			pass_button.disabled = true
	settings_button.disabled = true
	sort_button.disabled = true
	help_button.disabled = rtype != "help"


func _tut_apply_highlight(tag: String) -> void:
	_tut_clear_highlight()
	if tag == "none":
		if is_instance_valid(_tut_dim):
			_tut_dim.visible = false
		return
	if is_instance_valid(_tut_dim):
		_tut_dim.visible = true
	# Raise the action area + the table above the dim so it reads as focus
	var targets: Array = [status_label, last_play_panel, hand_fan, buttons_row]
	if tag == "help":
		targets.append(help_button)
	for node in targets:
		if is_instance_valid(node):
			_tut_raised.append({"node": node, "z": node.z_index})
			node.z_index = 82


func _tut_clear_highlight() -> void:
	for entry in _tut_raised:
		if is_instance_valid(entry["node"]):
			entry["node"].z_index = entry["z"]
	_tut_raised.clear()


# Persistent instruction panel (bark-bubble visuals, Lolo's accent).
func _tut_show_bubble(text: String) -> void:
	if is_instance_valid(_tut_bubble):
		_tut_bubble.queue_free()
	var accent = _speaker_accent(TutorialManager.SPEAKER)
	var width = 590.0
	var est_lines = maxi(2, ceili(text.length() / 58.0))
	var height = 34.0 + est_lines * 20.0
	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 10, 2, accent))
	panel.size = Vector2(width, height)
	panel.position = Vector2(BASE_W - width - 20, 150)
	panel.z_index = 96
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_tut_bubble = panel

	var name_tag = UIFactory.make_label("Lolo Carding", 12, accent, Vector2(14, 6))
	panel.add_child(name_tag)

	var label = UIFactory.make_label(text, 14, ThemeManager.get_color("text_primary"))
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 14
	label.offset_top = 28
	label.offset_right = -14
	label.offset_bottom = -8
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)

	panel.modulate.a = 0.0
	panel.create_tween().tween_property(panel, "modulate:a", 1.0, 0.2)


# --- player action gating ---

func _tut_handle_play(cards: Array) -> void:
	if not _tut_awaiting:
		return
	var rtype = String(_tut_required.get("type", ""))
	if not (rtype in ["play_exact", "play_pair", "play_straight"]) \
			or not _tut_play_matches(rtype, cards):
		_tut_correct()
		if not cards.is_empty():
			hand_fan.shake(cards)
		return
	_tut_awaiting = false
	await _tut_commit_play(cards)
	if is_inside_tree():
		_tut_step_signal.emit()


func _tut_commit_play(cards: Array) -> void:
	var origins = []
	for card in cards:
		origins.append(hand_fan.global_origin_of(card))
	if game_manager.try_play(cards):
		await _commit_human_play(origins, cards)
	else:
		hand_fan.shake(cards)   # validated already, but never trust blindly


func _tut_handle_pass() -> void:
	if not _tut_awaiting:
		return
	if String(_tut_required.get("type", "")) != "pass":
		_tut_correct()
		return
	_tut_awaiting = false
	game_manager.try_pass()
	var cleared = game_manager.table_cards.is_empty()
	SoundManager.play("table_clear" if cleared else "pass")
	hand_fan.clear_selection()
	if cleared:
		_animate_table_clear()
	_refresh_table()
	_refresh_hand()
	_update_avatars()
	await get_tree().process_frame
	if is_inside_tree():
		_tut_step_signal.emit()


func _tut_play_matches(rtype: String, cards: Array) -> bool:
	if not _same_card_set(cards, _tut_allowed_cards):
		return false
	match rtype:
		"play_pair":
			return HandEvaluator.get_play_type(cards) == HandEvaluator.PlayType.PAIR
		"play_straight":
			return HandEvaluator.get_play_type(cards) == HandEvaluator.PlayType.STRAIGHT
	return true


func _tut_resolve_cards(codes) -> Array:
	var result = []
	for code in codes:
		for card in game_manager.players[0].hand:
			if _card_code(card) == String(code) and not result.has(card):
				result.append(card)
				break
	return result


func _card_code(card: Card) -> String:
	return card.rank + ["C", "D", "H", "S"][card.suit]


func _same_card_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for card in a:
		if not b.has(card):
			return false
	return true


# A locked-out card was tapped — nudge with the current step's correction.
func _on_illegal_card_tapped() -> void:
	if _tut_guided() and _tut_awaiting:
		_tut_correct()


# Gentle nudge when the player does the wrong thing — the instruction stays.
# Throttled so rapid mis-taps don't spam bubbles.
func _tut_correct() -> void:
	var now = Time.get_ticks_msec()
	if now - _tut_last_correct_ms < 1200:
		return
	_tut_last_correct_ms = now
	var text = String(TutorialManager.step(_tut_step_index).get("correction", ""))
	if text.is_empty():
		text = "Sundin muna natin ang steps, apo."
	_show_speech_bubble(1, text, _speaker_accent(TutorialManager.SPEAKER), 2.4)


# --- free play + end ---

func _tut_enter_free_play(step: Dictionary) -> void:
	_tut_free_play = true
	_tut_awaiting = false
	_tut_clear_highlight()
	hand_fan.clear_selectable()
	settings_button.disabled = false
	sort_button.disabled = false
	help_button.disabled = false
	play_button.disabled = false
	if is_instance_valid(_tut_dim):
		var d = _tut_dim
		var t = create_tween()
		t.tween_property(d, "color:a", 0.0, 0.3)
		t.tween_callback(func():
			if is_instance_valid(d):
				d.queue_free())
		_tut_dim = null
	_tut_show_bubble(String(step["text"]))
	_tut_fade_bubble_later(4.5)
	_refresh_hand()     # resume the normal loop (player is on lead)
	_update_status()


func _tut_fade_bubble_later(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
	if is_instance_valid(_tut_bubble):
		var b = _tut_bubble
		var t = b.create_tween()
		t.tween_property(b, "modulate:a", 0.0, 0.4)
		t.tween_callback(b.queue_free)


func _show_tutorial_end() -> void:
	# The tutorial counts as done whether won or lost (or replayed).
	Settings.tutorial_completed = true
	Settings.save_settings()
	var won = game_manager.winner != null and game_manager.winner.id == 0

	var overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 135
	add_child(overlay)
	UIFactory.fill_viewport(overlay)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	UIFactory.fill_viewport(dim)

	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 16))
	panel.size = Vector2(480, 250)
	panel.position = get_viewport_rect().size / 2 - panel.size / 2
	overlay.add_child(panel)

	var title = UIFactory.make_label("Tutorial Complete! 🎉", 24,
			ThemeManager.get_color("status_color"), Vector2(0, 24))
	title.size = Vector2(panel.size.x, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var body = UIFactory.make_label(
			TutorialManager.END_WIN if won else TutorialManager.END_LOSE, 13,
			ThemeManager.get_color("text_soft"))
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 30
	body.offset_top = 66
	body.offset_right = -30
	body.offset_bottom = -84
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(body)

	_story_end_button(panel, "Replay", Vector2(56, 188), _replay_tutorial)
	_story_end_button(panel, "▸  Main menu", Vector2(264, 188), _tut_to_menu)


func _replay_tutorial() -> void:
	GameSession.mode = GameSession.Mode.TUTORIAL
	_on_play_again_pressed()


func _tut_to_menu() -> void:
	TransitionManager.change_scene("res://MainMenu.tscn")


# =============================================================
# DROP ZONE — dashed highlight over the last-play area
# =============================================================

class DropZone:
	extends Control

	var hovered: bool = false

	func _draw() -> void:
		var color = ThemeManager.get_color("selected")
		color.a = 1.0 if hovered else 0.55
		var corners = [
			Vector2.ZERO,
			Vector2(size.x, 0),
			size,
			Vector2(0, size.y),
		]
		for i in 4:
			draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 2.0, 9.0)

	func set_hovered(value: bool) -> void:
		if hovered != value:
			hovered = value
			queue_redraw()
