extends Node
## Online lockstep: an OPPONENT's ability, replayed from a recorded "activate" through RemoteAgent. Covers what the
## scripted human in lockstep_probe cannot reach on its board: a mana payment, a sacrifice-self cost and a target
## (Black Mage 10), and an S cost answered by the agent from the opponent's own hand (Vincent 94).

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const REMOTE_AGENT := preload("res://scripts/agents/remote_agent.gd")
const CODEC := preload("res://scripts/agents/lockstep_codec.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[AbilityReplay] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_game.get("field").play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.untap()
	return card

func _replay(remote, card: Card, skill: int, nested: Array) -> void:
	remote._replay = CODEC.encode(nested)
	_game.set("priority_holder", 2)
	await remote._replay_activation(card, skill)

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var stack = _game.get("stack")
	var remote = REMOTE_AGENT.new()
	remote.bind(_game)
	_game.set("opponent_agent", remote)

	# Black Mage: 《火》《Dull》, put Black Mage into the Break Zone: 4000 damage to a Forward.
	var mage: Card = _make(10, "opponent")
	var ranger: Card = _make(8, "opponent")
	var victim: Card = _make(41, "player")
	await _replay(remote, mage, 0, [
		{"kind": "pay_cost", "result": {"paid": true, "backups": [[ranger, "火"]], "hand": []}},
		{"kind": "choose_target", "result": {"picks": [victim], "cancel": false}},
	])
	_expect(not remote.diverged and remote._replay.is_empty(), "every recorded decision was asked for, in order")
	_expect(stack.stack_length() == 1, "the ability is on the stack")
	_expect(ranger.tapped, "the recorded Backup paid the mana")
	_expect(not mage.is_on_field(), "the sacrifice-self cost was paid at commit")
	if stack.stack_length() > 0:
		await stack.resolve_top_effect()
	_expect(victim.accumulated_damage == 4000, "the recorded target took 4000")

	# A FRESH AGENT. The commit above was an action, so the match's priority loop moved on to the opponent and is now
	# waiting on the first agent's inbox for a window this probe never sends.
	for _i in range(5):
		await get_tree().process_frame
	remote = REMOTE_AGENT.new()
	remote.bind(_game)
	_game.set("opponent_agent", remote)
	# Vincent: 《S》《Dull》: 6000 damage to a Forward. The S card comes from the OPPONENT's hand, through the agent.
	var vincent: Card = _make(94, "opponent")
	var dup: Card = _game.call("create_card", 94, "opponent")
	_game.add_child(dup)
	var opp_hand = _game.call("hand_for", 2)
	opp_hand.add_card(dup)
	var local_hand = _game.call("hand_for", 1)
	var local_before: int = local_hand.cards.size()
	var victim2: Card = _make(43, "player")
	await _replay(remote, vincent, 0, [
		{"kind": "choose_discard", "result": dup},
		{"kind": "choose_target", "result": {"picks": [victim2], "cancel": false}},
	])
	_expect(not remote.diverged and remote._replay.is_empty(), "the S card and the target were both asked for")
	_expect(vincent.tapped and stack.stack_length() == 1, "Vincent tapped and his ability is on the stack")
	_expect(not opp_hand.cards.has(dup), "the S cost left the opponent's hand")
	_expect(local_hand.cards.size() == local_before, "the local hand was not touched")
	if stack.stack_length() > 0:
		await stack.resolve_top_effect()
	_expect(victim2.accumulated_damage == 6000 or not victim2.is_on_field(), "the recorded target took 6000")

	print("[AbilityReplay] %d checks | failures: %d" % [_checks, _fails])
	print("[AbilityReplay] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
