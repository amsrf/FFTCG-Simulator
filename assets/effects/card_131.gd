extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-131R Cait Sith


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").cost_at_most(1)))
	if targets.is_empty():
		return
	ctx.break_cards(targets)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	ctx.reveal_top(1)
	if ctx.check_revealed(0, {"is_type": "Forward"}):
		ctx.damage(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT).tapped(false)), 7000)
	ctx.remove_revealed_from_game(0)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Slots 《S》《Lightning》《Dull》: Remove the top card of your deck from the game. If it is a Forward, deal 7000 damage to all active Forwards opponent controls."
		cost = {"雷": 1}
		tap = true
		s_cost = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
