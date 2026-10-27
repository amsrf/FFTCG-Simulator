extends "res://scripts/effects/card_effect.gd"
## 1-181H Onion Knight


func activated_abilities() -> Array:
	return [Ability0.new(self)]


class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《1》《Dull》, return Onion Knight to its owner's hand: You may play 1 Onion Knight from your hand onto the field. Use only during your turn."
		cost = {"neutral": 1}
		tap = true
		return_self = true
		only_your_turn = true

	func on_resolve(ctx) -> void:
		await ctx.may_play_from_hand({"is_named": "Onion Knight"}, false, "Play Onion Knight")
