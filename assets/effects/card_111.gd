extends "res://scripts/effects/card_effect.gd"
## 1-111C Tama
##
## 《X》《Dull》, put Tama into the Break Zone: Play 1 Character Card of cost X or less from your hand onto the field.
##
## X is declared BEFORE payment by Field.begin_skill_activation(); the chosen value is carried on the stack proxy and
## is available to this handler through ctx.ability_x(). The self-sacrifice is deferred to commit, so cancelling the
## mana modal leaves Tama on the field.


func activated_abilities() -> Array:
	return [Ability0.new(self)]


class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《X》《Dull》, put Tama into the Break Zone: Play 1 Character Card of cost X or less from your hand onto the field."
		tap = true
		sacrifice = {"is_source": true}
		defer_sacrifice = true
		x_cost = true
		x_min = 0

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		var x: int = ctx.ability_x()
		if x < 0:
			return
		var candidates: Array = ctx.cards_in(
			"hand",
			CARD_QUERY.new().character(true).cost_at_most(x),
			"self")
		if candidates.is_empty():
			return
		var picked: Card = await ctx.choose_hand_card(
			candidates,
			"Play a Character of cost %d or less" % x)
		if picked != null:
			ctx.play_from_hand_card(picked)
