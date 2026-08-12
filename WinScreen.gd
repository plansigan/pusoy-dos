# WinScreen.gd
# Handles the game over overlay

class_name WinScreen

static func show(parent: Control, winner_name: String, on_play_again: Callable,
		on_main_menu: Callable, summary_lines: Array = [], rating_countup: Dictionary = {}) -> void:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(overlay)
	UIFactory.fill_viewport(overlay)

	var panel_height = 220.0
	if not summary_lines.is_empty():
		panel_height += 10 + summary_lines.size() * 18
	if not rating_countup.is_empty():
		panel_height += 26

	var panel = _make_panel(parent, panel_height)
	overlay.add_child(panel)

	_add_labels(panel, winner_name)

	# Rating breakdown (ranked) or the casual tag
	for i in summary_lines.size():
		var line = UIFactory.make_label(summary_lines[i], 12,
				ThemeManager.get_color("text_secondary"), Vector2(0, 124 + i * 18))
		line.size = Vector2(400, 16)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(line)

	# Ranked: the new rating tallies up from the pre-match value
	if not rating_countup.is_empty():
		_add_rating_countup(panel, rating_countup, 124 + summary_lines.size() * 18 + 6)

	# Play Again stays the primary action (accent border); Main menu is the
	# secondary escape (neutral border, like the Pass button). Both start
	# disabled so a click during the slide-in can't fire mid-animation.
	var button_y = panel_height - 62
	var replay = Button.new()
	replay.text = "Play Again"
	replay.size = Vector2(165, 44)
	replay.position = Vector2(28, button_y)
	replay.disabled = true
	UIFactory.style_button(replay, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("selected"), ThemeManager.get_color("button_text"))
	replay.pressed.connect(on_play_again)
	panel.add_child(replay)

	var menu = Button.new()
	menu.text = "Main menu"
	menu.size = Vector2(165, 44)
	menu.position = Vector2(207, button_y)
	menu.disabled = true
	UIFactory.style_button(menu, ThemeManager.get_color("button_bg"),
			ThemeManager.get_color("border_soft"), ThemeManager.get_color("button_text"))
	menu.pressed.connect(on_main_menu)
	panel.add_child(menu)

	# Slide in from the top over a fading backdrop
	overlay.modulate.a = 0.0
	var final_y = panel.position.y
	panel.position.y = -panel.size.y - 20
	var tween = overlay.create_tween().set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.25)
	tween.tween_property(panel, "position:y", final_y, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Enable the buttons once the entrance settles; focus the primary action
	parent.get_tree().create_timer(0.3).timeout.connect(func():
		if is_instance_valid(replay):
			replay.disabled = false
			replay.grab_focus()
		if is_instance_valid(menu):
			menu.disabled = false)


static func _add_rating_countup(panel: Panel, spec: Dictionary, y: float) -> void:
	var from_v = int(spec.get("from", 0))
	var to_v = int(spec.get("to", from_v))
	var rank = String(spec.get("rank", ""))

	var label = UIFactory.make_label("Rating %d · %s" % [from_v, rank], 15,
			ThemeManager.get_color("status_color"), Vector2(0, y))
	label.size = Vector2(400, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	# Tween is bound to the label, so it auto-cancels if the overlay is
	# dismissed (Play Again) before the tally finishes — no dangling callback.
	var count = label.create_tween()
	count.tween_method(
			func(v): label.text = "Rating %d · %s" % [roundi(v), rank],
			float(from_v), float(to_v), 0.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.35)


static func _make_panel(parent: Control, height: float) -> Panel:
	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 16))
	panel.size = Vector2(400, height)
	panel.position = parent.get_viewport_rect().size / 2 - panel.size / 2
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel


static func _add_labels(panel: Panel, winner_name: String) -> void:
	var title = UIFactory.make_label("Game Over!", 28,
			ThemeManager.get_color("status_color"), Vector2(0, 30))
	title.size = Vector2(400, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var sub = UIFactory.make_label(winner_name + " wins!", 22,
			ThemeManager.get_color("text_primary"), Vector2(0, 85))
	sub.size = Vector2(400, 35)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(sub)
