extends "res://scripts/effects/card_effect.gd"
## 1-100C Black Belt


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx) -> void:
	ctx.power_change(ctx.targets, 1000, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《土》《Dull》: Choose 1 Forward blocking. It gains +1000 power."
		cost = {"土": 1}
		tap = true
		targets = {"is_type": "Forward", "is_blocking": true}

	func on_resolve(ctx) -> void:
		await _owner._activate(ctx)
