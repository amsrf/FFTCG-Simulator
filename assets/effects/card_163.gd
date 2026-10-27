extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	ctx.add_status([ctx.source], "brave", 1)
	ctx.extra_attacks_from_damage()

func power_modifier(ctx) -> int:
	return ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR).excluding_source()).size() * 1000

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Blitz Ace 《S》《Water》《Water》: Until the end of the turn Tidus gains Brave. Tidus can attack as many times as your points of damage this turn."
		cost = {"水": 2}
		s_cost = true

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
