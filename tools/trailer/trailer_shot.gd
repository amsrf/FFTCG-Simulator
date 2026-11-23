extends Node
## TRAILER SHOTS. Boots the real game on a scripted board, plays a scripted sequence (no clicking), moves a camera
## along keyframes and saves every frame. One shot per run, so each can be re-filmed alone; the edit (Blender's
## sequencer) cuts them together. The outline lives in the trailer memory note / tools/trailer/README.md.
##
## Run WINDOWED (a real renderer) with a fixed frame rate, so every frame is exactly 1/60 s of game time however long
## a PNG takes to write:
##   godot --resolution 1920x1080 --fixed-fps 60 res://tools/trailer/trailer_shot.tscn -- --shot crystals --out-dir <dir>
## Options after "--":
##   --shot <name>     which shot (see SHOTS below); --list prints them
##   --out-dir <dir>   where f_0000.png ... go (created if missing)
##   --every <n>       save every nth frame (default 1; 2 = a quick 30 fps preview)
##   --seconds <s>     override the shot's length
##   --still <s>       save ONE frame at that time instead (fast look at a camera pose)
##
## A shot is {config, seconds, camera: [keys], actions: Callable}. Camera keys are {t, target, elev, width, fov}: the
## board camera's own parametrisation (BoardCameraRig: look at `target` from `elev` degrees, framing `width` metres
## across), eased between keys. HOLD the camera still around a strong card's entry: its camera shake moves the camera
## from where it was when the shake began, so a camera moving under it would snap back.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const FPS := 60.0

## The board camera's default pose (camera_rig.gd).
const BOARD := {"target": Vector3(0.0, 0.35, -0.25), "elev": 67.0, "width": 9.6, "fov": 22.0}

const TRAILER_AGENT := preload("res://tools/trailer/trailer_agent.gd")
const CLASH := preload("res://scripts/vfx/clash_cinematic.gd")
const P := GlobalVariables.Phase

var _game: Node
var _camera: Camera3D
var _keys: Array = []
## Game time of the frame being filmed.
var _t: float = 0.0
## A shot ends here (its `seconds`, or earlier once its script calls _finish_in()).
var _end_at: float = INF
## An event-driven camera move (_move): eases from `from` to `to` over [t0, t0 + dur]; it replaces the keys from t0 on.
var _move_state: Dictionary = {}
## The two scripted seats, by player id.
var seats: Dictionary = {}
## A shot that films the HAND (Alma's draw) keeps it visible; it then needs a camera at the board view.
var _show_hands: bool = false
var _shot_name: String = ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var shot_name := _arg(args, "--shot", "crystals")
	if args.has("--list"):
		print("[Trailer] shots: %s" % ", ".join(_shots().keys()))
		get_tree().quit()
		return
	var shots := _shots()
	if not shots.has(shot_name):
		push_error("[Trailer] unknown shot '%s' (have: %s)" % [shot_name, ", ".join(shots.keys())])
		get_tree().quit(1)
		return
	var shot: Dictionary = shots[shot_name]
	_shot_name = shot_name
	var out_dir := _arg(args, "--out-dir", "user://trailer/%s" % shot_name)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var every := maxi(int(_arg(args, "--every", "1")), 1)
	var seconds := float(_arg(args, "--seconds", str(shot.seconds)))
	var still := float(_arg(args, "--still", "-1"))
	_keys = shot.camera
	_show_hands = bool(shot.get("show_hands", false))
	# --board-camera: film through the game's own board view (diagnosis: is a problem the trailer camera's?).
	if args.has("--board-camera"):
		_keys = [BOARD.merged({"t": 0.0})]

	var config: Dictionary = shot.config
	# Scripted seats: both players are TrailerAgents fed from the shot's "seats" (attacks, blocks, targets, steps).
	var seat_plan: Dictionary = shot.get("seats", {})
	config["wrap_agent"] = func(id: int, _agent) -> Object:
		var agent = TRAILER_AGENT.new()
		var plan: Dictionary = seat_plan.get(id, {})
		agent.steps = plan.get("steps", []).duplicate()
		agent.attacks = plan.get("attacks", []).duplicate()
		agent.blocks = plan.get("blocks", []).duplicate()
		agent.targets = plan.get("targets", []).duplicate()
		seats[id] = agent
		return agent
	MatchSetup.config = config
	_game = GAME_SCENE.instantiate()
	_game.set("return_to_menu_on_end", false)
	add_child(_game)
	# Settle: the match boots, the shaders warm up, the opening layout tweens finish.
	await get_tree().create_timer(1.5).timeout
	_hide_screen_ui()
	# The real mouse must not touch the take: a pointer resting over the window opened card hover previews mid-shot.
	get_viewport().physics_object_picking = false
	# The BOARD camera, made current: a board that starts with damage (the victory shot) can leave a damage camera
	# current after setup, and the moves below would then be filmed by nothing. The game's own damage zoom still
	# switches to its camera and back mid-shot.
	_camera = _game.get_node("Camera3D")
	_camera.make_current()
	_pose(0.0)
	await RenderingServer.frame_post_draw

	# Camera rolls: the seats may act from now on.
	for agent in seats.values():
		agent.held = false
	# The scripted play runs alongside the capture loop, on game time.
	var actions: Callable = shot.actions
	actions.call()
	var frames := int(round(seconds * FPS))
	_end_at = seconds
	var filmed := 0
	for frame in frames:
		var t := float(frame) / FPS
		if t >= _end_at:
			break
		_t = t
		filmed += 1
		_pose(t)
		await RenderingServer.frame_post_draw
		if still >= 0.0:
			if t + 0.5 / FPS >= still:
				_save(out_dir, "still_%s" % shot_name)
				break
			continue
		if frame % every == 0:
			_save(out_dir, "f_%04d" % frame)
	print("[Trailer] %s: %s -> %s" % [shot_name, "still at %.2f s" % still if still >= 0.0 else "%d frames" % filmed, out_dir])
	get_tree().quit()


