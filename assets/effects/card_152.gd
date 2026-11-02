extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").excluding(CARD_QUERY.new().named("Ultimecia")))
	ctx.add_status(targets, "frozen", 1)

func on_character_enter(entering: Card, _ctx: EFFECT_CONTEXT) -> void:
	if entering.is_type("Forward") and entering.card_name != "Ultimecia":
		entering.tap()

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Time Compression 《S》《Water》《Water》《Water》: Freeze all the Forwards other than Ultimecia."
		cost = {"水": 3}
		s_cost = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
