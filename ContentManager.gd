# ContentManager.gd
# Loads and validates JSON content (characters, story chapters) from
# res://content/. Static (like RulesManager/StatsManager) so it works in
# headless --script tests, which run without autoloads. MainMenu calls
# load_all() at boot; it is idempotent.
#
# Design rule: a malformed or incomplete file is logged with a clear
# reason and SKIPPED — it never crashes the game and never silently
# drops content without a message.

class_name ContentManager

const CHARACTERS_DIR = "res://content/characters"
const STORIES_DIR = "res://content/stories"
const PUZZLES_DIR = "res://content/puzzles"
const ACHIEVEMENTS_DIR = "res://content/achievements"
const TUTORIAL_PATH = "res://content/tutorial/tutorial_match.json"

const ALLOWED_THEME_KEYS = ["clubs", "diamonds", "hearts", "spades"]
const DIFFICULTY_MAP = {
	"easy": AIPlayer.Difficulty.EASY,
	"medium": AIPlayer.Difficulty.MEDIUM,
	"hard": AIPlayer.Difficulty.HARD,
}

static var characters: Dictionary = {}     # id -> validated character dict
static var chapters: Dictionary = {}       # id -> validated chapter dict
static var chapters_ordered: Array = []    # chapters sorted by number
static var puzzles: Dictionary = {}        # id -> validated puzzle dict
static var puzzles_ordered: Array = []     # puzzles sorted by order
static var achievements: Dictionary = {}   # id -> validated achievement dict
static var achievements_ordered: Array = []
static var tutorial: Dictionary = {}       # the guided-match layout (deal + seats)
static var load_errors: Array = []         # human-readable problems

static var _loaded: bool = false


# =============================================================
# LOADING
# =============================================================

static func load_all() -> void:
	if _loaded:
		return
	reload()


static func reload() -> void:
	characters.clear()
	chapters.clear()
	chapters_ordered.clear()
	puzzles.clear()
	puzzles_ordered.clear()
	achievements.clear()
	achievements_ordered.clear()
	tutorial.clear()
	load_errors.clear()
	_loaded = true

	for filename in _list_json(CHARACTERS_DIR):
		var data = _parse_file(CHARACTERS_DIR + "/" + filename, filename)
		if data == null:
			continue
		var character = _validate_character(data, filename)
		if character != null:
			characters[character["id"]] = character

	for filename in _list_json(STORIES_DIR):
		var data = _parse_file(STORIES_DIR + "/" + filename, filename)
		if data == null:
			continue
		var chapter = _validate_chapter(data, filename)
		if chapter != null:
			chapters[chapter["id"]] = chapter

	for filename in _list_json(PUZZLES_DIR):
		var data = _parse_file(PUZZLES_DIR + "/" + filename, filename)
		if data == null:
			continue
		var puzzle = _validate_puzzle(data, filename)
		if puzzle != null:
			puzzles[puzzle["id"]] = puzzle

	for filename in _list_json(ACHIEVEMENTS_DIR):
		var data = _parse_file(ACHIEVEMENTS_DIR + "/" + filename, filename)
		if data == null:
			continue
		var achievement = _validate_achievement(data, filename)
		if achievement != null:
			achievements[achievement["id"]] = achievement

	_load_tutorial()

	chapters_ordered = chapters.values()
	chapters_ordered.sort_custom(func(a, b): return a["chapter_number"] < b["chapter_number"])
	puzzles_ordered = puzzles.values()
	puzzles_ordered.sort_custom(func(a, b): return a["order"] < b["order"])
	achievements_ordered = achievements.values()
	achievements_ordered.sort_custom(func(a, b): return a["order"] < b["order"])

	for message in load_errors:
		push_warning("[ContentManager] " + message)
		print("[ContentManager] " + message)


