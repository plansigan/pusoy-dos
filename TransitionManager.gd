# TransitionManager.gd
# Autoload providing one consistent transition system:
#  - change_scene(path): a snappy "dip to dark" scene change (dim in ->
#    swap under the dim -> dim out) instead of a hard cut.
#  - press(button): a quick press-pop for button feedback.
#
# The dim lives on a CanvasLayer above the game (below PixelFilter) so it
# survives the scene swap. A re-entrancy guard means a transition always
# completes and can never soft-lock, even if a caller fires it twice.

extends CanvasLayer

# All timings live here so the whole app feels consistent. Snappy budget.
const DIM_IN := 0.15      # fade to dark
const DIM_OUT := 0.25     # fade back in over the new scene
const DIM_ALPHA := 0.7
const PRESS_HALF := 0.05  # each half of the button press pop
const PRESS_SCALE := 0.96
const STAGGER := 0.045    # per-item stagger for fade-in sequences
const FADE_SLIDE := 10.0  # slide distance for fade-ins

var _dim: ColorRect
var _transitioning := false


func _ready() -> void:
	layer = 90  # above the game (0), below PixelFilter (100)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)


func _process(_delta: float) -> void:
	# Keep the dim covering the viewport (CanvasLayer has no size of its own)
	if _dim.visible:
		_dim.size = get_viewport().get_visible_rect().size


