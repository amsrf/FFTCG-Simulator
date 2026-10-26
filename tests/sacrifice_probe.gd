extends Node
## SACRIFICE COST probe — Mystic 96: "Put 1 Backup into the Break Zone: Mystic gains +3000 power until end of turn."
##
## The cost is chosen by the owner through the agent seam, so nothing about it is hard-coded: the probe swaps in a
## MockAgent to answer automatically, and the same call opens a card picker for a human.

const GAME_SCENE := preload("res://game.tscn")

const MYSTIC := 96
const CHEMIST := 31
const RED_MAGE := 3

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Sacrifice] ok   %s" % what)
	else:
		_fails += 1
		print("[Sacrifice] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": MYSTIC}, {"id": CHEMIST}, {"id": RED_MAGE}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var mystic: Card = _card(MYSTIC)
	var skills: Array = mystic.activation_skills()
	_expect(skills.size() == 1, "Mystic has her one ability")
	_expect(skills.size() == 1 and skills[0].has("sacrifice"), "and its cost is a sacrifice")

	# The ability is offered while a Backup can be sacrificed.
	_game.set("priority_holder", 1)
	_expect(_field.can_activate_now(mystic), "the ability is available with Backups on the board")

	# Answer the sacrifice automatically instead of opening the picker.
	var mock = MockAgent.new()
	mock.bind(_game)
	_game.set("player_agent", mock)
	_game.set("_priority_lock", true)   # absorb the request_priority; the probe resolves the stack itself

	var backups_before: int = _field.get_back_cards_for("player").size()
	_field.call("begin_skill_activation", mystic, 0)
	for _i in range(6):
		await get_tree().process_frame
	var backups_after: int = _field.get_back_cards_for("player").size()
	var grave: int = _game.get("player").graveyard.graveyard_cards.size()
	print("[Sacrifice] backups %d -> %d, graveyard %d, stack %d, mystic power %d" % [
		backups_before, backups_after, grave, _game.get("stack").stack_length(), mystic.power])
	_expect(backups_after == backups_before - 1, "exactly one Backup left the board")
	_expect(grave == 1, "and arrived in the Break Zone")
	_expect(_game.get("stack").stack_length() == 1, "the ability is on the stack")
	_expect(not mystic.tapped, "the ability does not dull Mystic")

	await _game.get("stack").resolve_top_effect()
	await get_tree().process_frame
	_expect(mystic.power == 3000 + 3000, "resolving it gives Mystic +3000 (%d)" % mystic.power)

	# With no Backup left, the ability is not offered at all.
	var last: Card = null
	for c in _field.get_back_cards_for("player"):
		last = c
	if last != null:
		_game.call("put_card_into_graveyard", last)
	_game.set("priority_holder", 1)
	_expect(not _field.can_activate_now(mystic), "with no Backup to sacrifice, the ability is closed")

	print("[Sacrifice] %d checks | failures: %d" % [_checks, _fails])
	print("[Sacrifice] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
