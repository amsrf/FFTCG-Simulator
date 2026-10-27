extends "res://scripts/effects/card_effect.gd"
## 1-078C Ninja


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _activate(ctx) -> void:
	ctx.damage(ctx.targets, 2000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《風》, discard 1 card: Choose 1 Forward. Deal it 2000 damage."
		cost = {"風": 1}
		discard = 1
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._activate(ctx)
