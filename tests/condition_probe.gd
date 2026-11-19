extends Node
## CONDITION probe — the evaluator card code reads through EffectContext.condition() ("controls:Laguna",
## "cast_this_turn:Brynhildr"), and the cards that need it: Sazh 1-013H ("deal 4000 instead if you cast Brynhildr"),
## end to end. (The instruction-chain if/else this probe used to test went with the instruction executor.)

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")

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


	await get_tree().process_frame
	await get_tree().process_frame




func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- board conditions -----------------------------------------------------------------------------
	_expect(_game.call("_controls", "Squall", Card.PLAYER), "controls:Squall is true — the debug board has one")
	_expect(not _game.call("_controls", "Nobody", Card.PLAYER), "controls:Nobody is false")
	_expect(_game.call("_controls", "Backup", Card.PLAYER), "controls:Backup is true for a board with Backups")

	# --- cast_this_turn, read the way card code reads it ------------------------------------------------
	var probe_source: Card = _game.call("create_card", 13, "player")
	var probe_ctx = EFFECT_CONTEXT.new(_game, probe_source, "test")
	_expect(not probe_ctx.condition("cast_this_turn:Brynhildr"), "before the cast, cast_this_turn:Brynhildr is false")
	_game.call("record_action", "Casted Brynhildr", [], 1)
	_expect(probe_ctx.condition("cast_this_turn:Brynhildr"), "with the cast in the ledger, it is true")
	_expect(probe_ctx.condition("controls:Squall"), "and controls:Squall reads through the same context")

	# --- Sazh end to end: 4000 instead of 2000 ----------------------------------------------------------
	var field = _game.get("field")
	var target: Card = _game.call("create_card", 41, "opponent")
	_game.add_child(target)
	field.play_card(target, true, false, false)
	target.set_base_power(10000)
	target.accumulated_damage = 0

	# Sazh's real code effect, not a legacy instruction handler.
	var sazh_source: Card = _game.call("create_card", 13, "player")
	var sazh_code = load("res://assets/effects/card_13.gd").new()
	var sazh_ctx = EFFECT_CONTEXT.new(_game, sazh_source, "test")
	sazh_ctx.targets = [target]

	# Brynhildr HAS been cast in this turn (recorded above), so the guarded 4000 must apply.
	await sazh_code._sazh(sazh_ctx)
	print("[Condition] Sazh with Brynhildr cast: %d damage" % target.accumulated_damage)
	_expect(target.accumulated_damage == 4000, "Sazh deals 4000, not 4000+2000")

	# Next turn: the cast is no longer "this turn", so the other branch applies.
	var turn: int = int(_game.get("turn_number"))
	_game.set("turn_number", turn + 1)
	target.accumulated_damage = 0
	await sazh_code._sazh(sazh_ctx)
	print("[Condition] Sazh next turn: %d damage" % target.accumulated_damage)
	_expect(target.accumulated_damage == 2000, "and 2000 once the cast is no longer this turn")

	# --- untap_all_matching (Hope's Alexander branch) ----------------------------------------------------
	for backup in field.get_back_cards_for("player"):
		backup.tap()
	var tapped_before: int = 0
	for backup in field.get_back_cards_for("player"):
		if backup.tapped:
			tapped_before += 1
	var hope_ctx = EFFECT_CONTEXT.new(_game, probe_source, "test")
	hope_ctx.untap_all_matching(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.YOUR))
	var still_tapped: int = 0
	for backup in field.get_back_cards_for("player"):
		if backup.tapped:
			still_tapped += 1
	_expect(tapped_before > 0 and still_tapped == 0,
		"untap_all_matching untaps every match (%d tapped -> %d)" % [tapped_before, still_tapped])

	# --- the data ---------------------------------------------------------------------------------------
	var squall_cp: Array = load("res://assets/effects/card_42.gd").new().conditional_powers()
	_expect(squall_cp.size() == 1 and int(squall_cp[0].get("value", 0)) == 3000,
		"card 42's conditional is code-owned")
	_expect(load("res://assets/effects/card_43.gd").new().has_method("when_attack"),
		"Snow's attack trigger is code-owned")
	_expect(load("res://assets/effects/card_82.gd").new().has_method("when_enter_field"),
		"Hope's conditional ETB is code-owned")
	var sazh_effect = load("res://assets/effects/card_13.gd").new()
	var sazh_specs: Array = sazh_effect.activated_abilities()
	_expect(sazh_specs.size() == 1 and sazh_specs[0].run.is_valid(), "Sazh's conditional damage is code-owned")

	print("[Condition] %d checks | failures: %d" % [_checks, _fails])
	print("[Condition] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
