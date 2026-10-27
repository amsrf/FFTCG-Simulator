extends Node
## PROTECTION probe — Auron 1-002R: "The Backups you control cannot be broken by your opponent's Summons or abilities."
##
## The rule is a CONTINUOUS query (Field.is_protected_from_break), not a status on each Backup, so:
##   * a Backup that enters later is covered with no refresh;
##   * the query distinguishes the CAUSE (Summon/Ability vs combat) and the CONTROLLER;
##   * an explicit break and a damage-driven state-based break both ask the same question.

const GAME_SCENE := preload("res://game.tscn")

const AURON := 2
const CHEMIST_A := 31        # player Backup
const CHEMIST_B := 32        # player Backup
const RED_MAGE := 3          # used as the OPPONENT's Backup
const SQUALL := 41           # player Forward: not covered by Auron
const EVOKER := 68           # a Backup played LATER, to prove no refresh is needed

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Protect] ok   %s" % what)
	else:
		_fails += 1
		print("[Protect] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": AURON}, {"id": CHEMIST_A}, {"id": CHEMIST_B}, {"id": SQUALL}],
		"opponent_field": [{"id": RED_MAGE}],
		"player_deck": range(101, 121),
		"opponent_deck": range(141, 161),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var chemist_a: Card = _card(CHEMIST_A)
	var chemist_b: Card = _card(CHEMIST_B)
	var enemy_backup: Card = _card(RED_MAGE)
	var forward: Card = _card(SQUALL)
	var auron_effect = load("res://assets/effects/card_2.gd").new()
	_expect(auron_effect.has_method("prevents_break"),
		"Auron's protection is a code-owned break replacement")
	_expect(auron_effect.static_rules().is_empty(),
		"and no longer relies on a static protects block")

	# --- the query itself -----------------------------------------------------------------------------------
	_expect(_field.is_protected_from_break(chemist_a, "opponent", "Ability"),
		"an opponent's Ability cannot break your Backup while Auron is out")
	_expect(_field.is_protected_from_break(chemist_a, "opponent", "Summon"),
		"and neither can an opponent's Summon")
	_expect(not _field.is_protected_from_break(chemist_a, "player", "Ability"),
		"YOUR OWN abilities can still break it")
	_expect(not _field.is_protected_from_break(chemist_a, "opponent", ""),
		"and combat damage is not covered (empty kind)")
	_expect(not _field.is_protected_from_break(forward, "opponent", "Ability"),
		"Auron protects Backups only, not Forwards")
	_expect(not _field.is_protected_from_break(enemy_backup, "player", "Ability"),
		"and not the OPPONENT's Backups")

	# --- an explicit break is refused ------------------------------------------------------------------------
	_game.call("break_card", chemist_a, "opponent", "Ability")
	_expect(chemist_a.is_on_field(), "break_card() refuses to break a protected Backup")
	_expect(chemist_a.broken == false, "and does not mark it broken")

	# --- a Backup played LATER is covered, with no refresh ---------------------------------------------------
	var new_backup: Card = _game.call("create_card", EVOKER, "player")
	_game.add_child(new_backup)
	_field.play_card(new_backup, false, false, false)
	_expect(_field.is_protected_from_break(new_backup, "opponent", "Ability"),
		"a Backup that enters AFTER Auron is protected too — no status had to be stamped on it")

	# --- damage records its cause, so the state-based sweep can ask the same question ------------------------
	forward.suffer_damage(10000, "Ability", "opponent")
	print("[Protect] %s recorded kind=%s controller=%s" % [
		forward.card_name, forward.last_damage_kind, forward.last_damage_controller])
	_expect(forward.last_damage_kind == "Ability" and forward.last_damage_controller == "opponent",
		"damage records WHAT and WHO dealt it")
	_game.call("enforce_game_state_rules")
	_expect(not forward.is_on_field(), "an unprotected Forward still breaks from that damage")

	# --- your own ability breaks the Backup ------------------------------------------------------------------
	_game.call("break_card", chemist_b, "player", "Ability")
	_expect(not chemist_b.is_on_field(), "your own Ability breaks your Backup as normal")
	# --- removal that is not a break bypasses the protection -------------------------------------------------
	_game.call("put_card_into_graveyard", chemist_a)
	_expect(not chemist_a.is_on_field(), "put_card_into_graveyard() is not a break and is not protected")

	print("[Protect] %d checks | failures: %d" % [_checks, _fails])
	print("[Protect] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
