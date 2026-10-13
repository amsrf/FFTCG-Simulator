extends Node
## MULTI-TARGET SESSIONS. `choose_target` may carry a "count": the session then takes that many picks — each leaving its
## own arc locked on the card — before Confirm is offered, and a right-click steps back one pick at a time.
##
##   godot --headless res://tests/multi_target_probe.tscn --quit-after 900

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _confirms: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Multi] ok   ", what)
	else:
		_fails += 1
		print("[Multi] FAIL ", what)

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = game.field
	field.request_target_confirmation.connect(func(_target, _allow): _confirms += 1)

	var backups: Array[Card] = field.get_back_cards_for("player")
	_expect(backups.size() >= 3, "the debug board offers at least three Backups")
	if backups.size() < 3:
		_finish()
		return
	var source: Card = backups[0]
	# A FOURTH Backup: a three-pick session needs three targets that are not the source, and the debug board has three
	# Backups in total. (The first version of this probe re-picked one and the session correctly refused it.)
	var extra: Card = game.create_card(3, "player")
	field.add_child(extra)
	field.play_card(extra, false, false)
	backups = field.get_back_cards_for("player")
	print("[Multi] the board now has %d Backups, using %s as the source" % [backups.size(), source.card_name])
	_expect(backups.size() >= 4, "there are three Backups besides the source")

	# --- a three-target session ---------------------------------------------------------------------------------------
	field.request_target({"is_type": "Backup", "count": 3}, source, true, "Ability")
	print("[Multi] opened: count=%d picked=%d arcs=%d" % [
		field.targeting_count, field.targeting_picked.size(), field.targeting_arrows.size()])
	_expect(field.targeting_count == 3, "count 3 is read off the criteria")
	_expect(field.targeting_arrows.size() == 1, "with one aiming arc waiting")

	field.set_target_card(backups[1])
	print("[Multi] pick 1: picked=%d confirms=%d target_card=%s" % [
		field.targeting_picked.size(), _confirms, str(field.target_card)])
	_expect(field.targeting_picked.size() == 1, "the first pick is recorded")
	# UP TO N, so confirming early is allowed and Confirm is therefore offered from the FIRST pick onward — the session
	# stays open and the aiming arc stays, so the player can also keep going.
	_expect(_confirms >= 1, "Confirm is already offered after one pick — the card says 'up to 3'")
	_expect(field.target_card == null, "the session is ready for a second pick")

	field.set_target_card(backups[2])
	print("[Multi] pick 2: picked=%d arcs=%d" % [
		field.targeting_picked.size(), field.targeting_arrows.size()])
	_expect(field.targeting_picked.size() == 2, "the second pick is recorded")
	_expect(field.targeting_arrows.size() == 3, "two locked arcs plus the aiming one")
	# EVERY PICK KEEPS ITS RING. Refreshing the legal set after a pick runs set_viable_targets(), which clears the pick
	# highlight on every card — so without putting it back, only the newest pick stayed lit.
	var lit: int = 0
	for b in backups:
		if b.ring_selected():
			lit += 1
	print("[Multi] orange rings on %d cards for %d picks" % [lit, field.targeting_picked.size()])
	_expect(lit == field.targeting_picked.size(), "every picked card wears a ring, not just the last one")

	# --- the right-click step back ------------------------------------------------------------------------------------
	var dropped: Card = field.targeting_picked[1]
	field.clear_target_selection()
	print("[Multi] step back: picked=%d arcs=%d" % [
		field.targeting_picked.size(), field.targeting_arrows.size()])
	_expect(field.targeting_picked.size() == 1, "a right-click steps back exactly one pick")
	_expect(not dropped.ring_selected(),
		"and the card it gave back loses its ring")
	_expect(field.targeting_picked[0].ring_selected(),
		"while the pick that is still picked keeps its own")

	field.set_target_card(backups[2])
	field.set_target_card(backups[3] if backups.size() > 3 else backups[2])
	print("[Multi] three picks: picked=%d confirms=%d" % [field.targeting_picked.size(), _confirms])
	_expect(field.targeting_picked.size() == 3, "the session completes at three picks")
	_expect(_confirms >= 3, "and Confirm was offered at every pick, the last one closing the session")

	# --- AND IT STILL STEPS BACK FROM A FULL SESSION, one pick per click, all the way to none -------------------------
	# This is the case that was broken: at three of three the step-back guard no longer applied, so the first right-click
	# did nothing to the list and every one after it did nothing either.
	field.clear_target_selection()
	print("[Multi] step back 1 from full: picked=%d arcs=%d" % [
		field.targeting_picked.size(), field.targeting_arrows.size()])
	_expect(field.targeting_picked.size() == 2, "a full session steps back to two")
	field.clear_target_selection()
	print("[Multi] step back 2 from full: picked=%d" % field.targeting_picked.size())
	_expect(field.targeting_picked.size() == 1, "and again to one")
	field.clear_target_selection()
	print("[Multi] step back 3 from full: picked=%d" % field.targeting_picked.size())
	_expect(field.targeting_picked.size() == 0, "and again to none — every pick comes back, one per click")

	# --- the reported sequence: three picks, taken to none, then re-picked IN THE OTHER ORDER and stepped back once.
	# The arrows and the picks used to stop agreeing here, and the single step back took TWO arrows off the board.
	field.set_target_card(backups[3])
	field.set_target_card(backups[2])
	field.set_target_card(backups[1])
	print("[Multi] reversed order, full: picked=%d arcs=%d" % [
		field.targeting_picked.size(), field.targeting_arrows.size()])
	_expect(field.targeting_picked.size() == 3, "re-picking in the other order fills the session again")
	_expect(field.targeting_arrows.size() == 3, "a full session holds exactly one arc per pick, and none aiming")
	field.clear_target_selection()
	print("[Multi] reversed order, one step back: picked=%d arcs=%d" % [
		field.targeting_picked.size(), field.targeting_arrows.size()])
	_expect(field.targeting_picked.size() == 2, "one step back leaves two picks")
	_expect(field.targeting_arrows.size() == 3, "and takes exactly ONE arrow, not two")
	_expect(field.targeting_arrows.size() == field.targeting_picked.size() + 1,
		"leaving the invariant intact: one arc per pick, plus the aiming one")

	# --- count 1 is untouched -----------------------------------------------------------------------------------------
	_confirms = 0
	field.request_target({"is_type": "Backup"}, source, true, "Ability")
	_expect(field.targeting_count == 1, "no count means one target")
	field.set_target_card(backups[1])
	print("[Multi] single target: picked=%d confirms=%d" % [field.targeting_picked.size(), _confirms])
	_expect(field.targeting_picked.size() == 1 and _confirms == 1,
		"one pick goes straight to Confirm, exactly as before")

	_finish()

func _finish() -> void:
	print("[Multi] %d checks | failures: %d" % [_checks, _fails])
	print("[Multi] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0)
