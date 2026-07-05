# AchievementManager.gd
# Data-driven achievements. Conditions are evaluated against the other
# static managers (Stats/Story/Puzzle) plus a transient event context
# passed at evaluation time. Unlocks are one-way and persisted to
# user://achievements.cfg. Static like the rest so headless tests work.
#
# Condition types (achievement JSON):
#   {"type":"total_wins",     "value": N}   ranked+casual wins >= N
#   {"type":"ranked_rating",  "value": N}   rating >= N
#   {"type":"rank_index",     "value": N}   rank tier index >= N
#   {"type":"best_streak",    "value": N}   current ranked streak >= N
#   {"type":"flawless_wins",  "value": N}
#   {"type":"combos_played",  "value": N}
#   {"type":"story_chapters", "value": N}   completed chapters >= N
#   {"type":"puzzles_solved", "value": N}
#   {"type":"event",          "value": "flag"}  context[flag] is true

class_name AchievementManager

static var save_path: String = "user://achievements.cfg"

static var unlocked: Array = []
static var _loaded: bool = false


static func is_unlocked(id: String) -> bool:
	_ensure_loaded()
	return unlocked.has(id)


# Evaluates every not-yet-unlocked achievement against current state +
# the given event context. Returns the achievement dicts newly unlocked
# (so the caller can show toasts).
static func evaluate(context: Dictionary = {}) -> Array:
	_ensure_loaded()
	var newly: Array = []
	for achievement in ContentManager.achievements_ordered:
		var id = String(achievement["id"])
		if unlocked.has(id):
			continue
		if _condition_met(achievement.get("condition", {}), context):
			unlocked.append(id)
			newly.append(achievement)
	if not newly.is_empty():
		save()
	return newly


static func _condition_met(condition: Dictionary, context: Dictionary) -> bool:
	var value = condition.get("value", 0)
	match String(condition.get("type", "")):
		"total_wins":
			return StatsManager.ranked_wins + StatsManager.casual_wins >= int(value)
		"ranked_rating":
			return StatsManager.rating >= int(value)
		"rank_index":
			return StatsManager.get_rank_index() >= int(value)
		"best_streak":
			return StatsManager.streak >= int(value)
		"flawless_wins":
			return StatsManager.flawless_wins >= int(value)
		"combos_played":
			return StatsManager.combos_played >= int(value)
		"story_chapters":
			return StoryManager.completed.size() >= int(value)
		"puzzles_solved":
			return PuzzleManager.solved.size() >= int(value)
		"event":
			return bool(context.get(String(value), false))
	return false


# =============================================================
# PERSISTENCE
# =============================================================

static func save() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.save(save_path)


static func reload_from_disk() -> void:
	_loaded = false
	_ensure_loaded()


static func reset_all() -> void:
	unlocked = []
	_loaded = true
	save()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	unlocked = []
	var cfg = ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	unlocked = cfg.get_value("progress", "unlocked", [])
