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
