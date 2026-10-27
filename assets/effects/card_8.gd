extends "res://scripts/effects/card_effect.gd"

func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _shot(ctx) -> void:
	ctx.damage(ctx.targets, 2000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《火》《1》《Dull》: Choose 1 Forward of cost 3 or less. Deal it 2000 damage."
		cost = {"火": 1, "neutral": 1}
		tap = true
		targets = {"is_type": "Forward", "is_cost_lower_than": 3}
		target_count = 1

	func on_resolve(ctx) -> void:
		await _owner._shot(ctx)
