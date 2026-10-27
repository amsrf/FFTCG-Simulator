extends "res://scripts/effects/card_effect.gd"
## 1-189S Tifa


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx) -> void:
	ctx.dull(ctx.targets)
	ctx.damage(ctx.targets, 6000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Waterkick 《S》《火》: Choose 1 Forward. Dull it and deal it 6000 damage."
		s_cost = true
		cost = {"火": 1}
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._activate(ctx)
