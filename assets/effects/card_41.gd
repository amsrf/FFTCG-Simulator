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
