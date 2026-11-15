extends "res://scripts/vfx/counter_cue.gd"
## DRAINED (VfxEvent.Kind.DRAINED): a Forward whose power was drained to death - its power reached 0, or fell to or
## below the damage it already had. The rules already moved it (Game.put_card_into_graveyard / break_card); a stand-in
## holds its field slot and:
##   1. STAB   - the power-down's lethal form (power_down_drain.gd): the sword comes down and stabs its centre, the
##               rupture flashes and its orbs of light burst out, and the art goes cold with the sword still in.
##   2. CYAN   - the counter's second beat: solid cyan, cracks spreading from the centre (counter_cue.gd); the sword
##               fades as it cracks.
##   3. SHATTER - the counter's third beat: it breaks along the cracks and the pieces fly.
## `target_visuals[id].drain_elapsed` is how far the card's own drain had got when it died, so a drop that was
## already being drained on screen continues instead of restarting.

const POWER_DOWN_DRAIN := preload("res://scripts/vfx/power_down_drain.gd")

var _drain: Node3D = null
var _offset := 0.0


func _begin(event: VfxEvent) -> void:
	_offset = minf(float(_visual.get("drain_elapsed", 0.0)), POWER_DOWN_DRAIN.LETHAL_LEAD - 0.25)
	_drain = POWER_DOWN_DRAIN.new()
	_drain.name = "PowerDownDrain"
	add_child(_drain)
	# Driven from here, frame by frame, like the rest of the cue (freezing time freezes it for screenshots).
	_drain.set_process(false)
	_drain.call("setup", _stand_in, event.seed, VfxEvent.damage_tier_for(event.amount), true)


func _lead_seconds() -> float:
	return POWER_DOWN_DRAIN.LETHAL_LEAD - _offset


func _tick(t: float) -> void:
	if is_instance_valid(_drain):
		_drain.call("sample", t + _offset)


func _lead(_t: float, _u: float) -> void:
	pass


## Keep the cue alive until the sword and the orbs are done, whichever is later than the pieces.
func _min_seconds() -> float:
	return float(_drain.call("lifetime")) - _offset if is_instance_valid(_drain) else 0.0
