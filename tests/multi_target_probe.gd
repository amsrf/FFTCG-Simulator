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
	_expect(_confirms == 0, "and Confirm has NOT been offered yet")
	_expect(field.target_card == null, "the session is ready for a second pick")

	field.set_target_card(backups[2])
	print("[Multi] pick 2: picked=%d arcs=%d" % [
		field.targeting_picked.size(), field.targeting_arrows.size()])
	_expect(field.targeting_picked.size() == 2, "the second pick is recorded")
	_expect(field.targeting_arrows.size() == 3, "two locked arcs plus the aiming one")

	# --- the right-click step back ------------------------------------------------------------------------------------
	field.clear_target_selection()
	print("[Multi] step back: picked=%d arcs=%d" % [
		field.targeting_picked.size(), field.targeting_arrows.size()])
	_expect(field.targeting_picked.size() == 1, "a right-click steps back exactly one pick")

	field.set_target_card(backups[2])
	field.set_target_card(backups[3] if backups.size() > 3 else backups[2])
	print("[Multi] three picks: picked=%d confirms=%d" % [field.targeting_picked.size(), _confirms])
	_expect(field.targeting_picked.size() == 3, "the session completes at three picks")
	_expect(_confirms == 1, "and only then is Confirm offered, exactly once")

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
