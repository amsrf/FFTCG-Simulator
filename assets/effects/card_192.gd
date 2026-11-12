extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-192S Cid Raines


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT).tapped(false)))
	if targets.is_empty():
		return
	ctx.damage(targets, 4000)

func damage_caused_riders() -> Array:
	return [{
		"status": "raines_mark",
		"duration": 1,
		"on_enter_break_zone": [{"name": "opponent_discards", "author": "game", "argument": [1]}],
	}]
