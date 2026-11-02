extends "res://scripts/effects/card_effect.gd"

func allows_blocker(_owner: Card, blocker: Card) -> bool:
	return int(blocker.cost) < 3
