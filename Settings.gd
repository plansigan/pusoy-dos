# Settings.gd
# Autoload that owns persistent user settings (user://settings.cfg).
# Must be first in the autoload list so other singletons can read it.

extends Node

const PATH = "user://settings.cfg"

var theme_key: String = "classic_xp"
var ai_difficulty: int = AIPlayer.Difficulty.MEDIUM
var sound_enabled: bool = true
var volume: float = 1.0
var pixel_level: int = 1  # 0 off, 1 light, 2 medium, 3 heavy
var show_hints: bool = true
var sort_mode: String = "rank"  # "rank" or "suit"
var suit_ranking: int = RulesManager.SuitRanking.FILIPINO
var tutorial_completed: bool = false  # first-launch guided match seen/skipped

func _ready() -> void:
	load_settings()
	RulesManager.set_ranking(suit_ranking)


func load_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # first run — defaults stand
	theme_key = cfg.get_value("display", "theme", theme_key)
	pixel_level = cfg.get_value("display", "pixel_level", pixel_level)
	ai_difficulty = cfg.get_value("game", "ai_difficulty", ai_difficulty)
	sound_enabled = cfg.get_value("audio", "enabled", sound_enabled)
	volume = cfg.get_value("audio", "volume", volume)
	show_hints = cfg.get_value("gameplay", "show_hints", show_hints)
	sort_mode = cfg.get_value("gameplay", "sort_mode", sort_mode)
	suit_ranking = cfg.get_value("rules", "suit_ranking", suit_ranking)
	tutorial_completed = cfg.get_value("gameplay", "tutorial_completed", tutorial_completed)


func save_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("display", "theme", theme_key)
	cfg.set_value("display", "pixel_level", pixel_level)
	cfg.set_value("game", "ai_difficulty", ai_difficulty)
	cfg.set_value("audio", "enabled", sound_enabled)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("gameplay", "show_hints", show_hints)
	cfg.set_value("gameplay", "sort_mode", sort_mode)
	cfg.set_value("gameplay", "tutorial_completed", tutorial_completed)
	cfg.set_value("rules", "suit_ranking", suit_ranking)
	cfg.save(PATH)
