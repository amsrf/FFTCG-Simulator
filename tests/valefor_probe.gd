extends Node
## VALEFOR probe — can the AI actually cast "return all Forwards to their owners' hands", and does it work?
##
## Two separate questions, both checked:
##   1. AFFORDABILITY. The AI pays only from untapped Backups, so a 5-cost wind Summon needs five wind sources on
##      its board. Without them the card sits in hand forever and looks broken rather than unaffordable.
##   2. THE EFFECT. Every Forward — both sides — ends up in its owner's hand, as a real hand card.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Valefor] ok   %s" % what)
	else:
		_fails += 1
		print("[Valefor] FAIL %s" % what)


func _forwards(side: String) -> Array:
	var field = _game.get("field")
	var out: Array = []
	for c in field.get_front_cards_for(side):
		out.append(c)
	return out


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("ai")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = _game.get("field")
	var stack = _game.get("stack")
	var ai_hand = _game.get("opponent_hand")
	var player_hand = _game.get("hand")

	var valefor: Card = null
	for c in ai_hand.cards:
		if c.id == 62:
			valefor = c
	_expect(valefor != null, "Valefor is in the AI's hand")

	var wind: int = 0
	for b in field.get_back_cards_for("opponent"):
		if not b.tapped and "風" in (b.element if b.element is Array else [b.element]):
			wind += 1
	_expect(wind >= 5, "the AI has at least five untapped wind Backups (%d)" % wind)

	var player_before: int = player_hand.cards.size()
	var mine: int = _forwards("player").size()
	var theirs: int = _forwards("opponent").size()
	print("[Valefor] before: player %d Forwards / %d hand · AI %d Forwards" % [mine, player_before, theirs])

	var played: bool = await _game.play_card_for(2, valefor)
	_expect(played, "the AI paid for and played Valefor")

	# The Summon is a stack object now; resolve it.
	await stack.resolve_top_effect()
	# POLL IN WALL CLOCK, not frames. Each card returned awaits Hand.return_card, which is ~0.6 s of TWEEN time —
	# and headless frames run far faster than real time, so counting frames samples the animation mid-flight and
	# reports "only one card moved" while the rest are still in transit.
	var waited: float = 0.0
	while waited < 8.0 and (not _forwards("player").is_empty() or not _forwards("opponent").is_empty()):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	print("[Valefor] settled after %.1f s of animation time" % waited)

	_expect(_forwards("player").is_empty(),
		"every player Forward left the field (%d left)" % _forwards("player").size())
	_expect(_forwards("opponent").is_empty(),
		"and every AI Forward too — Valefor returns ALL Forwards (%d left)" % _forwards("opponent").size())
	_expect(player_hand.cards.size() == player_before + mine,
		"the player's Forwards are in hand (%d -> %d, expected +%d)" % [
			player_before, player_hand.cards.size(), mine])
	var in_hand_ok: bool = true
	for c in player_hand.cards:
		if c.current_zone != Card.Zone.HAND:
			in_hand_ok = false
	_expect(in_hand_ok, "and every card in hand reports the HAND zone")

	print("[Valefor] %d checks | failures: %d" % [_checks, _fails])
	print("[Valefor] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
