extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")


func activated_abilities() -> Array:
	return [Ability0.new(self), Ability1.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	ctx.power_change([ctx.source], 1000, 1)

func _skill_1(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = ctx.targets.duplicate()
	if not targets.is_empty():
		ctx.break_cards(targets)

func static_rules() -> Dictionary:
	return {"cannot_be_returned_to_hand": {"sources": ["Summon", "Ability"], "controller": "opponent"}}

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《雷》《雷》: Gilgamesh gains +1000 power until the end of the turn."
		cost = {"雷": 2}

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)

class Ability1 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Divider 《S》《雷》《雷》: Choose 1 Forward. Break it. Use only if you have received 4+ damage."
		cost = {"雷": 2}
		s_cost = true
		only_if_damage_received = 4
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))
		target_count = 1

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_1(ctx)
