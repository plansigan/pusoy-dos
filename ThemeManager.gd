# ThemeManager.gd
# Singleton that manages color themes for the game

extends Node

const THEMES = {
	"classic_xp": {
		"name": "Classic XP",
		"table_bg": Color(0.0, 0.42, 0.0),         # solitaire green felt (deepened for text contrast)
		"card_bg": Color(0.98, 0.98, 0.96),
		"card_back": Color(0.16, 0.35, 0.68),      # XP blue card back
		"card_border": Color(0.15, 0.15, 0.15),
		"hearts": Color(0.8, 0.04, 0.09),
		"spades": Color(0.05, 0.05, 0.08),
		"diamonds": Color(0.8, 0.04, 0.09),
		"clubs": Color(0.05, 0.05, 0.08),
		"selected": Color(0.19, 0.42, 0.77),       # XP highlight blue
		"text_primary": Color(1.0, 1.0, 1.0),
		"text_secondary": Color(0.84, 0.93, 0.84),
		"panel_bg": Color(0.0, 0.33, 0.0, 0.95),   # darker felt
		"status_color": Color(1.0, 0.85, 0.3),
		"text_soft": Color(0.95, 0.97, 0.92),
		"text_muted": Color(0.8, 0.9, 0.8),
		"border_soft": Color(0.4, 0.6, 0.4),
		"button_bg": Color(0.93, 0.91, 0.85),      # XP button face
		"button_text": Color(0.1, 0.1, 0.1),
		# Text for LIGHT/cream surfaces (buttons, list rows, cards). Here the
		# panels really are light, so these are dark and readable.
		"text_on_light_primary": Color(0.12, 0.14, 0.12),
		"text_on_light_secondary": Color(0.3, 0.4, 0.3),
	},
	"neon_noir": {
		"name": "Neon Noir",
		"table_bg": Color(0.051, 0.051, 0.102),
		"card_bg": Color(0.102, 0.102, 0.180),
		"card_back": Color(0.07, 0.07, 0.13),
		"card_border": Color(0.3, 0.3, 0.5),           # brighter border
		"hearts": Color(1.0, 0.176, 0.42),
		"spades": Color(0.0, 0.898, 1.0),
		"diamonds": Color(1.0, 0.902, 0.0),
		"clubs": Color(0.224, 1.0, 0.078),
		"selected": Color(1.0, 0.584, 0.0),
		"text_primary": Color(1.0, 1.0, 1.0),
		"text_secondary": Color(0.6, 0.6, 0.7),
		"panel_bg": Color(0.12, 0.12, 0.22, 0.95),     # brighter panels
		"status_color": Color(1.0, 0.902, 0.0),
		"text_soft": Color(0.7, 0.7, 0.8),
		"text_muted": Color(0.6, 0.6, 0.68),
		"border_soft": Color(0.2, 0.2, 0.35),
		"button_bg": Color(0.102, 0.102, 0.180),
		"button_text": Color(0.7, 0.7, 0.8),
		# This theme's button/row panels are dark, so on-surface text stays light
		"text_on_light_primary": Color(0.9, 0.9, 0.96),
		"text_on_light_secondary": Color(0.62, 0.62, 0.72),
	},
	"synthwave_sunset": {
		"name": "Synthwave Sunset",
		"table_bg": Color(0.075, 0.0, 0.122),
		"card_bg": Color(0.118, 0.0, 0.188),
		"card_back": Color(0.09, 0.0, 0.15),
		"card_border": Color(0.3, 0.1, 0.4),
		"hearts": Color(1.0, 0.235, 0.675),            # #ff3cac
		"spades": Color(0.471, 0.31, 1.0),             # #784fff
		"diamonds": Color(1.0, 0.42, 0.208),           # #ff6b35
		"clubs": Color(0.0, 0.961, 0.831),             # #00f5d4
		"selected": Color(1.0, 0.969, 0.0),            # #fff700
		"text_primary": Color(1.0, 1.0, 1.0),
		"text_secondary": Color(0.7, 0.5, 0.8),
		"panel_bg": Color(0.12, 0.0, 0.2, 0.85),
		"status_color": Color(1.0, 0.969, 0.0),
		"text_soft": Color(0.75, 0.6, 0.85),
		"text_muted": Color(0.62, 0.5, 0.72),
		"border_soft": Color(0.25, 0.1, 0.35),
		"button_bg": Color(0.118, 0.0, 0.188),
		"button_text": Color(0.75, 0.6, 0.85),
		"text_on_light_primary": Color(0.95, 0.9, 0.98),
		"text_on_light_secondary": Color(0.72, 0.6, 0.82),
	},
	"deep_ocean": {
		"name": "Deep Ocean",
		"table_bg": Color(0.0, 0.051, 0.102),
		"card_bg": Color(0.0, 0.094, 0.157),
		"card_back": Color(0.0, 0.07, 0.12),
		"card_border": Color(0.1, 0.2, 0.3),
		"hearts": Color(1.0, 0.302, 0.427),            # #ff4d6d
		"spades": Color(0.282, 0.792, 0.894),          # #48cae4
		"diamonds": Color(0.969, 0.498, 0.0),          # #f77f00
		"clubs": Color(0.024, 0.839, 0.627),           # #06d6a0
		"selected": Color(1.0, 0.839, 0.039),          # #ffd60a
		"text_primary": Color(1.0, 1.0, 1.0),
		"text_secondary": Color(0.5, 0.7, 0.8),
		"panel_bg": Color(0.0, 0.094, 0.157, 0.85),
		"status_color": Color(1.0, 0.839, 0.039),
		"text_soft": Color(0.6, 0.75, 0.85),
		"text_muted": Color(0.4, 0.55, 0.65),
		"border_soft": Color(0.1, 0.22, 0.32),
		"button_bg": Color(0.0, 0.094, 0.157),
		"button_text": Color(0.6, 0.75, 0.85),
		"text_on_light_primary": Color(0.9, 0.95, 0.98),
		"text_on_light_secondary": Color(0.62, 0.76, 0.85),
	},
	"ember_ash": {
		"name": "Ember & Ash",
		"table_bg": Color(0.059, 0.039, 0.0),
		"card_bg": Color(0.102, 0.039, 0.0),
		"card_back": Color(0.08, 0.03, 0.0),
		"card_border": Color(0.3, 0.15, 0.05),
		"hearts": Color(1.0, 0.2, 0.0),               # #ff3300
		"spades": Color(0.753, 0.753, 0.753),          # #c0c0c0
		"diamonds": Color(1.0, 0.667, 0.0),            # #ffaa00
		"clubs": Color(0.659, 1.0, 0.243),             # #a8ff3e
		"selected": Color(1.0, 0.4, 0.0),              # #ff6600
		"text_primary": Color(1.0, 1.0, 1.0),
		"text_secondary": Color(0.7, 0.6, 0.5),
		"panel_bg": Color(0.15, 0.06, 0.0, 0.85),
		"status_color": Color(1.0, 0.667, 0.0),
		"text_soft": Color(0.75, 0.65, 0.55),
		"text_muted": Color(0.62, 0.54, 0.46),
		"border_soft": Color(0.28, 0.14, 0.05),
		"button_bg": Color(0.102, 0.039, 0.0),
		"button_text": Color(0.75, 0.65, 0.55),
		"text_on_light_primary": Color(0.96, 0.92, 0.86),
		"text_on_light_secondary": Color(0.74, 0.66, 0.58),
	}
}

# Theme color key per suit, indexed by Card.Suit enum value
const SUIT_KEYS = ["clubs", "diamonds", "hearts", "spades"]

var current_theme_key: String = "classic_xp"

func _ready() -> void:
	# Settings is loaded first in the autoload order
	if THEMES.has(Settings.theme_key):
		current_theme_key = Settings.theme_key

func get_color(key: String) -> Color:
	return THEMES[current_theme_key][key]

func get_suit_color(suit: Card.Suit) -> Color:
	return get_color(SUIT_KEYS[suit])

func current_theme_name() -> String:
	return THEMES[current_theme_key]["name"]

func set_theme(theme_key: String) -> void:
	if THEMES.has(theme_key):
		current_theme_key = theme_key
		print("Theme changed to: " + THEMES[theme_key]["name"])

func get_theme_names() -> Array:
	var names = []
	for key in THEMES:
		names.append({"key": key, "name": THEMES[key]["name"]})
	return names
