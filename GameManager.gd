# GameManager.gd
# Controls the flow of a full Pusoy Dos game round

class_name GameManager

const PLAYER_COUNT = 4

# --- Player representation ---
class Player:
	var id: int
	var name: String
	var hand: Array[Card] = []

	func _init(p_id: int, p_name: String) -> void:
		id = p_id
		name = p_name

# --- Game state ---
var players: Array = []
var current_player_index: int = 0
var table_cards: Array = []       # Cards currently on the table
var last_player_index: int = -1   # Who played the last valid hand
var pass_count: int = 0           # How many consecutive passes
var game_over: bool = false
var winner: Player = null
var play_history: Array = []

# --- Setup ---
# preset_hands: optional array of 4 Card arrays (story stacked deal).
# When empty, a normal shuffle is used. The 3♣ opening rule applies
# either way — whoever holds 3♣ leads.
func setup_game(preset_hands: Array = []) -> void:
	game_over = false
	winner = null
	table_cards = []
	pass_count = 0
	play_history = []

	players.clear()
	for i in PLAYER_COUNT:
		players.append(Player.new(i, "Player %d" % (i + 1)))

	var hands = preset_hands if preset_hands.size() == PLAYER_COUNT else Deck.new().deal(PLAYER_COUNT)
	for i in PLAYER_COUNT:
		players[i].hand.assign(Card.sort_cards(hands[i]))

	# Find who has 3 of Clubs — they go first
	current_player_index = _find_first_player()
	print("Game started! %s goes first (has 3♣)" % players[current_player_index].name)


# --- Current player tries to play cards ---
# played_cards: array of Card objects the player wants to play
# Returns true if the play was accepted
func try_play(played_cards: Array) -> bool:
	if game_over:
		print("Game is already over!")
		return false

	var current = players[current_player_index]

	# Make sure the player actually has these cards
	if not _player_has_cards(current, played_cards):
		print("%s doesn't have those cards!" % current.name)
		return false

	# Validate the play type
	var play_type = HandEvaluator.get_play_type(played_cards)
	if play_type == HandEvaluator.PlayType.INVALID:
		print("Invalid play type!")
		return false

	# If table is empty (new round or all passed) — any valid play goes
	if table_cards.is_empty():
		if last_player_index == -1 and not _contains_three_of_clubs(played_cards):
			print("First play must include 3♣!")
			return false
	else:
		if not HandEvaluator.can_beat(table_cards, played_cards):
			print("That play doesn't beat the table!")
			return false

	# Play is valid — remove cards from hand (stays sorted)
	for card in played_cards:
		current.hand.erase(card)

	# Update table
	table_cards = played_cards
	last_player_index = current_player_index
	pass_count = 0

	# Record play in history
	play_history.append({
		"player": current.name,
		"cards": played_cards.duplicate()
	})

	print("%s played: %s" % [current.name, _cards_to_string(played_cards)])

	# Check if this player won
	if current.hand.is_empty():
		game_over = true
		winner = current
		print("🎉 %s wins!" % winner.name)
		return true

	# Advance turn
	_next_turn()
	return true


# --- Current player passes ---
func try_pass() -> void:
	if game_over:
		return

	var current = players[current_player_index]

	# Cannot pass if table is empty
	if table_cards.is_empty():
		print("%s cannot pass — table is empty, must play!" % current.name)
		_next_turn()
		return

	pass_count += 1
	print("%s passes." % current.name)

	# If all other players passed — table clears, last player leads
	if pass_count >= PLAYER_COUNT - 1:
		print("All others passed — table cleared! %s leads." % players[last_player_index].name)
		table_cards = []
		pass_count = 0
		current_player_index = last_player_index
		play_history.append({
			"player": "---",
			"cards": []
		})
		return

	_next_turn()


# --- Get current player ---
func get_current_player() -> Player:
	return players[current_player_index]


# --- Print all hands (for debugging) ---
func print_all_hands() -> void:
	for player in players:
		print("--- %s ---" % player.name)
		var card_names = []
		for card in player.hand:
			card_names.append(card.card_name())
		print("  " + ", ".join(card_names))


# =============================================================
# PRIVATE HELPERS
# =============================================================

func _find_first_player() -> int:
	for player in players:
		if _contains_three_of_clubs(player.hand):
			return player.id
	return 0  # fallback


func _player_has_cards(player: Player, cards: Array) -> bool:
	for card in cards:
		if not player.hand.has(card):
			return false
	return true


func _contains_three_of_clubs(cards: Array) -> bool:
	for card in cards:
		if card.rank == "3" and card.suit == Card.Suit.CLUBS:
			return true
	return false


func _next_turn() -> void:
	current_player_index = (current_player_index + 1) % PLAYER_COUNT


func _cards_to_string(cards: Array) -> String:
	var names = []
	for card in cards:
		names.append(card.card_name())
	return ", ".join(names)
