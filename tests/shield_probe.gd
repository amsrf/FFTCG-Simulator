extends Node
## SHIELD probe — Dajh 17 ("the Card Name Sazh you control cannot be chosen by your opponent's Summons or abilities")
## and Serah 45 ("...Snow... by your opponent's abilities").
##
## These are continuous grants from one card to another, so they are a FIELD query asked at the targeting gate.
## Crucially they do NOT filter set effects: "all the Backups" still hits a shielded card, because it was never chosen.

const GAME_SCENE := preload("res://game.tscn")

const DAJH := 17
const SAZH := 13
const SERAH := 45
const SNOW := 43
const CHEMIST := 31
const ENEMY := 41

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Shield] ok   %s" % what)
	else:
		_fails += 1
		print("[Shield] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": DAJH}, {"id": SAZH}, {"id": SERAH}, {"id": SNOW}, {"id": CHEMIST}],
		"opponent_field": [{"id": ENEMY}],
		"player_deck": range(101, 121),
		"opponent_deck": range(141, 161),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var dajh: Card = _card(DAJH)
	var sazh: Card = _card(SAZH)
	var _serah: Card = _card(SERAH)
	var snow: Card = _card(SNOW)
	var chemist: Card = _card(CHEMIST)
	var enemy: Card = _card(ENEMY)

	# --- Dajh: Sazh, from the opponent's Summons AND abilities -------------------------------------------------
	_expect(_field.is_protected_from_being_chosen(sazh, enemy, "Ability"),
		"Dajh shields Sazh from the opponent's abilities")
	_expect(_field.is_protected_from_being_chosen(sazh, enemy, "Summon"),
		"and from the opponent's Summons")
	_expect(not _field.is_protected_from_being_chosen(sazh, dajh, "Ability"),
		"but not from YOUR OWN abilities")
	_expect(not _field.is_protected_from_being_chosen(chemist, enemy, "Ability"),
		"only the NAMED card is shielded")

	# --- Serah: Snow, abilities only --------------------------------------------------------------------------
	_expect(_field.is_protected_from_being_chosen(snow, enemy, "Ability"),
		"Serah shields Snow from the opponent's abilities")
	_expect(not _field.is_protected_from_being_chosen(snow, enemy, "Summon"),
		"but NOT from the opponent's Summons (her text says abilities)")

	# --- the real targeting gate: the blue ring / click validation -------------------------------------------
	_field.set_viable_targets({"is_type": "Backup"}, enemy, "Ability")
	print("[Shield] opponent Ability vs Backups: Sazh valid=%s, Chemist valid=%s, Dajh valid=%s" % [
		sazh.is_valid_target, chemist.is_valid_target, dajh.is_valid_target])
	_expect(not sazh.is_valid_target, "against an opponent's Ability, Sazh is NOT a legal target")
	_expect(chemist.is_valid_target, "while another Backup still is")
	_expect(dajh.is_valid_target, "Dajh does not shield himself")

	_field.set_viable_targets({"is_type": "Forward"}, enemy, "Ability")
	_expect(not snow.is_valid_target, "against an opponent's Ability, Snow is NOT a legal target")
	_field.set_viable_targets({"is_type": "Forward"}, enemy, "Summon")
	_expect(snow.is_valid_target, "but against an opponent's Summon he IS — Serah only covers abilities")

	_field.set_viable_targets({"is_type": "Backup"}, dajh, "Ability")
	_expect(sazh.is_valid_target, "you may still choose Sazh yourself")
	_field.reset_targets()

	# --- SET EFFECTS STILL HIT: "all the Backups" never chooses ----------------------------------------------
	var matched: Array = _game.call("_cards_matching", {"is_type": "Backup"}, enemy)
	var ids: Array = []
	for c in matched:
		ids.append(c.id)
	print("[Shield] an opponent's 'all Backups' effect matches: %s" % str(ids))
	_expect(sazh in matched, "an opponent's 'all Backups' effect still hits Sazh — he was not chosen")
	_expect(chemist in matched, "and every other Backup with it")

	print("[Shield] %d checks | failures: %d" % [_checks, _fails])
	print("[Shield] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
