# Deck.gd
# Builds, shuffles, and deals a full 52-card deck

class_name Deck

const RANKS = ["3","4","5","6","7","8","9","10","J","Q","K","A","2"]
const SUITS = [Card.Suit.CLUBS, Card.Suit.DIAMONDS, Card.Suit.HEARTS, Card.Suit.SPADES]

var cards: Array[Card] = []

func _init() -> void:
	build()

# Build a fresh 52-card deck
func build() -> void:
	cards.clear()
	for suit in SUITS:
		for rank in RANKS:
			cards.append(Card.new(rank, suit))

# Shuffle the deck randomly
func shuffle() -> void:
	cards.shuffle()

# Deal cards evenly to N players — returns array of arrays
func deal(num_players: int) -> Array:
	shuffle()
	var hands = []
	for i in num_players:
		hands.append([])
	for i in cards.size():
		hands[i % num_players].append(cards[i])
	return hands
