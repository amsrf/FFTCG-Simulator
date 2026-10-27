extends "res://scripts/effects/card_effect.gd"
## 1-130C Black Mage


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _break_target(ctx) -> void:
	ctx.break_cards(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《雷》《雷》《Dull》, put Black Mage into the Break Zone: Choose 1 damaged Forward. Break it."
		cost = {"雷": 2}
		tap = true
		sacrifice = {"is_source": true}
		targets = {"is_type": "Forward", "is_damaged": true}

	func on_resolve(ctx) -> void:
		await _owner._break_target(ctx)
