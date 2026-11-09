extends Node
## ONLINE PLAY OVER A REAL SOCKET, as two processes on one machine. With no arguments it HOSTS and launches its own
## joiner (that is how run_all_probes runs it). The two sides can also be started by hand:
##   godot --headless --path . res://tests/net_probe.tscn -- --role=host
##   godot --headless --path . res://tests/net_probe.tscn -- --role=join
## Both seats are the AI. Each machine sends its own seat's decisions and replays the other's, and they compare their
## state hash at every turn boundary. Passing means: connected, agreed on the match, and stayed identical.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const PRESENTATION := preload("res://scripts/core/presentation.gd")
const NET_SESSION := preload("res://scripts/net/net_session.gd")
const TIME_LIMIT := 150.0

var ROLE := "host"
var _spawn_joiner := true
var PORT := 7790
var TURNS := 3
var SEED := 0
var _checks := 0
var _fails := 0
var _peer_done := false

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[Net-%s] %s %s" % [ROLE, "ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a: String = str(arg)
		if a.begins_with("--role="):
			ROLE = a.get_slice("=", 1)
			_spawn_joiner = false
		elif a.begins_with("--port="):
			PORT = int(a.get_slice("=", 1))
		elif a.begins_with("--turns="):
			TURNS = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			SEED = int(a.get_slice("=", 1))
	PRESENTATION.fast_mode = true
	var session: Node = NET_SESSION.new()
	add_child(session)
	session.config_overrides = {"player_type": "ai"}
	session.peer_done.connect(func(): _peer_done = true)
	var ready_cfg := [null]
	session.match_ready.connect(func(cfg: Dictionary): ready_cfg[0] = cfg)
	# THE PRACTICE BOARD, so both AIs have mana and really cast and attack: each seat brings that preset's cards for
	# its side, and the host sends the starting field.
	var board: Dictionary = MatchSetup.build_config("ai")
	var deck: Array = (board["player_hand"] + board["player_deck"]) if ROLE == "host" \
		else (board["opponent_hand"] + board["opponent_deck"])
	if ROLE == "host":
		session.fixed_seed = SEED
		session.start_fields = {"1": board["player_field"], "2": board["opponent_field"]}
	var err: Error = session.host(PORT, deck) if ROLE == "host" else session.join("127.0.0.1", PORT, deck)
	_expect(err == OK, "%s on port %d" % [ROLE, PORT])
	if ROLE == "host" and _spawn_joiner and err == OK:
		var pid: int = OS.create_process(OS.get_executable_path(), ["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "res://tests/net_probe.tscn", "--",
			"--role=join", "--port=%d" % PORT, "--turns=%d" % TURNS])
		_expect(pid > 0, "launched the joining machine (pid %d)" % pid)

	var start := Time.get_ticks_msec()
	while ready_cfg[0] == null and (Time.get_ticks_msec() - start) < 20000:
		await get_tree().create_timer(0.1).timeout
	_expect(ready_cfg[0] != null, "the two machines agreed on a match")
	if ready_cfg[0] == null:
		_finish()
		return

	MatchSetup.config = ready_cfg[0]
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	start = Time.get_ticks_msec()
	while not game.match_over and game.turn_number <= TURNS:
		await get_tree().create_timer(0.1).timeout
		if (Time.get_ticks_msec() - start) / 1000.0 > TIME_LIMIT:
			print("[Net-%s] time limit at turn %d" % [ROLE, game.turn_number])
			break
	session.send_bye()
	var wait_start := Time.get_ticks_msec()
	while not _peer_done and (Time.get_ticks_msec() - wait_start) < 60000:
		await get_tree().create_timer(0.1).timeout
	# The host also lets the joiner it launched print its own result before this process ends.
	await get_tree().create_timer(2.0 if _spawn_joiner else 0.3).timeout

	print("[Net-%s] seat %d, reached turn %d, hashes %s" % [ROLE, session.local_seat, game.turn_number, str(game.turn_hashes)])
	_expect(game.turn_number > TURNS, "played past turn %d (at %d)" % [TURNS, game.turn_number])
	_expect(not game.out_of_sync, "never fell out of sync")
	_expect(session.remote != null and not session.remote.diverged, "every replayed decision was the kind asked for")
	_expect(session.hashes_matched >= TURNS and session.hashes_matched == game.turn_hashes.size(),
		"every turn hash matched the other machine (%d / %d)" % [session.hashes_matched, game.turn_hashes.size()])
	_expect(_peer_done, "the other machine finished too")
	session.close()
	_finish()

func _finish() -> void:
	print("[Net-%s] %d checks | failures: %d" % [ROLE, _checks, _fails])
	print("[Net-%s] RESULT: %s" % [ROLE, "all checks passed" if _fails == 0 else "%d FAILED" % _fails])
	get_tree().quit()
