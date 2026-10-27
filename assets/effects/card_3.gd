extends "res://scripts/effects/card_effect.gd"
## 1-003C Red Mage
## 《Fire》《1》《Dull》: Choose 1 Forward. It cannot block this turn.


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _bind_forward(ctx) -> void:
	ctx.add_status(ctx.targets, "block_disabled", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《火》《1》《Dull》: Choose 1 Forward. It cannot block this turn."
		cost = {"火": 1, "neutral": 1}
		tap = true
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._bind_forward(ctx)
