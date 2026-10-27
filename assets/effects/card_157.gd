extends "res://scripts/effects/card_effect.gd"
## 1-157C Scholar


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _return_target(ctx) -> void:
	ctx.return_to_hand(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》, put Scholar into the Break Zone: Choose 1 Forward you control. Return it to its owner's hand."
		cost = {}
		tap = true
		sacrifice = {"is_source": true}
		targets = {"is_type": "Forward", "controller": "player"}

	func on_resolve(ctx) -> void:
		await _owner._return_target(ctx)
