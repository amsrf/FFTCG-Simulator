extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	ctx.add_status([ctx.source], "brave", 1)
	ctx.extra_attacks_from_damage()

func power_per_rules() -> Array:
	return [{"count": {"is_type": "Forward", "controller": "player", "exclude": {"is_source": true}}, "value": 1000}]

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Blitz Ace 《S》《Water》《Water》: Until the end of the turn Tidus gains Brave. Tidus can attack as many times as your points of damage this turn."
		cost = {"水": 2}
		s_cost = true

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
