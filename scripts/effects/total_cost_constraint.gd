extends "res://scripts/effects/selection_constraint.gd"
## A bound on the sum of printed costs in the selection. `min_total == max_total` makes it an exact-cost
## requirement ("cards whose total cost is 4"); a max alone is "up to".

var min_total: int = 0
var max_total: int = 0


func _init(p_min: int = 0, p_max: int = 0) -> void:
	min_total = mini(p_min, p_max)
	max_total = maxi(p_min, p_max)


func allows(id: int, selected: Array) -> bool:
	var candidate: int = int(CARD_FILTER.card_by_id(id).get("cost", 0))
	return total_of(selected) + candidate <= max_total


func valid(selected: Array) -> bool:
	var total: int = total_of(selected)
	return total >= min_total and total <= max_total


func reason(id: int, selected: Array) -> String:
	var candidate: int = int(CARD_FILTER.card_by_id(id).get("cost", 0))
	if total_of(selected) + candidate > max_total:
		return "Total cost would exceed %d" % max_total
	return ""


func total_of(selected: Array) -> int:
	var total: int = 0
	for id in selected:
		total += int(CARD_FILTER.card_by_id(int(id)).get("cost", 0))
	return total
