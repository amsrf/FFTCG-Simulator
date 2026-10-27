extends "res://scripts/effects/card_effect.gd"
## 4-062C Chocobo: when it forms a party and attacks, the party gains +3000.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.PARTY_ATTACK: Callable(self, "when_party_attack"),
	}


func when_party_attack(ctx) -> void:
	ctx.power_change_party(3000, 1)
