extends "res://scripts/effects/card_effect.gd"
## 1-211S Rygdea


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward", "is_tapped": false})
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
