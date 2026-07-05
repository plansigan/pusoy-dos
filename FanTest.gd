# FanTest.gd
# Headless checks of the fanned hand: rotated hit detection AND the
# click/drag input state machine, driven by synthesized mouse events.
# Run with:  godot --headless --path . res://FanTest.tscn

extends Control

var fan: HandFan
var failures: int = 0
var double_clicks: Array = []
var reorders: Array = []

func _ready() -> void:
	await get_tree().process_frame
	fan = HandFan.new()
	fan.position = Vector2(576, 584)
	add_child(fan)
	fan.card_double_clicked.connect(func(card): double_clicks.append(card))
	fan.order_changed.connect(func(cards): reorders.append(cards))

	var hand = Card.sort_cards(Deck.new().deal(4)[0])  # 13 cards
	fan.sync(hand, true)
	await get_tree().process_frame

	_test_exposed_strips()
	_test_topmost_wins()
	await _test_selection_pop()
	_test_click_select()
	_test_right_click_deselect()
	_test_double_click()
	await _test_drag_reorder()

	print("FAN TEST %s — %d failures" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _fail(message: String) -> void:
	failures += 1
	print("FAIL " + message)


# --- event helpers ---

func _strip_point(card_ui: CardUI) -> Vector2:
	return card_ui.get_global_transform() * Vector2(8, card_ui.size.y * 0.6)


func _send_button(pos: Vector2, pressed: bool, index := MOUSE_BUTTON_LEFT) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = pos
	fan._input(event)


func _send_motion(pos: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = pos
	fan._input(event)


func _click(pos: Vector2) -> void:
	_send_button(pos, true)
	_send_button(pos, false)


# --- tests ---

# 1) Each card's exposed left strip must resolve to that card
func _test_exposed_strips() -> void:
	for i in fan._cards.size():
		var card_ui = fan._cards[i]
		var hit = fan._hit_card(_strip_point(card_ui))
		if hit != card_ui:
			_fail("exposed-strip: card %d resolved to %s" %
					[i, "nothing" if hit == null else "card %d" % fan._cards.find(hit)])


# 2) Topmost wins: for a point on a card's overlapped right half,
#    no card ABOVE the returned hit may also contain the point
func _test_topmost_wins() -> void:
	for i in fan._cards.size():
		var card_ui = fan._cards[i]
		var point = card_ui.get_global_transform() * Vector2(card_ui.size.x - 8, card_ui.size.y * 0.6)
		var hit = fan._hit_card(point)
		if hit == null:
			_fail("right-half: card %d point hit nothing" % i)
			continue
		var hit_index = fan._cards.find(hit)
		for j in range(hit_index + 1, fan._cards.size()):
			var above = fan._cards[j]
			var local = above.get_global_transform().affine_inverse() * point
			if Rect2(Vector2.ZERO, above.size).has_point(local):
				_fail("z-order: point resolved to card %d but card %d is above it" %
						[hit_index, j])


# 3) A selected (popped) card stays hittable at its popped position
func _test_selection_pop() -> void:
	var mid = fan._cards[6]
	fan._toggle(mid)
	await get_tree().create_timer(0.25).timeout
	var popped_point = mid.get_global_transform() * Vector2(mid.size.x / 2, 10)
	if fan._hit_card(popped_point) != mid:
		_fail("popped card not hittable at its popped position")
	if not fan.get_selected().has(mid.card_data):
		_fail("selection not recorded after toggle")


# 4) Press+release under the drag threshold = click, toggles selection
func _test_click_select() -> void:
	var target = fan._cards[2]
	_click(_strip_point(target))
	if not fan.get_selected().has(target.card_data):
		_fail("click-select: card 2 not selected after click")


# 5) Right-click inside the hand area deselects everything
func _test_right_click_deselect() -> void:
	if fan.get_selected().is_empty():
		_fail("right-click precondition: nothing selected")
		return
	_send_button(_strip_point(fan._cards[6]), true, MOUSE_BUTTON_RIGHT)
	if not fan.get_selected().is_empty():
		_fail("right-click: selection not cleared")


# 6) Two quick clicks on the same card emit card_double_clicked
func _test_double_click() -> void:
	var target = fan._cards[4]
	var point = _strip_point(target)
	_click(point)
	_click(point)
	if double_clicks.size() != 1 or double_clicks[0] != target.card_data:
		_fail("double-click signal not emitted exactly once for the clicked card")


# 7) Drag beyond the threshold reorders the hand and emits order_changed
func _test_drag_reorder() -> void:
	var dragged = fan._cards[0]
	var start = _strip_point(dragged)
	_send_button(start, true)

	# Move to slot 8's center x, staying at hand height (reorder, not play)
	var slot8 = fan.slot_transform(8, fan._cards.size())
	var target_x = fan.global_position.x + slot8["position"].x + HandFan.CARD_SIZE.x / 2
	var drag_y = fan.global_position.y - 60
	_send_motion(start + Vector2(15, 0))  # crosses the 10px threshold
	_send_motion(Vector2(target_x, drag_y))
	_send_button(Vector2(target_x, drag_y), false)
	await get_tree().process_frame

	var new_index = fan._cards.find(dragged)
	if new_index == 0:
		_fail("drag-reorder: card did not move from index 0")
	if reorders.size() != 1:
		_fail("drag-reorder: order_changed emitted %d times, expected 1" % reorders.size())
	elif reorders[0].size() != 13 or reorders[0][new_index] != dragged.card_data:
		_fail("drag-reorder: emitted order doesn't match the fan")
