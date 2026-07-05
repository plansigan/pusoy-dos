# RulesManager.gd
# Configurable rule variants. Static (class_name, not an autoload) so the
# core logic — and the headless tests, which run without autoloads — can
# use it directly. Settings pushes the persisted choice in at boot;
# GameTable re-applies it at the start of every game so a mid-game
# settings change never corrupts a round in progress.

class_name RulesManager

enum SuitRanking { FILIPINO, BIG_TWO }

# Weakest → strongest
const SUIT_ORDER = {
	SuitRanking.FILIPINO: [Card.Suit.CLUBS, Card.Suit.SPADES,
			Card.Suit.HEARTS, Card.Suit.DIAMONDS],   # 2♦ is the boss card
	SuitRanking.BIG_TWO: [Card.Suit.CLUBS, Card.Suit.DIAMONDS,
			Card.Suit.HEARTS, Card.Suit.SPADES],     # 2♠ is the boss card
}

const RANKING_NAMES = ["Filipino (2♦ high)", "Big Two (2♠ high)"]

static var suit_ranking: int = SuitRanking.FILIPINO
static var _rank_by_suit: Array = []   # indexed by Card.Suit enum value

static func _static_init() -> void:
	_rebuild_lookup()


static func set_ranking(value: int) -> void:
	suit_ranking = clampi(value, 0, SuitRanking.size() - 1)
	_rebuild_lookup()


# 0 = weakest suit, 3 = strongest, under the active ranking
static func get_suit_rank(suit: Card.Suit) -> int:
	return _rank_by_suit[suit]


static func _rebuild_lookup() -> void:
	_rank_by_suit.resize(4)
	var order: Array = SUIT_ORDER[suit_ranking]
	for i in order.size():
		_rank_by_suit[order[i]] = i
