extends Node
## ONLINE LOCKSTEP, end to end without a network. Machine A plays seat 1 with its decisions RECORDED (RecordingAgent
## around the AI) into JSON messages. Machine B plays the same match as seat 2, with seat 1 answered ONLY from those
## messages (RemoteAgent). If the protocol carries everything, B's board hash matches A's at every turn boundary.
##
## Run one match after the other rather than side by side: two live games would share the autoloads (player mode,
## the presentation queue), which a real pair of machines does not.
##   godot --headless res://tests/lockstep_probe.tscn -- --seed=2 --turns=4

const GAME_SCENE := preload("res://game.tscn")
const PRESENTATION := preload("res://scripts/presentation.gd")
const RECORDING_AGENT := preload("res://scripts/agents/recording_agent.gd")
const REMOTE_AGENT := preload("res://scripts/agents/remote_agent.gd")
const TIME_LIMIT := 150.0

var SEED := 424242
var TURNS := 3
## --tamper drops one message on the way to machine B: the probe then REQUIRES the divergence to be caught.
var TAMPER := false
var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[Lockstep] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var a: String = str(arg)
		if a.begins_with("--seed="):
			SEED = int(a.get_slice("=", 1))
		elif a.begins_with("--turns="):
			TURNS = int(a.get_slice("=", 1))
		elif a == "--tamper":
			TAMPER = true

func _base() -> Dictionary:
	var cfg: Dictionary = MatchSetup.build_config("ai", {"player_type": "ai", "opponent_type": "ai", "seed": SEED, "starting_player": 1})
	if SEED != 424242:
		cfg["player_deck"] = MatchSetup._shuffled(cfg.get("player_deck", []), SEED)
		cfg["opponent_deck"] = MatchSetup._shuffled(cfg.get("opponent_deck", []), SEED + 1)
	return cfg

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
	var desyncs: Array = []
	game.desync_detected.connect(func(t, a, b): desyncs.append("turn %s: %s vs %s" % [t, a, b]))
	while not game.match_over and game.turn_number <= TURNS:
		await get_tree().create_timer(0.1).timeout
		if (Time.get_ticks_msec() - start) / 1000.0 > TIME_LIMIT:
			print("[Lockstep] %s hit the time limit at turn %d" % [label, game.turn_number])
			break
	var out := {"hashes": game.turn_hashes.duplicate(), "turn": game.turn_number, "desyncs": desyncs,
		"snapshot": game.snapshot_by_seat()}
	print("[Lockstep] %s: turn %d after %.1fs" % [label, game.turn_number, (Time.get_ticks_msec() - start) / 1000.0])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return out

func _ready() -> void:
	_read_args()
	print("[Lockstep] seed=%d turns=%d tamper=%s" % [SEED, TURNS, TAMPER])
	PRESENTATION.fast_mode = true
	var base := _base()

	# MACHINE A: seat 1 is local; its decisions are recorded.
	var recorder := [null]
	var cfg_a := base.duplicate()
	cfg_a["wrap_agent"] = func(local_id: int, agent: Agent) -> Agent:
		if local_id == 1:
			recorder[0] = RECORDING_AGENT.new(agent)
			return recorder[0]
		return agent
	var a: Dictionary = await _play(cfg_a, "machine A (seat 1, recording)")
	var messages: Array = recorder[0].sent if recorder[0] != null else []
	var plays := 0
	for m in messages:
		if m.contains("\"take_priority\"") and m.contains("\"card\""):
			plays += 1
	print("[Lockstep] seat 1 sent %d messages (%d priority windows with a play)" % [messages.size(), plays])
	_expect(messages.size() > 5, "seat 1 sent decisions to replay (%d)" % messages.size())

	if TAMPER and messages.size() > 3:
		messages = messages.duplicate()
		messages.remove_at(2)
	# MACHINE B: seat 2 is local; seat 1 is answered only from A's messages.
	var remote := [null]
	var cfg_b := _mirrored(base)
	cfg_b["wrap_agent"] = func(local_id: int, agent: Agent) -> Agent:
		if local_id == 2:   # on machine B the "opponent" is seat 1
			var r = REMOTE_AGENT.new()
			for m in messages:
				r.receive(m)
			remote[0] = r
			return r
		return agent
	var b: Dictionary = await _play(cfg_b, "machine B (seat 2, seat 1 remote)")
	PRESENTATION.fast_mode = false

	if TAMPER:
		# A missing message must be CAUGHT (a wrong kind of decision, or a board that no longer matches), never absorbed.
		var hashes_differ := false
		for t in a["hashes"]:
			if str(a["hashes"][t]) != str(b["hashes"].get(t, "")):
				hashes_differ = true
		_expect((remote[0] != null and remote[0].diverged) or not b["desyncs"].is_empty() or hashes_differ,
			"a dropped message is detected (diverged=%s, hashes differ=%s)" % [str(remote[0].diverged if remote[0] else null), str(hashes_differ)])
	else:
		_expect(remote[0] != null and not remote[0].diverged, "every replayed decision was the kind the game asked for")
		_expect(b["desyncs"].is_empty(), "no desync reported on machine B %s" % str(b["desyncs"]))
		var h_a: Dictionary = a["hashes"]
		var h_b: Dictionary = b["hashes"]
		var same := 0
		for t in h_a:
			var ok: bool = str(h_a[t]) == str(h_b.get(t, ""))
			print("[Lockstep] turn %d  A %s  B %s  %s" % [t, h_a[t], h_b.get(t, "-"), "ok" if ok else "MISMATCH"])
			if ok:
				same += 1
		_expect(not h_a.is_empty() and same == h_a.size() and h_a.size() == h_b.size(),
			"both machines hash every turn identically (%d / %d)" % [same, h_a.size()])
		if same != h_a.size():
			for line in GAME_SCENE.instantiate().get_script().diff_snapshots(a["snapshot"], b["snapshot"]):
				print("[Lockstep] DIFF " + line)
	print("[Lockstep] %d checks | failures: %d" % [_checks, _fails])
	print("[Lockstep] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
