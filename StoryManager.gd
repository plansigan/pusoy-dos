# StoryManager.gd
# Story-mode progression: which chapters are completed / unlocked and
# which rewards have already been granted. Static (like the other
# managers) so headless tests can drive it directly. Saves to
# user://story.cfg synchronously.

class_name StoryManager

static var save_path: String = "user://story.cfg"

static var completed: Array = []         # chapter ids finished at least once
static var unlocked: Array = []          # chapter ids explicitly unlocked by rewards
static var rewards_granted: Array = []    # chapter ids whose rewards were applied

static var _loaded: bool = false


# =============================================================
# QUERIES
# =============================================================

static func is_completed(chapter_id: String) -> bool:
	_ensure_loaded()
	return completed.has(chapter_id)


# A chapter is playable when its requirement chapter is completed (or it
# has none — the opener) and any rank requirement is met. Rewards may
# also unlock chapters explicitly.
static func is_unlocked(chapter_id: String) -> bool:
	_ensure_loaded()
	var chapter = ContentManager.get_chapter(chapter_id)
	if chapter.is_empty():
		return false
	if completed.has(chapter_id) or unlocked.has(chapter_id):
		return true

	var unlock = chapter.get("unlock", {})
	var req_chapter = unlock.get("requires_chapter", null)
	var req_rank = unlock.get("requires_rank", null)

	var chapter_ok = req_chapter == null or completed.has(String(req_chapter))
	var rank_ok = req_rank == null or StatsManager.get_rank_index() >= int(req_rank)
	return chapter_ok and rank_ok


# Human-readable reason a chapter is still locked (for the story list)
static func lock_reason(chapter_id: String) -> String:
	var chapter = ContentManager.get_chapter(chapter_id)
	var unlock = chapter.get("unlock", {})
	var req_chapter = unlock.get("requires_chapter", null)
	var req_rank = unlock.get("requires_rank", null)
	if req_chapter != null and not completed.has(String(req_chapter)):
		var needed = ContentManager.get_chapter(String(req_chapter))
		var title = needed.get("title", req_chapter) if not needed.is_empty() else req_chapter
		return "Finish \"%s\" first" % title
	if req_rank != null and StatsManager.get_rank_index() < int(req_rank):
		return "Reach %s" % StatsManager.RANKS[int(req_rank)]["name"]
	return "Locked"


# =============================================================
# MUTATIONS
# =============================================================

# Mark a chapter done and apply its rewards exactly once. Safe to call
# again on replay — rewards are guarded by rewards_granted.
static func complete_chapter(chapter_id: String) -> void:
	_ensure_loaded()
	var chapter = ContentManager.get_chapter(chapter_id)
	if chapter.is_empty():
		return
	if not completed.has(chapter_id):
		completed.append(chapter_id)

	if not rewards_granted.has(chapter_id):
		rewards_granted.append(chapter_id)
		var rewards = chapter.get("rewards", {})
		var unlock_chapter = rewards.get("unlock_chapter", null)
		if unlock_chapter != null and not unlocked.has(String(unlock_chapter)):
			unlocked.append(String(unlock_chapter))
		# unlock_theme / unlock_card_back / achievement are handled in a
		# later task; completion is still recorded here.
	save()


# =============================================================
# PERSISTENCE
# =============================================================

static func save() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("progress", "completed", completed)
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "rewards_granted", rewards_granted)
	cfg.save(save_path)


static func reload_from_disk() -> void:
	_loaded = false
	_ensure_loaded()


static func reset_all() -> void:
	completed = []
	unlocked = []
	rewards_granted = []
	_loaded = true
	save()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	completed = []
	unlocked = []
	rewards_granted = []
	var cfg = ConfigFile.new()
	if cfg.load(save_path) != OK:
		return  # fresh profile — only the opener chapter is unlocked
	completed = cfg.get_value("progress", "completed", [])
	unlocked = cfg.get_value("progress", "unlocked", [])
	rewards_granted = cfg.get_value("progress", "rewards_granted", [])
