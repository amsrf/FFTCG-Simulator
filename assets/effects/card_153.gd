extends "res://scripts/effects/card_effect.gd"
## Alma 1-153R: this card costs 1 less while you control Ovelia.


func modify_cost(ctx: COST_CONTEXT, _card: Card, cost: Dictionary) -> Dictionary:
	if ctx.controls({"is_named": "Ovelia"}):
		return ctx.adjust(cost, -1)
	return cost


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 1)
	await ctx.discard(ctx.owner_id, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: Draw 1 card, then discard 1 card from your hand."
		cost = {}
		tap = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
