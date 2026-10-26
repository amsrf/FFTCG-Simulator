extends Node
## FIRST STRIKE probe — the two damage steps, the window between them, and the single-step cases.
##
## Every case is built explicitly: two cards with KNOWN powers are placed, the attacker/blocker slots are set, and
## one clash is driven. Powers are set on the cards so the outcome does not depend on the database.
##
## The decisive cases are the "one-shot" ones: a First Strike striker that can kill in step 1 must take NO damage
## back. That is the whole mechanic in one assertion, and it fails loudly if the two steps collapse into one.
##
## First Strike is granted as a STATUS here, which exercises the granted half of the printed/granted split. The
## printed half is covered by cards 29 and 87 in card_effects.json.

const GAME_SCENE := preload("res://game.tscn")

const STRONG := 6000
const WEAK := 4000

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[FirstStrike] ok   %s" % what)
	else:
		_fails += 1
		print("[FirstStrike] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- neither has it: ONE simultaneous step ---------------------------------------------------------
	var r: Array = await _clash(true, false, false)
	_expect(r[0] == WEAK and r[1] == STRONG,
		"neither: both deal damage in one step (attacker took %s, blocker took %s)" % [r[0], r[1]])
	_expect(not r[3], "neither: the weaker blocker dies — there was no first strike to save it")

	# --- attacker has it and can one-shot: takes NOTHING back ------------------------------------------
	r = await _clash(true, true, false)
	_expect(r[0] == 0,
		"attacker FS: the killed blocker deals NO damage back (attacker took %s)" % r[0])
	_expect(not r[3], "attacker FS: the blocker is dead after step 1")
	_expect(r[2], "attacker FS: and the attacker survives")

	# --- blocker has it and can one-shot: takes NOTHING back -------------------------------------------
	r = await _clash(false, false, true)
	_expect(r[1] == 0,
		"blocker FS: the killed attacker deals NO damage back (blocker took %s)" % r[1])
	_expect(not r[2], "blocker FS: the attacker is dead after step 1")
	_expect(r[3], "blocker FS: and the blocker survives")

	# --- both have it: ONE step, as if neither did -----------------------------------------------------
	r = await _clash(true, true, true)
	_expect(r[0] == WEAK and r[1] == STRONG,
		"both: one simultaneous step (attacker took %s, blocker took %s)" % [r[0], r[1]])
	_expect(not r[3], "both: the weaker blocker still dies, because neither struck first")

	_finish()


## One clash. `attacker_strong` decides who can one-shot, so each case can be arranged to prove something.
## Returns [damage on attacker, damage on blocker, attacker alive, blocker alive].
func _clash(attacker_strong: bool, attacker_fs: bool, blocker_fs: bool) -> Array:
	var field = _game.get("field")
	var attacker: Card = _game.create_card(29, "player")
	var blocker: Card = _game.create_card(29, "player")
	for card in [attacker, blocker]:
		_game.add_child(card)
		field.play_card(card, false, false)
		card.status_effects.clear()
		card.card_effects.clear()
		card.accumulated_damage = 0
	attacker.set_base_power(STRONG if attacker_strong else WEAK)
	blocker.set_base_power(WEAK if attacker_strong else STRONG)
	if attacker_fs:
		attacker.status_effects["first_strike"] = 99
	if blocker_fs:
		blocker.status_effects["first_strike"] = 99

	field.attacker_card = attacker
	field.blocker_card = blocker
	await _game.clash_attacker_blocker()

	var result: Array = [
		attacker.accumulated_damage,
		blocker.accumulated_damage,
		attacker.is_on_field(),
		blocker.is_on_field(),
	]
	# UNTRACK THE SURVIVORS, but do NOT free them. remove_card() is the part that matters: the field walks its
	# card lists for state-based actions, so anything still tracked has to be valid. queue_free() is DEFERRED, and
	# a tween started on such a card runs the frame AFTER it is freed — that produced three "previously freed"
	# SCRIPT ERRORs here while every check still passed, which is the trap this project has recorded twice. The
	# probe quits right after the last case, so leaving the nodes in the tree costs nothing.
	for card in [attacker, blocker]:
		if is_instance_valid(card):
			field.remove_card(card)
	field.reset_attacker()
	field.reset_blocker()
	await get_tree().process_frame
	await get_tree().process_frame
	return result


func _finish() -> void:
	print("[FirstStrike] %d checks | failures: %d" % [_checks, _fails])
	print("[FirstStrike] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
