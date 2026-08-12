# AchievementsScreen.gd
# Achievement gallery overlay. Two-column grid of cards; unlocked cards
# show icon/name/description in full, locked ones are dimmed, and hidden
# locked ones are masked as "???".

class_name AchievementsScreen
extends Control

const PANEL_SIZE = Vector2(760, 560)
const CARD_SIZE = Vector2(338, 82)

var panel: Panel

static func open(parent: Control) -> AchievementsScreen:
	var screen = AchievementsScreen.new()
	parent.add_child(screen)
	return screen


func _ready() -> void:
	UIFactory.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	ContentManager.load_all()
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

	var total = ContentManager.achievements_ordered.size()
	var got = ContentManager.achievements_ordered.filter(
			func(a): return AchievementManager.is_unlocked(String(a["id"]))).size()
	var title = UIFactory.make_label("ACHIEVEMENTS  (%d / %d)" % [got, total], 24,
			ThemeManager.get_color("status_color"), Vector2(0, 18))
	title.size = Vector2(PANEL_SIZE.x, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(24, 62)
	scroll.size = Vector2(PANEL_SIZE.x - 48, PANEL_SIZE.y - 138)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	if ContentManager.achievements_ordered.is_empty():
		grid.add_child(UIFactory.make_label("No achievements yet.", 14,
				ThemeManager.get_color("text_muted")))
	for achievement in ContentManager.achievements_ordered:
		grid.add_child(_make_card(achievement))

	_add_back_button()


func _make_card(achievement: Dictionary) -> Control:
	var unlocked = AchievementManager.is_unlocked(String(achievement["id"]))
	var hidden = bool(achievement.get("hidden", false)) and not unlocked

	var card = Panel.new()
	card.custom_minimum_size = CARD_SIZE
	var border = ThemeManager.get_color("selected") if unlocked \
			else ThemeManager.get_color("border_soft")
	card.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("button_bg"), 8, 2, border))
	card.modulate.a = 1.0 if unlocked else 0.55

	var icon_text = String(achievement.get("icon", "🏆")) if not hidden else "❔"
	var icon = UIFactory.make_label(icon_text, 30, Color.WHITE, Vector2(14, 20))
	card.add_child(icon)

	# Card face is button_bg (light/cream in the classic theme) → on-light text
	var name_text = String(achievement.get("name", "")) if not hidden else "???"
	var name_color = ThemeManager.get_color("text_on_light_primary") if unlocked \
			else ThemeManager.get_color("text_on_light_secondary")
	card.add_child(UIFactory.make_label(name_text, 15, name_color, Vector2(60, 12)))

	var desc_text = "Hidden achievement" if hidden \
			else String(achievement.get("description", ""))
	var desc = UIFactory.make_label(desc_text, 11, ThemeManager.get_color("text_on_light_secondary"))
	desc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desc.offset_left = 60
	desc.offset_top = 36
	desc.offset_right = -10
	desc.offset_bottom = -8
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(desc)

	if unlocked:
		var mark = UIFactory.make_label("✔", 16, ThemeManager.get_color("clubs"),
				Vector2(CARD_SIZE.x - 28, 10))
		card.add_child(mark)
	return card


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
