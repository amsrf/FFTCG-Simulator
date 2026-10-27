extends "res://scripts/effects/card_effect.gd"
## 1-169C Scholar


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _look_top(ctx: EFFECT_CONTEXT) -> void:
	await ctx.look_top_may_bottom()

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: Look at the top card of your deck. You may put it on the bottom."
		cost = {}
		tap = true

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._look_top(ctx)
