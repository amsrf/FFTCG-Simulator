extends "res://scripts/effects/card_effect.gd"
## 1-102H Kimahri


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _copy_special(ctx) -> void:
	if not ctx.targets.is_empty():
		await ctx.copy_skill(ctx.targets[0])

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Ronso Rage 《S》《土》《土》: Choose 1 opponent Forward with a Special Ability. Kimahri gains it, usable once for free."
		s_cost = true
		cost = {"土": 2}
		targets = {"is_type": "Forward", "controller": "opponent", "has_special_ability": true}

	func on_resolve(ctx) -> void:
		await _owner._copy_special(ctx)
