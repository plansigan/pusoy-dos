# PuzzleManager.gd
# Puzzle-mode progression: which puzzles are solved and the fewest plays
# used to solve each (for a "par" star). Static like the other managers
# so headless tests can drive it. Saves to user://puzzles.cfg.

class_name PuzzleManager

static var save_path: String = "user://puzzles.cfg"

static var solved: Array = []          # puzzle ids cleared at least once
static var best_plays: Dictionary = {}  # id -> fewest player plays used

static var _loaded: bool = false


static func is_solved(id: String) -> bool:
	_ensure_loaded()
	return solved.has(id)


# First puzzle (no requirement) is open; others need their prerequisite solved.
static func is_unlocked(id: String) -> bool:
	_ensure_loaded()
	var puzzle = ContentManager.get_puzzle(id)
	if puzzle.is_empty():
		return false
	if solved.has(id):
		return true
	var req = puzzle.get("unlock", {}).get("requires_puzzle", null)
	return req == null or solved.has(String(req))


static func best_for(id: String) -> int:
	_ensure_loaded()
	return int(best_plays.get(id, 0))


# Pure objective evaluation — kept here (not in GameTable) so the
# headless tests can exercise it without any autoloads.
#   {"type":"win"}                          just win the round
#   {"type":"win_in",   "value": N}         win using <= N plays
#   {"type":"win_with", "value": "TYPE"}    final play is that PlayType name
static func objective_met(objective: Dictionary, human_won: bool,
		plays_used: int, final_play_type: String) -> bool:
	if not human_won:
		return false
	var value = objective.get("value", 0)
	match String(objective.get("type", "win")):
		"win_in":
			return plays_used <= int(value)
		"win_with":
			return final_play_type == String(value)
		_:
			return true


static func objective_text(objective: Dictionary) -> String:
	var value = objective.get("value", 0)
	match String(objective.get("type", "win")):
		"win_in":
			return "Objective: win in %d plays or fewer" % int(value)
		"win_with":
			return "Objective: win with a %s as your final play" \
					% String(value).replace("_", " ").to_lower()
		_:
			return "Objective: win the round"


# Records a solve; keeps the fewest plays seen. Returns true if this run
# was a new best.
static func mark_solved(id: String, plays: int) -> bool:
	_ensure_loaded()
	if not solved.has(id):
		solved.append(id)
	var improved = not best_plays.has(id) or plays < int(best_plays[id])
	if improved:
		best_plays[id] = plays
	save()
	return improved


# =============================================================
# PERSISTENCE
# =============================================================

static func save() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("progress", "solved", solved)
	cfg.set_value("progress", "best_plays", best_plays)
	cfg.save(save_path)


static func reload_from_disk() -> void:
	_loaded = false
	_ensure_loaded()


static func reset_all() -> void:
	solved = []
	best_plays = {}
	_loaded = true
	save()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	solved = []
	best_plays = {}
	var cfg = ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	solved = cfg.get_value("progress", "solved", [])
	best_plays = cfg.get_value("progress", "best_plays", {})
