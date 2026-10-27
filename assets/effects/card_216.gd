extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-216S Wakka


func when_attack(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR)))
	if targets.is_empty():
		return
	var forwards: int = ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR)).size()
	ctx.power_change(targets, forwards * 1000, 1)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.add_status(targets, "abilities_nullified", 1)
	ctx.set_power(targets, 1000, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Status Reels 《S》《水》: Choose 1 Forward. Until the end of the turn, it loses all its abilities and its power becomes 1000."
		cost = {"水": 1}
		s_cost = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))
		target_count = 1

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
