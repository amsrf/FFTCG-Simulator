extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-211S Rygdea


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field").chooses(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").tapped(false))),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_trigger_targets()
	if targets.is_empty():
		return
	ctx.add_status(targets, "rygdea_mark", 1, {
		"source": ctx.source,
		"controller": ctx.controller,
		"effect_id": ctx.source.id,
		# Called by the engine when the marked Forward reaches the Break Zone this turn (see card_72.gd).
		"on_enter_break_zone": "marked_card_to_break_zone",
	})
	ctx.damage(targets, 3000)


## The marked Forward was put into the Break Zone this turn: choose 1 Forward your opponent controls and dull it.
func marked_card_to_break_zone(ctx: EFFECT_CONTEXT) -> void:
	var picks: Array = await ctx.choose_targets(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT))
	ctx.dull(picks)
