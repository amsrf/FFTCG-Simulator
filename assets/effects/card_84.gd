extends "res://scripts/effects/card_effect.gd"
## 1-084H Y'shtola

func activated_abilities() -> Array:
	return [Ability0.new(self), Ability1.new(self)]
func _wind(ctx) -> void:
	ctx.damage(ctx.targets, 1000)

func _dull(ctx) -> void:
	ctx.damage(ctx.targets, 2000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《風》: Choose 1 Forward. Deal it 1000 damage."
		cost = {"風": 1}
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._wind(ctx)

class Ability1 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: Choose 1 Forward. Deal it 2000 damage."
		cost = {}
		tap = true
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._dull(ctx)
