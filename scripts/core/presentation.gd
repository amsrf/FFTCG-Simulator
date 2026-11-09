extends RefCounted
## THE ONE PLACE THE RULES WAIT FOR VISUALS. Every await that exists only so an animation can finish goes through
## PRESENTATION.wait(); waits for a DECISION (priority, blockers, targets, "may" choices) never do.
##
##   await PRESENTATION.wait(flip_tween)
##   await PRESENTATION.wait(get_tree().create_timer(block_announce_time))
##
## `fast_mode` makes every such wait return at once: the rules run straight through while the animations (if any)
## play on their own. Rules probes and AI simulations turn it on; normal play leaves it off and behaves exactly as
## before. Searching for PRESENTATION.wait lists every spot where the rules are still coupled to animation timing.
##
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache, which is
## a parse error on every headless run.

## Also switchable from the command line, so any probe can run fast without editing it:
##   godot --headless res://tests/flow_probe.tscn -- --fast
static var fast_mode: bool = "--fast" in OS.get_cmdline_user_args()

## Accepts a Tween, a SceneTreeTimer or a Signal. A finished/invalid tween returns immediately (a plain
## `await tween.finished` on one would hang forever).
static func wait(waitable: Variant) -> void:
	if fast_mode or waitable == null:
		return
	if waitable is Tween:
		if waitable.is_valid() and waitable.is_running():
			await waitable.finished
	elif waitable is SceneTreeTimer:
		await waitable.timeout
	elif waitable is Signal:
		await waitable

## Wait until the presentation queue (Vfx) has drained. A STOPGAP for rules that still need a queued animation to have
## finished before they continue; every caller is a conversion still to do (grep wait_for_queue).
static func wait_for_queue() -> void:
	if fast_mode:
		return
	await Vfx.idle()
