extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-084H Y'shtola

func activated_abilities() -> Array:
	return [Ability0.new(self), Ability1.new(self)]
func _wind(ctx: EFFECT_CONTEXT) -> void:
	ctx.damage(ctx.targets, 1000)

func _dull(ctx: EFFECT_CONTEXT) -> void:
	ctx.damage(ctx.targets, 2000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《風》: Choose 1 Forward. Deal it 1000 damage."
		cost = {"風": 1}
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._wind(ctx)

class Ability1 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: Choose 1 Forward. Deal it 2000 damage."
		cost = {}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._dull(ctx)
