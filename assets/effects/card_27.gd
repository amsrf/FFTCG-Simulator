extends "res://scripts/effects/card_effect.gd"

func allows_blocker(owner: Card, blocker: Card) -> bool:
	return blocker.power <= owner.power


func can_block_attacker(owner: Card, attacker: Card) -> bool:
	return attacker.power <= owner.power
