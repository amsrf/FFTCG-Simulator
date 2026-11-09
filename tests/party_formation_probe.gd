extends Node
## PARTY FORMATION (presentation): the party closes up inside its own row, cards in the way slide aside, a plate and
## the party total appear, and everything goes back home when the party disbands or shrinks to one.
##
## Uses the debug board's Fire Forwards (Red XIII, Zack) plus Auron, and Squall (Ice) as the bystander. Squall is put
## BETWEEN the Fire members first — the A, C, B case where a naive "gather at the midpoint" would land on him.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const AURON := 1

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[Formation] %s %s" % ["ok  " if ok else "FAIL", what])

func _named(row: Array, name: String) -> Card:
	for c in row:
		if c.card_name == name:
			return c
	return null

func _settle() -> void:
	for i in range(3):
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout

func _no_overlap(row: Array, field) -> bool:
	for a in row:
		for b in row:
			if a != b and absf(a.position.x - b.position.x) < field.ROW_CARD_STEP - 0.01:
				return false
	return true

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	for i in range(4):
		await get_tree().process_frame
	var field = game.field
	var row: Array = field.front_cards
	var red: Card = _named(row, "Red XIII")
	var zack: Card = _named(row, "Zack")
	var squall: Card = _named(row, "Squall")
	if red == null or zack == null or squall == null:
		print("[Formation] debug board changed: need Red XIII, Zack, Squall in the Forward row")
		print("[Formation] RESULT: 1 FAILED")
		get_tree().quit(1)
		return
	# A, C, B: Squall between the two Fire Forwards.
	red.position.x = -0.65
	squall.position.x = 0.0
	zack.position.x = 0.65
	var home := {red: -0.65, squall: 0.0, zack: 0.65}
	for c in [red, zack]:
		c.status_effects.erase("summoning_sickness")
		if c.tapped:
			c.untap()

	# --- form the party ---------------------------------------------------------------------------------------------
	field.set_attacker(red)
	field.add_party_member(zack)
	await _settle()
	_expect(field.is_party(), "Red XIII and Zack form a party")
	_expect(absf(absf(red.position.x - zack.position.x) - field.ROW_CARD_STEP) < 0.01,
		"the members close up, one step apart (%.2f, %.2f)" % [red.position.x, zack.position.x])
	_expect(absf((red.position.x + zack.position.x) / 2.0) < 0.01, "around their midpoint")
	_expect(_no_overlap(row, field), "Squall, who stood between them, was pushed aside: nothing overlaps (squall %.2f)" % squall.position.x)
	var plate: Node3D = field.get_node_or_null("PartyPlate")
	var badge: Label3D = field.get_node_or_null("PartyBadge")
	_expect(plate != null and plate.visible, "the party plate is shown")
	_expect(badge != null and badge.visible and badge.text.contains(str(red.power + zack.power)),
		"the badge shows the party total (%s)" % (badge.text.replace("\n", " ") if badge != null else "none"))

	# --- a third member, then losing one of three keeps the party ----------------------------------------------------
	var auron: Card = game.create_card(AURON, Card.PLAYER)
	# In play a card always arrives from somewhere (hand, deck); a parentless one cannot be moved onto the field.
	game.hand.add_card(auron)
	field.play_card(auron, false, false)
	auron.status_effects.erase("summoning_sickness")
	await get_tree().process_frame
	field.add_party_member(auron)
	await _settle()
	_expect(field.attacking_party.size() == 3 and _no_overlap(row, field), "a third member joins; still no overlap")
	_expect(badge.text.contains(str(red.power + zack.power + auron.power)), "the total counts all three")
	field.remove_card(zack)   # every way off the field ends here (break, return, exile)
	await _settle()
	_expect(field.is_party() and plate.visible, "losing one of three keeps the party and its plate")
	_expect(badge.text.contains(str(red.power + auron.power)), "the total drops to the two survivors (%s)" % badge.text.replace("\n", " "))
	_expect(absf(absf(red.position.x - auron.position.x) - field.ROW_CARD_STEP) < 0.01, "the survivors close the hole (red %.2f, auron %.2f)" % [red.position.x, auron.position.x])

	# --- down to one: no party, everyone home ------------------------------------------------------------------------
	field.remove_card(auron)
	await _settle()
	_expect(not field.is_party() and not plate.visible and not badge.visible, "one left: no party, plate and badge gone")
	_expect(absf(red.position.x - home[red]) < 0.01 and absf(squall.position.x - home[squall]) < 0.01,
		"the row is back home (red %.2f, squall %.2f)" % [red.position.x, squall.position.x])

	# --- a fresh party disbanding normally (reset_attacker) restores the row too -------------------------------------
	field.reset_attacker()
	if not row.has(zack):
		row.append(zack)   # back on the field for a second, plain party
	zack.position.x = home[zack]
	field.set_attacker(red)
	field.add_party_member(zack)
	await _settle()
	field.reset_attacker()
	await _settle()
	_expect(absf(red.position.x - home[red]) < 0.01 and absf(squall.position.x - home[squall]) < 0.01
		and absf(zack.position.x - home[zack]) < 0.01, "after the attack disbands, every card is exactly home")
	_expect(not plate.visible, "and the plate is gone")

	# --- neighbours: nothing moves at all ------------------------------------------------------------------------------
	red.position.x = -0.65
	zack.position.x = 0.0
	squall.position.x = 0.65
	field.set_attacker(red)
	field.add_party_member(zack)
	await _settle()
	_expect(absf(red.position.x + 0.65) < 0.001 and absf(zack.position.x) < 0.001 and absf(squall.position.x - 0.65) < 0.001,
		"members already side by side: no card moves (red %.2f, zack %.2f, squall %.2f)" % [red.position.x, zack.position.x, squall.position.x])
	_expect(plate.visible and absf(badge.position.x - (-0.325)) < 0.01 and badge.text == str(red.power + zack.power),
		"the plate still shows, and the bare total sits in the gap between them (%s at %.2f)" % [badge.text, badge.position.x])
	field.reset_attacker()
	await _settle()

	print("[Formation] %d checks | failures: %d" % [_checks, _fails])
	print("[Formation] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
