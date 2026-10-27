extends Node
## TERRA 47 probe — data-only card:
##   ETB: choose up to 2 DULL Forwards the opponent controls, 4000 damage each
##   《Ice》: choose 1 dull Forward, 1000 damage
##
## The point of this probe is that the criteria do the work: `is_tapped` picks the legal set, `count` allows "up to 2",
## and `ctx.damage` applies to all of them at once.

const GAME_SCENE := preload("res://game.tscn")

const TERRA := 47
const SQUALL := 41          # dulled: legal
const SNOW := 43            # active: NOT legal
const KNIGHT_55 := 55       # dulled: legal
const ICE_MANA := 31

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Terra47] ok   %s" % what)
	else:
		_fails += 1
		print("[Terra47] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": TERRA}, {"id": ICE_MANA}],
		"opponent_field": [
			{"id": SQUALL, "tapped": true},
			{"id": SNOW, "tapped": false},
			{"id": KNIGHT_55, "tapped": true},
		],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var terra: Card = _card(TERRA)
	var squall: Card = _card(SQUALL)
	var snow: Card = _card(SNOW)
	var knight: Card = _card(KNIGHT_55)

	var terra_effect = load("res://assets/effects/card_47.gd").new()
	_expect(terra_effect.has_method("when_enter_field"), "the ETB is code-owned")

	# --- the ETB, end to end ------------------------------------------------------------------------------
	_field.execute_card_effect(terra, "when_enter_field")
	await get_tree().process_frame
	_game.stack.resolve_top_effect()
	for _i in range(60):
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
			break
		await get_tree().process_frame
	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"the ETB opens a targeting session")
	_expect(squall.is_valid_target, "a dull Forward is a legal target")
	_expect(not snow.is_valid_target, "an active Forward is not")
	_field.set_target_card(squall)
	_field.set_target_card(knight)
	await get_tree().process_frame
	_game.get("assistant").call("on_target_complete")
	await get_tree().process_frame
	var stack = _game.get("stack")
	await stack.resolve_top_effect()
	await get_tree().process_frame
	print("[Terra47] after ETB: Squall %d, Snow %d, Dark Knight %d" % [
		squall.accumulated_damage, snow.accumulated_damage, knight.accumulated_damage])
	_expect(squall.accumulated_damage == 4000, "the first dull Forward takes 4000")
	_expect(knight.accumulated_damage == 4000, "the second dull Forward takes 4000")
	_expect(snow.accumulated_damage == 0, "the active Forward takes nothing")
	_expect(not snow.is_on_field() or snow.accumulated_damage == 0, "and is untouched")

	# --- the code ability ---------------------------------------------------------------------------------
	var skills: Array = terra.activation_skills()
	_expect(skills.size() == 1, "Terra has her one code ability")
	var spec = terra.activation_ability_spec(0)
	_expect(spec != null, "the ability is an AbilitySpec")
	if spec != null:
		_expect(int(spec.cost.get("氷", 0)) == 1, "it costs one ice")
		_expect(not spec.tap, "and does not dull her")
		_expect(spec.targets != null and bool(spec.targets.to_legacy().get("is_tapped", false)),
			"it targets a dull Forward")
		_expect(spec.run.is_valid(), "with a callable damage handler")

	print("[Terra47] %d checks | failures: %d" % [_checks, _fails])
	print("[Terra47] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
