extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	ctx.power_change([ctx.source], 2000, 1)
	ctx.add_status([ctx.source], "haste", 1)
	ctx.add_status([ctx.source], "first_strike", 1)

func power_modifier(ctx) -> int:
	return ctx.cards_in("field", CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.YOUR)).size() * 1000

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Shout 《S》《Lightning》: Until the end of the turn, Ramza gains +2000 power, Haste and First Strike."
		cost = {"雷": 1}
		s_cost = true

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
