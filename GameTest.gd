extends Node

func _ready() -> void:
	var gm = GameManager.new()
	gm.setup_game()

	print("\n=== INITIAL HANDS ===")
	gm.print_all_hands()

	print("\n=== GAME SIMULATION ===")

	# Get the first player and find their 3 of clubs
	var p1 = gm.get_current_player()
	var three_clubs = _find_card(p1.hand, "3", Card.Suit.CLUBS)

	# First play — must include 3 of Clubs
	gm.try_play([three_clubs])

	# Everyone else passes
	gm.try_pass()
	gm.try_pass()
	gm.try_pass()

	# Original player leads again with any single card
	var current = gm.get_current_player()
	var any_card = current.hand[0]
	gm.try_play([any_card])

	print("\n=== CURRENT TABLE ===")
	print("Table: " + gm._cards_to_string(gm.table_cards))
	print("Current turn: " + gm.get_current_player().name)


# Helper to find a specific card in a hand
func _find_card(hand: Array, rank: String, suit: Card.Suit) -> Card:
	for card in hand:
		if card.rank == rank and card.suit == suit:
			return card
	return hand[0]  # fallback
