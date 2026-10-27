extends "res://scripts/effects/card_effect.gd"
## 1-035C Shiva


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _dull_target(ctx) -> void:
	ctx.dull(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《氷》《氷》《Dull》: Choose 1 Forward. Dull it."
		cost = {"氷": 2}
		tap = true
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._dull_target(ctx)
