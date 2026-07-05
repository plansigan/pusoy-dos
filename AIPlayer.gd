# AIPlayer.gd
# Handles all AI decision making for Pusoy Dos
#
# EASY   — plays the weakest legal card, sometimes passes or picks badly
# MEDIUM — priority system: pressures near-winners, conserves 2s,
#          prefers combos, avoids breaking pairs/triples
# HARD   — MEDIUM plus: dumps cheap five-card combos early, applies
#          pressure sooner, and holds a lone 2 when it isn't worth spending

class_name AIPlayer

enum Difficulty { EASY, MEDIUM, HARD }

# Story roles. Casual/ranked always use NEUTRAL.
#   ALLY   — cooperates with the human (seat 0): protects their plays,
#            blocks the rival ("ipit")
#   RIVAL2 — targets the human: prefers beating their plays
enum Role { NEUTRAL, ALLY, RIVAL2 }

var game_manager: GameManager
var difficulty: Difficulty = Difficulty.MEDIUM

# Story mode overrides, keyed by player id. Empty for casual/ranked,
# so behavior there is identical to before.
var difficulty_by_id: Dictionary = {}
var role_by_id: Dictionary = {}
var rival_id: int = -1

# The difficulty in force for the seat currently taking its turn
var _active_difficulty: int = Difficulty.MEDIUM

func _init(gm: GameManager) -> void:
	game_manager = gm


func take_turn(player) -> bool:
	_active_difficulty = difficulty_by_id.get(player.id, difficulty)
	if game_manager.table_cards.is_empty():
		return _lead(player)
	match role_by_id.get(player.id, Role.NEUTRAL):
		Role.ALLY:
			return _follow_ally(player)
		Role.RIVAL2:
			return _follow_rival2(player)
		_:
			return _follow(player)


# =============================================================
# LEADING (table is empty — this AI starts the round)
# =============================================================

func _lead(player) -> bool:
	if _active_difficulty == Difficulty.EASY:
		# Weakest single, always (also guarantees 3♣ on the first play)
		return _play(player, [Card.sort_cards(player.hand)[0]])
	return _play(player, _choose_lead(player))


func _choose_lead(player) -> Array:
	var hand: Array = player.hand
	var first_play = game_manager.last_player_index == -1
	var min_opp = _min_opponent_cards(player)

	var pairs = _sort_by_strength(_get_groups(hand, 2))
	var triples = _sort_by_strength(_get_groups(hand, 3))
	var fives = []
	if _active_difficulty == Difficulty.HARD or min_opp <= 2:
		fives = _sort_by_strength(_valid_five_cards(hand))

	# The very first play of the game must include the 3 of Clubs
	if first_play:
		pairs = pairs.filter(_contains_three_of_clubs)
		triples = triples.filter(_contains_three_of_clubs)
		fives = fives.filter(_contains_three_of_clubs)

	# Rule 1: someone is about to win — lead a size they can't even follow
	if min_opp <= 2:
		for pool in [pairs, triples, fives]:
			if not pool.is_empty() and pool[0].size() > min_opp:
				return pool[0]
		# No such combo — pressure with our strongest single instead
		return [Card.sort_cards(hand).back()]

	# Rule 6: holding exactly 3 of a kind — dump the triple, not the pair
	for triple in triples:
		if _rank_count(hand, triple[0].rank) == 3 and not _contains_two(triple):
			return triple

	# HARD: clear a cheap five-card combo while the hand is still big
	if _active_difficulty == Difficulty.HARD and hand.size() >= 8:
		for five in fives:
			var key = HandEvaluator.key_card(five, HandEvaluator.get_play_type(five))
			if key.rank_value() < Card.RANK_ORDER["A"] and not _contains_two(five):
				return five

	# Rule 3/4: lead the weakest pair that doesn't spend 2s
	for pair in pairs:
		if not _contains_two(pair):
			return pair

	if first_play:
		return [_find_three_of_clubs(hand)]

	# Weakest single that isn't a 2 and doesn't break up a pair/triple
	var singles = Card.sort_cards(hand)
	for card in singles:
		if card.rank != "2" and _rank_count(hand, card.rank) == 1:
			return [card]
	for card in singles:
		if card.rank != "2":
			return [card]
	return [singles[0]]  # nothing but 2s left


# =============================================================
# FOLLOWING (must beat the table or pass)
# =============================================================

func _follow(player) -> bool:
	var table: Array = game_manager.table_cards
	var candidates = _beating_candidates(player, table.size())
	if candidates.is_empty():
		game_manager.try_pass()
		return false

	if _active_difficulty == Difficulty.EASY:
		# Mistakes: sometimes passes with a play in hand, sometimes
		# burns a stronger card than needed
		if randf() < 0.25:
			game_manager.try_pass()
			return false
		var pick = candidates[randi() % candidates.size()] if randf() < 0.3 else candidates[0]
		return _play(player, pick)

	var min_opp = _min_opponent_cards(player)
	var aggressive = min_opp <= 2 or (_active_difficulty == Difficulty.HARD and min_opp <= 3)

	# Rule 1/7: someone is about to win — play our strongest beat so
	# they can't cheaply top it
	if aggressive:
		return _play(player, candidates.back())

	# Rule 2: keep 2s out of it while there are other options
	var no_twos = candidates.filter(func(c): return not _contains_two(c))
	if no_twos.is_empty():
		# A 2 is the only way to beat the table
		if _active_difficulty == Difficulty.HARD and _not_worth_a_two(player, table):
			game_manager.try_pass()
			return false
		return _play(player, candidates[0])

	# Rule 5-ish: when beating a single, prefer cards that don't break
	# up our pairs/triples
	if table.size() == 1:
		var non_breaking = no_twos.filter(
				func(c): return _rank_count(player.hand, c[0].rank) == 1)
		if not non_breaking.is_empty():
			return _play(player, non_breaking[0])

	return _play(player, no_twos[0])


