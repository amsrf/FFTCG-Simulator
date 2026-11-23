extends Node3D
## Cinematic single-clash presentation.
##
## The rules resolve first (Game.clash_attacker_blocker). This node only replays
## the result with two visual proxies, so it never owns card state and never
## competes with Field/Hand layout.
##
## The real cards are hidden while the proxies perform. Survivors return to their
## exact captured transform; defeated proxies tumble, then hand off to the normal
## card-shatter effect. Game.break_card suppresses its own shatter for these two
## cards while the cinematic is running.
##
## One look for every clash, First Strike included: the exchange shows only WHO SURVIVED. A dulled card is turned
## STRAIGHT before anything else moves, stays straight through the whole exchange (no turning to face the other card,
## whatever the columns), and is turned back to dulled once it is home again. An unblocked attack is the
## same strike aimed at the defending player (play_player_strike()).

signal finished
## play_player_strike(): the strike has landed and the card has started its glide home. The damage may be dealt from
## here (the zoom then overlaps the glide). Emitted on EVERY path, including a strike that had nothing to play.
signal handoff
## play_player_strike(): every proxy is gone and the real cards are shown again.
signal strike_finished

const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const CARD_SHARDS := preload("res://scenes/cards/card_shards.tscn")
const HALO_SHADER := preload("res://shaders/orb_halo.gdshader")
const EDGE_WAVE_SHADER := preload("res://shaders/player_impact_wave.gdshader")

@export_group("Choreography")
@export var lift_height: float = 0.85
@export var windup_distance: float = 0.80
## LIFT, PULL-BACK AND LEAN ARE ONE SNAP (Artifact's clash, ~/Desktop/Clips/damage 630-633: ~4 frames off the board
## into the leaning, pulled-back pose). They used to be two beats (a 0.22 s lift, then a 0.32 s overshooting lean),
## which read as the card sliding up the screen and then tipping.
@export var windup_seconds: float = 0.17
@export_range(-70.0, 70.0) var windup_pitch_degrees: float = -32.0
## A deliberate beat with no movement at the end of the pull-back. This is the "moment of nothing" before the charge
## (the clip holds ~0.4 s, 633-656). The height is read from the wood shadow, which falls further away the higher the
## card is (card_field_shadow.gd).
## ~/Desktop/Clips/death2: the card hangs pulled back for 6 frames (54-59) before the charge.
## THE ARTIFACT CLIPS ARE 30 FPS (measured 2026-11-23: the on-screen clock ticks every 30 frames in death and death2),
## so a reference frame is 1/30 s. The clash's beats were first converted at 60 fps and played twice too fast.
@export var windup_hold_seconds: float = 0.20
@export var charge_seconds: float = 0.13
## A freeze at the contact point before the loser flies. 0 since 2026-11-23: the user found the pause at impact
## "awful"; the hit carries straight into the knock-back.
@export var hitstop_seconds: float = 0.0
@export var recovery_seconds: float = 0.32
## Time spent tumbling intact before the airborne shatter.
@export var defeat_seconds: float = 0.55

## A dulled card turns straight before the clash, and back to dulled after it is home.
@export var straighten_seconds: float = 0.16
@export var redull_seconds: float = 0.20

@export_group("Player Strike")
## The defending player is a point at the screen's horizontal centre, this many pixels past its top (or bottom) edge.
@export var player_offscreen_pixels: float = 12.0
## Party members charge side by side: the gap between their contact points, in card widths.
@export var party_contact_spacing: float = 1.1
## HIT STUN: the striker stays STILL at the player (no tremble: the user's call) and is flashed white
## (`hitstun_whiteout` at contact, gone after `hitstun_flash_seconds`). The hold and the bounce scale with the
## attacker's strength (`hitstun_strength_range`, a multiplier from weakest to strongest).
@export var hitstun_seconds: float = 0.40
@export var hitstun_whiteout: float = 0.75
@export var hitstun_flash_seconds: float = 0.16
@export var hitstun_strength_range := Vector2(0.8, 1.35)
## The BOUNCE off the player: knocked back this far (m), leaning back by `bounce_pitch_degrees`, then it HANGS there.
@export var bounce_distance: float = 0.38
@export var bounce_seconds: float = 0.18
@export var bounce_pitch_degrees: float = 18.0
@export var hang_seconds: float = 0.15
## The calm GLIDE home (no spring, no overshoot — the clash's return is the snappy one), then it dulls again.
@export var glide_seconds: float = 0.85
## The impact at the player's EDGE: a wide flat shockwave in the screen plane (m), and a camera shake that PUSHES
## toward the player and settles back (`player_shake_push` m, damped over `player_shake_seconds`).
@export var edge_wave_size := Vector2(5.0, 1.1)
@export var edge_wave_seconds: float = 0.45
@export var edge_wave_intensity: float = 2.2
@export var player_shake_push: float = 0.07
@export var player_shake_seconds: float = 0.45

@export_group("Defeat")
@export var knockback_speed: float = 2.4
@export var upward_impulse: float = 1.7
@export var gravity: float = 7.0
@export var tumble_speed: float = 520.0

@export_group("Defeat: Toss")
## THE TOSS (~/Desktop/Clips/death2 frames 56-109): the loser is thrown back over its own side, climbing toward the
## camera while it flips end over end about its width axis (two full turns, the spin axis drifting a little), lands
## face up, turned, between the contact point and its slot, and only THEN breaks. See `defeat_styles` for how a death
## is picked.
## Flight time (reference: frames 66-96 = 1.0 s; the clip is 30 fps).
@export var toss_seconds: float = 1.0
## How far the card climbs TOWARD THE CAMERA (metres along the line of sight, so it grows rather than shooting up the
## screen: world-up under the 67 degree camera reads as up-screen). With `toss_swell` this gives the reference's
## ~1.7x on screen at the top of the climb.
@export var toss_climb: float = 3.0
## The small drift of the top of the climb on screen, in card heights: toward the winner and to one side (the
## reference ends up level with, and beside, the winner).
@export var toss_drift := Vector2(0.45, 0.55)
## When the top of the climb is reached, as a fraction of the flight (reference: frame ~75 of 66-96).
@export_range(0.1, 0.9, 0.01) var toss_peak_at: float = 0.33
@export var toss_swell: float = 0.35
## Where it lands: this fraction of the way from its own slot toward the contact point. The reference drops it back
## by its own slot (frames 96-100); 0.35 put it near the river.
@export_range(0.0, 1.0, 0.01) var toss_land_fraction: float = 0.08
## How far it is turned on the board when it lands (reference: ~35 degrees), and the roll wobble on the way.
@export var toss_yaw_degrees: float = 35.0
@export var toss_roll_degrees: float = 16.0
## The beat on the floor before the break.
@export var toss_rest_seconds: float = 0.2

