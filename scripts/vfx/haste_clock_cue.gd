extends "res://scripts/vfx/vfx_cue.gd"
## Presentation for a `STATUS_APPLIED` event with status "haste": a card GAINED Haste, or entered the field with it.
## The event is raised by Card.sync_haste_vfx(), which watches has_haste() (printed, timed status, aura grant or code
## keyword all count), not by the status dictionary alone.
##
## Each card on the field gets one haste_clock.gd. The clocks live under the tree root and free themselves; the cue
## holds the presentation queue only until the dial has drawn itself, so Haste never slows the game down.

const CLOCK := preload("res://scripts/vfx/haste_clock.gd")

var _clock_count: int = 0


func play(event: VfxEvent) -> void:
	for entry in event.targets:
		# Untyped first: assigning a FREED card to a `Card` variable is itself an error.
		if not is_instance_valid(entry) or not (entry is Card):
			continue
		var card: Card = entry
		if not card.is_drawn_on_field():
			continue
		var clock: Node3D = CLOCK.new()
		clock.name = "HasteClock"
		get_tree().root.add_child(clock)
		clock.call("setup", card, event.seed + _clock_count * 131)
		_clock_count += 1
	if _clock_count == 0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(CLOCK.APPEAR_SECONDS).timeout


## Probe hook: how many clocks this cue started.
func clock_count() -> int:
	return _clock_count
