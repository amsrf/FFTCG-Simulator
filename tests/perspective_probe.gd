extends Node
## ONLINE PERSPECTIVE: the same match, seen from either seat, must play out identically.
##
## Each machine in an online match runs it as "player" = itself. This plays one seeded AI-vs-AI match twice: as seat 1
## (the normal config) and as seat 2 (the mirrored config: every player_/opponent_ key swapped, local_seat = 2). Both
## final boards are translated to SEATS and compared — names, uids, damage, tapped state, hands, piles, whose turn.
## A difference means some rule or ordering depends on which side is "player", which would desync two machines.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const PRESENTATION := preload("res://scripts/core/presentation.gd")
## Defaults; override from the command line to widen coverage, e.g.
##   godot --headless res://tests/perspective_probe.tscn -- --preset=standard --turns=5 --seed=12345
## "standard" builds seeded shuffled decks, so different seeds are genuinely different games ("ai" has fixed decks).
var SEED := 424242
var TURNS := 3
var PRESET := "ai"
const TIME_LIMIT := 120.0

func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var a: String = str(arg)
		if a.begins_with("--seed="):
			SEED = int(a.get_slice("=", 1))
		elif a.begins_with("--turns="):
			TURNS = int(a.get_slice("=", 1))
		elif a.begins_with("--preset="):
			PRESET = a.get_slice("=", 1)

func _base() -> Dictionary:
	var cfg: Dictionary = MatchSetup.build_config(PRESET, {"player_type": "ai", "opponent_type": "ai", "seed": SEED, "starting_player": 1})
	if PRESET == "standard":
		# Rebuild the standard decks from SEED (the preset picks its own random seed), so a failure replays exactly.
		var p_deck: Array = MatchSetup._shuffled(range(1, 51), SEED)
		var o_deck: Array = MatchSetup._shuffled(range(51, 101), SEED + 1)
		cfg["player_hand"] = p_deck.slice(0, 5)
		cfg["player_deck"] = p_deck.slice(5)
		cfg["opponent_hand"] = o_deck.slice(0, 5)
		cfg["opponent_deck"] = o_deck.slice(5)
	elif PRESET == "ai" and SEED != 424242:
		# The practice board has fixed decks; shuffle them by SEED so each seed is a different game the AIs still play.
		cfg["player_deck"] = MatchSetup._shuffled(cfg.get("player_deck", []), SEED)
		cfg["opponent_deck"] = MatchSetup._shuffled(cfg.get("opponent_deck", []), SEED + 1)
	return cfg

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
	var snap: Dictionary = game.snapshot_by_seat()
	snap["_turn_hashes"] = game.turn_hashes.duplicate()
	print("[Perspective] %s: turn %d after %.1fs" % [label, game.turn_number, (Time.get_ticks_msec() - start) / 1000.0])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return snap

func _ready() -> void:
	_read_args()
	print("[Perspective] preset=%s seed=%d turns=%d" % [PRESET, SEED, TURNS])
	PRESENTATION.fast_mode = true
	var base := _base()
	var as_seat_1: Dictionary = await _play(base, "as seat 1")
	var as_seat_2: Dictionary = await _play(_mirrored(base), "as seat 2")
	PRESENTATION.fast_mode = false
	# 1. THE DESYNC CHECK ITSELF: the hash each machine would send at every turn boundary must match.
	var h1: Dictionary = as_seat_1["_turn_hashes"]
	var h2: Dictionary = as_seat_2["_turn_hashes"]
	var diffs := 0
	for turn in h1:
		var same: bool = str(h1[turn]) == str(h2.get(turn, ""))
		print("[Perspective] turn %d hash  seat1-view %s  seat2-view %s  %s" % [turn, h1[turn], h2.get(turn, "-"), "ok" if same else "MISMATCH"])
		if not same:
			diffs += 1
	if h1.size() != h2.size() or h1.is_empty():
		diffs += 1
		print("[Perspective] hashes recorded: %d vs %d" % [h1.size(), h2.size()])
	# 2. The final boards, field by field (what a desync report would print).
	as_seat_1.erase("_turn_hashes")
	as_seat_2.erase("_turn_hashes")
	var report: Array = GAME_SCENE.instantiate().get_script().diff_snapshots(as_seat_1, as_seat_2)
	for line in report:
		print("[Perspective] DIFF " + line)
	diffs += report.size()
	print("[Perspective] %d turn hashes and %d final fields compared" % [h1.size(), as_seat_1.size()])
	print("[Perspective] RESULT: %s" % ("all checks passed" if diffs == 0 else "%d FAILED" % diffs))
	get_tree().quit()
