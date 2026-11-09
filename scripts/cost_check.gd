extends RefCounted
## CAN THIS CP COST BE PAID FROM THESE SOURCES? (comprehensive rules 11.2)
##
## - A Backup dulled for CP gives 1 CP of its element; a hand card discarded gives 2 CP of its element. Light and Dark
##   cards cannot be discarded for CP.
## - At least one CP of each element on the cost must come from that element (11.2.2, 11.2.2.1); Light and Dark costs
##   only need the amount.
## - Payment is exact, except that discards may overshoot by one CP per element needed (11.2.1.1). So overshooting
##   never blocks a payment: "enough CP" is the test.
##
## NECESSARY CONDITIONS ONLY, ON PURPOSE. A rare overlap (one multi-element source counted for two elements) can make
## this say yes to a payment that is not possible, but it never says no to one that is. Its callers (the "you can play
## this" ring, auto-pass) must never hide a real play, and a wrong yes only costs the player a click.

const LIGHT := "光"
const DARK := "闇"

## `cost`: {element: n, "neutral": m}. `backups`: untapped Backups that could be dulled. `hand_cards`: cards that could
## be discarded (the caller leaves out the card being played and anything already spoken for).
static func can_pay(cost: Dictionary, backups: Array, hand_cards: Array) -> bool:
	var need: Dictionary = {}
	var total: int = 0
	for key in cost:
		var amount: int = int(cost[key])
		if amount <= 0:
			continue
		total += amount
		var element: String = str(key)
		if element != "neutral" and element != LIGHT and element != DARK:
			need[element] = int(need.get(element, 0)) + amount
	if total <= 0:
		return true
	var capacity: int = 0
	var by_element: Dictionary = {}
	for backup in backups:
		if backup == null or not is_instance_valid(backup):
			continue
		capacity += 1
		for element in backup.mana_elements():
			by_element[element] = int(by_element.get(element, 0)) + 1
	for card in hand_cards:
		if card == null or not is_instance_valid(card) or card.is_light_or_dark():
			continue
		capacity += 2
		for element in card.mana_elements():
			by_element[element] = int(by_element.get(element, 0)) + 2
	if capacity < total:
		return false
	for element in need:
		if int(by_element.get(element, 0)) < int(need[element]):
			return false
	return true
