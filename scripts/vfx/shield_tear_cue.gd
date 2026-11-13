extends "res://scripts/vfx/vfx_cue.gd"
## Presentation for a `STATUS_APPLIED` event with status "block_disabled": a card can no longer block. The event is
## raised by Card._sync_status_vfx() when the status appears.
##
## Each card on the field gets one shield_tear.gd. They live under the tree root and free themselves; the cue holds the
## presentation queue only until the shield has torn apart.

const TEAR := preload("res://scripts/vfx/shield_tear.gd")

var _tear_count: int = 0


func play(event: VfxEvent) -> void:
	for entry in event.targets:
		# Untyped first: assigning a FREED card to a `Card` variable is itself an error.
		if not is_instance_valid(entry) or not (entry is Card):
			continue
		var card: Card = entry
		if not card.is_drawn_on_field():
			continue
		var tear: Node3D = TEAR.new()
		tear.name = "ShieldTear"
		get_tree().root.add_child(tear)
		tear.call("setup", card)
		_tear_count += 1
	if _tear_count == 0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(TEAR.APPEAR_SECONDS).timeout


## Probe hook: how many tears this cue started.
func tear_count() -> int:
	return _tear_count
