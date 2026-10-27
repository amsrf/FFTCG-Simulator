extends "res://scripts/effects/card_effect.gd"
## 1-089C Thief


func activated_abilities() -> Array:
	return [Ability0.new(self), Ability1.new(self)]
func _mill_one(ctx: EFFECT_CONTEXT) -> void:
	await ctx.opponent_mills(1)

func _mill_two_draw(ctx: EFFECT_CONTEXT) -> void:
	await ctx.opponent_mills(2)
	ctx.draw(ctx.owner_id, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《風》《Dull》: Your opponent mills 1."
		cost = {"風": 1}
		tap = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._mill_one(ctx)

class Ability1 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《S》《風》《Dull》: Your opponent mills 2. You draw 1."
		s_cost = true
		cost = {"風": 1}
		tap = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._mill_two_draw(ctx)
