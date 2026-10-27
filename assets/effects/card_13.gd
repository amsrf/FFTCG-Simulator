extends "res://scripts/effects/card_effect.gd"
## 1-013C Sazh


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _sazh(ctx) -> void:
	if ctx.game.cast_this_turn("Brynhildr", ctx.owner_id):
		ctx.damage(ctx.targets, 4000)
	else:
		ctx.damage(ctx.targets, 2000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: Choose 1 Forward. Deal it 4000 damage if you cast Brynhildr this turn; otherwise 2000."
		cost = {}
		tap = true
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._sazh(ctx)
