extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-064R Aerith


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").excluding(CARD_QUERY.new().named("Aerith"))).up_to(3))
	ctx.untap(targets)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	var targets: Array = ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR))
	ctx.untap(targets)
	ctx.add_status(targets, "cannot_be_chosen", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Planet Protector 《S》《Dull》: Choose up to 3 Backups you control other than Aerith. Activate them."
		cost = {}
		tap = true
		s_cost = true

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
