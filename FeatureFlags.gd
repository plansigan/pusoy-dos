# FeatureFlags.gd
# Autoload gating staged-launch features. Ship a feature by flipping its
# value in FLAGS and shipping an update — nothing else changes.
#
# DEV OVERRIDE: a local user://dev_flags.cfg overrides FLAGS so locked
# modes can be tested locally. Shipped builds have no such file and use
# the hardcoded defaults. Format:
#   [flags]
#   story=true
#   puzzles=true

extends Node

const FLAGS := {
	"casual": true,
	"ranked": true,
	"story": false,
	"puzzles": false,
}
const DEV_PATH := "user://dev_flags.cfg"

# Runtime values (defaults, with any dev overrides applied at boot).
var _flags: Dictionary = FLAGS.duplicate()


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DEV_PATH) != OK:
		return  # shipped build — hardcoded defaults stand

	var changes: Array = []
	for key in FLAGS:
		var value = cfg.get_value("flags", key, _flags[key])
		var enabled := bool(value)
		if enabled != _flags[key]:
			changes.append("%s: %s -> %s" % [key, FLAGS[key], enabled])
		_flags[key] = enabled

	if changes.is_empty():
		print("[FeatureFlags] %s found, no changes vs defaults" % DEV_PATH)
	else:
		print("[FeatureFlags] DEV OVERRIDE active (%s): %s" % [DEV_PATH, ", ".join(changes)])


func is_enabled(feature: String) -> bool:
	return bool(_flags.get(feature, false))
