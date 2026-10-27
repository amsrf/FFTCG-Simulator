extends "res://scripts/effects/card_effect.gd"
## 12-058C Gippal: when a party you control attacks, that party gains +5000.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.PARTY_ATTACKS: Callable(self, "when_party_attacks"),
	}


func when_party_attacks(ctx) -> void:
	ctx.power_change_party(5000, 1)

func static_rules() -> Dictionary:
	return {"party_brave": true}
