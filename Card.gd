# Card.gd
# Represents a single playing card in Pusoy Dos

class_name Card

# --- Suits (ranked low to high in Pusoy Dos) ---
enum Suit { CLUBS, DIAMONDS, HEARTS, SPADES }

# --- Ranks: 3 is lowest, 2 is highest ---
# We map card faces to numeric values for easy comparison
const RANK_ORDER = {
	"3": 0, "4": 1, "5": 2, "6": 3, "7": 4,
	"8": 5, "9": 6, "10": 7, "J": 8, "Q": 9,
	"K": 10, "A": 11, "2": 12
}

# Indexed by Suit enum value
const SUIT_NAMES = ["Clubs", "Diamonds", "Hearts", "Spades"]
const SUIT_SYMBOLS = ["♣", "♦", "♥", "♠"]

# Single-letter suit codes used in stacked-deal JSON ("3C", "10H", "AS")
const SUIT_CODES = {
	"C": Suit.CLUBS, "D": Suit.DIAMONDS, "H": Suit.HEARTS, "S": Suit.SPADES
}

var rank: String   # e.g. "3", "K", "A", "2"
var suit: Suit     # e.g. Suit.SPADES

func _init(r: String, s: Suit) -> void:
	rank = r
	suit = s

# Returns the numeric rank value (0 = lowest, 12 = highest)
func rank_value() -> int:
	return RANK_ORDER[rank]

# Suit strength under the active ruleset (0 = weakest, 3 = strongest).
# The Suit enum itself stays in deck order — only comparisons go
# through the configurable ranking.
func suit_value() -> int:
	return RulesManager.get_suit_rank(suit)

# Compare this card to another — returns true if self beats other
func beats(other: Card) -> bool:
	if rank_value() != other.rank_value():
		return rank_value() > other.rank_value()
	return suit_value() > other.suit_value()

# Human-readable name e.g. "A of Spades"
func card_name() -> String:
	return rank + " of " + SUIT_NAMES[suit]

# Unicode suit symbol e.g. "♠"
func suit_symbol() -> String:
	return SUIT_SYMBOLS[suit]

# Parse a card code like "3C", "10H", "AS", "2D". Returns null on a bad
# code so callers (the content loader) can report the offending string.
static func from_code(code: String) -> Card:
	if code.length() < 2:
		return null
	var suit_letter = code.substr(code.length() - 1, 1).to_upper()
	var rank_part = code.substr(0, code.length() - 1).to_upper()
	if not SUIT_CODES.has(suit_letter) or not RANK_ORDER.has(rank_part):
		return null
	return Card.new(rank_part, SUIT_CODES[suit_letter])

# Canonical Pusoy Dos hand order: rank ascending, suit breaks ties.
# Returns a sorted copy; the original array is untouched.
static func sort_cards(cards: Array) -> Array:
	var sorted = cards.duplicate()
	sorted.sort_custom(func(a, b):
		if a.rank_value() != b.rank_value():
			return a.rank_value() < b.rank_value()
		return a.suit_value() < b.suit_value()
	)
	return sorted
