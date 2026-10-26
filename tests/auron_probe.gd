extends Node
## 1-001H Auron: when he deals player damage, may play a Fire Backup from hand dull.

const GAME_SCENE := preload("res://game.tscn")
const TEST_GROUNDS := preload("res://scripts/test_grounds.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node
var _field
var _stack


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Auron] ok   ", what)
	else:
		_fails += 1
		print("[Auron] FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	MatchSetup.config = TEST_GROUNDS.config("clean")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	_game.player_agent = MockAgent.new()
	_game.player_agent.bind(_game)
	_game.opponent_agent = MockAgent.new()
	_game.opponent_agent.bind(_game)
	_field = _game.field
	_stack = _game.stack

	var auron: Card = _game.create_card(1, "player")
	_game.add_child(auron)
	_field.play_card(auron, false, false)
	var backup: Card = _game.create_card(17, "player")  # Dajh, a Fire Backup
	_game.add_child(backup)
	_game.hand.add_card(backup)
	var before_hand: int = _game.hand.cards.size()

	_field.set_attacker(auron)
	_game.turn_owner = 1
	_game.cause_damage()
	await get_tree().process_frame
	_expect(_stack.stack_length() == 1, "Auron's damage trigger goes on the stack")
	if _stack.stack_length() > 0:
		await _stack.resolve_top_effect()
	await get_tree().process_frame

	print("[Auron] hand %d -> %d, backup field=%s tapped=%s" % [
		before_hand, _game.hand.cards.size(), backup.is_on_field(), backup.tapped])
	_expect(backup.is_on_field(), "Auron plays the Fire Backup from hand")
	_expect(backup.tapped, "and it enters the field dull")
	_expect(_game.hand.cards.size() == before_hand - 1, "and it leaves the hand")

	print("[Auron] %d checks | failures: %d" % [_checks, _fails])
	print("[Auron] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
