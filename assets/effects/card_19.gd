extends "res://scripts/effects/card_effect.gd"
## 1-019C Black Mage


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _untap_target(ctx) -> void:
	ctx.untap(ctx.targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《火》《Dull》: Choose 1 Fire Backup you control. Activate it."
		cost = {"火": 1}
		tap = true
		targets = {"is_type": "Backup", "is_element": "Fire", "controller": "player"}

	func on_resolve(ctx) -> void:
		await _owner._untap_target(ctx)
