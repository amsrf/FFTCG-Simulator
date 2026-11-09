extends Node
## THE RULES MUST NOT DEPEND ON ANIMATION TIMING.
##
## Plays the same seeded AI-vs-AI match twice — once with PRESENTATION.fast_mode (no animation waits) and once in
## normal mode — and compares the board after a few turns. Any difference means some rule reads animation timing,
## which a server running the rules headless (online play) could not reproduce. The diff names what differs.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const PRESENTATION := preload("res://scripts/core/presentation.gd")
const SEED := 424242
## Turns to play. Few enough that normal mode (real-time animations) stays well under a minute or two.
const TURNS := 3
const MODE_TIME_LIMIT := 150.0

func _config() -> Dictionary:
	# The "ai" practice board: both sides have mana sources and affordable hands, so the AIs actually play cards
	# and attack. Its decks are fixed lists; the only randomness left is the match RNG, seeded here.
	return MatchSetup.build_config("ai", {"player_type": "ai", "seed": SEED})

func _names(cards: Array) -> Array:
	return cards.map(func(c): return "%s#%d|dmg=%d|tap=%s" % [c.card_name, c.uid, c.accumulated_damage, c.tapped] if is_instance_valid(c) else "<freed>")

func _snapshot(game: Node) -> Dictionary:
	var field = game.get("field")
	var d := {
		"turn": game.turn_number,
		"turn_owner": game.turn_owner,
		"match_over": game.match_over,
		"field.p1.front": _names(field.front_cards), "field.p1.back": _names(field.back_cards),
		"field.p2.front": _names(field.opponent_front_cards), "field.p2.back": _names(field.opponent_back_cards),
	}
	for id in [1, 2]:
		var side = game.side_for(id)
		d["p%d.hand" % id] = side.hand.cards.map(func(c): return "%s#%d" % [c.card_name, c.uid])
		d["p%d.deck" % id] = side.deck.deck_cards.size()
		d["p%d.damage" % id] = side.damage_count()
		d["p%d.break_zone" % id] = side.graveyard.graveyard_cards.size()
	return d

func _play(fast: bool) -> Dictionary:
	PRESENTATION.fast_mode = fast
	MatchSetup.config = _config()
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	var start := Time.get_ticks_msec()
	while not game.match_over and game.turn_number <= TURNS:
		await get_tree().create_timer(0.1).timeout
		if (Time.get_ticks_msec() - start) / 1000.0 > MODE_TIME_LIMIT:
			print("[Determinism] %s mode hit the time limit at turn %d" % ["fast" if fast else "normal", game.turn_number])
			break
	var snap := _snapshot(game)
	print("[Determinism] %s mode: turn %d after %.1fs" % ["fast" if fast else "normal", game.turn_number, (Time.get_ticks_msec() - start) / 1000.0])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return snap

func _ready() -> void:
	var fast: Dictionary = await _play(true)
	var normal: Dictionary = await _play(false)
	PRESENTATION.fast_mode = false
	var diffs := 0
	for key in fast:
		if str(fast[key]) != str(normal.get(key)):
			diffs += 1
			print("[Determinism] DIFF %s\n    fast:   %s\n    normal: %s" % [key, fast[key], normal.get(key)])
	print("[Determinism] reached turn %d; %d field(s) compared" % [fast["turn"], fast.size()])
	for key in fast:
		print("[Determinism]   %s = %s" % [key, fast[key]])
	print("[Determinism] RESULT: %s" % ("all checks passed" if diffs == 0 else "%d FAILED" % diffs))
	get_tree().quit()
