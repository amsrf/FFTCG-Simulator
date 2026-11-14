extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-013C Sazh


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _sazh(ctx: EFFECT_CONTEXT) -> void:
	if ctx.cast_this_turn("Brynhildr", ctx.owner_id):
		ctx.damage(ctx.targets, 4000)
	else:
		ctx.damage(ctx.targets, 2000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: Choose 1 Forward. Deal it 2000 damage. Sazh will not activate during your next Active Phase. If you have cast Brynhildr this turn, deal that Forward 4000 damage instead. Sazh will not activate during your next Active Phase."
		cost = {}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._sazh(ctx)
