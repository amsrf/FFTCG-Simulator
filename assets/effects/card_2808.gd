extends "res://scripts/effects/card_effect.gd"
## 5-134R Celestia: when a party you control attacks, that party gains +1000.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.PARTY_ATTACKS: Callable(self, "when_party_attacks"),
	}


func when_party_attacks(ctx) -> void:
	ctx.power_change_party(1000, 1)