@export_group("Defeat: Pop")
## THE POP (~/Desktop/Clips/death frames 90-127, the blue card): the loser pops nearly STRAIGHT UP over the clash, turns
## over ONCE (face, back, face), HANGS at the top with its back to the camera (~2x on screen), and drops back beside
## its own slot almost straight, with a small bounce and a slow turn before it breaks. Same flight engine as the toss,
## its own numbers.
@export var pop_seconds: float = 0.75
@export var pop_climb: float = 3.5
@export var pop_drift := Vector2(1.0, 0.15)
@export_range(0.1, 0.9, 0.01) var pop_peak_at: float = 0.42
@export var pop_swell: float = 0.45
@export_range(0.0, 1.0, 0.01) var pop_land_fraction: float = 0.08
@export var pop_yaw_degrees: float = 12.0
@export var pop_roll_degrees: float = 10.0
## Longer than the toss: the reference lies there ~12 frames, turning slowly.
@export var pop_rest_seconds: float = 0.4
## The landing bounce (degrees about the flip axis) and the slow turn while it lies there.
@export var pop_settle_degrees: float = 5.0
@export var pop_settle_turn_degrees: float = 5.0

@export_group("Defeat")
## The deaths a clash loser picks from, uniformly, never the same one twice in a row (board-wide, `_last_defeat_style`):
## "tumble" (random spin, shattered in the air), "toss" (death2) and "pop" (death).
@export var defeat_styles: PackedStringArray = PackedStringArray(["tumble", "toss", "pop"])
## Forces the next defeat's style ("toss" / "pop" / "tumble"), then clears itself. For demos and probes.
static var next_defeat_style: String = ""
static var _last_defeat_style: String = ""

## The pop's flip, keyed off the reference frames 93..115 (u = (frame - 93) / 22): edge at 97, the back coming round
## 98-100, HELD 101-105 (182..190) while it hangs big at the top, edge again at 108, face up at the landing (360).
const POP_PITCH_KEYS := [
	Vector2(0.000, 0.0), Vector2(0.091, 50.0), Vector2(0.182, 90.0), Vector2(0.273, 150.0), Vector2(0.318, 170.0),
	Vector2(0.409, 182.0), Vector2(0.545, 190.0), Vector2(0.591, 205.0), Vector2(0.636, 235.0),
	Vector2(0.682, 270.0), Vector2(0.727, 300.0), Vector2(0.773, 322.0), Vector2(0.864, 345.0),
	Vector2(0.955, 357.0), Vector2(1.000, 360.0),
]

## The flip angle through the flight, keyed off the reference frames 66..96 (u = (frame - 66) / 30): face (0), edge
## (90) at 70, the BACK held large toward the camera 72-77 (150..215), edge 79, face 81, edge 83, the back again,
## falling, 85-90, edge 91, and face up on landing (720). Two holds where the back faces the camera make it read as a
## thrown card rather than a spinning one.
const TOSS_PITCH_KEYS := [
	Vector2(0.000, 0.0), Vector2(0.067, 40.0), Vector2(0.133, 90.0), Vector2(0.200, 150.0), Vector2(0.300, 180.0),
	Vector2(0.367, 215.0), Vector2(0.433, 270.0), Vector2(0.500, 360.0), Vector2(0.567, 450.0),
	Vector2(0.633, 520.0), Vector2(0.733, 545.0), Vector2(0.800, 560.0), Vector2(0.867, 630.0),
	Vector2(0.933, 690.0), Vector2(1.000, 720.0),
]

@export_group("Impact")
@export var impact_flash_size: float = 0.65
@export var impact_flash_seconds: float = 0.12
@export var impact_flash_intensity: float = 2.0
@export var camera_shake_seconds: float = 0.22
@export var camera_shake_strength: float = 0.045
@export var random_seed: int = 0

## POWER DRIVES THE BLOW. Each card's power maps to a strength 0..1 between these two values; a stronger card draws
## back further, charges faster (it leaves later and still arrives on the same frame), drives the meeting point into
## its opponent's half, and throws a defeated opponent harder.
@export_group("Power")
@export var weak_power: int = 2000
@export var strong_power: int = 10000
## Wind-up distance multiplier at strength 0 and 1.
@export var windup_scale_range := Vector2(0.70, 1.40)
## Charge time multiplier at strength 0 and 1 (lower = faster). The weak end was 1.7: with the expo ease-in a weak card
## then hung still for ~8 frames before it moved, which read as more waiting (death2 charges in 4 frames, 60-63).
@export var charge_scale_range := Vector2(1.00, 0.55)
## How far the meeting point moves toward the weaker card, in card heights, at the largest strength gap.
@export var impact_push: float = 0.45
## Knockback multiplier on a defeated card at its opponent's strength 0 and 1.
@export var knockback_scale_range := Vector2(0.75, 1.65)

var _attacker: Card = null
var _defender: Card = null
var _proxy_a: Card = null
var _proxy_b: Card = null
var _snap_a: Transform3D = Transform3D.IDENTITY
var _snap_b: Transform3D = Transform3D.IDENTITY
var _survives_a: bool = true
var _survives_b: bool = true
var _running: bool = false
var _camera: Camera3D = null
var _camera_home: Transform3D = Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()
var _defeated: Dictionary = {}
## Strength 0..1 of the attacker (a) and the defender (b), from their power when the clash started.
var _strength_a: float = 0.5
var _strength_b: float = 0.5
## Each real card's hidden state when the cinematic began, restored for a defeated card: one that broke is already
## swallowed (hidden) by its pit, and un-hiding it would draw it on top of the pit.
var _was_hidden_a: bool = false
var _was_hidden_b: bool = false
## play_player_strike(): one {card, proxy, snap, hidden} per attacking card.
var _strikers: Array = []
var _handed_off: bool = false


