extends "res://scripts/effects/card_effect.gd"
## 1-209C Red Mage


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _first_strike_target(ctx) -> void:
	ctx.add_status(ctx.targets, "first_strike", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《雷》《Dull》: Choose 1 attacking Lightning Forward. It gains First Strike."
		cost = {"雷": 1}
		tap = true
		targets = {"is_type": "Forward", "is_attacking": true, "is_element": "雷"}

	func on_resolve(ctx) -> void:
		await _owner._first_strike_target(ctx)