# Dip-to-dark scene change. Fire-and-forget; the caller may free itself.
func change_scene(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	_dim.size = get_viewport().get_visible_rect().size
	_dim.color.a = 0.0
	_dim.visible = true

	# Stage 1 — dim in
	var t_in := create_tween()
	t_in.tween_property(_dim, "color:a", DIM_ALPHA, DIM_IN) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t_in.finished

	# Swap under the dim
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame  # let the new scene build

	# Stage 2 — dim out as the new screen (e.g. the deal) begins
	var t_out := create_tween()
	t_out.tween_property(_dim, "color:a", 0.0, DIM_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t_out.finished

	_dim.visible = false
	_transitioning = false


# Quick press-pop (scale down then back). Tween is bound to the button so
# it auto-cleans if the button is freed by its own handler.
func press(button: Control) -> void:
	if not is_instance_valid(button):
		return
	button.pivot_offset = button.size / 2
	var t := button.create_tween()
	t.tween_property(button, "scale", Vector2(PRESS_SCALE, PRESS_SCALE), PRESS_HALF) \
			.set_trans(Tween.TRANS_SINE)
	t.tween_property(button, "scale", Vector2.ONE, PRESS_HALF).set_trans(Tween.TRANS_SINE)


# Fade + slide a control up into place (used for staggered menu intros).
func fade_in(control: Control, delay: float, target_alpha: float = 1.0) -> void:
	if not is_instance_valid(control):
		return
	var final_y := control.position.y
	control.position.y = final_y + FADE_SLIDE
	control.modulate.a = 0.0
	var t := control.create_tween().set_parallel(true)
	t.tween_property(control, "modulate:a", target_alpha, 0.16) \
			.set_ease(Tween.EASE_OUT).set_delay(delay)
	t.tween_property(control, "position:y", final_y, 0.16) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)


# =============================================================
# MODAL / OVERLAY MOTION  (motion pass)
# =============================================================
# One open/close for every dimmed panel, so nothing pops. Tweens bind to
# the animated node (auto-killed on free) and every entry point guards
# with is_instance_valid, so a panel freed mid-animation never soft-locks.
# The dim's own alpha is the darkness target, so each modal keeps the dim
# strength it chose.
const MODAL_DIM_IN := 0.12        # dim fade-in on open
const MODAL_OPEN := 0.22          # panel rise + fade + settle
const MODAL_CLOSE := 0.15         # close is quicker
const MODAL_RISE := 24.0          # px the panel starts below its rest spot
const MODAL_START_SCALE := 0.97   # settles up to 1.0 with a tiny overshoot

# --- Staggered content entrance (lists / galleries) ---
const STAGGER_STEP := 0.04
const STAGGER_CAP := 0.35         # last animated row still starts within this
const STAGGER_MAX_ROWS := 12      # ~one screenful; extra rows just appear

# --- Toasts ---
const TOAST_IN := 0.26
const TOAST_HOLD := 1.6
const TOAST_OUT := 0.22
const TOAST_DROP := 44.0          # slides in from this far above rest

# --- Reactive juice ---
const SHAKE_PX := 2.0             # invalid-action nudge
const COUNT_TIME := 0.4           # number count-up/down

# --- Achievement banner (queued so unlocks never overlap) ---
const BANNER_IN := 0.34
const BANNER_HOLD := 3.0
const BANNER_OUT := 0.28

var _banner_queue: Array = []
var _banner_running := false


# Fade the dim in while the panel rises, fades, and settles from a tiny
# under-scale. Call right after building the (dim, panel) pair.
func open_modal(dim: ColorRect, panel: Control) -> void:
	if is_instance_valid(dim):
		var target_a := dim.color.a
		dim.color.a = 0.0
		dim.create_tween().tween_property(dim, "color:a", target_a, MODAL_DIM_IN) \
				.set_ease(Tween.EASE_OUT)
	if not is_instance_valid(panel):
		return
	panel.pivot_offset = panel.size / 2.0
	var rest_y := panel.position.y
	panel.position.y = rest_y + MODAL_RISE
	panel.modulate.a = 0.0
	panel.scale = Vector2(MODAL_START_SCALE, MODAL_START_SCALE)
	var t := panel.create_tween().set_parallel(true)
	t.tween_property(panel, "position:y", rest_y, MODAL_OPEN) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "modulate:a", 1.0, MODAL_OPEN).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "scale", Vector2.ONE, MODAL_OPEN) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Reverse of open_modal; on_closed fires once the panel has faded (that's
# where the caller frees the overlay). Bound to the panel, so a panel freed
# out from under it simply cancels — no dangling free, no soft-lock.
func close_modal(dim: ColorRect, panel: Control, on_closed: Callable = Callable()) -> void:
	var driver: Control = panel if is_instance_valid(panel) else dim
	if not is_instance_valid(driver):
		if on_closed.is_valid():
			on_closed.call()
		return
	var t := driver.create_tween().set_parallel(true)
	if is_instance_valid(panel):
		panel.pivot_offset = panel.size / 2.0
		t.tween_property(panel, "position:y", panel.position.y + MODAL_RISE * 0.6, MODAL_CLOSE) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.tween_property(panel, "modulate:a", 0.0, MODAL_CLOSE)
	if is_instance_valid(dim):
		t.tween_property(dim, "color:a", 0.0, MODAL_CLOSE)
	t.chain().tween_callback(func():
		if on_closed.is_valid():
			on_closed.call())


# Stagger a set of rows/cards in (fade + 8px rise). Rows are hidden the
# instant this is called (no first-frame flash), then a frame later — once
# their container has laid them out — they animate. Only the first screenful
# animates; long lists compress the stagger to stay within STAGGER_CAP.
func stagger_in(controls: Array) -> void:
	var count := mini(controls.size(), STAGGER_MAX_ROWS)
	if count <= 0:
		return
	for i in count:
		if is_instance_valid(controls[i]):
			controls[i].modulate.a = 0.0
	await get_tree().process_frame
	var step := STAGGER_STEP
	if (count - 1) * step > STAGGER_CAP:
		step = STAGGER_CAP / float(maxi(1, count - 1))
	for i in count:
		var c: Control = controls[i]
		if not is_instance_valid(c):
			continue
		var final_y := c.position.y
		c.position.y = final_y + 8.0
		var t := c.create_tween().set_parallel(true)
		t.tween_property(c, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT).set_delay(i * step)
		t.tween_property(c, "position:y", final_y, 0.2) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(i * step)


# Subtle horizontal nudge for an invalid action. Bound to the control.
func shake(control: Control, px: float = SHAKE_PX) -> void:
	if not is_instance_valid(control):
		return
	var base_x := control.position.x
	var t := control.create_tween()
	for off in [px, -px, px * 0.6, -px * 0.6, 0.0]:
		t.tween_property(control, "position:x", base_x + off, 0.05).set_trans(Tween.TRANS_SINE)


# Count a label's number from -> to, briefly tinting it the theme accent
# and easing back to its base colour. fmt renders the integer to a string.
func count_number(label: Label, from_v: int, to_v: int, fmt: Callable, accent: Color) -> void:
	if not is_instance_valid(label):
		return
	var base: Color = label.get_theme_color("font_color")
	label.add_theme_color_override("font_color", accent)
	var upd := func(v: float):
		if is_instance_valid(label):
			label.text = String(fmt.call(roundi(v)))
	var t := label.create_tween().set_parallel(true)
	t.tween_method(upd, float(from_v), float(to_v), COUNT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "theme_override_colors/font_color", base, COUNT_TIME) \
			.set_ease(Tween.EASE_IN)


# Top-of-screen toast: slides down with a small overshoot, holds, slides
# back up and fades. Lives on this CanvasLayer, above the scene.
func toast(text: String, accent: Color = Color(0, 0, 0, 0)) -> void:
	var col := accent if accent.a > 0.0 else ThemeManager.get_color("selected")
	var vw := get_viewport().get_visible_rect().size.x
	var width := 440.0
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel",
			UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 10, 2, col))
	panel.size = Vector2(width, 42)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rest_y := 44.0
	panel.position = Vector2((vw - width) / 2.0, rest_y - TOAST_DROP)
	panel.modulate.a = 0.0
	add_child(panel)

	var label := UIFactory.make_label(text, 14, ThemeManager.get_color("text_primary"))
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)

	SoundManager.play("button_click")
	var t := panel.create_tween()
	t.tween_property(panel, "position:y", rest_y, TOAST_IN) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(panel, "modulate:a", 1.0, TOAST_IN * 0.6)
	t.tween_interval(TOAST_HOLD)
	t.tween_property(panel, "position:y", rest_y - TOAST_DROP, TOAST_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(panel, "modulate:a", 0.0, TOAST_OUT)
	t.chain().tween_callback(panel.queue_free)


# Enqueue an achievement banner. A single worker shows them one at a time
# so multiple unlocks never overlap.
func notify_achievement(icon: String, ach_name: String) -> void:
	_banner_queue.append({"icon": icon, "name": ach_name})
	if not _banner_running:
		_run_banners()


func _run_banners() -> void:
	_banner_running = true
	while not _banner_queue.is_empty():
		var data: Dictionary = _banner_queue.pop_front()
		await _show_banner(String(data["icon"]), String(data["name"]))
	_banner_running = false


func _show_banner(icon: String, ach_name: String) -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var width := 340.0
	var accent := ThemeManager.get_color("selected")
	var style := UIFactory.flat_style(ThemeManager.get_color("panel_bg"), 10, 2, accent)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.size = Vector2(width, 60)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rest_y := 16.0
	panel.position = Vector2((vw - width) / 2.0, rest_y - 74.0)
	panel.modulate.a = 0.0
	add_child(panel)

	panel.add_child(UIFactory.make_label(icon, 26, Color.WHITE, Vector2(14, 14)))
	panel.add_child(UIFactory.make_label("Achievement unlocked!", 10,
			ThemeManager.get_color("text_muted"), Vector2(56, 10)))
	panel.add_child(UIFactory.make_label(ach_name, 15,
			ThemeManager.get_color("status_color"), Vector2(56, 28)))

	SoundManager.play("win")
	var t := panel.create_tween()
	t.tween_property(panel, "position:y", rest_y, BANNER_IN) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(panel, "modulate:a", 1.0, BANNER_IN * 0.6)
	# sparkle-free flash: a quick border brighten-and-back
	t.tween_property(style, "border_color", accent.lightened(0.55), 0.16)
	t.tween_property(style, "border_color", accent, 0.34)
	t.tween_interval(BANNER_HOLD)
	t.tween_property(panel, "position:y", rest_y - 74.0, BANNER_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(panel, "modulate:a", 0.0, BANNER_OUT)
	await t.finished
	if is_instance_valid(panel):
		panel.queue_free()
