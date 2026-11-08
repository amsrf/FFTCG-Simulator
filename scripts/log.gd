extends RefCounted
## CONSOLE LOG with an on/off switch per area. Every line reads "[Area] message" — the same shape the old print()
## calls used — so the console looks the same until something is muted.
##
##   LOG.info("Mana", "cost already fulfilled")
##   LOG.mute("Priority")     # silence one noisy area
##   LOG.enabled = false      # silence everything (a test, a recording)
##
## Real problems go through push_error()/push_warning() instead, so they show up red/yellow in the editor.
##
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache, which is
## a parse error on every headless run.

static var enabled := true
static var _muted := {}

static func info(area: String, message: Variant) -> void:
	if enabled and not _muted.has(area):
		print("[%s] %s" % [area, message])

static func mute(area: String) -> void:
	_muted[area] = true

static func unmute(area: String) -> void:
	_muted.erase(area)