static func _list_json(dir_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return result
	for filename in DirAccess.get_files_at(dir_path):
		# Godot may expose a .remap/.import sibling in exports; keep raw json
		if filename.to_lower().ends_with(".json"):
			result.append(filename)
	return result


static func _parse_file(path: String, filename: String):
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		load_errors.append("%s: file is empty or unreadable" % filename)
		return null
	var parsed = JSON.parse_string(text)
	if parsed == null:
		load_errors.append("%s: invalid JSON (parse failed)" % filename)
		return null
	if not (parsed is Dictionary):
		load_errors.append("%s: top level must be a JSON object" % filename)
		return null
	return parsed


# =============================================================
# VALIDATION
# =============================================================

static func _validate_character(data: Dictionary, filename: String):
	for field in ["id", "display_name"]:
		if not data.has(field) or String(data[field]).is_empty():
			load_errors.append("%s: missing '%s'" % [filename, field])
			return null

	var key = String(data.get("theme_color", "spades"))
	if not ALLOWED_THEME_KEYS.has(key):
		load_errors.append("%s: theme_color '%s' unknown, defaulting to spades" % [filename, key])
		key = "spades"
	data["theme_color"] = key

	# Fill optional blocks so consumers never key-check
	data["portraits"] = data.get("portraits", {})
	data["ai"] = data.get("ai", {})
	data["barks"] = data.get("barks", {})
	data["emote_pool"] = data.get("emote_pool", [])
	return data


static func _validate_chapter(data: Dictionary, filename: String):
	for field in ["id", "chapter_number", "title"]:
		if not data.has(field):
			load_errors.append("%s: missing '%s'" % [filename, field])
			return null
	if not data.has("seats") or not (data["seats"] is Dictionary):
		load_errors.append("%s: missing 'seats'" % filename)
		return null
	if not data["seats"].has("rival"):
		load_errors.append("%s: missing 'seats.rival'" % filename)
		return null

	data["chapter_number"] = int(data["chapter_number"])
	data["subtitle"] = data.get("subtitle", "")
	data["unlock"] = data.get("unlock", {})
	data["scenes"] = data.get("scenes", {})
	data["match_events"] = data.get("match_events", [])
	data["rewards"] = data.get("rewards", {})
	data["on_lose"] = data.get("on_lose", {"retry": true})

	# A stacked deal, if present, must be a legal full 52-card layout
	if data.get("deal", null) != null:
		var error = _validate_deal(data["deal"])
		if not error.is_empty():
			load_errors.append("%s: %s" % [filename, error])
			return null
	return data


# Returns "" if valid, else a human-readable reason
static func _validate_deal(deal) -> String:
	if not (deal is Dictionary):
		return "deal must be an object with player/rival/seat3/seat4"
	var seen := {}
	var total := 0
	for seat in ["player", "rival", "seat3", "seat4"]:
		if not deal.has(seat) or not (deal[seat] is Array):
			return "deal.%s missing or not an array" % seat
		for code in deal[seat]:
			var card = Card.from_code(String(code))
			if card == null:
				return "deal.%s has invalid card code '%s'" % [seat, code]
			var id = card.rank + "_" + str(card.suit)
			if seen.has(id):
				return "deal has duplicate card '%s'" % code
			seen[id] = true
			total += 1
	if total != 52:
		return "deal must contain exactly 52 cards, found %d" % total
	return ""


# The tutorial's fixed layout. Validated like a puzzle deal; a bad file
# leaves tutorial empty (the tutorial then falls back to a normal shuffle).
static func _load_tutorial() -> void:
	if not FileAccess.file_exists(TUTORIAL_PATH):
		load_errors.append("tutorial_match.json: file not found")
		return
	var data = _parse_file(TUTORIAL_PATH, "tutorial_match.json")
	if data == null:
		return
	if data.get("deal", null) == null:
		load_errors.append("tutorial_match.json: requires a 'deal'")
		return
	var deal_error = _validate_deal(data["deal"])
	if not deal_error.is_empty():
		load_errors.append("tutorial_match.json: %s" % deal_error)
		return
	data["seats"] = data.get("seats", {})
	tutorial = data


# =============================================================
# ACCESSORS
# =============================================================

static func _validate_puzzle(data: Dictionary, filename: String):
	for field in ["id", "title"]:
		if not data.has(field) or String(data[field]).is_empty():
			load_errors.append("%s: missing '%s'" % [filename, field])
			return null
	if data.get("deal", null) == null:
		load_errors.append("%s: puzzle requires a 'deal'" % filename)
		return null
	var deal_error = _validate_deal(data["deal"])
	if not deal_error.is_empty():
		load_errors.append("%s: %s" % [filename, deal_error])
		return null

	data["description"] = data.get("description", "")
	data["order"] = int(data.get("order", 999))
	data["ai"] = data.get("ai", {})
	data["unlock"] = data.get("unlock", {})
	var objective = data.get("objective", {})
	if not (objective is Dictionary) or not objective.has("type"):
		objective = {"type": "win"}
	data["objective"] = objective
	return data


static func _validate_achievement(data: Dictionary, filename: String):
	for field in ["id", "name"]:
		if not data.has(field) or String(data[field]).is_empty():
			load_errors.append("%s: missing '%s'" % [filename, field])
			return null
	if not data.has("condition") or not (data["condition"] is Dictionary) \
			or not data["condition"].has("type"):
		load_errors.append("%s: missing 'condition.type'" % filename)
		return null

	data["description"] = data.get("description", "")
	data["icon"] = String(data.get("icon", "🏆"))
	data["hidden"] = bool(data.get("hidden", false))
	data["order"] = int(data.get("order", 999))
	return data


static func get_tutorial() -> Dictionary:
	load_all()
	return tutorial


static func get_puzzle(id: String) -> Dictionary:
	load_all()
	return puzzles.get(id, {})


static func get_achievement(id: String) -> Dictionary:
	load_all()
	return achievements.get(id, {})


static func puzzle_ai_difficulty(puzzle: Dictionary) -> int:
	var ai = puzzle.get("ai", {})
	return DIFFICULTY_MAP.get(String(ai.get("difficulty", "medium")), AIPlayer.Difficulty.MEDIUM)


static func get_character(id: String) -> Dictionary:
	load_all()
	return characters.get(id, _fallback_character(id))


static func has_character(id: String) -> bool:
	load_all()
	return characters.has(id)


static func get_chapter(id: String) -> Dictionary:
	load_all()
	return chapters.get(id, {})


static func _fallback_character(id: String) -> Dictionary:
	return {
		"id": id,
		"display_name": id.capitalize(),
		"title": "",
		"portraits": {},
		"theme_color": "spades",
		"ai": {"difficulty": "medium", "personality": "neutral"},
		"barks": {},
		"emote_pool": [],
	}


static func theme_color_key(character: Dictionary) -> String:
	var key = String(character.get("theme_color", "spades"))
	return key if ALLOWED_THEME_KEYS.has(key) else "spades"


static func ai_difficulty(character: Dictionary) -> int:
	var ai = character.get("ai", {})
	return DIFFICULTY_MAP.get(String(ai.get("difficulty", "medium")), AIPlayer.Difficulty.MEDIUM)


# Portrait for an emotion, falling back to neutral, then "" (no art).
static func portrait_path(character: Dictionary, emotion: String) -> String:
	var portraits = character.get("portraits", {})
	if portraits.has(emotion) and _texture_exists(portraits[emotion]):
		return String(portraits[emotion])
	if portraits.has("neutral") and _texture_exists(portraits["neutral"]):
		return String(portraits["neutral"])
	return ""


static func _texture_exists(path) -> bool:
	return path is String and not path.is_empty() and ResourceLoader.exists(path)


static func bark_lines(character: Dictionary, trigger: String) -> Array:
	var barks = character.get("barks", {})
	var pool = barks.get(trigger, [])
	return pool if pool is Array else []


static func initials(character: Dictionary) -> String:
	var name = String(character.get("display_name", "?"))
	var parts = name.split(" ", false)
	if parts.size() >= 2:
		return (parts[0].substr(0, 1) + parts[1].substr(0, 1)).to_upper()
	return name.substr(0, 2).to_upper()


# Fresh Card arrays [player, rival, seat3, seat4] for a stacked deal,
# rebuilt each call so the shared chapter dict is never mutated.
# Returns [] when the chapter uses a normal shuffle.
static func deal_to_hands(chapter: Dictionary) -> Array:
	var deal = chapter.get("deal", null)
	if deal == null:
		return []
	var hands = []
	for seat in ["player", "rival", "seat3", "seat4"]:
		var cards: Array[Card] = []
		for code in deal[seat]:
			cards.append(Card.from_code(String(code)))
		hands.append(cards)
	return hands
