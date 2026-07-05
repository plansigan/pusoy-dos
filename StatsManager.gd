# StatsManager.gd
# Player progression: ranked rating/rank/streak, per-mode tallies,
# global records, and match history. Static (not an autoload) so the
# headless tests can exercise the rating rules directly.
#
# Every record_* call saves synchronously — required so an Alt+F4
# forfeit is on disk before the process exits.

class_name StatsManager

const HISTORY_LIMIT = 20

const RANKS = [
	{"name": "Rookie", "min": 0},
	{"name": "Street King", "min": 200},
	{"name": "Card Shark", "min": 500},
	{"name": "Neighborhood Master", "min": 1000},
	{"name": "The Legend", "min": 2000},
]

const WIN_POINTS = 20
const LOSS_POINTS = 10          # also the forfeit penalty
const FLAWLESS_BONUS = 15
const STREAK_STEP = 5
const STREAK_CAP = 25
const STRAIGHT_FLUSH_BONUS = 10

static var save_path: String = "user://stats.cfg"

# Ranked
static var rating: int = 0
static var streak: int = 0
static var ranked_games: int = 0
static var ranked_wins: int = 0
# Casual
static var casual_games: int = 0
static var casual_wins: int = 0
# Global records
static var combos_played: int = 0
static var fastest_win_turns: int = 0   # 0 = no win recorded yet
static var flawless_wins: int = 0
# Newest first: {result: "win"/"loss"/"forfeit", mode: "casual"/"ranked", rating_delta: int}
static var match_history: Array = []

static var _loaded: bool = false


# =============================================================
# RANKS
# =============================================================

static func get_rank_index() -> int:
	_ensure_loaded()
	var index = 0
	for i in RANKS.size():
		if rating >= RANKS[i]["min"]:
			index = i
	return index


static func get_rank_name() -> String:
	return RANKS[get_rank_index()]["name"]


# Rating needed for the next rank, or -1 at the top
static func next_rank_threshold() -> int:
	var index = get_rank_index()
	return -1 if index == RANKS.size() - 1 else RANKS[index + 1]["min"]


# AI difficulty for a ranked game, derived from the current rank
static func ranked_difficulty() -> int:
	match get_rank_index():
		0:
			return AIPlayer.Difficulty.EASY
		1:
			return AIPlayer.Difficulty.MEDIUM
		2:
			# Card Shark: coin flip between medium and hard each game
			return AIPlayer.Difficulty.MEDIUM if randf() < 0.5 else AIPlayer.Difficulty.HARD
		_:
			return AIPlayer.Difficulty.HARD


# =============================================================
# RECORDING
# =============================================================

# Returns the applied breakdown: [{delta, label}, ...]
static func record_ranked_win(flawless: bool, straight_flush_finish: bool,
		win_turns: int) -> Array:
	_ensure_loaded()
	streak += 1
	var breakdown = [{"delta": WIN_POINTS, "label": "ranked win"}]
	if flawless:
		breakdown.append({"delta": FLAWLESS_BONUS, "label": "flawless"})
		flawless_wins += 1
	var streak_bonus = mini(STREAK_CAP, STREAK_STEP * (streak - 1))
	if streak_bonus > 0:
		breakdown.append({"delta": streak_bonus, "label": "streak x%d" % streak})
	if straight_flush_finish:
		breakdown.append({"delta": STRAIGHT_FLUSH_BONUS, "label": "straight flush finish"})

	var total = 0
	for entry in breakdown:
		total += entry["delta"]
	rating += total
	ranked_games += 1
	ranked_wins += 1
	_note_win_turns(win_turns)
	_push_history("win", "ranked", total)
	save()
	return breakdown


# Returns the applied delta (negative, floored at rating 0)
static func record_ranked_loss() -> int:
	_ensure_loaded()
	var delta = -mini(LOSS_POINTS, rating)
	rating += delta
	streak = 0
	ranked_games += 1
	_push_history("loss", "ranked", delta)
	save()
	return delta


# Quitting an unfinished ranked game — loss penalty, streak gone
static func record_forfeit() -> void:
	_ensure_loaded()
	var delta = -mini(LOSS_POINTS, rating)
	rating += delta
	streak = 0
	ranked_games += 1
	_push_history("forfeit", "ranked", delta)
	save()


# Casual games never touch rating or streak
static func record_casual(won: bool, flawless: bool, win_turns: int) -> void:
	_ensure_loaded()
	casual_games += 1
	if won:
		casual_wins += 1
		if flawless:
			flawless_wins += 1
		_note_win_turns(win_turns)
	_push_history("win" if won else "loss", "casual", 0)
	save()


# Story games never affect rating/streak; they add to global records
# and get tagged "story" in the history.
static func record_story(won: bool, flawless: bool, win_turns: int) -> void:
	_ensure_loaded()
	if won:
		if flawless:
			flawless_wins += 1
		_note_win_turns(win_turns)
	_push_history("win" if won else "loss", "story", 0)
	save()


# Not saved immediately — the match-end save picks it up
static func record_combo() -> void:
	_ensure_loaded()
	combos_played += 1


# =============================================================
# PERSISTENCE
# =============================================================

static func save() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("ranked", "rating", rating)
	cfg.set_value("ranked", "streak", streak)
	cfg.set_value("ranked", "games", ranked_games)
	cfg.set_value("ranked", "wins", ranked_wins)
	cfg.set_value("casual", "games", casual_games)
	cfg.set_value("casual", "wins", casual_wins)
	cfg.set_value("global", "combos_played", combos_played)
	cfg.set_value("global", "fastest_win_turns", fastest_win_turns)
	cfg.set_value("global", "flawless_wins", flawless_wins)
	cfg.set_value("history", "entries", match_history)
	cfg.save(save_path)


static func reload_from_disk() -> void:
	_loaded = false
	_ensure_loaded()


static func reset_all() -> void:
	_apply_defaults()
	_loaded = true
	save()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_apply_defaults()
	var cfg = ConfigFile.new()
	if cfg.load(save_path) != OK:
		return  # fresh profile
	rating = cfg.get_value("ranked", "rating", 0)
	streak = cfg.get_value("ranked", "streak", 0)
	ranked_games = cfg.get_value("ranked", "games", 0)
	ranked_wins = cfg.get_value("ranked", "wins", 0)
	casual_games = cfg.get_value("casual", "games", 0)
	casual_wins = cfg.get_value("casual", "wins", 0)
	combos_played = cfg.get_value("global", "combos_played", 0)
	fastest_win_turns = cfg.get_value("global", "fastest_win_turns", 0)
	flawless_wins = cfg.get_value("global", "flawless_wins", 0)
	match_history = cfg.get_value("history", "entries", [])


static func _apply_defaults() -> void:
	rating = 0
	streak = 0
	ranked_games = 0
	ranked_wins = 0
	casual_games = 0
	casual_wins = 0
	combos_played = 0
	fastest_win_turns = 0
	flawless_wins = 0
	match_history = []


static func _note_win_turns(turns: int) -> void:
	if turns > 0 and (fastest_win_turns == 0 or turns < fastest_win_turns):
		fastest_win_turns = turns


static func _push_history(result: String, mode: String, delta: int) -> void:
	match_history.push_front({"result": result, "mode": mode, "rating_delta": delta})
	if match_history.size() > HISTORY_LIMIT:
		match_history.resize(HISTORY_LIMIT)
