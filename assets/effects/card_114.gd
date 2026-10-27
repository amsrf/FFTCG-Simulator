extends "res://scripts/effects/card_effect.gd"
## 1-114R Barret


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx) -> void:
	ctx.damage(ctx.targets, 4000)
	ctx.source.power_change(4000, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Hammer Blow 《S》《土》《土》: Choose 1 Forward. Deal it 4000 damage. Barret gains +4000 power."
		s_cost = true
		cost = {"土": 2}
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._activate(ctx)
