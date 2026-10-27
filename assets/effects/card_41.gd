extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-041L Squall


func when_blocks(ctx) -> void:
	await _may_deal_6000(ctx)


func when_blocked(ctx) -> void:
	await _may_deal_6000(ctx)


func _may_deal_6000(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")))
	if targets.is_empty():
		return
	if await ctx.may("Deal 6000"):
		ctx.damage(targets, 6000)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	ctx.add_status([ctx.source], "first_strike", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Renzokuken 《S》《Ice》: Squall gains First Strike until the end of the turn."
		cost = {"氷": 1}
		s_cost = true

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
