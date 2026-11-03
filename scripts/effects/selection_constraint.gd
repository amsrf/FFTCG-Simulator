extends RefCounted
## One rule over a multi-card selection. `allows()` decides whether a card can be picked given the current
## selection (the UI dims it and blocks the click); `valid()` decides whether the whole selection is legal for
## Confirm (e.g. a total-cost rule that must equal 4).
##
## Constraints receive card DATABASE IDS and the list of ids already selected. They use CardFilter to read the
## printed card data, because deck search works with ids rather than live Card nodes.

const CARD_FILTER := preload("res://scripts/card_filter.gd")


func allows(_id: int, _selected: Array) -> bool:
	return true


func valid(_selected: Array) -> bool:
	return true


## Short UI explanation for why a card is disabled, or "" when the card is available.
func reason(_id: int, _selected: Array) -> String:
	return ""
