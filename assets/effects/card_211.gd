extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-211S Rygdea


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").tapped(false)))
	if targets.is_empty():
		return
	ctx.add_status(targets, "rygdea_mark", 1, {
		"source": ctx.source,
		"controller": ctx.controller,
		"on_enter_break_zone": [
			{"name": "choose_target", "author": "game", "argument": [
				{"is_type": "Forward", "controller": "opponent"}]},
			{"name": "dull_targets", "author": "game", "argument": []},
		],
	})
	ctx.damage(targets, 3000)
