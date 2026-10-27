extends "res://scripts/effects/card_effect.gd"
## 3-075 Chocobo: when it forms a party and attacks, the party gains +3000.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.PARTY_ATTACK: Callable(self, "when_party_attack"),
	}


func when_party_attack(ctx: EFFECT_CONTEXT) -> void:
	ctx.power_change_party(3000, 1)


func keywords() -> Array[String]:
	return ["haste"]
