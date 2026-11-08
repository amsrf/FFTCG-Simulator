extends Node
## ONLINE PLAY: one connection to the other player's machine, over Godot's ENet (reliable, ordered packets).
##
## 1. One player HOSTS (listens on a port), the other JOINS by IP.
## 2. HANDSHAKE: the joiner says hello with its deck; the host rolls the seed and who starts, and sends the setup back.
##    Both build the same match from it (MatchSetup.online_config), each seeing itself as "player": the host is
##    seat 1, the joiner seat 2.
## 3. MATCH: this machine's seat is a RecordingAgent whose messages are sent here; the other seat is a RemoteAgent
##    fed from here. At every turn boundary both send their state hash, and a mismatch stops the match.
##
## Every packet is a small JSON object with a "t" (type): hello, setup, act, hash, bye.
## See the project doc "online-lockstep-messages.md" for what an "act" contains.

const RECORDING_AGENT := preload("res://scripts/agents/recording_agent.gd")
const REMOTE_AGENT := preload("res://scripts/agents/remote_agent.gd")
## Bumped whenever the messages change, so two different builds refuse to play instead of desyncing.
const PROTOCOL := 1
const DEFAULT_PORT := 7777

signal status_changed(text: String)
## The handshake is done: start a match from this config (the menu changes scene; a probe instantiates the game).
signal match_ready(config: Dictionary)
## The other machine finished (see send_bye()).
signal peer_done
signal disconnected

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var local_seat: int = 1
var my_deck: Array = []
## Merged into the match config (a probe sets "player_type": "ai").
var config_overrides: Dictionary = {}
## HOST ONLY, for tests: cards each seat starts with on the field, {"1": [{id, tapped}...], "2": [...]}. Sent in the
## setup, so both machines place the same board. A real match starts with an empty field.
var start_fields: Dictionary = {}

var game: Node = null
var remote: Agent = null
var recorder: Agent = null
## Actions that arrived before the RemoteAgent existed.
var _early_acts: Array[String] = []
var _remote_hashes: Dictionary = {}
var hashes_matched: int = 0
var _connected: bool = false
var _closing: bool = false

func status(text: String) -> void:
	print("[Net] " + text)
	status_changed.emit(text)

# --- connecting -------------------------------------------------------------

func host(port: int, deck: Array) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, 1)
	if err != OK:
		status("Could not host on port %d (%s)" % [port, error_string(err)])
		peer = null
		return err
	is_host = true
	local_seat = 1
	my_deck = deck
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	status("Hosting on port %d - waiting for the other player..." % port)
	return OK

func join(address: String, port: int, deck: Array) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		status("Could not connect to %s:%d (%s)" % [address, port, error_string(err)])
		peer = null
		return err
	is_host = false
	local_seat = 2
	my_deck = deck
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	status("Connecting to %s:%d..." % [address, port])
	return OK

func close() -> void:
	_closing = true
	if peer != null:
		peer.close()
	peer = null
	game = null
	remote = null
	recorder = null

