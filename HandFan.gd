# HandFan.gd
# The player's hand as a fanned arc of cards, like holding real cards.
#
# Owns all hand input via a small state machine:
#   press → (release under 10px) click: toggle select, double-click plays
#         → (move over 10px)     reorder drag: card follows mouse x
#         → (selected card pulled up out of the hand) play drag: all
#           selected cards cluster under the cursor for a table drop
#
# Hit detection transforms the point into each card's local space
# (exact under rotation) and walks cards in reverse z-order — the
# topmost card wins.

class_name HandFan
extends Control

signal selection_changed
signal card_double_clicked(card)
signal order_changed(cards)
signal play_drag_started
signal play_drag_moved(global_pos)
signal play_drag_ended
signal play_dropped(cards, global_pos)
signal illegal_card_tapped          # a locked-out card was pressed (tutorial)

const CARD_SIZE = Vector2(72, 95)
const MAX_SPACING = 56.0        # loosest the fan gets with few cards
const MAX_WIDTH = 640.0         # 13 cards compress to fit inside this
const MAX_ANGLE_STEP = 3.2      # degrees between neighbouring cards
const TOTAL_ANGLE = 40.0        # full spread from far left to far right
const ARC_RADIUS = 520.0        # controls how much edge cards dip
const SELECT_POP = 30.0         # selected cards rise out of the fan
const HOVER_POP = 10.0          # hovered card raises as a preview
const HOVER_SCALE = 1.03        # hovered card grows slightly with the raise
const REFLOW_TIME = 0.25
const POP_TIME = 0.15
const DRAG_THRESHOLD = 10.0     # below this, a press+release is a click
const DOUBLE_CLICK_MS = 300
const DRAG_SCALE = 1.08
const PLAY_PULL_MARGIN = 45.0   # how far above the fan starts a play drag
const HINT_DIM = 0.45           # alpha for cards that can't beat the table

enum DragMode { NONE, PENDING, REORDER, PLAY }

var input_enabled: bool = false

var _cards: Array = []          # CardUI children, left-to-right fan order
var _selected: Dictionary = {}  # Card -> true
var _hints: Dictionary = {}     # Card -> true = playable; empty = no dimming
var _hovered: CardUI = null
var _tweens: Dictionary = {}    # CardUI -> its active Tween

# Tutorial lock: when active, only cards in the filter can be hovered,
# selected, or dragged. Everything else reports illegal_card_tapped.
var _filter_active: bool = false
var _selectable_filter: Dictionary = {}   # Card -> true

var _drag_mode := DragMode.NONE
var _press_card: CardUI = null
var _press_pos := Vector2.ZERO
var _last_click_card: CardUI = null
var _last_click_ms: int = 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# =============================================================
# PUBLIC API
# =============================================================

# Reconcile the fan with the player's hand: played cards leave, the
# rest tween smoothly to their new slots. Newly created cards (fresh
# game or theme rebuild) are placed instantly.
func sync(hand: Array, enabled: bool) -> void:
	set_input_enabled(enabled)

	for card in _selected.keys():
		if not hand.has(card):
			_selected.erase(card)

	for card_ui in _cards.duplicate():
		if not hand.has(card_ui.card_data):
			_release_card(card_ui)
			card_ui.queue_free()

	var rebuilt: Array = []
	for card in hand:
		var card_ui = _find_card_ui(card)
		if card_ui == null:
			card_ui = _make_card_ui(card)
			card_ui.set_meta("place_instantly", true)
		rebuilt.append(card_ui)
	_cards = rebuilt

	# Child order = z-order: rightmost card draws on top
	for i in _cards.size():
		move_child(_cards[i], i)

	_reflow()
	_apply_hint_dimming()


# Build the hand hidden and without input — deal-animation placeholders.
# Returns the CardUI list so proxies can fly to each one's transform.
func build_hidden(hand: Array) -> Array:
	clear()
	for card in hand:
		var card_ui = _make_card_ui(card)
		card_ui.modulate.a = 0.0
		_cards.append(card_ui)
	_place_all_instantly()
	return _cards.duplicate()


func clear() -> void:
	for card_ui in _cards:
		card_ui.queue_free()
	_cards.clear()
	_selected.clear()
	_tweens.clear()
	_hints.clear()
	_hovered = null
	_drag_mode = DragMode.NONE
	_press_card = null
	input_enabled = false


func get_selected() -> Array:
	var result = []
	for card_ui in _cards:
		if _selected.has(card_ui.card_data):
			result.append(card_ui.card_data)
	return result


