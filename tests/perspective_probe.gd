extends Node
## ONLINE PERSPECTIVE: the same match, seen from either seat, must play out identically.
##
## Each machine in an online match runs it as "player" = itself. This plays one seeded AI-vs-AI match twice: as seat 1
## (the normal config) and as seat 2 (the mirrored config: every player_/opponent_ key swapped, local_seat = 2). Both
## final boards are translated to SEATS and compared — names, uids, damage, tapped state, hands, piles, whose turn.
## A difference means some rule or ordering depends on which side is "player", which would desync two machines.

const GAME_SCENE := preload("res://game.tscn")
const PRESENTATION := preload("res://scripts/presentation.gd")
const SEED := 424242
const TURNS := 3
const TIME_LIMIT := 120.0

func _base() -> Dictionary:
	return MatchSetup.build_config("ai", {"player_type": "ai", "opponent_type": "ai", "seed": SEED, "starting_player": 1})

## Swap every player_/opponent_ key and flip who starts: the same match, seen from the other chair.
func _mirrored(cfg: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in cfg:
		var k: String = str(key)
		if k.begins_with("player_"):
			out["opponent_" + k.substr(7)] = cfg[key]
		elif k.begins_with("opponent_"):
			out["player_" + k.substr(9)] = cfg[key]
		else:
			out[key] = cfg[key]
	out["starting_player"] = 3 - int(cfg.get("starting_player", 1))
	out["local_seat"] = 2
	return out

func _cards(cards: Array) -> Array:
	return cards.map(func(c): return "%s#%d|dmg=%d|tap=%s" % [c.card_name, c.uid, c.accumulated_damage, c.tapped] if is_instance_valid(c) else "<freed>")

func _by_seat(game: Node) -> Dictionary:
	var field = game.get("field")
	var ls: int = game.local_seat
	var d := {
		"turn": game.turn_number,
		"turn_seat": ls if game.turn_owner == 1 else 3 - ls,
		"match_over": game.match_over,
	}
	for seat in [1, 2]:
		var controller: String = game.controller_of_seat(seat)
		var mine: bool = controller == Card.PLAYER
		var side = game.side_for(1 if mine else 2)
		d["s%d.front" % seat] = _cards(field.front_cards if mine else field.opponent_front_cards)
		d["s%d.back" % seat] = _cards(field.back_cards if mine else field.opponent_back_cards)
		d["s%d.hand" % seat] = side.hand.cards.map(func(c): return "%s#%d" % [c.card_name, c.uid])
		d["s%d.deck" % seat] = side.deck.deck_cards.size()
		d["s%d.damage" % seat] = side.damage_count()
		d["s%d.break_zone" % seat] = side.graveyard.graveyard_cards.map(func(c): return "%s#%d" % [c.card_name, c.uid])
	return d

func _play(cfg: Dictionary, label: String) -> Dictionary:
	MatchSetup.config = cfg
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	var start := Time.get_ticks_msec()
	while not game.match_over and game.turn_number <= TURNS:
		await get_tree().create_timer(0.1).timeout
		if (Time.get_ticks_msec() - start) / 1000.0 > TIME_LIMIT:
			print("[Perspective] %s hit the time limit at turn %d" % [label, game.turn_number])
			break
	var snap := _by_seat(game)
	print("[Perspective] %s: turn %d after %.1fs" % [label, game.turn_number, (Time.get_ticks_msec() - start) / 1000.0])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return snap

func _ready() -> void:
	PRESENTATION.fast_mode = true
	var base := _base()
	var as_seat_1: Dictionary = await _play(base, "as seat 1")
	var as_seat_2: Dictionary = await _play(_mirrored(base), "as seat 2")
	PRESENTATION.fast_mode = false
	var diffs := 0
	for key in as_seat_1:
		if str(as_seat_1[key]) != str(as_seat_2.get(key)):
			diffs += 1
			print("[Perspective] DIFF %s\n    as seat 1: %s\n    as seat 2: %s" % [key, as_seat_1[key], as_seat_2.get(key)])
	print("[Perspective] %d field(s) compared at turn %d" % [as_seat_1.size(), as_seat_1["turn"]])
	for key in as_seat_2:
		print("[Perspective]   %s = %s" % [key, as_seat_2[key]])
	print("[Perspective] RESULT: %s" % ("all checks passed" if diffs == 0 else "%d FAILED" % diffs))
	get_tree().quit()