func _process(_delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	if peer == null:
		return
	if not is_host and not _connected and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		status("Could not reach the host.")
		close()
		disconnected.emit()
		return
	while peer != null and peer.get_available_packet_count() > 0:
		var text: String = peer.get_packet().get_string_from_utf8()
		_on_packet(text)

func _on_peer_connected(_id: int) -> void:
	_connected = true
	if is_host:
		status("The other player connected.")
	else:
		status("Connected - sending our deck...")
		_send({"t": "hello", "protocol": PROTOCOL, "deck": my_deck})

func _on_peer_disconnected(_id: int) -> void:
	if _closing:
		return
	status("The other player left.")
	if game != null and is_instance_valid(game):
		game.halt_match("OPPONENT LEFT")
	disconnected.emit()

func _send(message: Dictionary) -> void:
	if peer == null:
		return
	peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.put_packet(JSON.stringify(message).to_utf8_buffer())

# --- handshake --------------------------------------------------------------

func _on_packet(text: String) -> void:
	var message = JSON.parse_string(text)
	if not (message is Dictionary):
		push_error("[Net] unreadable packet: %s" % text.left(80))
		return
	match str(message.get("t", "")):
		"hello":
			_on_hello(message)
		"setup":
			_on_setup(message)
		"act":
			_on_act(str(message.get("m", "")))
		"hash":
			_on_remote_hash(int(message.get("turn", -1)), str(message.get("h", "")))
		"bye":
			peer_done.emit()
		"refused":
			status("The host refused: %s" % str(message.get("why", "")))
			close()
			disconnected.emit()

func _ints(value) -> Array:
	var out: Array = []
	if value is Array:
		for v in value:
			out.append(int(v))
	return out

## HOST: the joiner's deck arrived. Roll the match and send it back; both sides start from the same numbers.
func _on_hello(message: Dictionary) -> void:
	if not is_host:
		return
	if int(message.get("protocol", -1)) != PROTOCOL:
		_send({"t": "refused", "why": "different game versions (host %d, you %d)" % [PROTOCOL, int(message.get("protocol", -1))]})
		status("The other player runs a different version - refused.")
		return
	var their_deck: Array = _ints(message.get("deck", []))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var setup := {
		"t": "setup", "protocol": PROTOCOL,
		"seed": rng.randi_range(1, 999999),
		"starting_seat": rng.randi_range(1, 2),
		"decks": {"1": my_deck, "2": their_deck},
		"fields": start_fields,
	}
	_send(setup)
	_start(setup)

## JOINER: the host's setup arrived.
func _on_setup(message: Dictionary) -> void:
	if is_host:
		return
	_start(message)

func _start(setup: Dictionary) -> void:
	var decks: Dictionary = setup.get("decks", {})
	var cfg: Dictionary = MatchSetup.online_config(int(setup.get("seed", 1)), local_seat,
		int(setup.get("starting_seat", 1)), _ints(decks.get("1", [])), _ints(decks.get("2", [])),
		setup.get("fields", {}))
	for key in config_overrides:
		cfg[key] = config_overrides[key]
	cfg["wrap_agent"] = _wrap_agent
	cfg["on_match_started"] = _on_match_started
	status("Match starting - you are seat %d, seat %d goes first." % [local_seat, int(setup.get("starting_seat", 1))])
	match_ready.emit(cfg)

# --- during the match -------------------------------------------------------

## The game's agents, as Game.start_match() creates them: id 1 is always this machine's player.
func _wrap_agent(local_id: int, agent):
	if local_id == 1:
		recorder = RECORDING_AGENT.new(agent)
		recorder.message_sent.connect(func(json: String): _send({"t": "act", "m": json}))
		return recorder
	remote = REMOTE_AGENT.new()
	for json in _early_acts:
		remote.receive(json)
	_early_acts.clear()
	return remote

func _on_match_started(started_game: Node) -> void:
	game = started_game
	_remote_hashes.clear()
	hashes_matched = 0
	game.turn_state_recorded.connect(_on_local_hash)

func _on_act(json: String) -> void:
	if remote == null:
		_early_acts.append(json)
	else:
		remote.receive(json)

func _on_local_hash(turn: int, h: String) -> void:
	_send({"t": "hash", "turn": turn, "h": h})
	_compare(turn)

func _on_remote_hash(turn: int, h: String) -> void:
	_remote_hashes[turn] = h
	_compare(turn)

## Compared only once BOTH hashes for the turn are known: either machine may reach the turn boundary first.
func _compare(turn: int) -> void:
	if game == null or not is_instance_valid(game):
		return
	if not _remote_hashes.has(turn) or not game.turn_hashes.has(turn):
		return
	if game.compare_remote_hash(turn, str(_remote_hashes[turn])):
		hashes_matched += 1
	_remote_hashes.erase(turn)

## This machine is done (a probe after N turns). The other side waits for it before closing, so neither sees the
## other's disconnect as "the opponent left".
func send_bye() -> void:
	_send({"t": "bye"})