func clear_selection() -> void:
	_selected.clear()
	for card_ui in _cards:
		card_ui.set_selected(false)
	_reflow()
	_apply_hint_dimming()


# Tutorial lock: restrict interaction to exactly these Card instances.
# Pass an empty array to lock the hand entirely (nothing selectable).
func set_selectable(cards: Array) -> void:
	_filter_active = true
	_selectable_filter.clear()
	for card in cards:
		_selectable_filter[card] = true


func clear_selectable() -> void:
	_filter_active = false
	_selectable_filter.clear()


func set_input_enabled(value: bool) -> void:
	input_enabled = value
	if not value:
		if _drag_mode != DragMode.NONE:
			_cancel_drag()
		if _hovered != null:
			_hovered = null
			_reflow()


# Dim cards that can't participate in beating the table.
# playable: Card -> true. An empty dictionary disables the hints.
func apply_hints(playable: Dictionary) -> void:
	_hints = playable
	_apply_hint_dimming()


# Cards snap back into the fan after a play drag that didn't play
func return_play_drag() -> void:
	for card_ui in _cards:
		card_ui.z_index = 0
		card_ui.scale = Vector2.ONE
	_reflow()


# Quick horizontal shake — invalid play feedback
func shake(cards: Array) -> void:
	for card in cards:
		var card_ui = _find_card_ui(card)
		if card_ui == null:
			continue
		_kill_tween(card_ui)
		var i = _cards.find(card_ui)
		var target = _target_for(card_ui, slot_transform(i, _cards.size()))
		card_ui.position = target["position"]
		card_ui.rotation = target["rotation"]
		var base_x: float = target["position"].x
		var tween = create_tween()
		for offset in [6.0, -6.0, 3.0, 0.0]:
			tween.tween_property(card_ui, "position:x", base_x + offset, 0.06)
		_tweens[card_ui] = tween


# Current global position of the card's node — captured by GameTable
# before a play so the flight animation starts from the right spot
func global_origin_of(card: Card) -> Vector2:
	var card_ui = _find_card_ui(card)
	return card_ui.global_position if card_ui else global_position


# Layout math for slot i of n — also used by the deal animation
func slot_transform(i: int, n: int) -> Dictionary:
	var spacing = _spacing(n)
	var angle_step = MAX_ANGLE_STEP if n <= 1 \
			else minf(MAX_ANGLE_STEP, TOTAL_ANGLE / (n - 1))
	var rel = i - (n - 1) / 2.0
	var angle_deg = rel * angle_step
	var pos = Vector2(
			rel * spacing - CARD_SIZE.x / 2,
			-CARD_SIZE.y + (1.0 - cos(deg_to_rad(angle_deg))) * ARC_RADIUS)
	return {"position": pos, "rotation": deg_to_rad(angle_deg)}


# =============================================================
# INPUT STATE MACHINE
# =============================================================

func _input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event is InputEventMouseMotion:
		_handle_motion(event)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_press(event)
		else:
			_handle_release(event)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed and _drag_mode == DragMode.NONE:
		if not _selected.is_empty() and _hand_bounds().has_point(event.position):
			get_viewport().set_input_as_handled()
			clear_selection()
			selection_changed.emit()


func _handle_press(event: InputEvent) -> void:
	var hit = _hit_card(event.position)
	if hit == null:
		return
	# Tutorial lock: a card that isn't part of this step can't be grabbed.
	if _filter_active and not _selectable_filter.has(hit.card_data):
		get_viewport().set_input_as_handled()
		illegal_card_tapped.emit()
		return
	get_viewport().set_input_as_handled()
	_press_card = hit
	_press_pos = event.position
	_drag_mode = DragMode.PENDING


func _handle_motion(event: InputEvent) -> void:
	match _drag_mode:
		DragMode.NONE:
			_update_hover(event.position)
		DragMode.PENDING:
			if event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_begin_reorder_drag()
				_reorder_drag_motion(event.position)
		DragMode.REORDER:
			_reorder_drag_motion(event.position)
		DragMode.PLAY:
			_play_drag_motion(event.position)


func _handle_release(event: InputEvent) -> void:
	var mode = _drag_mode
	_drag_mode = DragMode.NONE
	match mode:
		DragMode.PENDING:
			get_viewport().set_input_as_handled()
			_finish_click(_press_card)
		DragMode.REORDER:
			get_viewport().set_input_as_handled()
			_finish_reorder(_press_card)
		DragMode.PLAY:
			get_viewport().set_input_as_handled()
			play_drag_ended.emit()
			play_dropped.emit(get_selected(), event.position)
	_press_card = null