## Start the cinematic. `survives_*` comes from the already-resolved game state.
func play(attacker: Card, defender: Card, snap_a: Transform3D, snap_b: Transform3D,
		survives_a: bool, survives_b: bool) -> void:
	if _running:
		return
	_running = true
	_attacker = attacker
	_defender = defender
	_snap_a = snap_a
	_snap_b = snap_b
	_survives_a = survives_a
	_survives_b = survives_b
	_rng.seed = random_seed if random_seed != 0 else int(Time.get_ticks_usec())
	_strength_a = strength_for(attacker)
	_strength_b = strength_for(defender)

	_camera = get_viewport().get_camera_3d()
	if _camera != null:
		_camera_home = _camera.global_transform

	_proxy_a = _make_proxy(attacker, snap_a)
	_proxy_b = _make_proxy(defender, snap_b)
	if _proxy_a == null or _proxy_b == null:
		_cleanup()
		return

	if attacker != null and is_instance_valid(attacker):
		_was_hidden_a = not attacker.visible
		attacker.set_hidden(true)
	if defender != null and is_instance_valid(defender):
		_was_hidden_b = not defender.visible
		defender.set_hidden(true)

	await _choreograph()
	_cleanup()


## A card's strength 0..1 for the choreography: its current power between weak_power and strong_power.
func strength_for(card: Card) -> float:
	if card == null or not is_instance_valid(card):
		return 0.5
	return clampf(inverse_lerp(float(weak_power), float(strong_power), float(card.power)), 0.0, 1.0)


func _make_proxy(source: Card, snapshot: Transform3D) -> Card:
	if source == null or not is_instance_valid(source):
		return null
	var proxy: Card = CARD_SCENE.instantiate()
	proxy.initialize(source.id, source.controller)
	add_child(proxy)
	proxy.enter_zone(Card.Zone.FIELD)
	proxy.global_transform = snapshot
	proxy.hide_power_display()
	proxy.set_highlight(false)
	proxy.set_process(false)
	proxy.process_mode = Node.PROCESS_MODE_DISABLED
	var area: Area3D = proxy.get_node_or_null("CardArea3D") as Area3D
	if area != null:
		area.monitoring = false
		area.monitorable = false
		area.input_ray_pickable = false
		area.collision_layer = 0
		area.collision_mask = 0
	return proxy