## The trailer shows the BOARD: the 2D overlays (pass-mode bar, debug text) are hidden. World-space parts of the board
## (crystals, coins, phase dial) stay.
func _hide_screen_ui() -> void:
	for node in _game.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in _game.find_children("*", "Control", true, false):
		var parent: Node = node.get_parent()
		if parent is Node3D or parent == _game or not (parent is Control):
			(node as Control).visible = false
	# The hands float between the board and the BOARD camera; a trailer camera moving in would fly through them. A card
	# leaves its hand node when it is played (parked on the Stack, then the field), so it shows again from there.
	for hand in [_game.get("hand"), _game.get("opponent_hand")]:
		if hand != null:
			hand.visible = _show_hands
	var phase_text := _game.get_node_or_null("PhaseText")
	if phase_text != null:
		phase_text.visible = false


func _save(dir: String, stem: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, stem])


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


# --- camera ---------------------------------------------------------------------------------------------------------

## Place the camera for time `t` from the keys (smoothstep between neighbours; holds before the first / after the last).
func _pose(t: float) -> void:
	if _camera == null:
		return
	_apply_pose(_pose_at(t))


## The camera pose at `t`: an event move if one has started, otherwise the keys.
func _pose_at(t: float) -> Dictionary:
	if not _move_state.is_empty() and t >= float(_move_state.t0):
		var k := clampf((t - float(_move_state.t0)) / maxf(float(_move_state.dur), 0.001), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var a: Dictionary = _move_state.from
		var b: Dictionary = _move_state.to
		return {
			"target": (a.target as Vector3).lerp(b.get("target", a.target), k),
			"elev": lerpf(float(a.elev), float(b.get("elev", a.elev)), k),
			"width": lerpf(float(a.width), float(b.get("width", a.width)), k),
			"fov": lerpf(float(a.fov), float(b.get("fov", a.fov)), k),
		}
	return _key_pose(t)


## Ease the camera from wherever it is now to `to` (any of target / elev / width / fov) over `seconds`.
func _move(to: Dictionary, seconds: float) -> void:
	_move_state = {"from": _pose_at(_t), "to": to, "t0": _t, "dur": seconds}


func _key_pose(t: float) -> Dictionary:
	if _keys.is_empty():
		return BOARD.duplicate()
	var a: Dictionary = _keys[0]
	var b: Dictionary = a
	for i in _keys.size():
		if float(_keys[i].t) <= t:
			a = _keys[i]
			b = _keys[mini(i + 1, _keys.size() - 1)]
	var span := float(b.t) - float(a.t)
	var k := 0.0 if span <= 0.0 else clampf((t - float(a.t)) / span, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return {
		"target": (a.get("target", BOARD.target) as Vector3).lerp(b.get("target", BOARD.target), k),
		"elev": lerpf(float(a.get("elev", BOARD.elev)), float(b.get("elev", BOARD.elev)), k),
		"width": lerpf(float(a.get("width", BOARD.width)), float(b.get("width", BOARD.width)), k),
		"fov": lerpf(float(a.get("fov", BOARD.fov)), float(b.get("fov", BOARD.fov)), k),
	}


func _apply_pose(pose: Dictionary) -> void:
	var target: Vector3 = pose.target
	var elev := float(pose.elev)
	var width := float(pose.width)
	var fov := float(pose.fov)
	var view := get_viewport().get_visible_rect().size
	var aspect := view.x / maxf(view.y, 1.0)
	var distance := width / (2.0 * aspect * tan(deg_to_rad(fov) * 0.5))
	var e := deg_to_rad(elev)
	_camera.fov = fov
	_camera.global_position = target + Vector3(0.0, distance * sin(e), -distance * cos(e))
	_camera.look_at(target, Vector3.UP)


# --- scripted play --------------------------------------------------------------------------------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Play the first card with `id` from `player_id`'s hand, paid for free (the trailer is not about the payment).
func _play(player_id: int, id: int) -> void:
	var hand = _game.hand_for(player_id)
	var card: Card = null
	for c in hand.cards:
		if int(c.id) == id:
			card = c
			break
	if card == null:
		push_error("[Trailer] player %d has no card %d in hand" % [player_id, id])
		return
	if not hand.charge(card):
		push_error("[Trailer] player %d could not play %d" % [player_id, id])
		return
	await get_tree().process_frame
	await _wait(0.12)
	_game.get("assistant").on_charge_complete()


# --- the shots ------------------------------------------------------------------------------------------------------

## Both decks start at 101+ so board cards never collide; no shuffle, seed 0: a shot is identical every run.
func _base(overrides: Dictionary) -> Dictionary:
	var cfg := {
		"player_hand": [],
		"opponent_hand": [],
		"player_field": [],
		"opponent_field": [],
		"player_deck": range(101, 141),
		"opponent_deck": range(141, 181),
		"opponent_type": "mock",
		"seed": 0,
	}
	for key in overrides:
		cfg[key] = overrides[key]
	return MatchSetup.build_config("clean", cfg)


func _shots() -> Dictionary:
	var all := _first_shots()
	all.merge(_play_shots())
	return all


func _first_shots() -> Dictionary:
	return {
		# 1. "Destroy the 7 crystals of your enemy": along the opponent's crown, then up to the whole row.
		"crystals": {
			"config": _base({}),
			"seconds": 8.0,
			"camera": [
				{"t": 0.0, "target": Vector3(0.95, 0.25, 2.25), "elev": 38.0, "width": 1.5},
				{"t": 5.0, "target": Vector3(-0.95, 0.25, 2.25), "elev": 42.0, "width": 1.7},
				{"t": 8.0, "target": Vector3(0.0, 0.25, 2.0), "elev": 58.0, "width": 3.6},
			],
			"actions": _act_none,
		},
		# 2a. "But first you will need backup": my three Backups land on my back row.
		"backups_mine": {
			"config": _base({"player_hand": [10, 3, 30], "starting_player": 1}),
			"seconds": 5.0,
			"camera": [
				{"t": 0.0, "target": Vector3(0.0, 0.1, -1.05), "elev": 58.0, "width": 4.4},
				{"t": 5.0, "target": Vector3(0.0, 0.1, -1.0), "elev": 62.0, "width": 3.7},
			],
			"actions": _act_backups_mine,
		},
		# 2b. ...and theirs on theirs (their turn: a Character is played only by the turn player).
		"backups_theirs": {
			"config": _base({"opponent_hand": [161, 177, 65], "starting_player": 2}),
			"seconds": 5.0,
			"camera": [
				{"t": 0.0, "target": Vector3(0.0, 0.1, 1.75), "elev": 58.0, "width": 4.4},
				{"t": 5.0, "target": Vector3(0.0, 0.1, 1.7), "elev": 62.0, "width": 3.7},
			],
			"actions": _act_backups_theirs,
		},
		# 3. "But of course we need swords too": two Forwards, then a strong one throws the field.
		# 3. "But of course we need swords too": Red XIII and Tifa, then Orlandeau (cost 5: the strong entry), his
		# 《Lightning》《Lightning》 Haste (the clock), and his attack: 3000 to EVERY opponent Forward (the lightning row;
		# Snow and Zidane, 3000 each, break; Lightning 9000 takes it).
		"forwards": {
			"config": _base({"starting_player": 1, "player_hand": [29, 189, 126],
				"player_field": _f([10, 3, 30], true),
				"opponent_field": _f([43, 141, 71, 161, 177, 65])}),
			"seconds": 26.0,
			"camera": [
				{"t": 0.0, "target": Vector3(0.2, 0.15, -0.35), "elev": 55.0, "width": 4.8},
				{"t": 2.4, "target": Vector3(0.4, 0.2, 0.1), "elev": 60.0, "width": 6.8},
			],
			"seats": {
				1: {"attacks": [[126]], "steps": [
					{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _cast(29)},
					{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _cast(189)},
					{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _cast(126)},
					{"when": _main_free_with(P.FIRST_MAIN_PHASE, 1, 126), "do": _activate(126)},
				]},
				2: {"blocks": [0]},
			},
			"actions": _act_forwards,
		},
	}


func _act_none() -> void:
	pass


func _act_backups_mine() -> void:
	await _wait(0.3)
	for id in [10, 3, 30]:
		await _play(1, id)
		await _wait(1.0)


func _act_backups_theirs() -> void:
	await _wait(0.3)
	for id in [161, 177, 65]:
		await _play(2, id)
		await _wait(1.0)


## Done once Orlandeau's attack has broken Snow and Zidane (his lightning has struck the row).
func _act_forwards() -> void:
	# He attacks: in on the opponent's Forward row, where his lightning lands.
	await _on_phase(P.ATTACK_DECLARATION_STEP, 40.0)
	_move({"target": Vector3(0.4, 0.2, 0.75), "elev": 62.0, "width": 4.8}, 0.9)
	await _until(func() -> bool: return seats[2].field_card(2, 43) == null and seats[2].field_card(2, 71) == null, 40.0)
	_finish_in(1.8)


# --- scripted-match helpers -----------------------------------------------------------------------------------------

## End the shot `seconds` from now (game time).
func _finish_in(seconds: float) -> void:
	_end_at = minf(_end_at, _t + seconds)


func _phase_is(phase: int) -> Callable:
	return func(game) -> bool: return game.phase == phase


## In `phase`, with nothing on the stack.
func _main_free(phase: int, turn_owner: int) -> Callable:
	return func(game) -> bool:
		return game.phase == phase and game.turn_owner == turn_owner and game.stack.stack_length() == 0


## In `phase` with an empty stack, and card `id` of `turn_owner` on the field (e.g. to activate what was just played).
func _main_free_with(phase: int, turn_owner: int, id: int) -> Callable:
	var free := _main_free(phase, turn_owner)
	return func(game) -> bool:
		return free.call(game) and seats[turn_owner].field_card(turn_owner, id) != null


func _top_is(id: int) -> Callable:
	return func(game) -> bool:
		return game.stack.stack_length() > 0 and int(game.stack.cards[game.stack.cards.size() - 1].id) == id


func _blocking(player_id: int, id: int) -> Callable:
	return func(game) -> bool:
		var b: Card = game.field.blocker_card
		return b != null and int(b.id) == id and b.controller == game.controller_for(player_id) and not b.tapped


## A step that casts / plays card `id` from hand (paid for free by the agent).
func _cast(id: int) -> Callable:
	return func(agent, player_id: int) -> bool:
		var card: Card = agent.hand_card(player_id, id)
		if card == null:
			push_error("[Trailer] P%d has no %d in hand" % [player_id, id])
			return false
		return await _game.play_card_for(player_id, card)


## A step that activates the first ability of field card `id`.
func _activate(id: int) -> Callable:
	return func(agent, player_id: int) -> bool:
		var card: Card = agent.field_card(player_id, id)
		if card == null:
			push_error("[Trailer] P%d has no %d on the field" % [player_id, id])
			return false
		await _game.field.begin_skill_activation(card, 0, true)
		return true


## Wait until `cond` holds (checked every frame), at most `limit` seconds.
func _until(cond: Callable, limit: float = 20.0) -> void:
	var start := _t
	while not cond.call() and _t - start < limit:
		await get_tree().process_frame


func _on_phase(phase: int, limit: float = 20.0) -> void:
	await _until(func() -> bool: return _game.phase == phase, limit)


func _stack_settled() -> bool:
	return _game.stack.stack_length() == 0 and _game.stack.get("resolving_card") == null


## Forwards placed on the board at setup; tapped = false unless given.
func _f(ids: Array, tapped: bool = false) -> Array:
	return ids.map(func(id) -> Dictionary: return {"id": id, "tapped": tapped})


# --- the play shots (scripted matches) ------------------------------------------------------------------------------

const COMBAT_VIEW := {"target": Vector3(0.2, 0.2, 0.3), "elev": 62.0, "width": 6.4}
## For scenes with targeting arrows: close to the board view, where the arrows' arcs are drawn right.
const ARROW_VIEW := {"target": Vector3(0.15, 0.3, 0.0), "elev": 66.0, "width": 8.4}
## On a clash (no arrows), centred between the two Forward rows. Wide enough for the wind-up: at 4.6 m it pulled both
## cards half out of frame.
const CLASH_VIEW := {"target": Vector3(0.1, 0.2, 0.3), "elev": 63.0, "width": 6.6}


func _play_shots() -> Dictionary:
	return {
		# 4. "Defend yourself...": their Knight (7000) attacks, Gordon (4000) blocks and uses his ability (next damage = 0):
		# Gordon takes 0, the Knight 4000, both live. Attackers/blockers here have NO combat abilities (Squall's block
		# trigger put a stack card in the middle of the clash).
		"block_survive": {
			"config": _base({"starting_player": 2,
				"player_field": _f([160, 10, 3]), "opponent_field": _f([50, 161, 177])}),
			"seconds": 14.0,
			# Wider and to the left: Gordon's ability goes on the STACK, which sits at the left of this view.
			"camera": [{"t": 0.0, "target": Vector3(1.0, 0.2, 0.3), "elev": 62.0, "width": 6.0}],
			"seats": {
				1: {"blocks": [160], "steps": [{"when": _blocking(1, 160), "do": _activate(160)}]},
				2: {"attacks": [[50]]},
			},
			"actions": _act_combat,
		},
		# 5. "Break through your opponent's defences": Ultimecia's Time Compression (S: discard the other Ultimecia)
		# freezes every other Forward; then Delita attacks, their Knight blocks, and Delita's Northswain's Strike (S:
		# discard the other Delita, 1-113) breaks the blocker.
		"break_through": {
			"config": _base({"starting_player": 1, "player_hand": [113, 152],
				"player_field": _f([112, 152, 10, 3]), "opponent_field": _f([50, 43, 161, 177])}),
			"seconds": 24.0,
			"camera": [COMBAT_VIEW.merged({"t": 0.0})],
			"seats": {
				1: {"attacks": [[112]], "targets": ["o:50"], "steps": [
					{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _activate(152)},
					{"when": _blocking(2, 50), "do": _activate(112)},
				]},
				2: {"blocks": [50]},
			},
			"actions": _act_break_through,
		},
		# 6-8. An unblocked hit breaks a crystal... the damage check reveals Ramuh (EX BURST), whose bolt breaks our
		# other, still active Forward (Red XIII 5000). One take; the edit splits it.
		"hit_exburst": {
			"config": _base({"starting_player": 1,
				"player_field": _f([189, 29, 10, 3]), "opponent_field": _f([161, 177]),
				"opponent_deck": [143] + range(150, 180)}),
			"seconds": 20.0,
			# A little wider and to the right: the opponent's Ramuh lands on the right of the stack.
			"camera": [{"t": 0.0, "target": Vector3(-0.2, 0.2, 0.3), "elev": 62.0, "width": 7.0}],
			"seats": {1: {"attacks": [[189]]}, 2: {"blocks": [0], "targets": ["p:29"]}},
			"actions": _act_hit_exburst,
		},
		# 9. "Use Summons to gain advantage": Brynhildr (fire) breaks Squall, Shiva (ice) freezes Lightning, Alexander
		# (wind) breaks Sephiroth.
		"summons": {
			"config": _base({"starting_player": 1, "player_hand": [23, 38, 61],
				"player_field": _f([187, 10, 3]), "opponent_field": _f([41, 141, 44, 161, 177])}),
			"seconds": 20.0,
			"camera": [{"t": 0.0, "target": Vector3(0.6, 0.2, 0.55), "elev": 62.0, "width": 6.8}],
			"seats": {1: {
				"targets": ["o:41", "o:141", "o:44"],
				"steps": [
					{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _cast(23)},
					{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _cast(38)},
					{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _cast(61)},
				]}},
			"actions": _act_summons,
		},
		# 10. "Help your pieces...": their Brynhildr (7000) at our Red XIII (5000); we answer with Titan: it cannot break.
		"titan": {
			"config": _base({"starting_player": 2, "player_hand": [110], "opponent_hand": [23],
				"player_field": _f([29, 189, 10, 3]), "opponent_field": _f([41, 161, 177])}),
			"seconds": 16.0,
			# Near the board view: the targeting arrows from the stack cards are drawn right there; a camera much
			# closer started them off screen.
			"camera": [{"t": 0.0, "target": ARROW_VIEW.target, "elev": ARROW_VIEW.elev, "width": ARROW_VIEW.width}],
			"seats": {
				1: {"targets": ["p:29"], "steps": [{"when": _top_is(23), "do": _cast(110)}]},
				2: {"targets": ["p:29"], "steps": [{"when": _main_free(P.FIRST_MAIN_PHASE, 2), "do": _cast(23)}]},
			},
			"actions": _act_stack_play,
		},
		# 11. "Fight magic with magic", the stack ZIG-ZAGS player, opponent, player: our Ramuh at their Thief (5000: it
		# breaks); their Ifrit at our Gadot; our Summoner cancels Ifrit. (Not Zidane: he cannot be chosen by the
		# opponent's Summons.)
		"stack3": {
			"config": _base({"starting_player": 1, "player_hand": [143], "opponent_hand": [4],
				"player_field": _f([7, 53, 10, 3]), "opponent_field": _f([69, 161, 177])}),
			"seconds": 20.0,
			# Wide: our stack cards land on the left, the opponent's Ifrit on the right.
			"camera": [{"t": 0.0, "target": Vector3(-0.05, 0.2, 0.35), "elev": 62.0, "width": 8.4}],
			"seats": {
				1: {"targets": ["o:69", "s:4"], "steps": [
					{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _cast(143)},
					{"when": _top_is(4), "do": _activate(53)},
				]},
				2: {"targets": ["p:7"], "steps": [{"when": _top_is(143), "do": _cast(4)}]},
			},
			"actions": _act_stack_play,
		},
		# 5. "Break through your opponent's defences": three clash WINS, one per death style (cut together quickly).
		"clash_toss": _clash_shot(189, 50, "toss"),     # Tifa 8000 vs Knight 7000
		# (study) OUR card loses by the toss, through the board view: the case ~/Desktop/Clips/death2 48-100 shows.
		"lose_toss": {
			"config": _base({"starting_player": 1,
				"player_field": _f([26, 10, 3]), "opponent_field": _f([50, 161, 177])}),
			"seconds": 8.0,
			"camera": [BOARD.merged({"t": 0.0})],
			"seats": {1: {"attacks": [[26]]}, 2: {"blocks": [50]}},
			"style": "toss", "loser_side": 1, "loser": 26,
			"actions": _act_lose,
		},
		"clash_pop": _clash_shot(99, 14, "pop"),        # Black Belt 8000 vs Samurai 6000
		"clash_tumble": _clash_shot(22, 165, "tumble"), # Firion 7000 vs Knight 5000
		# 9. "Use Summons to gain advantage": one scene per Summon, each its own board (cut together quickly).
		"sm_fire": _summon_shot(23, ["o:41"], [41, 141]),           # Brynhildr breaks Squall
		"sm_ice": _summon_shot(38, ["o:141"], [41, 141]),           # Shiva freezes Lightning
		"sm_wind": _summon_shot(198, [], [43, 141, 71]),            # Valefor: 3000 to all, the tornado
		"sm_earth": _summon_shot(117, ["o:171"], [141], [171, 161]), # Hecatoncheir breaks Minwu (a Backup)
		"sm_lightning": _summon_shot(123, ["o:50"], [50, 141]),     # Odin breaks Knight
		# NEW BEAT "Use your characters' abilities to break through" (Orlandeau, Delita and Ultimecia come from the
		# forwards / break_through takes):
		# Alma: 《Dull》: draw 1, then discard 1 (the water splash on the deck). Films the hand, so the board view.
		"ab_alma": {
			"config": _base({"starting_player": 1, "player_hand": [9, 16, 25],
				"player_field": _f([153, 10, 3, 189]), "opponent_field": _f([41, 161])}),
			"seconds": 12.0, "show_hands": true,
			"camera": [BOARD.merged({"t": 0.0})],
			"seats": {1: {"steps": [{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _activate(153)}]}},
			"actions": _act_stack_play,
		},
		# Kefka: 《Dull》: our Tifa gains +5000 (the power-up swords).
		"ab_kefka": {
			"config": _base({"starting_player": 1,
				"player_field": _f([104, 10, 189]), "opponent_field": _f([41, 161])}),
			"seconds": 12.0,
			"camera": [ARROW_VIEW.merged({"t": 0.0})],
			"seats": {1: {"targets": ["p:189"],
				"steps": [{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _activate(104)}]}},
			"actions": _act_stack_play,
		},
		# Kain enters (cost 6: the strong entry); his arrival takes 5000 power from their Thief (5000): the drain death.
		"ab_kain": {
			"config": _base({"starting_player": 1, "player_hand": [127],
				"player_field": _f([10, 3, 189]), "opponent_field": _f([69, 141, 161])}),
			"seconds": 14.0,
			"camera": [ARROW_VIEW.merged({"t": 0.0})],
			"seats": {1: {"targets": ["o:69"],
				"steps": [{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _cast(127)}]}},
			"actions": _act_kain,
		},
		# (check) The opponent hits US unblocked: our own damage reveal, for checking the near damage zone.
		"hit_me": {
			"config": _base({"starting_player": 2,
				"player_field": _f([10, 3]), "opponent_field": _f([50, 161, 177]),
				"player_deck": [143] + range(150, 180)}),
			"seconds": 9.0,
			"camera": [COMBAT_VIEW.merged({"t": 0.0})],
			"seats": {1: {"blocks": [0]}, 2: {"attacks": [[50]]}},
			"actions": _act_none,
		},
		# 12. Victory: they stand at 5 damage; two unblocked hits break the last two crystals.
		"victory": {
			"config": _base({"starting_player": 1,
				"player_field": _f([189, 29, 10, 3]), "opponent_field": _f([161, 177]),
				"opponent_damage": [181, 182, 183, 184, 185]}),
			"seconds": 26.0,
			"camera": [COMBAT_VIEW.merged({"t": 0.0})],
			"seats": {1: {"attacks": [[189], [29]]}, 2: {"blocks": [0, 0]}},
			"actions": _act_victory,
		},
	}


## A blocked attack: closer once the block is declared, held still through the clash, done after combat.
func _act_combat() -> void:
	await _on_phase(P.BLOCKER_DECLARATION_STEP)
	_move({"width": _pose_at(_t).width * 0.85, "elev": 64.0}, 0.8)
	await _on_phase(P.SECOND_MAIN_PHASE, 30.0)
	_finish_in(0.8)


## Time Compression resolves: in on the Forwards while the frost spreads (it is subtle from the board view), back
## out for Delita's attack.
func _act_break_through() -> void:
	await _until(func() -> bool: return _game.stack.stack_length() > 0, 15.0)
	await _until(_stack_settled, 15.0)
	_move({"target": Vector3(0.25, 0.2, 0.25), "elev": 64.0, "width": 3.6}, 0.7)
	await _wait(1.6)
	# Back out, wide enough for Delita's ability card on the stack (left of the rows). No zoom at the block: a second
	# move there would cut this one short.
	_move({"target": Vector3(0.9, 0.2, 0.3), "elev": 62.0, "width": 6.6}, 0.9)
	await _until(func() -> bool: return seats[2].field_card(2, 50) == null, 40.0)
	_finish_in(2.0)


## The rules reach Main 2 while the EX BURST is still being presented, so wait for the OUTCOME: Red XIII leaving.
func _act_hit_exburst() -> void:
	await _until(func() -> bool: return seats[1].field_card(1, 29) == null, 40.0)
	_finish_in(2.0)


## Plays on the stack: wait for the scripted casts to be used up and the stack to empty, then a beat.
## The last step is used up BEFORE its card reaches the stack (the cast is still choosing its target), so: every step
## used, then the stack filled again, then the stack empty.
func _act_stack_play() -> void:
	await _until(func() -> bool: return seats.values().all(func(a) -> bool: return a.steps.is_empty()), 30.0)
	await _until(func() -> bool: return _game.stack.stack_length() > 0, 8.0)
	await _until(_stack_settled, 30.0)
	_finish_in(1.6)


func _act_summons() -> void:
	await _act_stack_play()


## The rules end the match at the 7th damage, BEFORE the zoom and the last crystal's break are presented.
func _act_victory() -> void:
	await _until(func() -> bool: return _game.match_over, 40.0)
	_finish_in(5.5)


## One attack, one block, the attacker wins the clash; the loser dies in `style` (toss / pop / tumble).
func _clash_shot(attacker: int, blocker: int, style: String) -> Dictionary:
	return {
		"config": _base({"starting_player": 1,
			"player_field": _f([attacker, 10, 3]), "opponent_field": _f([blocker, 161, 177])}),
		"seconds": 14.0,
		"camera": [CLASH_VIEW.merged({"t": 0.0})],
		"seats": {1: {"attacks": [[attacker]]}, 2: {"blocks": [blocker]}},
		"style": style,
		"blocker": blocker,
		"actions": _act_clash,
	}


## One Summon from our hand in Main 1, at `targets`; the opponent's Forwards `forwards` (+ Backups).
func _summon_shot(id: int, targets: Array, forwards: Array, backups: Array = [161, 177]) -> Dictionary:
	return {
		"config": _base({"starting_player": 1, "player_hand": [id],
			"player_field": _f([10, 3, 189]), "opponent_field": _f(forwards + backups)}),
		"seconds": 14.0,
		"camera": [ARROW_VIEW.merged({"t": 0.0})],
		"seats": {1: {"targets": targets,
			"steps": [{"when": _main_free(P.FIRST_MAIN_PHASE, 1), "do": _cast(id)}]}},
		"actions": _act_stack_play,
	}


func _act_clash() -> void:
	var shot: Dictionary = _shots()[_shot_name]
	CLASH.next_defeat_style = shot.style
	await _on_phase(P.BLOCKER_DECLARATION_STEP, 20.0)
	# The rules take the loser off the field BEFORE the cinematic plays; at 30 fps-correct timing its flight, rest and
	# break take ~2 s from contact, so 2.2 s cut the break off.
	await _until(func() -> bool: return seats[2].field_card(2, int(shot.blocker)) == null, 30.0)
	_finish_in(3.4)


## Kain's arrival trigger resolves, Thief is drained to 0 and dies.
func _act_kain() -> void:
	await _until(func() -> bool: return seats[2].field_card(2, 69) == null, 30.0)
	_finish_in(2.0)


## OUR card loses: done once it has left the field.
func _act_lose() -> void:
	var shot: Dictionary = _shots()[_shot_name]
	CLASH.next_defeat_style = shot.style
	await _on_phase(P.BLOCKER_DECLARATION_STEP, 20.0)
	await _until(func() -> bool: return seats[1].field_card(1, int(shot.loser)) == null, 30.0)
	_finish_in(2.0)