# --- click / double-click ---

func _finish_click(card_ui: CardUI) -> void:
	var now = Time.get_ticks_msec()
	if _last_click_card == card_ui and now - _last_click_ms <= DOUBLE_CLICK_MS:
		# Second click of a double-click: don't toggle again, just play
		_last_click_card = null
		card_double_clicked.emit(card_ui.card_data)
		return
	_last_click_card = card_ui
	_last_click_ms = now
	_toggle(card_ui)


func _toggle(card_ui: CardUI) -> void:
	var card = card_ui.card_data
	if _selected.has(card):
		_selected.erase(card)
		card_ui.set_selected(false)
	else:
		_selected[card] = true
		card_ui.set_selected(true)
	SoundManager.play("card_select")
	_animate_card(card_ui, POP_TIME)
	_apply_hint_dimming()
	selection_changed.emit()


# --- reorder drag ---

func _begin_reorder_drag() -> void:
	_drag_mode = DragMode.REORDER
	_set_hover(null)
	SoundManager.play("card_select")
	_kill_tween(_press_card)
	_press_card.z_index = 50
	_press_card.rotation = 0.0
	create_tween().tween_property(_press_card, "scale",
			Vector2(DRAG_SCALE, DRAG_SCALE), 0.08)


func _reorder_drag_motion(global_pos: Vector2) -> void:
	# A selected card pulled up out of the hand becomes a play drag
	if _selected.has(_press_card.card_data) \
			and global_pos.y < global_position.y - CARD_SIZE.y - PLAY_PULL_MARGIN:
		_begin_play_drag(global_pos)
		return

	var lp = get_global_transform().affine_inverse() * global_pos
	_press_card.position = Vector2(lp.x - CARD_SIZE.x / 2, -CARD_SIZE.y - 10)

	# Live reorder: shift the dragged card's slot as it passes others
	var n = _cards.size()
	var rel = lp.x / _spacing(n) + (n - 1) / 2.0
	var target_index = clampi(roundi(rel), 0, n - 1)
	var current_index = _cards.find(_press_card)
	if target_index != current_index:
		_cards.remove_at(current_index)
		_cards.insert(target_index, _press_card)
		for i in _cards.size():
			move_child(_cards[i], i)
		_reflow_except(_press_card)


func _finish_reorder(card_ui: CardUI) -> void:
	card_ui.z_index = 0
	create_tween().tween_property(card_ui, "scale", Vector2.ONE, 0.08)
	order_changed.emit(_cards.map(func(c): return c.card_data))
	_reflow()


# --- play drag ---

func _begin_play_drag(global_pos: Vector2) -> void:
	_drag_mode = DragMode.PLAY
	_press_card.z_index = 0
	_press_card.scale = Vector2.ONE
	var uis = _selected_uis()
	for i in uis.size():
		_kill_tween(uis[i])
		uis[i].z_index = 60 + i
	play_drag_started.emit()
	_play_drag_motion(global_pos)


func _play_drag_motion(global_pos: Vector2) -> void:
	var uis = _selected_uis()
	var lp = get_global_transform().affine_inverse() * global_pos
	for i in uis.size():
		var rel = i - (uis.size() - 1) / 2.0
		uis[i].rotation = deg_to_rad(rel * 4.0)
		uis[i].position = lp + Vector2(rel * 16.0 - CARD_SIZE.x / 2, -CARD_SIZE.y / 2)
	play_drag_moved.emit(global_pos)


func _cancel_drag() -> void:
	var was_play = _drag_mode == DragMode.PLAY
	_drag_mode = DragMode.NONE
	_press_card = null
	for card_ui in _cards:
		card_ui.z_index = 0
		card_ui.scale = Vector2.ONE
	if was_play:
		play_drag_ended.emit()
	_reflow()


# =============================================================
# HIT DETECTION
# =============================================================

# Walk cards top-to-bottom (reverse z-order); transforming the point
# into each card's local space makes the test exact under rotation
func _hit_card(global_point: Vector2) -> CardUI:
	for i in range(_cards.size() - 1, -1, -1):
		var card_ui = _cards[i]
		var local = card_ui.get_global_transform().affine_inverse() * global_point
		if Rect2(Vector2.ZERO, card_ui.size).has_point(local):
			return card_ui
	return null


