extends Node
## PARTY probe (slice 1) — formation, tapping, First Strike, the combat maths, and disbanding.
##
## The blocker's damage split is exercised through the Agent seam's default (greedy, 1000-point chunks); the human
## arrow window is slice 2 and is not tested here.
##
## IDs are fixed on purpose: 41 Squall and 43 Snow are BOTH ice (party), 29 Red XIII is fire (must not join). The
## first version of this probe searched a candidate list and happily returned the reference card itself, which made
## "a second same-element Forward" a copy of the first.

const GAME_SCENE := preload("res://game.tscn")

const ICE_A := 41      # Squall, Forward, 氷
const ICE_B := 43      # Snow,   Forward, 氷
const FIRE_C := 29     # Red XIII, Forward, 火

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Party] ok   %s" % what)
	else:
		_fails += 1
		print("[Party] FAIL %s" % what)


func _make_forward(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


## A fresh same-element pair, already selected as an attacking party.
##
## RESET FIRST. Without it the previous combat's party is still selected, the first click JOINS it (same element) and
## the "pair" silently becomes four or six members — which is exactly what the first draft did.
func _form_pair() -> Array:
	_field.reset_attacker()
	var x: Card = _make_forward(ICE_A, "player")
	var y: Card = _make_forward(ICE_B, "player")
	_field.set_attacker(x)
	_field.set_attacker(y)
	return [x, y]


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	# --- formation ----------------------------------------------------------------------------------------
	var a: Card = _make_forward(ICE_A, "player")
	var b: Card = _make_forward(ICE_B, "player")
	var c: Card = _make_forward(FIRE_C, "player")
	print("[Party] a=%s %s · b=%s %s · c=%s %s" % [
		a.card_name, str(_field.element_set(a)), b.card_name, str(_field.element_set(b)),
		c.card_name, str(_field.element_set(c))])
	_expect(_field.element_set(a) == _field.element_set(b), "the pair really is the same element")
	_expect(_field.element_set(a) != _field.element_set(c), "and the third card really is a different one")

	_field.set_attacker(a)
	_expect(_field.attacker_card == a and _field.party_members().size() == 1,
		"the first click is a normal single attacker")
	_field.set_attacker(b)
	_expect(_field.is_party() and _field.party_members().size() == 2,
		"a same-element Forward JOINS the party (%d members)" % _field.party_members().size())
	_field.set_attacker(c)
	_expect(_field.party_members().size() == 2 and _field.attacker_card == a,
		"a DIFFERENT-element Forward does nothing — it does not join and does not replace the attacker")

	# --- leaving and disbanding ---------------------------------------------------------------------------
	_field.remove_party_member(b)
	_expect(_field.party_members().size() == 1, "clicking a member again drops it from the party")
	_field.set_attacker(b)
	_expect(_field.party_members().size() == 2, "and it can rejoin")

	# ACTUALLY leave the field: remove_card() alone leaves the card's zone as FIELD, so pruning correctly does
	# nothing. break_card() is a real departure and goes through remove_card -> prune_party().
	_game.call("break_card", b)
	await get_tree().process_frame
	_expect(_field.party_members().size() == 1 and not _field.is_party(),
		"a member leaving the field disbands the party down to one")
	_expect(_field.attacker_card == a, "and the remaining member keeps attacking as a normal attack")

	# --- Brave is per member -------------------------------------------------------------------------------
	var pair: Array = _form_pair()
	var x: Card = pair[0]
	var y: Card = pair[1]
	_expect(_field.party_members().size() == 2, "party formed for the tapping check")
	x.status_effects["brave"] = 1        # x does not dull
	y.status_effects.erase("brave")      # y does
	_field.execute_card_attack()
	_expect(not x.tapped, "a Brave member does NOT dull when the party attacks")
	_expect(y.tapped, "and a member without Brave does")
	x.untap()
	y.untap()
	x.status_effects.erase("brave")

	# --- First Strike only if EVERY member has it ------------------------------------------------------------
	_expect(not _field.party_has_first_strike(), "no First Strike on the members -> no First Strike on the party")
	y.status_effects["first_strike"] = 1
	_expect(not _field.party_has_first_strike(), "one member is not enough")
	x.status_effects["first_strike"] = 1
	_expect(_field.party_has_first_strike(), "all members -> the party has it")
	x.status_effects.erase("first_strike")
	y.status_effects.erase("first_strike")

	# --- the combat maths (fresh pair, so nothing is already damaged) ------------------------------------------
	var pair2: Array = _form_pair()
	var p: Card = pair2[0]
	var q: Card = pair2[1]
	var blocker: Card = _make_forward(ICE_A, "opponent")
	blocker.power = 20000
	p.power = 3000
	q.power = 5000
	_expect(_field.party_members().size() == 2, "party formed for the combat check")
	_expect(_field.party_has_first_strike() == false, "no First Strike on the party")
	_field.set("blocker_card", blocker)
	await _game.call("clash_attacker_blocker")
	print("[Party] blocker took %d, members took %d + %d (blocker power %d)" % [
		blocker.accumulated_damage, p.accumulated_damage, q.accumulated_damage, blocker.power])
	_expect(blocker.accumulated_damage == 8000, "the party deals the SUM of its members' power (3000 + 5000)")
	_expect(p.accumulated_damage + q.accumulated_damage == blocker.power,
		"the blocker's power is fully distributed across the party")
	_expect(p.accumulated_damage > 0 and q.accumulated_damage > 0, "and both members took a share")

	# --- one block arc PER party member ---------------------------------------------------------------------
	var pair4: Array = _form_pair()
	var blocker_arc: Card = _make_forward(ICE_A, "opponent")
	_field.show_block_arc(blocker_arc)
	_expect(_field.block_arrows.size() == 2,
		"blocking a two-member party draws TWO arcs (%d)" % _field.block_arrows.size())
	var hits: int = 0
	for arc in _field.block_arrows:
		for member in pair4:
			if arc.locked_target.distance_to(member.get_global_face_centre()) < 0.01:
				hits += 1
	_expect(hits == 2, "each arc lands on a different party member (%d matched)" % hits)
	var from_blocker: bool = true
	for arc in _field.block_arrows:
		if arc.start_pos.distance_to(blocker_arc.get_global_face_centre()) >= 0.01:
			from_blocker = false
	_expect(from_blocker, "and every arc starts at the blocker's centre")
	_field.hide_block_arc()
	_expect(_field.block_arrows.is_empty(), "hide_block_arc() disposes of them all")

	# --- "when this card forms a party and attacks": Chocobo 75 / 76 ---------------------------------------
	# Wind pair, because the Chocobos are wind: 75 (Chocobo, 4000, +3000 to the party) and 82 (Hope, wind Forward).
	var choco: Card = _make_forward(75, "player")
	var hope: Card = _make_forward(82, "player")
	_field.reset_attacker()
	_field.set_attacker(choco)
	_field.add_party_member(hope)
	var choco_before: int = choco.power
	var hope_before: int = hope.power
	_field.execute_card_attack()
	var stack = _game.get("stack")
	var guard: int = 0
	while stack.stack_length() > 0 and guard < 8:
		await stack.resolve_top_effect()
		guard += 1
	print("[Party] after the Chocobo party attack: Chocobo %d -> %d, Hope %d -> %d" % [
		choco_before, choco.power, hope_before, hope.power])
	_expect(choco.power == choco_before + 3000, "the Chocobo buffs ITSELF (+3000)")
	_expect(hope.power == hope_before + 3000, "and every other Forwards forming the party with it")

	# A party of ONE is not a party: the same card must not trigger it.
	var solo: Card = _make_forward(75, "player")
	_field.reset_attacker()
	_field.set_attacker(solo)
	var solo_before: int = solo.power
	_field.execute_card_attack()
	guard = 0
	while stack.stack_length() > 0 and guard < 8:
		await stack.resolve_top_effect()
		guard += 1
	_expect(solo.power == solo_before, "a lone Chocobo attacking does NOT trigger the party effect")


	# --- unblocked party deals ONE damage (fresh pair again; the previous one may have broken) ------------------
	var pair3: Array = _form_pair()
	var m: Card = pair3[0]
	var n: Card = pair3[1]
	_expect(m.is_on_field() and n.is_on_field(), "the unblocked pair is on the field")
	_field.set("blocker_card", null)
	var before: int = _game.get("opponent").damage_count()
	_field.execute_card_attack()
	_game.call("cause_attacking_damage")
	await get_tree().process_frame
	var after: int = _game.get("opponent").damage_count()
	_expect(after == before + 1, "an unblocked party deals ONE damage, not one per member (%d -> %d)" % [before, after])

	print("[Party] %d checks | failures: %d" % [_checks, _fails])
	print("[Party] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
