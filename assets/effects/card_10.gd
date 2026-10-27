extends "res://scripts/effects/card_effect.gd"
## 1-010C Black Mage


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx) -> void:
	ctx.damage(ctx.targets, 4000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《火》《Dull》, put Black Mage into the Break Zone: Choose 1 Forward. Deal it 4000 damage."
		cost = {"火": 1}
		tap = true
		sacrifice = {"is_source": true}
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._activate(ctx)