# =============================================================
# STORY ROLE FOLLOWS
# =============================================================

# ALLY: protect the human (seat 0), pressure the rival.
func _follow_ally(player) -> bool:
	var table: Array = game_manager.table_cards
	var candidates = _beating_candidates(player, table.size())

	# Take a winning play if one is available — going out is always best
	for combo in candidates:
		if combo.size() == player.hand.size():
			return _play(player, combo)

	# The human's play is on top — never beat it (passing is legal here)
	if game_manager.last_player_index == 0:
		game_manager.try_pass()
		return false

	if candidates.is_empty():
		game_manager.try_pass()
		return false

	# Table belongs to the rival (or a third seat). Block hard — "ipit" —
	# if the rival is low or currently controls the table.
	var rival_low = rival_id >= 0 and rival_id < game_manager.players.size() \
			and game_manager.players[rival_id].hand.size() <= 5
	var rival_controls = game_manager.last_player_index == rival_id
	if rival_low or rival_controls:
		return _play(player, candidates.back())   # strongest beat
	return _play(player, candidates[0])            # otherwise weakest beat


# RIVAL2: treat the human as the target — beat their plays when possible.
func _follow_rival2(player) -> bool:
	var candidates = _beating_candidates(player, game_manager.table_cards.size())
	if candidates.is_empty():
		game_manager.try_pass()
		return false
	# Human's play on top → beat it with the weakest sufficient play
	if game_manager.last_player_index == 0:
		return _play(player, candidates[0])
	# Otherwise behave like a normal opponent
	return _follow(player)


# HARD only: spending a 2 on a low table early in the game is a waste
func _not_worth_a_two(player, table: Array) -> bool:
	var table_key = HandEvaluator.key_card(table, HandEvaluator.get_play_type(table))
	return player.hand.size() >= 8 \
			and _min_opponent_cards(player) >= 5 \
			and table_key.rank_value() < Card.RANK_ORDER["J"]


# =============================================================
# CANDIDATE GENERATION
# =============================================================

# All plays of size n that beat the table, sorted weakest first
func _beating_candidates(player, n: int) -> Array:
	var table: Array = game_manager.table_cards
	var hand: Array = player.hand
	var candidates = []

	match n:
		1:
			for card in hand:
				if HandEvaluator.can_beat(table, [card]):
					candidates.append([card])
		2, 3:
			for group in _get_groups(hand, n):
				if HandEvaluator.can_beat(table, group):
					candidates.append(group)
		5:
			for combo in _get_combinations(hand, 5):
				if HandEvaluator.can_beat(table, combo):
					candidates.append(combo)

	return _sort_by_strength(candidates)


func _valid_five_cards(hand: Array) -> Array:
	var result = []
	for combo in _get_combinations(hand, 5):
		if HandEvaluator.get_play_type(combo) != HandEvaluator.PlayType.INVALID:
			result.append(combo)
	return result


# Sort plays weakest → strongest by their deciding card
func _sort_by_strength(plays: Array) -> Array:
	plays.sort_custom(func(a, b):
		var key_a = HandEvaluator.key_card(a, HandEvaluator.get_play_type(a))
		var key_b = HandEvaluator.key_card(b, HandEvaluator.get_play_type(b))
		return key_b.beats(key_a)
	)
	return plays


# =============================================================
# HELPERS
# =============================================================

# Play the given cards; falls back to passing so a bad candidate can
# never stall the game
func _play(player, cards: Array) -> bool:
	if not cards.is_empty() and game_manager.try_play(cards):
		return true
	game_manager.try_pass()
	return false


func _min_opponent_cards(player) -> int:
	var lowest = 99
	for other in game_manager.players:
		if other.id != player.id:
			lowest = min(lowest, other.hand.size())
	return lowest


func _rank_count(hand: Array, rank: String) -> int:
	var count = 0
	for card in hand:
		if card.rank == rank:
			count += 1
	return count


func _contains_two(cards: Array) -> bool:
	for card in cards:
		if card.rank == "2":
			return true
	return false


func _contains_three_of_clubs(cards: Array) -> bool:
	for card in cards:
		if card.rank == "3" and card.suit == Card.Suit.CLUBS:
			return true
	return false


func _find_three_of_clubs(hand: Array) -> Card:
	for card in hand:
		if card.rank == "3" and card.suit == Card.Suit.CLUBS:
			return card
	return hand[0]  # unreachable for the opening player


# Groups cards by rank and returns groups of exact size n
func _get_groups(hand: Array, n: int) -> Array:
	var by_rank = {}
	for card in hand:
		if not by_rank.has(card.rank):
			by_rank[card.rank] = []
		by_rank[card.rank].append(card)
	var result = []
	for rank in by_rank:
		if by_rank[rank].size() >= n:
			result.append(by_rank[rank].slice(0, n))
	return result


func _get_combinations(arr: Array, k: int) -> Array:
	var result = []
	_combine(arr, k, 0, [], result)
	return result


func _combine(arr: Array, k: int, start: int, combo: Array, result: Array) -> void:
	if combo.size() == k:
		result.append(combo.duplicate())
		return
	for i in range(start, arr.size()):
		combo.append(arr[i])
		_combine(arr, k, i + 1, combo, result)
		combo.pop_back()
