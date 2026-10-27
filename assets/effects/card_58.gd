extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-058L Laguna


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAUSE_DAMAGE_TO_PLAYER: Callable(self, "when_cause_damage_to_player"),
	}


func when_cause_damage_to_player(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").tapped(true)))
	if targets.is_empty():
		return
	if await ctx.may("Deal 7000"):
		ctx.damage(targets, 7000)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.damage(targets, 9000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Desperado 《S》《Ice》《Ice》: Choose 1 dull Forward. Deal it 9000 damage."
		cost = {"氷": 2}
		s_cost = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").tapped(true))
		target_count = 1

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