func _choreograph() -> void:
	var a0: Vector3 = _proxy_a.position
	var b0: Vector3 = _proxy_b.position
	var a_rest: Quaternion = _proxy_a.quaternion
	var b_rest: Quaternion = _proxy_b.quaternion
	var a_straight: Quaternion = _straight_rotation(_attacker, a_rest)
	var b_straight: Quaternion = _straight_rotation(_defender, b_rest)
	var a_scale0: Vector3 = _proxy_a.scale
	var b_scale0: Vector3 = _proxy_b.scale

	# STRAIGHT FIRST, in place: a dulled card would otherwise wind up and charge at its tilt. The cards stay straight
	# for the whole exchange; they never turn to face each other.
	# Only when one of them IS turned: for two upright cards it was 0.16 s of nothing before every wind-up.
	if a_straight.angle_to(a_rest) > 0.001 or b_straight.angle_to(b_rest) > 0.001:
		await _run([[_proxy_a, a0, a_straight], [_proxy_b, b0, b_straight]], straighten_seconds,
			Tween.TRANS_SINE, Tween.EASE_IN_OUT)

	var travel: Vector3 = b0 - a0
	travel.y = 0.0
	if travel.length_squared() < 0.0001:
		travel = Vector3.RIGHT
	var axis: Vector3 = travel.normalized()
	var lift: Vector3 = Vector3.UP * lift_height
	# Horizontal midpoint, before the lift. Using the lifted midpoint for the retreat direction would point
	# diagonally DOWN and lower both cards during the wind-up.
	var mid_ground: Vector3 = (a0 + b0) * 0.5
	var midpoint: Vector3 = mid_ground + lift
	# A top-edge-to-top-edge collision separates the CENTRES by a card height, not a card width.
	var card_height: float = 0.60 * maxf(_proxy_a.global_transform.basis.get_scale().x,
			_proxy_b.global_transform.basis.get_scale().x)
	var half_extent: float = card_height * 0.5 + 0.03
	# The stronger card drives the collision into the weaker one's half.
	var contact: Vector3 = midpoint + axis * (_strength_a - _strength_b) * impact_push * card_height
	var a_impact: Vector3 = contact - axis * half_extent
	var b_impact: Vector3 = contact + axis * half_extent
	var a_away: Vector3 = a0 - mid_ground
	var b_away: Vector3 = b0 - mid_ground
	a_away.y = 0.0
	b_away.y = 0.0
	a_away = a_away.normalized() if a_away.length_squared() > 0.0001 else -axis
	b_away = b_away.normalized() if b_away.length_squared() > 0.0001 else axis

	# Wind-up, ONE snap: off the board, away from the midpoint, leaning back about the card's own right axis.
	await _run([
		[_proxy_a, a0 + lift + a_away * windup_distance * _windup_scale(_strength_a), _leaning(_proxy_a, a_straight)],
		[_proxy_b, b0 + lift + b_away * windup_distance * _windup_scale(_strength_b), _leaning(_proxy_b, b_straight)],
	], windup_seconds, Tween.TRANS_CUBIC, Tween.EASE_OUT)

	# The beat before the hit. No movement, no easing to distract from it; the cards are simply held back.
	await _wait(windup_hold_seconds)

	# Charge: very short, very sharp acceleration into the collision point. Each card at its own speed; the faster
	# one leaves later, so both arrive on the same frame.
	var a_time: float = _charge_time(_strength_a)
	var b_time: float = _charge_time(_strength_b)
	var longest: float = maxf(a_time, b_time)
	var charge: Tween = create_tween().set_parallel(true)
	charge.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_pose(charge, _proxy_a, a_impact, a_straight, a_time, longest - a_time)
	_pose(charge, _proxy_b, b_impact, b_straight, b_time, longest - b_time)
	await charge.finished

	_impact_flash(contact)
	_shake_camera(maxf(_strength_a, _strength_b))
	await _wait(hitstop_seconds)

	var recovery: Array[Tween] = []
	if _survives_a:
		recovery.append(_start_recovery(_proxy_a, a0, a_straight, a_scale0))
	else:
		_start_defeat(_proxy_a, -axis, _strength_b, a0, a_straight, a_scale0)
	if _survives_b:
		recovery.append(_start_recovery(_proxy_b, b0, b_straight, b_scale0))
	else:
		_start_defeat(_proxy_b, axis, _strength_a, b0, b_straight, b_scale0)
	for tween in recovery:
		await tween.finished
	# Home again: a survivor turns back to how it rested (dulled, if it was).
	var back: Array = []
	if _survives_a:
		back.append([_proxy_a, a0, a_rest])
	if _survives_b:
		back.append([_proxy_b, b0, b_rest])
	await _run(back, redull_seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	# Simulation time owns the delay, including slow motion and pause.
	while not _defeated.is_empty():
		await get_tree().process_frame


## AN UNBLOCKED ATTACK: every attacking card charges the defending player. The player is not on the board, so they are
## a point at the screen's horizontal centre, `player_offscreen_pixels` past the TOP edge (the opponent) or the BOTTOM
## edge (`hit_bottom`: the local player), at the height the cards are lifted to. Same beats as the exchange, and just
## as STRAIGHT: straighten, lift, wind up, hold, charge, impact, return home, dull again. Nothing is defeated.
func play_player_strike(attackers: Array, hit_bottom: bool) -> void:
	if _running:
		_hand_off()
		return
	_running = true
	_rng.seed = random_seed if random_seed != 0 else int(Time.get_ticks_usec())
	_camera = get_viewport().get_camera_3d()
	if _camera != null:
		_camera_home = _camera.global_transform
	for card in attackers:
		if card == null or not is_instance_valid(card):
			continue
		var proxy: Card = _make_proxy(card, card.global_transform)
		if proxy == null:
			continue
		_strikers.append({"card": card, "proxy": proxy, "snap": card.global_transform, "hidden": not card.visible})
		card.set_hidden(true)
	if not _strikers.is_empty():
		await _choreograph_player_strike(hit_bottom)
	_hand_off()
	_cleanup()
	strike_finished.emit()


func is_handed_off() -> bool:
	return _handed_off


func _hand_off() -> void:
	if _handed_off:
		return
	_handed_off = true
	handoff.emit()


func _choreograph_player_strike(hit_bottom: bool) -> void:
	var count: int = _strikers.size()
	var proxies: Array = []
	var starts: Array = []
	var rests: Array = []
	var straights: Array = []
	var scales: Array = []
	var strengths: Array = []
	for entry in _strikers:
		var proxy: Card = entry.proxy
		proxies.append(proxy)
		starts.append(proxy.position)
		rests.append(proxy.quaternion)
		straights.append(_straight_rotation(entry.card, proxy.quaternion))
		scales.append(proxy.scale)
		strengths.append(strength_for(entry.card))

	var straighten: Array = []
	for i in count:
		straighten.append([proxies[i], starts[i], straights[i]])
	await _run(straighten, straighten_seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT)

	var lift: Vector3 = Vector3.UP * lift_height
	var card_scale: float = (proxies[0] as Card).global_transform.basis.get_scale().x
	var half_extent: float = 0.60 * card_scale * 0.5 + 0.03
	var target: Vector3 = to_local(player_point(hit_bottom, (proxies[0] as Card).global_position.y + lift_height))
	# Side by side along the screen's horizontal, so a party does not pile into one point.
	var across: Vector3 = Vector3.RIGHT
	if _camera != null:
		across = global_basis.inverse() * _camera.global_basis.x
		across.y = 0.0
		across = across.normalized() if across.length_squared() > 0.0001 else Vector3.RIGHT
	var contacts: Array = []
	var axes: Array = []
	for i in count:
		var contact: Vector3 = target + across * (float(i) - float(count - 1) * 0.5) \
				* party_contact_spacing * 0.429 * card_scale
		var axis: Vector3 = contact - (starts[i] + lift)
		axis.y = 0.0
		axes.append(axis.normalized() if axis.length_squared() > 0.0001 else Vector3.FORWARD)
		contacts.append(contact)

	var winding: Array = []
	for i in count:
		winding.append([proxies[i], starts[i] + lift - axes[i] * windup_distance * _windup_scale(strengths[i]),
			_leaning(proxies[i], straights[i])])
	await _run(winding, windup_seconds, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	await _wait(windup_hold_seconds)

	# Charge, straight: the top edge meets the player point; the faster card leaves later, so all arrive together.
	var longest: float = 0.0
	var strongest: float = 0.0
	for strength in strengths:
		longest = maxf(longest, _charge_time(strength))
		strongest = maxf(strongest, strength)
	var charge: Tween = create_tween().set_parallel(true)
	charge.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	for i in count:
		var time: float = _charge_time(strengths[i])
		_pose(charge, proxies[i], contacts[i] - axes[i] * half_extent, straights[i], time, longest - time)
	await charge.finished

	# IMPACT AT THE PLAYER'S EDGE: the round flash, a wide flat shockwave, and a shake that pushes toward the player.
	var stun_scale: float = lerpf(hitstun_strength_range.x, hitstun_strength_range.y, strongest)
	_impact_flash(to_global(target))
	_edge_wave(to_global(target), stun_scale)
	var push: Vector3 = Vector3.ZERO
	for axis in axes:
		push += axis
	_push_camera(global_basis * push.normalized() if push.length_squared() > 0.0001 else Vector3.ZERO, stun_scale)

	# HIT STUN: every striker holds still at its contact point, flashed white. All at once: a party hits as one.
	var contact_poses: Array = []
	for i in count:
		contact_poses.append(proxies[i].position)
	var stun: float = hitstun_seconds * stun_scale
	var stunning: Tween = create_tween()
	stunning.tween_method(func(t: float) -> void:
		var flash: float = 1.0 - clampf(t / maxf(hitstun_flash_seconds, 0.0001), 0.0, 1.0)
		for i in count:
			_set_whiteout(proxies[i], hitstun_whiteout * flash * flash), 0.0, stun, stun)
	await stunning.finished

	# BOUNCE off the player, leaning back, and HANG there.
	var bounced: Array = []
	for i in count:
		_set_whiteout(proxies[i], 0.0)
		# Leaning BACK, the same way as the wind-up (whose sign is mirrored for the opponent's cards).
		var pitch: float = deg_to_rad(bounce_pitch_degrees if proxies[i].controller == Card.OPPONENT \
				else -bounce_pitch_degrees)
		bounced.append([proxies[i], contact_poses[i] - axes[i] * bounce_distance * stun_scale,
			straights[i] * Quaternion(Vector3.RIGHT, pitch)])
	await _run(bounced, bounce_seconds, Tween.TRANS_QUART, Tween.EASE_OUT)
	await _wait(hang_seconds)
	_restore_camera()

	# GLIDE home: slow and calm. The damage may be dealt from here on.
	var gliding: Tween = create_tween().set_parallel(true)
	gliding.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in count:
		_pose(gliding, proxies[i], starts[i], straights[i], glide_seconds)
	_hand_off()
	await gliding.finished
	var back: Array = []
	for i in count:
		back.append([proxies[i], starts[i], rests[i]])
	await _run(back, redull_seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


func _set_whiteout(proxy: Card, value: float) -> void:
	if proxy == null or not is_instance_valid(proxy):
		return
	var mat: ShaderMaterial = proxy.get("mat") as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("whiteout", value)


## The wide flat shockwave at the player's edge: a camera-facing quad, longer across the screen than it is tall.
func _edge_wave(point: Vector3, size_scale: float) -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = edge_wave_size * size_scale
	quad.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = EDGE_WAVE_SHADER
	material.set_shader_parameter("intensity", edge_wave_intensity)
	material.set_shader_parameter("progress", 0.0)
	material.render_priority = 10
	quad.material_override = material
	quad.extra_cull_margin = 2.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	var basis: Basis = _camera.global_transform.basis if _camera != null else Basis()
	quad.global_transform = Transform3D(basis, point)
	var tween: Tween = create_tween()
	tween.tween_method(func(value: float) -> void:
		material.set_shader_parameter("progress", value), 0.0, 1.0, edge_wave_seconds)
	tween.tween_callback(quad.queue_free)


## A DIRECTIONAL shake: the camera is jolted `player_shake_push` toward the player at once, then swings back and
## settles about its home (a damped cosine), with a little sideways jitter. It is exactly home at the end.
var _push_tween: Tween = null

func _push_camera(direction: Vector3, push_scale: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var dir: Vector3 = direction
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO
	var side: Vector3 = dir.cross(Vector3.UP)
	var home: Vector3 = _camera_home.origin
	var amount: float = player_shake_push * push_scale
	var seconds: float = maxf(player_shake_seconds, 0.0001)
	_push_tween = create_tween()
	_push_tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(_camera):
			return
		var u: float = t / seconds
		var envelope: float = exp(-5.0 * u) * (1.0 - u)
		var along: float = cos(u * TAU * 2.2) * envelope
		var jitter: float = sin(u * TAU * 7.0) * envelope * 0.35
		_camera.global_position = home + dir * amount * along + side * amount * jitter, 0.0, seconds, seconds)
	_push_tween.tween_callback(_restore_camera)


func _restore_camera() -> void:
	if _push_tween != null and _push_tween.is_valid():
		_push_tween.kill()
	_push_tween = null
	if _camera != null and is_instance_valid(_camera):
		_camera.global_position = _camera_home.origin


## The defending player's point in WORLD space: the screen's horizontal centre, `player_offscreen_pixels` beyond the
## top edge (or the bottom edge), on the horizontal plane at `plane_y`.
func player_point(hit_bottom: bool, plane_y: float) -> Vector3:
	var camera: Camera3D = _camera if _camera != null and is_instance_valid(_camera) else get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(0.0, plane_y, 0.0)
	var view: Vector2 = get_viewport().get_visible_rect().size
	var screen := Vector2(view.x * 0.5,
		view.y + player_offscreen_pixels if hit_bottom else -player_offscreen_pixels)
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	if absf(direction.y) < 0.0001:
		return Vector3(origin.x, plane_y, origin.z)
	return origin + direction * ((plane_y - origin.y) / direction.y)


## STRAIGHT = the card's resting orientation without its dull tilt. Measured from the REAL card, not assumed from
## `tapped`: its current turn about Y minus the angle it rests at upright (`_upright_y`) is exactly the tilt to undo,
## however it got there. Applied about the board's up axis, which the cinematic shares with the Field.
func _straight_rotation(source, rest: Quaternion) -> Quaternion:
	if source == null or not is_instance_valid(source) or not (source is Card):
		return rest
	var card: Card = source
	var tilt: float = wrapf(card.rotation.y - deg_to_rad(float(card.get("_upright_y"))), -PI, PI)
	return Quaternion(Vector3.UP, -tilt) * rest


## The wind-up lean: `straight` pitched back about the card's own right axis (mirrored for the opponent's cards).
func _leaning(proxy: Card, straight: Quaternion) -> Quaternion:
	var pitch: float = deg_to_rad(-windup_pitch_degrees if proxy.controller == Card.OPPONENT else windup_pitch_degrees)
	return straight * Quaternion(Vector3.RIGHT, pitch)


## Tween `proxy` to (`to_pos`, `to_rot`) on `tween` (its transition applies). ROTATION IS SLERPED, never tweened as
## Euler angles: a card resting at a yaw of 180° reads back as +PI or -PI, and an Euler tween between the two spins it
## a full turn, which is what made the player strike rotate for no reason. The start is read when the tweener is made.
func _pose(tween: Tween, proxy: Card, to_pos: Vector3, to_rot: Quaternion, seconds: float, delay: float = 0.0) -> void:
	var from_pos: Vector3 = proxy.position
	var from_rot: Quaternion = proxy.quaternion
	tween.tween_method(func(w: float) -> void:
		if is_instance_valid(proxy):
			proxy.position = from_pos.lerp(to_pos, w)
			proxy.quaternion = from_rot.slerp(to_rot, w),
		0.0, 1.0, seconds).set_delay(delay)


## Move every [proxy, position, rotation] together and wait. A card already there is skipped, and nothing to move is
## no wait at all: an untapped card does not sit through an empty straighten beat.
func _run(moves: Array, seconds: float, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	var tween: Tween = null
	for move in moves:
		var proxy: Card = move[0]
		if proxy == null or not is_instance_valid(proxy):
			continue
		if proxy.position.is_equal_approx(move[1]) and proxy.quaternion.angle_to(move[2]) < 0.001:
			continue
		if tween == null:
			tween = create_tween().set_parallel(true)
			tween.set_trans(trans).set_ease(ease_type)
		_pose(tween, proxy, move[1], move[2], seconds)
	if tween != null:
		await tween.finished


func _windup_scale(strength: float) -> float:
	return lerpf(windup_scale_range.x, windup_scale_range.y, strength)


func _charge_time(strength: float) -> float:
	return charge_seconds * lerpf(charge_scale_range.x, charge_scale_range.y, strength)


func _start_recovery(proxy: Card, start_pos: Vector3, rot: Quaternion, base_scale: Vector3 = Vector3.ZERO) -> Tween:
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pose(tween, proxy, start_pos, rot, recovery_seconds)
	# THE OVERSHOOT IS SIDEWAYS ONLY. Field cards rest ON the wood, so the back-ease's dip past the slot took the card
	# UNDER the board for a few frames: the art vanished and its wood shadow showed through as a black slab. The
	# height is clamped to the slot from here on (it runs after _pose's method in the same tween step).
	var floor_y: float = start_pos.y
	tween.tween_method(func(_w: float) -> void:
		if is_instance_valid(proxy) and proxy.position.y < floor_y:
			proxy.position.y = floor_y,
		0.0, 1.0, recovery_seconds)
	if base_scale != Vector3.ZERO:
		tween.tween_property(proxy, "scale", base_scale, recovery_seconds)
	return tween


## `hit_by` is the winner's strength 0..1: a stronger blow throws the loser further and higher. `home`, `straight` and
## `rest_scale` are the loser's slot, upright rotation and resting scale (the toss lands near the slot, face up).
func _start_defeat(proxy: Card, direction: Vector3, hit_by: float = 0.5, home: Variant = null,
		straight: Quaternion = Quaternion.IDENTITY, rest_scale: Vector3 = Vector3.ZERO) -> void:
	var style: String = next_defeat_style
	next_defeat_style = ""
	if style.is_empty():
		style = _pick_defeat_style()
	_last_defeat_style = style
	if (style == "toss" or style == "pop") and home is Vector3:
		_start_toss(proxy, direction, hit_by, home, straight, rest_scale, _flight_profile(style))
		return
	var force := lerpf(knockback_scale_range.x, knockback_scale_range.y, hit_by)
	var spin_axis: Vector3 = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)).normalized()
	if spin_axis.length_squared() < 0.0001:
		spin_axis = Vector3.RIGHT
	_defeated[proxy] = {
		"style": "tumble",
		"age": 0.0,
		"velocity": (direction * knockback_speed + Vector3.UP * upward_impulse) * force,
		"spin": spin_axis * deg_to_rad(tumble_speed * _rng.randf_range(0.75, 1.2) * sqrt(force)),
	}


## Uniform over `defeat_styles`, never the style the last defeated card used.
func _pick_defeat_style() -> String:
	var pool: Array = []
	for style in defeat_styles:
		if style != _last_defeat_style:
			pool.append(style)
	if pool.is_empty():
		pool = Array(defeat_styles) if not defeat_styles.is_empty() else ["tumble"]
	return String(pool[_rng.randi_range(0, pool.size() - 1)])


## The numbers that make a flight a TOSS or a POP. `hang` sharpens the top of the climb (a higher power holds it
## longer); `track` is when the card travels over the board (early for a throw, late for a pop that drops back).
func _flight_profile(style: String) -> Dictionary:
	if style == "pop":
		return {"style": "pop", "keys": POP_PITCH_KEYS, "seconds": pop_seconds, "climb": pop_climb,
			"drift": pop_drift, "peak": pop_peak_at, "swell": pop_swell, "land": pop_land_fraction,
			"yaw": pop_yaw_degrees, "roll": pop_roll_degrees, "rest": pop_rest_seconds, "hang": 3.0,
			"track_late": true, "settle": pop_settle_degrees, "settle_turn": pop_settle_turn_degrees}
	return {"style": "toss", "keys": TOSS_PITCH_KEYS, "seconds": toss_seconds, "climb": toss_climb,
		"drift": toss_drift, "peak": toss_peak_at, "swell": toss_swell, "land": toss_land_fraction,
		"yaw": toss_yaw_degrees, "roll": toss_roll_degrees, "rest": toss_rest_seconds, "hang": 2.0,
		"track_late": false, "settle": 0.0, "settle_turn": 0.0}


## THE TOSS and THE POP: see their exports. Everything is a function of the flight's age (`_toss_pose`), so a frozen
## demo can show any moment and the landing is exact: face up, on the wood, at the chosen spot and turn.
func _start_toss(proxy: Card, direction: Vector3, hit_by: float, home: Vector3, straight: Quaternion,
		rest_scale: Vector3, profile: Dictionary) -> void:
	var dir: Vector3 = Vector3(direction.x, 0.0, direction.z)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.BACK
	var start: Vector3 = proxy.position
	var contact_ground: Vector3 = Vector3(start.x, home.y, start.z)
	var land: Vector3 = home.lerp(contact_ground, float(profile["land"]))
	# A little sideways scatter, so two tosses never land on the same spot.
	var side: Vector3 = Vector3.UP.cross(dir).normalized()
	land += side * _rng.randf_range(-0.12, 0.12)
	var turn_sign: float = -1.0 if _rng.randf() < 0.5 else 1.0
	var force: float = lerpf(0.85, 1.15, hit_by)
	# The top of the climb, relative to the ground track: along the line of sight to the camera, plus a small drift up
	# the screen and to the side the card turns toward. Converted into this node's frame (the proxies' parent).
	var climb_m: float = float(profile["climb"]) * force
	var drift: Vector2 = profile["drift"]
	var climb := Vector3.UP * climb_m
	if _camera != null and is_instance_valid(_camera):
		var cam_basis: Basis = global_basis.inverse() * _camera.global_transform.basis.orthonormalized()
		# UP AND BACK OVER ITS OWN SIDE, never simply "toward the camera". For my card that is the same thing (my side is
		# the camera's side), which is the case the reference shows; for the opponent's card "toward the camera" threw it
		# over MY board. The mix is the board camera's own line of sight (67 degrees), so my card's flight is unchanged.
		# The FAR side's card goes straight UP instead: "up and back" from there runs off the top of the screen (their
		# row is already near the top edge), and straight up reads as rising toward the viewer and stays in view.
		var elevation: float = deg_to_rad(67.0)
		var sight: Vector3 = (Vector3.UP * sin(elevation) + dir * cos(elevation)).normalized()
		var toward_camera: Vector3 = Vector3(cam_basis.z.x, 0.0, cam_basis.z.z)
		var far_side: bool = dir.dot(toward_camera) <= 0.0
		if far_side:
			sight = Vector3.UP
		var card_h: float = 0.6 * absf(proxy.scale.z)
		# "Toward the winner" on screen: the throw direction reversed, flattened into the camera plane. Up the screen
		# for my card, DOWN it for the opponent's (a fixed screen-up drift threw their card off the top edge).
		var toward_winner: Vector3 = -dir - cam_basis.z * (-dir).dot(cam_basis.z)
		toward_winner = toward_winner.normalized() if toward_winner.length_squared() > 0.0001 else cam_basis.y
		var aside: Vector3 = cam_basis.z.cross(toward_winner).normalized()
		# No drift TOWARD the winner for the far side's card: on screen that is down, over the other player's board.
		var winner_drift: float = 0.0 if far_side else drift.x
		climb = sight * climb_m + toward_winner * winner_drift * card_h + aside * drift.y * card_h * turn_sign
		# THE TOP OF THE FLIGHT STAYS ON SCREEN, whatever the camera: the far side's card rising straight up left the top
		# of a closer camera's frame for ~16 frames. Shrink the climb until its peak projects inside the frame.
		var view: Vector2 = get_viewport().get_visible_rect().size
		# The PEAK is the card's centre; at the top of the climb the card is drawn large, so leave room for half of it.
		var margin: float = view.y * 0.18
		for _step in 8:
			var peak_world: Vector3 = global_transform * (start + climb)
			if not _camera.is_position_behind(peak_world):
				var px: Vector2 = _camera.unproject_position(peak_world)
				if px.y > margin and px.y < view.y - margin and px.x > margin and px.x < view.x - margin:
					break
			climb *= 0.8
	# The shadow on the wood would slide off on its own far below the card; it comes back when the card lands.
	if proxy.field_shadow != null and is_instance_valid(proxy.field_shadow):
		proxy.field_shadow.set_active(false)
	_defeated[proxy] = {
		"style": profile["style"],
		"profile": profile,
		"age": 0.0,
		"start": start,
		"land": land,
		"climb": climb,
		"seconds": float(profile["seconds"]),
		# Flip about the world axis that throws the TOP edge (pointing at the winner) up and back over the loser.
		"axis": Vector3.UP.cross(dir).normalized(),
		"dir": dir,
		"straight": straight,
		"start_scale": proxy.scale,
		"rest_scale": rest_scale if rest_scale != Vector3.ZERO else proxy.scale,
		"yaw": deg_to_rad(float(profile["yaw"]) * _rng.randf_range(0.8, 1.15)) * turn_sign,
		"roll": deg_to_rad(float(profile["roll"])) * (-turn_sign),
		"turn_sign": turn_sign,
		"landed": false,
	}
	_toss_pose(proxy, _defeated[proxy], 0.0)


## The flight at fraction u (0..1, clamped); `after` is the time since it landed (the pop's bounce and slow turn).
func _toss_pose(proxy: Card, st: Dictionary, u: float, after: float = 0.0) -> void:
	u = clampf(u, 0.0, 1.0)
	var profile: Dictionary = st["profile"]
	var start: Vector3 = st["start"]
	var land: Vector3 = st["land"]
	var peak: float = float(profile["peak"])
	var hang: float = float(profile["hang"])
	# The climb toward the camera: a fast rise that eases into the top (the card hangs there, big), then an accelerating
	# fall back onto the ground track, which it meets exactly at the landing. A higher `hang` holds the top longer.
	var climb: float
	if u < peak:
		climb = 1.0 - pow(1.0 - u / peak, hang)
	else:
		climb = 1.0 - pow((u - peak) / (1.0 - peak), hang)
	# Ground track, from the contact point (lifted) to the landing spot on the wood: a throw covers most of it early,
	# a pop rises over the clash and drops back late.
	var g: float = pow(u, 1.8) if bool(profile["track_late"]) else 1.0 - pow(1.0 - u, 1.6)
	proxy.position = start.lerp(land, g) + (st["climb"] as Vector3) * climb
	# Rotation: the keyed flip about the throw axis, a roll wobble about the throw direction, and the turn on the board
	# that it lands with. On the wood the pop bounces once on its flip axis and keeps turning slowly.
	var pitch: float = deg_to_rad(_keyed(profile["keys"], u))
	var roll: float = float(st["roll"]) * sin(PI * u) * (1.0 - u * 0.3)
	var yaw: float = float(st["yaw"]) * (u * u * (3.0 - 2.0 * u))
	if after > 0.0:
		pitch += deg_to_rad(float(profile["settle"])) * sin(after * TAU / 0.14) * exp(-after / 0.06)
		yaw += deg_to_rad(float(profile["settle_turn"])) * float(st["turn_sign"]) \
			* (1.0 - exp(-after / maxf(float(profile["rest"]) * 0.5, 0.01)))
	var q: Quaternion = Quaternion(Vector3.UP, yaw) * Quaternion(st["dir"], roll) * Quaternion(st["axis"], pitch) \
		* (st["straight"] as Quaternion)
	proxy.quaternion = q.normalized()
	# Size: back to the resting size quickly (the charge squashed or swelled it), then the swell toward the camera.
	var base: Vector3 = (st["start_scale"] as Vector3).lerp(st["rest_scale"], clampf(u / 0.15, 0.0, 1.0))
	proxy.scale = base * (1.0 + float(profile["swell"]) * climb * (1.0 - smoothstep(0.85, 1.0, u)))


## Monotone-ish smooth interpolation through (u, value) keys: smoothstep inside each span keeps every key exact.
static func _keyed(keys: Array, u: float) -> float:
	if u <= keys[0].x:
		return keys[0].y
	for i in range(1, keys.size()):
		var b: Vector2 = keys[i]
		if u <= b.x:
			var a: Vector2 = keys[i - 1]
			var k: float = (u - a.x) / maxf(b.x - a.x, 0.0001)
			# Blend linear and smoothstep: pure smoothstep stops dead at every key, pure linear kinks.
			var s: float = lerpf(k, k * k * (3.0 - 2.0 * k), 0.5)
			return lerpf(a.y, b.y, s)
	return keys[keys.size() - 1].y


func _process(delta: float) -> void:
	if _defeated.is_empty():
		return
	for proxy in _defeated.keys():
		if proxy == null or not is_instance_valid(proxy):
			_defeated.erase(proxy)
			continue
		var state: Dictionary = _defeated[proxy]
		if state.has("profile"):
			state["age"] = float(state["age"]) + delta
			var flight: float = float(state["seconds"])
			_toss_pose(proxy, state, float(state["age"]) / flight, maxf(0.0, float(state["age"]) - flight))
			if not bool(state["landed"]) and float(state["age"]) >= flight:
				state["landed"] = true
				if proxy.field_shadow != null and is_instance_valid(proxy.field_shadow):
					proxy.field_shadow.set_active(true)
			# On the wood: the beat, then it breaks where it lies.
			if float(state["age"]) >= flight + float(state["profile"]["rest"]):
				_shatter_defeated(proxy, Vector3.ZERO, Vector3.ZERO)
				_defeated.erase(proxy)
			continue
		var velocity: Vector3 = state["velocity"]
		velocity.y -= gravity * delta
		state["velocity"] = velocity
		proxy.position += velocity * delta
		var spin: Vector3 = state["spin"]
		if spin.length_squared() > 0.00001:
			proxy.quaternion = Quaternion(spin.normalized(), spin.length() * delta) * proxy.quaternion
		state["age"] = float(state["age"]) + delta
		if float(state["age"]) >= defeat_seconds:
			_shatter_defeated(proxy, velocity, spin)
			_defeated.erase(proxy)



func _shatter_defeated(proxy: Card, velocity: Vector3, spin: Vector3) -> void:
	var shards := CARD_SHARDS.instantiate()
	# Keep fragments alive after this cinematic releases its visual proxies.
	get_parent().add_child(shards)
	var game_field := get_parent().get_node_or_null("Field") as Node3D
	if game_field != null:
		shards.floor_world_y = game_field.global_position.y
	shards.burst_from_card(proxy, global_basis * velocity, global_basis.orthonormalized() * spin)
	proxy.visible = false


func _impact_flash(point: Vector3) -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(impact_flash_size, impact_flash_size)
	quad.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = HALO_SHADER
	material.set_shader_parameter("halo_color", Color(1.0, 0.86, 0.55, 1.0))
	material.set_shader_parameter("intensity", impact_flash_intensity)
	material.set_shader_parameter("falloff", 2.0)
	material.set_shader_parameter("skirt_amount", 0.8)
	quad.material_override = material
	add_child(quad)
	var basis: Basis = _camera.global_transform.basis if _camera != null else Basis()
	quad.global_transform = Transform3D(basis, point)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(quad, "scale", Vector3.ONE * 1.6, impact_flash_seconds)
	tween.tween_method(func(value: float) -> void:
		material.set_shader_parameter("intensity", value),
		impact_flash_intensity, 0.0, impact_flash_seconds)
	tween.chain().tween_callback(quad.queue_free)


func _shake_camera(strength: float = 0.5) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var amount := camera_shake_strength * lerpf(0.75, 1.5, strength)
	var base: Vector3 = _camera_home.origin
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for _i in range(6):
		var offset := Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)) * amount
		tween.tween_property(_camera, "global_position", base + offset,
			camera_shake_seconds / 7.0)
	tween.tween_property(_camera, "global_position", base,
		camera_shake_seconds / 7.0)


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout


