extends Node
## Lightning 141's must-block marker and the block-declaration gate.

const GAME_SCENE := preload("res://game.tscn")
const TEST_GROUNDS := preload("res://scripts/test_grounds.gd")
const LIGHTNING := 141
const SQUALL := 41
const DARK_KNIGHT := 55
const ONION_KNIGHT := 125

var _checks: int = 0
var _fails: int = 0
var _game: Node
var _field


func _ready() -> void:
	await get_tree().process_frame
	MatchSetup.config = TEST_GROUNDS.config("clean")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	_game.player_agent = MockAgent.new()
	_game.player_agent.bind(_game)
	_game.opponent_agent = AIAgent.new()
	_game.opponent_agent.bind(_game)
	_field = _game.field

	var lightning: Card = _game.create_card(LIGHTNING, "opponent")
	_game.add_child(lightning)
	_field.play_card(lightning, true, false)
	var squall: Card = _game.create_card(SQUALL, "player")
	_game.add_child(squall)
	_field.play_card(squall, false, false)
	var second: Card = _game.create_card(DARK_KNIGHT, "player")
	_game.add_child(second)
	_field.play_card(second, false, false)
	var onion: Card = _game.create_card(ONION_KNIGHT, "opponent")
	_game.add_child(onion)
	_field.play_card(onion, true, false)
	_field.set_attacker(lightning)
	_field.reset_blocker()

	# A marker that names Lightning forces only this card, and only while it can legally block.
	squall.add_status_effect("must_block", 1, {"source_id": lightning.get_instance_id()})
	_expect(_field.forced_blocker_for(lightning) == squall,
		"a must-block marker names Squall as the forced blocker")
	_expect(squall.must_block_against([lightning]), "the marker matches Lightning")
	_expect(not squall.must_block_against([second]), "but not an unrelated attacker")

	GlobalVariables.push_modal(GlobalVariables.Player_Mode.BLOCKING)
	_game._refresh_block_declaration_button()
	_expect(_game.assistant.confirmButton._disabled,
		"the No Block button is disabled while the forced blocker is unselected")

	_field.set_blocker_card(squall)
	_expect(not _game.assistant.confirmButton._disabled,
		"selecting the forced blocker enables the declaration")
	_expect(_field.blocker_card == squall, "and records it as the blocker")

	_field.set_blocker_card(second)
	_expect(_game.assistant.confirmButton._disabled,
		"selecting a different legal blocker is not enough")

	_field.set_blocker_card(second)  # deselect
	_field.set_blocker_card(squall)
	squall.tap()
	_field.reset_blocker()
	_expect(_field.forced_blocker_for(lightning) == null,
		"a tapped forced blocker is not an impossible requirement")
	_game._refresh_block_declaration_button()
	_expect(not _game.assistant.confirmButton._disabled,
		"so the player may pass without blocking")
	squall.untap()
	squall.turn_end()
	_expect(_field.forced_blocker_for(lightning) == null,
		"and the marker expires at end of turn")

	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.BLOCKING)

	# Army of One installs the timed permissions and the attack trigger.
	var effect = load("res://assets/effects/card_141.gd").new()
	var specs: Array = effect.activated_abilities()
	_expect(specs.size() == 1, "Lightning has one Army of One ability")
	if not specs.is_empty():
		_expect(bool(specs[0].s_cost), "it has an S cost")
		_expect(int(specs[0].cost.get("雷", 0)) == 1, "and one Lightning CP")
		_expect(not bool(specs[0].tap), "it does not tap")
		var ctx = lightning.make_effect_context("activated_ability")
		await specs[0].on_resolve(ctx)
		_expect(lightning.status_effects.has("haste"), "Army of One grants Haste")
		_expect(lightning.status_effects.has("first_strike"), "and First Strike")
		_expect(lightning.status_effects.has("army_of_one"), "and its attack trigger")

	# The attack trigger marks the chosen opponent Forward with the source id.
	lightning.add_status_effect("army_of_one", 1)
	await effect.when_attack(lightning.make_effect_context("attack"))
	var marked: Card = squall if squall.status_effects.has("must_block") else second
	_expect(marked.status_effects.has("must_block"),
		"the attack trigger marks a target with must_block")
	_expect(int(marked.status_effects["must_block"].get("source_id", 0)) == lightning.get_instance_id(),
		"and remembers that it must block Lightning specifically")

	# A forced blocker must block the whole party, not just Lightning as a lone attacker.
	_field.reset_attacker()
	_field.set_attacker(onion)
	_field.add_party_member(lightning)
	_expect(_field.party_members().size() == 2, "a Lightning party has two members")
	squall.add_status_effect("must_block", 1, {"source_id": lightning.get_instance_id()})
	_expect(_field.forced_blocker_for(onion) == squall,
		"the marker still forces the blocker when Lightning is a party member")

	lightning.queue_free()
	squall.queue_free()
	second.queue_free()
	onion.queue_free()
	print("[MustBlock] %d checks | failures: %d" % [_checks, _fails])
	print("[MustBlock] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[MustBlock] ok   %s" % what)
	else:
		_fails += 1
		print("[MustBlock] FAIL %s" % what)
