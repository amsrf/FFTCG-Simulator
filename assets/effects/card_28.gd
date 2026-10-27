extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-028 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.search_deck({"is_named": "Lann"})


func ex_burst_event() -> String:
	return "when_enter_field"


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.power_change(targets, 1000, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Fire》《1》《Dull》: Choose 1 Lann. It gains +1000 power until the end of the turn."
		cost = {"火": 1, "neutral": 1}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().named("Lann"))
		target_count = 1

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