func _cleanup() -> void:
	if _proxy_a != null and is_instance_valid(_proxy_a):
		_proxy_a.queue_free()
	if _proxy_b != null and is_instance_valid(_proxy_b):
		_proxy_b.queue_free()
	_proxy_a = null
	_proxy_b = null
	_defeated.clear()
	if _attacker != null and is_instance_valid(_attacker):
		_attacker.set_hidden(_was_hidden_a and not _survives_a)
		if _survives_a and _attacker.is_drawn_on_field():
			_attacker.global_transform = _snap_a
	if _defender != null and is_instance_valid(_defender):
		_defender.set_hidden(_was_hidden_b and not _survives_b)
		if _survives_b and _defender.is_drawn_on_field():
			_defender.global_transform = _snap_b
	for entry in _strikers:
		if entry.proxy != null and is_instance_valid(entry.proxy):
			entry.proxy.queue_free()
		var card: Card = entry.card if entry.card != null and is_instance_valid(entry.card) else null
		if card != null:
			card.set_hidden(entry.hidden)
			if card.is_drawn_on_field():
				card.global_transform = entry.snap
	_strikers.clear()
	if _camera != null and is_instance_valid(_camera):
		_camera.global_transform = _camera_home
	_camera = null
	_running = false
	finished.emit()
