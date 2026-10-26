extends "res://scripts/effects/card_effect.gd"
## 1-041L Squall


func when_blocks(ctx) -> void:
	await _may_deal_6000(ctx)


func when_blocked(ctx) -> void:
	await _may_deal_6000(ctx)


func _may_deal_6000(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"})
	if targets.is_empty():
		return
	if await ctx.may("Deal 6000"):
		ctx.damage(targets, 6000)


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Renzokuken 《S》《Ice》: Squall gains First Strike until the end of the turn.",
			"cost": {"氷": 1},
			"s_cost": true,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.add_status([ctx.source], "first_strike", 1)