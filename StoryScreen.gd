# StoryScreen.gd
# Chapter-select overlay for Story Mode. Opened from the main menu.
# Locked / unlocked / completed states; selecting an unlocked chapter
# plays its intro then drops into the match.

class_name StoryScreen
extends Control

const PANEL_SIZE = Vector2(760, 560)
const ROW_HEIGHT = 92.0

var panel: Panel

static func open(parent: Control) -> StoryScreen:
	var screen = StoryScreen.new()
	parent.add_child(screen)
	return screen


func _ready() -> void:
	UIFactory.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Deep guard: bounce out if the feature is locked, whatever the path in.
	if not FeatureFlags.is_enabled("story"):
		_bounce_to_menu()
		return
	ContentManager.load_all()
	_build()


func _bounce_to_menu() -> void:
	if get_tree().current_scene == self:
		TransitionManager.change_scene("res://MainMenu.tscn")
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

	var title = UIFactory.make_label("STORY", 24,
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

	if ContentManager.chapters_ordered.is_empty():
		list.add_child(UIFactory.make_label("No chapters yet.", 14,
				ThemeManager.get_color("text_muted")))
	for chapter in ContentManager.chapters_ordered:
		list.add_child(_make_chapter_row(chapter))

	_add_back_button()


func _make_chapter_row(chapter: Dictionary) -> Control:
	var id = String(chapter["id"])
	var unlocked = StoryManager.is_unlocked(id)
	var completed = StoryManager.is_completed(id)

	var row = Panel.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var border = ThemeManager.get_color("selected") if unlocked and not completed \
			else ThemeManager.get_color("border_soft")
	row.add_theme_stylebox_override("panel", UIFactory.flat_style(
			ThemeManager.get_color("button_bg"), 8, 2, border))
	row.modulate.a = 1.0 if unlocked else 0.5

	var rival = ContentManager.get_character(String(chapter["seats"]["rival"]))
	var num = "Ch. %d" % int(chapter["chapter_number"])

	# Row panel is button_bg (light/cream in the classic theme), so use the
	# on-light token family for its text.
	var num_label = UIFactory.make_label(num, 12,
			ThemeManager.get_color("text_on_light_secondary"), Vector2(16, 12))
	row.add_child(num_label)

	var title = UIFactory.make_label(String(chapter.get("title", id)), 20,
			ThemeManager.get_color("text_on_light_primary"), Vector2(16, 28))
	row.add_child(title)

	var subtitle = UIFactory.make_label(String(chapter.get("subtitle", "")), 12,
			ThemeManager.get_color("text_on_light_secondary"), Vector2(16, 58))
	row.add_child(subtitle)

	var rival_label = UIFactory.make_label("vs %s" % String(rival.get("display_name", "?")), 13,
			ThemeManager.get_color(ContentManager.theme_color_key(rival)), Vector2(PANEL_SIZE.x - 320, 36))
	rival_label.size = Vector2(230, 20)
	rival_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(rival_label)

	if not unlocked:
		var lock = UIFactory.make_label("🔒 %s" % StoryManager.lock_reason(id), 12,
				ThemeManager.get_color("text_on_light_secondary"), Vector2(PANEL_SIZE.x - 320, 60))
		lock.size = Vector2(230, 18)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(lock)
		return row

	if completed:
		var check = UIFactory.make_label("✔ done", 13,
				ThemeManager.get_color("clubs"), Vector2(PANEL_SIZE.x - 320, 60))
		check.size = Vector2(230, 18)
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(check)

	# Whole row is a click target when playable
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(_start_chapter.bind(id))
	row.add_child(btn)
	return row


func _start_chapter(chapter_id: String) -> void:
	GameSession.mode = GameSession.Mode.STORY
	GameSession.story_chapter_id = chapter_id
	GameSession.story_skip_intro = false

	var chapter = ContentManager.get_chapter(chapter_id)
	var intro = chapter.get("scenes", {}).get("intro", [])
	# Capture the host before freeing self; the scene change itself runs on
	# the TransitionManager autoload, so it's safe past this node's free.
	var host = get_tree().current_scene
	queue_free()

	if intro.is_empty():
		TransitionManager.change_scene("res://GameTable.tscn")
	else:
		DialogueScreen.play(host, intro,
				func(): TransitionManager.change_scene("res://GameTable.tscn"))


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
