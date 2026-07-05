# HandEvaluator.gd
# Validates plays and determines if a play beats the current table play

class_name HandEvaluator

# --- Play types ranked low to high ---
enum PlayType {
	INVALID,
	SINGLE,
	PAIR,
	TRIPLE,
	STRAIGHT,
	FLUSH,
	FULL_HOUSE,
	FOUR_OF_A_KIND,
	STRAIGHT_FLUSH
}

# --- Main entry point ---
# Takes an array of Card objects, returns the PlayType
static func get_play_type(cards: Array) -> PlayType:
	match cards.size():
		1: return PlayType.SINGLE
		2: return PlayType.PAIR if _rank_counts(cards) == [2] else PlayType.INVALID
		3: return PlayType.TRIPLE if _rank_counts(cards) == [3] else PlayType.INVALID
		5: return _check_five_card(cards)
		_: return PlayType.INVALID


# --- Can a new play beat the table play? ---
# Both inputs are arrays of Card objects
static func can_beat(table_cards: Array, new_cards: Array) -> bool:
	# Must be same number of cards
	if table_cards.size() != new_cards.size():
		return false

	var table_type = get_play_type(table_cards)
	var new_type = get_play_type(new_cards)

	# Both must be valid
	if table_type == PlayType.INVALID or new_type == PlayType.INVALID:
		return false

	# For singles, pairs, triples — same type, compare highest card
	if table_cards.size() < 5:
		if new_type != table_type:
			return false
		return best_card(new_cards).beats(best_card(table_cards))

	# For 5-card hands — higher type wins outright
	if new_type != table_type:
		return new_type > table_type

	# Same 5-card type — compare the card that decides the tie
	return key_card(new_cards, new_type).beats(key_card(table_cards, table_type))


# The card that decides ties between same-type plays.
# Full houses and quads are ranked by their triple/quad,
# everything else by the highest card.
static func key_card(cards: Array, play_type: PlayType) -> Card:
	match play_type:
		PlayType.FULL_HOUSE:
			return _best_of_group(cards, 3)
		PlayType.FOUR_OF_A_KIND:
			return _best_of_group(cards, 4)
		_:
			return best_card(cards)


# Returns the highest card in a set (used for comparison)
static func best_card(cards: Array) -> Card:
	var best = cards[0]
	for card in cards:
		if card.beats(best):
			best = card
	return best


# =============================================================
# PRIVATE HELPERS
# =============================================================

static func _check_five_card(cards: Array) -> PlayType:
	var sorted = Card.sort_cards(cards)
	var is_flush = _is_flush(sorted)
	var is_straight = _is_straight(sorted)
	var counts = _rank_counts(cards)

	if is_flush and is_straight:
		return PlayType.STRAIGHT_FLUSH
	if counts == [1, 4]:
		return PlayType.FOUR_OF_A_KIND
	if counts == [2, 3]:
		return PlayType.FULL_HOUSE
	if is_flush:
		return PlayType.FLUSH
	if is_straight:
		return PlayType.STRAIGHT
	return PlayType.INVALID


# Sorted list of rank multiplicities, e.g. AAKKK -> [2, 3], quads -> [1, 4]
static func _rank_counts(cards: Array) -> Array:
	var counts = {}
	for card in cards:
		counts[card.rank] = counts.get(card.rank, 0) + 1
	var sizes = counts.values()
	sizes.sort()
	return sizes


# Highest card of the rank that appears at least n times
static func _best_of_group(cards: Array, n: int) -> Card:
	var counts = {}
	for card in cards:
		counts[card.rank] = counts.get(card.rank, 0) + 1
	for rank in counts:
		if counts[rank] >= n:
			return best_card(cards.filter(func(c): return c.rank == rank))
	return best_card(cards)  # unreachable for valid plays


static func _is_flush(sorted: Array) -> bool:
	var suit = sorted[0].suit
	for card in sorted:
		if card.suit != suit:
			return false
	return true


static func _is_straight(sorted: Array) -> bool:
	for i in range(1, sorted.size()):
		if sorted[i].rank_value() != sorted[i - 1].rank_value() + 1:
			return false
	return true