# Rough bounds of the whole fan — right-click deselect zone
func _hand_bounds() -> Rect2:
	if _cards.is_empty():
		return Rect2()
	var rect: Rect2 = _cards[0].get_global_rect()
	for card_ui in _cards:
		rect = rect.merge(card_ui.get_global_rect())
	return rect.grow(20)


func _update_hover(global_point: Vector2) -> void:
	var hit = _hit_card(global_point)
	# Locked-out cards don't preview-raise, reinforcing which are playable
	if hit != null and _filter_active and not _selectable_filter.has(hit.card_data):
		hit = null
	_set_hover(hit)


func _set_hover(card_ui: CardUI) -> void:
	if card_ui == _hovered:
		return
	var previous = _hovered
	_hovered = card_ui
	if previous != null and is_instance_valid(previous):
		_animate_card(previous, POP_TIME)
	if _hovered != null:
		_animate_card(_hovered, POP_TIME)


# =============================================================
# LAYOUT + MOTION
# =============================================================

func _spacing(n: int) -> float:
	return MAX_SPACING if n <= 1 else minf(MAX_SPACING, (MAX_WIDTH - CARD_SIZE.x) / (n - 1))


func _make_card_ui(card: Card) -> CardUI:
	var card_ui = CardUI.new()
	card_ui.custom_minimum_size = CARD_SIZE
	card_ui.size = CARD_SIZE
	card_ui.pivot_offset = Vector2(CARD_SIZE.x / 2, CARD_SIZE.y)
	card_ui.setup(card)
	add_child(card_ui)
	return card_ui


func _find_card_ui(card: Card) -> CardUI:
	for card_ui in _cards:
		if card_ui.card_data == card:
			return card_ui
	return null


func _selected_uis() -> Array:
	return _cards.filter(func(card_ui): return _selected.has(card_ui.card_data))


func _release_card(card_ui: CardUI) -> void:
	_cards.erase(card_ui)
	if _hovered == card_ui:
		_hovered = null
	if _press_card == card_ui:
		_press_card = null
		_drag_mode = DragMode.NONE
	_kill_tween(card_ui)


func _kill_tween(card_ui: CardUI) -> void:
	if _tweens.has(card_ui):
		_tweens[card_ui].kill()
		_tweens.erase(card_ui)


func _apply_hint_dimming() -> void:
	for card_ui in _cards:
		var dim = not _hints.is_empty() \
				and not _hints.has(card_ui.card_data) \
				and not _selected.has(card_ui.card_data)
		card_ui.modulate.a = HINT_DIM if dim else 1.0


# Where the card should sit right now, pops included
func _target_for(card_ui: CardUI, slot: Dictionary) -> Dictionary:
	var pos: Vector2 = slot["position"]
	var rot: float = slot["rotation"]
	var scale := 1.0
	if _selected.has(card_ui.card_data):
		# Pop up and out along the card's fan angle, then straighten
		pos += Vector2.UP.rotated(rot) * SELECT_POP
		rot = 0.0
	elif card_ui == _hovered:
		pos += Vector2.UP.rotated(rot) * HOVER_POP
		scale = HOVER_SCALE
	return {"position": pos, "rotation": rot, "scale": Vector2(scale, scale)}


func _reflow() -> void:
	_reflow_except(null)


func _reflow_except(skip: CardUI) -> void:
	for i in _cards.size():
		var card_ui = _cards[i]
		if card_ui == skip:
			continue
		if card_ui.has_meta("place_instantly"):
			card_ui.remove_meta("place_instantly")
			var target = _target_for(card_ui, slot_transform(i, _cards.size()))
			card_ui.position = target["position"]
			card_ui.rotation = target["rotation"]
		else:
			_animate_card(card_ui, REFLOW_TIME)


func _place_all_instantly() -> void:
	for i in _cards.size():
		var target = _target_for(_cards[i], slot_transform(i, _cards.size()))
		_cards[i].position = target["position"]
		_cards[i].rotation = target["rotation"]


func _animate_card(card_ui: CardUI, duration: float) -> void:
	var i = _cards.find(card_ui)
	if i == -1:
		return
	if _drag_mode != DragMode.NONE and card_ui == _press_card:
		return  # never fight the finger
	var target = _target_for(card_ui, slot_transform(i, _cards.size()))
	_kill_tween(card_ui)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(card_ui, "position", target["position"], duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_ui, "rotation", target["rotation"], duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_ui, "scale", target["scale"], duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tweens[card_ui] = tween
