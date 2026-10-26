extends "res://scripts/effects/card_effect.gd"
## Alma 1-153R: this card costs 1 less while you control Ovelia.


func modify_cost(ctx, _card: Card, cost: Dictionary) -> Dictionary:
	if ctx.controls({"is_named": "Ovelia"}):
		return ctx.adjust(cost, -1)
	return cost


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》: Draw 1 card, then discard 1 card from your hand.",
			"cost": {},
			"tap": true,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
	await ctx.discard(ctx.owner_id, 1)