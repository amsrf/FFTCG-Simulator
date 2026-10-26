extends Node
## CONDITION probe — the evaluator, the negation, and the two cards that need them.
##
## The important shape is the if/else built from a guarded instruction plus its negation:
##
##   {damage 4000, condition: "cast_this_turn:Brynhildr"}
##   {damage 2000, condition: "if_last_did_not_succeed"}
##
## which is Sazh 1-013H ("deal 4000 instead if you cast Brynhildr"). It only works if a SKIPPED instruction writes
## false to the latch, and a RUNNING one writes true — both are checked here.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Condition] ok   %s" % what)
	else:
		_fails += 1
		print("[Condition] FAIL %s" % what)


func _run(chain: Array[Instruction]) -> void:
	_game.call("_execute_instructions", chain)
	await get_tree().process_frame
	await get_tree().process_frame


func _activities() -> Array:
	var out: Array = []
	for entry in _game.call("actions_this_turn"):
		out.append(str(entry.get("activity", "")))
	return out


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- board conditions -----------------------------------------------------------------------------
	_expect(_game.call("_controls", "Squall"), "controls:Squall is true — the debug board has one")
	_expect(not _game.call("_controls", "Nobody"), "controls:Nobody is false")
	_expect(_game.call("_controls", "Backup"), "controls:Backup is true for a board with Backups")

	# --- skip writes FALSE, so the negation is a real else-branch --------------------------------------
	var not_cast: Array[Instruction] = [
		Instruction.new("record_action", "game", ["guarded", [], 1], "cast_this_turn:Brynhildr"),
		Instruction.new("record_action", "game", ["else_branch", [], 1], "if_last_did_not_succeed"),
	]
	await _run(not_cast)
	var acts: Array = _activities()
	print("[Condition] without the cast: %s" % str(acts))
	_expect(acts.has("else_branch"), "with the cast condition false, the ELSE branch runs")
	_expect(not acts.has("guarded"), "and the guarded instruction does not")

	# --- now with the cast in the ledger -----------------------------------------------------------------
	_game.call("record_action", "Casted Brynhildr", [], 1)
	var did_cast: Array[Instruction] = [
		Instruction.new("record_action", "game", ["guarded", [], 1], "cast_this_turn:Brynhildr"),
		Instruction.new("record_action", "game", ["else_branch_2", [], 1], "if_last_did_not_succeed"),
	]
	await _run(did_cast)
	acts = _activities()
	print("[Condition] with the cast: %s" % str(acts))
	_expect(acts.has("guarded"), "with the cast in the ledger, the guarded instruction runs")
	_expect(not acts.has("else_branch_2"),
		"and the running instruction writes TRUE, so the else branch is skipped")

	# --- Sazh end to end: 4000 instead of 2000 ----------------------------------------------------------
	var field = _game.get("field")
	var target: Card = _game.call("create_card", 41, "opponent")
	_game.add_child(target)
	field.play_card(target, true, false, false)
	target.set_base_power(10000)
	target.accumulated_damage = 0
	_game.set("_targets", [target])

	# Brynhildr HAS been cast in this turn (recorded above), so the guarded 4000 must apply, not 2000.
	var sazh: Array[Instruction] = [
		Instruction.new("damage_targets", "game", [4000], "cast_this_turn:Brynhildr"),
		Instruction.new("damage_targets", "game", [2000], "if_last_did_not_succeed"),
	]
	await _run(sazh)
	print("[Condition] Sazh with Brynhildr cast: %d damage" % target.accumulated_damage)
	_expect(target.accumulated_damage == 4000, "Sazh deals 4000, not 4000+2000")

	# Next turn: the cast is no longer "this turn", so the else branch applies.
	var turn: int = int(_game.get("turn_number"))
	_game.set("turn_number", turn + 1)
	target.accumulated_damage = 0
	_game.set("_targets", [target])
	await _run(sazh)
	print("[Condition] Sazh next turn: %d damage" % target.accumulated_damage)
	_expect(target.accumulated_damage == 2000, "and 2000 once the cast is no longer this turn")

	# --- untap_all_matching (Hope's Alexander branch) ----------------------------------------------------
	for backup in field.get_back_cards_for("player"):
		backup.tap()
	var tapped_before: int = 0
	for backup in field.get_back_cards_for("player"):
		if backup.tapped:
			tapped_before += 1
	await _run([Instruction.new("untap_all_matching", "game",
		[{"is_type": "Backup", "controller": "player"}])])
	var still_tapped: int = 0
	for backup in field.get_back_cards_for("player"):
		if backup.tapped:
			still_tapped += 1
	_expect(tapped_before > 0 and still_tapped == 0,
		"untap_all_matching untaps every match (%d tapped -> %d)" % [tapped_before, still_tapped])

	# --- the data ---------------------------------------------------------------------------------------
	var d: Dictionary = CardDatabase.card_effects
	for id in ["82", "42", "43"]:
		_expect(d.has(id), "card %s has an entry" % id)
	var sazh_effect = load("res://assets/effects/card_13.gd").new()
	var sazh_specs: Array = sazh_effect.activated_abilities()
	_expect(sazh_specs.size() == 1 and sazh_specs[0].run.is_valid(), "Sazh's conditional damage is code-owned")
	_expect(str(d["43"]["when_attack"]["instructions"][1].get("condition", "")) == "cast_this_turn:Shiva",
		"Snow's Freeze is conditional on casting Shiva")
	_expect(str(d["82"]["when_enter_field"]["instructions"][0].get("condition", "")) == "cast_this_turn:Alexander",
		"Hope's all-Backups branch is conditional on Alexander")

	print("[Condition] %d checks | failures: %d" % [_checks, _fails])
	print("[Condition] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
