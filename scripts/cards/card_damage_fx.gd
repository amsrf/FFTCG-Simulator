extends RefCounted
## DAMAGE PRESENTATION for one card: the quick recoil on effect damage, and the Earth launch (the card is thrown up
## by a totem and lands back in its slot). Pure presentation — the damage itself is Card.suffer_damage(). Owned by
## Card as `card.damage_fx`.
##
## Both animate the HandMesh rather than the Card root: the Card's transform belongs to the field layout, so animating
## it would fight the board. They share one tween and one "rest pose", which is why they live together.
##
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache, which is
## a parse error on every headless run.

## RECOIL: the card SNAPS up and PITCHES about its BOTTOM edge (the one nearest the camera; ~30-39 deg, the top edge
## swinging up toward the viewer), hangs, FALLS back over ~0.4 s (FALL_SECONDS) and lands flat, then SETTLES on a
## damped bounce hinged on that same bottom edge: the top edge kicks up a few degrees and drops, two or three times,
## each smaller, in ~0.4 s. After landing the card never leaves the board again (no second jump) and never tips the
## other way (the old spring swung past flat, lifting the bottom edge, then lifted the whole card: user: "jumps again").
## The tip pivots on the edge or corner that stays down, so no corner enters the board.
##   SHADING   the face brightens as it turns toward the light (camera side), and flickers as it bounces
##             (card.gdshader `face_light`);
##   SHADOW    a soft board shadow that grows with height.
## Every hit is ROLLED (roll_reaction): first a STYLE (STYLES: which way it tips, how high it jumps, how much it
## turns), never the one the card or the board played last; then each size and timing below is a base that the roll
## varies within its range. So consecutive hits are different MOTIONS, not just different sizes of one motion.
## The snap: seconds from rest to the full jump.
const REACTION_RISE := 0.04
## THE FALL BACK: from the top of the jump to the board takes this long (rolled by VARY_FALL and the style's `fall`).
## A gravity parabola (1 - k^2): it leaves the top at rest (a hang) and speeds up into the board (user: the spring's
## own quarter swing, ~0.25 s, was too fast).
const FALL_SECONDS := 0.42
const VARY_FALL := Vector2(0.9, 1.1)
## THE SETTLE after landing: bounces on the bottom edge. The first kick leaves the board with RESTITUTION of the
## landing speed and lasts BOUNCE_SECONDS; each next kick is BOUNCE_DECAY of the one before. Cut at BOUNCE_CUTOFF of the
## jump, faded to zero over the last REACTION_FADE seconds.
const RESTITUTION := Vector2(0.45, 0.6)
const BOUNCE_SECONDS := 0.18
const VARY_BOUNCE := Vector2(0.9, 1.1)
const BOUNCE_DECAY := 0.35
const BOUNCE_CUTOFF := 0.004
const REACTION_FADE := 0.15
## THE WOBBLE (reaction_wobble): how far the card leans onto one long edge as it comes down, before the style's
## `wobble` multiplier; one rock from side to side takes WOBBLE_SWING_SECONDS and each is WOBBLE_DECAY of the last.
## WOBBLE_YAW turns that much of the roll into an in-plane rattle. Big and slow, and only 3-4 rocks you can see
## (user: "higher amplitude, less frequency, 3 to 4 times max"): 12 -> 6.6 -> 3.6 -> 2 deg, then it is still. It
## ends once a rock would be under WOBBLE_CUTOFF_DEG.
const WOBBLE_DEG := 12.0
const VARY_WOBBLE := Vector2(0.85, 1.15)
const WOBBLE_SWING_SECONDS := 0.15
const VARY_WOBBLE_SWING := Vector2(0.9, 1.1)
const WOBBLE_DECAY := 0.55
const WOBBLE_CUTOFF_DEG := 0.6
const WOBBLE_YAW := 0.3
## Sizes, by damage tier: a LITTLE jump and a big pitch. On this ~67 deg board camera a flat card is 23 deg from facing
## it, so the pitch toward the viewer turns the face square to the camera and a little past (user: "pitch more").
const REACTION_LIFT := [0.16, 0.19, 0.22, 0.25]
const REACTION_PITCH_DEG := [30.0, 33.0, 36.0, 39.0]
const REACTION_YAW_DEG := [3.0, 3.5, 4.0, 4.5]
## Roll ranges (multipliers unless noted).
const VARY_LIFT := Vector2(0.85, 1.15)
const VARY_PITCH_DEG := Vector2(-3.0, 3.0)
const VARY_YAW := Vector2(0.6, 1.4)
## Most hits turn left, a few right.
const YAW_LEFT_CHANCE := 0.7
## THE HIT STYLES. `axis` = where the tip axis points, in degrees about the card's up axis from its local +X (0 = the
## top edge swings up toward the camera about the bottom edge; +-30 = a top CORNER leads, the card hinged on a bottom
## corner; +-65 = mostly a lean onto one side, still hinged low). Every axis stays within 90 deg of 0, so every style
## pivots on the bottom edge or one of its corners. One is picked per hit. `tilt`, `lift`, `yaw` scale the tier's REACTION_* sizes, `rise` is
## the snap's length (a hop rises a little slower, so the jump reads), `fall` scales FALL_SECONDS, `wobble` scales
## WOBBLE_DEG (0 = it lands square and only bounces on its bottom edge). Whatever the axis, the card pivots on the edge
## or corner that stays down (reaction_pose), so no style puts a corner into the board.
const STYLES: Array[Dictionary] = [
	{"name": "tip", "axis": [0.0], "tilt": 1.0, "lift": 1.0, "yaw": 1.0, "rise": 0.04, "fall": 1.0, "wobble": 0.0},
	{"name": "lean", "axis": [65.0, -65.0], "tilt": 0.8, "lift": 0.9, "yaw": 0.6, "rise": 0.045, "fall": 1.0, "wobble": 0.75},
	{"name": "corner", "axis": [30.0, -30.0], "tilt": 1.0, "lift": 1.0, "yaw": 1.3, "rise": 0.045, "fall": 1.0, "wobble": 1.0},
	{"name": "hop", "axis": [0.0], "tilt": 0.45, "lift": 1.35, "yaw": 0.6, "rise": 0.075, "fall": 1.15, "wobble": 1.0},
	{"name": "twist", "axis": [0.0], "tilt": 0.65, "lift": 0.85, "yaw": 3.0, "rise": 0.05, "fall": 0.95, "wobble": 0.7},
]
## The style the board played last: the next hit anywhere avoids it (so a multi-target hit shows several styles).
static var _last_style_on_board: String = ""
## Half the card face in its local units (Card._card_face_size() / 2).
const HALF_FACE := Vector2(0.2145, 0.3)
## Shading: the light sits above, on the camera side and a little to the right; FACE_LIGHT_GAIN turns the change in
## dot(normal, light) into the shader's -1..1 `face_light` (20 deg of tip -> ~+0.15).
const LIGHT_DIR := Vector3(0.35, 0.6, 0.7)
const FACE_LIGHT_GAIN := 0.75
const FACE_LIGHT_LIMIT := 0.3
## The board shadow.
const SHADOW_STRENGTH := 0.65
const SHADOW_SOFTNESS := Vector2(0.012, 0.05)
const SHADOW_MARGIN := 0.12
const SHADOW_DEPTH := 0.002
## Per metre of height: screen-left and toward the camera, so it shows beside the card instead of under it.
const SHADOW_FALL := Vector2(-0.25, 0.45)
const SHADOW_SHADER := preload("res://shaders/card_lift_shadow.gdshader")
## Card children drawn ON the face that are not HandMesh children; they ride with the pose. (Plus the power readout.)
const CHROME_NODES: Array[String] = ["CardEdge", "CostBadge"]

## Earth launch follows gravity and returns exactly to the mesh's resting pose.
const EARTH_LAUNCH_HEIGHTS: Array[float] = [1.0, 1.6, 2.2, 2.9]
const EARTH_LAUNCH_GRAVITY := 9.8
## Whole PITCH turns the thrown card makes in the air, per damage tier. Whole turns, with the spin dying out toward
## touchdown, so it comes down flat on its slot and needs no correction on landing.
const EARTH_LAUNCH_TURNS: Array[int] = [1, 1, 2, 2]
signal earth_landed

## Card is a Node3D; kept untyped so this file and card.gd do not depend on each other's class_name.
var _card: Node3D
## The running recoil OR launch tween. Starting either one stops the other.
var tween: Tween = null
## When the falling card first touches the board, measured from the start of the launch (after any delay).
var earth_contact_seconds := 0.0

## This hit's roll (roll_reaction): sizes, timings and directions; see reaction_pose() for the keys.
var _params: Dictionary = {}
var _far_sign := 1.0
## The style this card played last (it never plays it twice in a row).
var _last_style: String = ""
## Probe/demo hook: the style name the NEXT hit must use ("" = rolled).
var next_style: String = ""
## How far the card is turned from upright about its up axis when the hit starts (radians): its DULL TILT. The hit
## undoes it, so a dulled card is shown STRAIGHT while it is knocked loose and dulled again once it settles.
var _untilt := 0.0
## Presentation-only randomness; never Game.rng, which is reserved for rules.
var _rng := RandomNumberGenerator.new()
var _shadow: MeshInstance3D = null
var _shadow_mat: ShaderMaterial = null
var _chrome_active := false
var _chrome_homes: Dictionary = {}
var _power_home := Transform3D.IDENTITY
var _power_was_visible := false
var _power_hidden := false

func _init(card: Node3D) -> void:
	_card = card
	_rng.randomize()

func is_reacting() -> bool:
	return tween != null and tween.is_valid() and tween.is_running()

## Stop whatever is running and put the mesh back at rest. Called on every zone change.
func normalize() -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	tween = null
	_reset_pose()

## Quick physical recoil on the visible mesh.
func play_reaction(damage: int, delay: float = 0.0) -> void:
	var hand_mesh = _card.hand_mesh
	if damage <= 0 or hand_mesh == null or not _card.is_drawn_on_field():
		return
	var tier: int = VfxEvent.damage_tier_for(damage)
	normalize()
	_params = roll_reaction(tier, _rng.randi(), [_last_style, _last_style_on_board], next_style)
	next_style = ""
	_last_style = _params.style
	_last_style_on_board = _params.style
	_far_sign = _toward_camera_sign()
	_untilt = wrapf(deg_to_rad(_card.rotation_degrees.y - float(_card.get("_upright_y"))), -PI, PI)
	var seconds: float = _params.end
	var t := _card.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_callback(func() -> void: _capture_chrome(false))
	t.tween_method(_set_reaction_pose, 0.0, seconds, seconds)
	t.tween_callback(_finish)
	tween = t

## A STRONG CARD LANDED NEAR THIS ONE (power_entry_burst.gd). KEYED OFF ~/Desktop/Clips/entry 46-57, every frame at
## full size (16.7 ms each):
##   46     at rest
##   47-48  THROWN in one frame: ~35 px up the screen (~0.25 card heights), tipped hard away from the new card (~35
##          degrees: the face squashes to ~85% and the edge facing the blast shows as a dark band). (The reference
##          also turns them 10-20 degrees in the board plane; ours does NOT, see below.)
##   49-52  HELD up there
##   53     down;  54 flat and upright;  55-57 a tiny wobble, still  (ours falls and wobbles longer: see HOP_KEYS_T)
## Each card rolls its own tip direction (away from the new card, wobbled), tip, size and pace from `_rng`, and its
## own cost scales it (cheap cards higher, HOP_COST_SCALE). `strength` 0..1 (distance) scales all of it. Posed on the
## HandMesh + chrome like every reaction here; the Card root (its layout) is never touched.

## The jump's keys, in seconds at pace 1. The SHAPE is the reference's (thrown up tipped, held, down, a little rebound,
## rocks). The speed sits between the reference's (~0.5 s, "too fast") and a 1.4 s version ("too slow"), the user's
## calls on 2026-11-22: up in 0.06 s, hangs ~0.15 s while the tip eases off, falls ~0.2 s accelerating (the keys follow
## a parabola), a small rebound, three rocks edge to edge (~0.09 s each, each smaller), still at ~0.9 s. Values are
## fractions of the rolled amounts; a tilt with no rise is a rock ON the wood (the clearance lifts the centre just
## enough for the low edge to touch).
const HOP_KEYS_T: Array[float] = [0.0, 0.06, 0.13, 0.21, 0.29, 0.36, 0.42, 0.48, 0.53, 0.62, 0.71, 0.80, 0.90]
const HOP_KEYS_RISE: Array[float] = [0.0, 1.0, 0.97, 0.88, 0.70, 0.42, 0.0, 0.06, 0.0, 0.0, 0.0, 0.0, 0.0]
const HOP_KEYS_TILT: Array[float] = [0.0, 1.0, 0.96, 0.88, 0.72, 0.55, 0.40, -0.10, -0.26, 0.16, -0.09, 0.04, 0.0]
## NO TURN IN THE BOARD PLANE (the user, 2026-11-22): a push from underneath cannot spin the card about the vertical,
## so the card only TIPS (about a horizontal axis). An in-plane turn made the throw look wrong.
## Full-strength amounts, measured off the reference.
## A modest tip (the reference's ~35 degrees, with the jump below, left one edge where it was on screen, so the card
## read as LEANING on that edge, never leaving the wood: the user, 2026-11-22).
const HOP_TILT_DEG := 14.0
## The JUMP, in world metres STRAIGHT UP, on top of the clearance the tip needs. NOT along the camera's line of sight:
## a point moved along the line of sight stays on the same pixel, so the low edge never left its spot on screen. Up
## separates the WHOLE card from its shadow (which stays on the wood) and moves it up the screen.
const HOP_HEIGHT := 0.45
const HOP_PUSH := 0.04
## Cost 1 -> x, cost 8+ -> y.
const HOP_COST_SCALE := Vector2(1.25, 0.75)
## Probe hook: the last hop's rolled numbers.
var hop_params: Dictionary = {}

func play_tremor(source: Vector3, strength: float, delay: float = 0.0) -> void:
	var hand_mesh = _card.hand_mesh
	if strength <= 0.0 or hand_mesh == null or not _card.is_drawn_on_field() or is_reacting():
		return
	normalize()
	var away: Vector3 = _card.global_position - source
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.RIGHT
	# Each card tips about its OWN axis: "away from the new card", wobbled by up to 30 degrees.
	var wobble: float = deg_to_rad(_rng.randf_range(-30.0, 30.0))
	var push_dir: Vector3 = away.rotated(Vector3.UP, wobble)
	var inv: Basis = _card.global_basis.orthonormalized().inverse()
	var tip_axis: Vector3 = (inv * Vector3.UP.cross(push_dir)).normalized()
	var up_local: Vector3 = (inv * Vector3.UP).normalized()
	var push_local: Vector3 = (inv * push_dir).normalized()
	var card_scale: float = maxf(_card.global_basis.get_scale().y, 0.0001)
	var cost_total: int = 0
	if _card.has_method("get_cost"):
		for value in _card.get_cost().values():
			cost_total += int(value)
	var weight: float = lerpf(HOP_COST_SCALE.x, HOP_COST_SCALE.y, clampf(float(cost_total - 1) / 7.0, 0.0, 1.0))
	var amount: float = strength * weight
	hop_params = {
		"pace": _rng.randf_range(0.9, 1.15),
		"cost": cost_total,
		"height_m": HOP_HEIGHT * amount * _rng.randf_range(0.85, 1.15),
		"tilt": deg_to_rad(HOP_TILT_DEG) * minf(amount, 1.1) * _rng.randf_range(0.85, 1.15),
		"push": HOP_PUSH * amount / card_scale,
		"wobble": wobble,
	}
	hop_params["height"] = float(hop_params.height_m) / card_scale
	var params: Dictionary = hop_params
	var total: float = HOP_KEYS_T[HOP_KEYS_T.size() - 1] * float(params.pace)
	var t := _card.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_callback(func() -> void: _capture_chrome(false))
	t.tween_method(func(time: float) -> void:
		if not _card.is_drawn_on_field():
			_reset_pose()
			return
		var p: Dictionary = hop_at(time / float(params.pace))
		var tilt: float = float(params.tilt) * float(p.tilt)
		var rot := Basis(tip_axis, tilt)
		# EXACT clearance: how far the rotated face's lowest corner would drop below the wood, nothing more.
		var drop: float = 0.0
		for corner in [Vector3(-HALF_FACE.x, 0, -HALF_FACE.y), Vector3(HALF_FACE.x, 0, -HALF_FACE.y),
				Vector3(HALF_FACE.x, 0, HALF_FACE.y), Vector3(-HALF_FACE.x, 0, HALF_FACE.y)]:
			drop = maxf(drop, -(rot * corner).dot(up_local))
		var push: Vector3 = push_local * float(params.push) * float(p.rise)
		# The JUMP is clear air under the lowest corner: first lift the tipped card until that corner is on the wood,
		# then add the jump straight up ON TOP.
		var base: float = maxf(0.0, drop - push.dot(up_local))
		var jump: Vector3 = up_local * float(params.height) * float(p.rise)
		var offset: Vector3 = push + jump
		var h: float = base
		var pose := Transform3D(rot, up_local * h + offset)
		hand_mesh.transform = pose
		_apply_chrome(pose)
		_set_face_light(face_light_for(pose))
		# ITS SHADOW STAYS ON THE WOOD: the tremor moves the art, not the Card, so the board shadow cannot tell it left
		# the ground; the lift shadow stays behind as it rises.
		var world_h: float = (h + offset.dot(up_local)) * card_scale
		# Soft: a full-strength lift shadow read as a black slab under every airborne card.
		_set_shadow(clampf(float(p.rise), 0.0, 1.0) * 0.45, world_h), 0.0, total, total)
	t.tween_callback(_finish)
	tween = t

## The jump at `time` (seconds at pace 1): `rise` and `tilt` as fractions of the rolled amounts, read off the
## HOP_KEYS_* (smoothstep between keys). Everything is exactly 0 at the last key.
static func hop_at(time: float) -> Dictionary:
	var n: int = HOP_KEYS_T.size()
	if time >= HOP_KEYS_T[n - 1]:
		return {"rise": 0.0, "tilt": 0.0}
	var i: int = 0
	while i < n - 2 and time >= HOP_KEYS_T[i + 1]:
		i += 1
	var k: float = clampf((time - HOP_KEYS_T[i]) / maxf(HOP_KEYS_T[i + 1] - HOP_KEYS_T[i], 0.0001), 0.0, 1.0)
	# Half smoothstep, half linear: pure smoothstep stops dead at every key (a floaty fall, a soft landing).
	var s: float = lerpf(k, k * k * (3.0 - 2.0 * k), 0.5)
	return {
		"rise": lerpf(HOP_KEYS_RISE[i], HOP_KEYS_RISE[i + 1], s),
		"tilt": lerpf(HOP_KEYS_TILT[i], HOP_KEYS_TILT[i + 1], s),
	}

func earth_launch_seconds(damage: int) -> float:
	return sqrt(8.0 * EARTH_LAUNCH_HEIGHTS[VfxEvent.damage_tier_for(damage)] / EARTH_LAUNCH_GRAVITY)

func play_earth_launch(damage: int, seed_value: int = 1, delay: float = 0.0) -> Tween:
	var hand_mesh = _card.hand_mesh
	if hand_mesh == null or not _card.is_drawn_on_field():
		return null
	normalize()
	var duration := earth_launch_seconds(damage)
	var velocity := EARTH_LAUNCH_GRAVITY * duration * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# The card flips end over end (pitch) a whole number of times; a small bounded wavering rides on top. Both fade
	# away before touchdown, preserving the planned landing pose.
	var turns := float(EARTH_LAUNCH_TURNS[VfxEvent.damage_tier_for(damage)]) * (1.0 if rng.randf() < 0.5 else -1.0)
	var frequencies := Vector3(rng.randf_range(5.0, 7.0), rng.randf_range(3.0, 5.0), rng.randf_range(4.0, 6.0))
	var phases := Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
	var excursion := Vector3(rng.randf_range(-0.045, 0.045), 0.0, rng.randf_range(-0.035, 0.035))
	var landing_offset := Vector3(rng.randf_range(-0.006, 0.006), 0.0, rng.randf_range(-0.006, 0.006))
	var landing_tilt := Vector3(rng.randf_range(-0.015, 0.015), rng.randf_range(-0.020, 0.020), rng.randf_range(-0.015, 0.015))
	var card := _card
	var pose_at := func(time: float) -> Transform3D:
		var p := clampf(time / duration, 0.0, 1.0)
		var height := velocity * time - 0.5 * EARTH_LAUNCH_GRAVITY * time * time
		var lateral := excursion * pow(sin(PI * p), 2.0) + landing_offset * smoothstep(0.45, 0.94, p)
		var position_local: Vector3 = card.global_basis.inverse() * (Vector3.UP * height + lateral)
		var envelope := pow(sin(PI * p), 2.0)
		var angles := Vector3(
			sin(time * frequencies.x + phases.x) * deg_to_rad(7.5),
			sin(time * frequencies.y + phases.y) * deg_to_rad(3.0),
			sin(time * frequencies.z + phases.z) * deg_to_rad(6.0)) * envelope
		angles += landing_tilt * smoothstep(0.65, 0.94, p)
		# Spin speed follows 1 - cos: nothing at the launch, fastest at the top of the arc, nothing again at the
		# landing - so the last stretch of the fall is the card arriving flat, not a rotation being stopped.
		var spin := TAU * turns * (p - sin(TAU * p) / TAU)
		var orientation := Basis(Vector3.RIGHT, spin) * Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.UP, angles.y) \
			* Basis(Vector3.BACK, angles.z)
		return Transform3D(orientation, position_local)
	# First corner contact ends the free fall. The centre need not reach zero:
	# a tilted card touches the ground earlier than a flat one.
	var resting_bottom := _earth_lowest_offset(Transform3D.IDENTITY)
	var low := duration * 0.5
	var high := duration + 0.2
	for i in range(1, 81):
		var sample_time := lerpf(duration * 0.5, duration + 0.2, float(i) / 80.0)
		if _earth_lowest_offset(pose_at.call(sample_time)) <= resting_bottom:
			high = sample_time
			break
		low = sample_time
	for _iteration in range(18):
		var middle := (low + high) * 0.5
		if _earth_lowest_offset(pose_at.call(middle)) > resting_bottom:
			low = middle
		else:
			high = middle
	earth_contact_seconds = high
	var contact_pose: Transform3D = pose_at.call(earth_contact_seconds)
	_capture_chrome(true)
	var apply_pose := func(pose: Transform3D) -> void:
		if not card.is_drawn_on_field():
			return
		hand_mesh.transform = pose
		_apply_chrome(pose)
	var t := _card.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_method(func(time: float): apply_pose.call(pose_at.call(time)), 0.0, earth_contact_seconds, earth_contact_seconds)
	t.tween_callback(func(): earth_landed.emit())
	# A small damped rebound and short roll/slide bring a survivor back to its
	# slot after contact, instead of steering it upright while still airborne.
	t.tween_method(func(p: float) -> void:
		var settle := 1.0 - pow(1.0 - p, 3.0)
		var pose := contact_pose.interpolate_with(Transform3D.IDENTITY, settle)
		var penetration := resting_bottom - _earth_lowest_offset(pose)
		pose.origin += card.global_basis.inverse() * Vector3.UP * (maxf(0.0, penetration) + sin(PI * p) * 0.012 * (1.0 - p))
		apply_pose.call(pose)
	, 0.0, 1.0, 0.12)
	t.tween_callback(_finish)
	tween = t
	return t

## The lowest corner of the card face, in world Y, for a given HandMesh pose.
func _earth_lowest_offset(pose: Transform3D) -> float:
	var half: Vector2 = _card._card_face_size() * 0.5
	var lowest := INF
	for corner in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]:
		lowest = minf(lowest, (_card.global_basis * (pose * corner)).y)
	return lowest

## +1 when tipping about the card's local X raises its local -Z edge toward the camera (the local player's cards),
## -1 when the far edge is local +Z (the other seat's cards face the other way).
func _toward_camera_sign() -> float:
	var camera := _card.get_viewport().get_camera_3d() if _card.is_inside_tree() else null
	if camera == null:
		return 1.0
	var top: Vector3 = _card.global_basis * Vector3.FORWARD
	var to_camera: Vector3 = camera.global_position - _card.global_position
	top.y = 0.0
	to_camera.y = 0.0
	return -1.0 if top.dot(to_camera) > 0.0 else 1.0

static func _ease_out(u: float) -> float:
	return 1.0 - (1.0 - u) * (1.0 - u)

static func _smoother(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)

## Rolls one hit: a STYLE (not one of `avoid`, unless `force` names one), then every size and timing varied within
## its range, and the turn's direction. Static and seeded, so a probe can sweep many seeds.
static func roll_reaction(tier: int, seed_value: int, avoid: Array = [], force: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	tier = clampi(tier, 0, REACTION_LIFT.size() - 1)
	var vary := func(range_value: Vector2) -> float: return rng.randf_range(range_value.x, range_value.y)
	var choices: Array[Dictionary] = []
	for entry in STYLES:
		if force != "" and entry.name == force:
			choices.assign([entry])
			break
		if force == "" and not avoid.has(entry.name):
			choices.append(entry)
	if choices.is_empty():
		choices.assign(STYLES)
	var style: Dictionary = choices[rng.randi_range(0, choices.size() - 1)]
	var axes: Array = style.axis
	var axis_deg: float = float(axes[rng.randi_range(0, axes.size() - 1)])
	var yaw_sign := 1.0 if rng.randf() < YAW_LEFT_CHANCE else -1.0
	var fall: float = FALL_SECONDS * float(style.fall) * vary.call(VARY_FALL)
	var rise: float = float(style.rise)
	# The settle: |sin| arches of length `bounce`, each BOUNCE_DECAY of the last; the first leaves the board with
	# RESTITUTION of the landing speed (2 / fall, in jumps per second, from the parabola).
	var bounce: float = BOUNCE_SECONDS * vary.call(VARY_BOUNCE)
	var bounce_w: float = PI / bounce
	var bounce_d: float = log(1.0 / BOUNCE_DECAY) / bounce
	var bounce_amp: float = vary.call(RESTITUTION) * (2.0 / fall) / bounce_w
	# The wobble: which long edge lands first is a coin toss.
	var wobble_sign := 1.0 if rng.randf() < 0.5 else -1.0
	var wobble: float = deg_to_rad(WOBBLE_DEG * float(style.wobble)) * vary.call(VARY_WOBBLE) * wobble_sign
	var swing: float = WOBBLE_SWING_SECONDS * vary.call(VARY_WOBBLE_SWING)
	# The tip axis and the direction that rises under a positive tip (`normal` = up x axis), both in the face plane.
	var axis := Basis(Vector3.UP, deg_to_rad(axis_deg)) * Vector3.RIGHT
	var normal := Vector3.UP.cross(axis)
	return {
		"style": String(style.name),
		"axis_deg": axis_deg,
		"rise": rise,
		"fall": fall,
		"bounce_w": bounce_w,
		"bounce_d": bounce_d,
		"bounce_amp": bounce_amp,
		"wobble": wobble,
		"wobble_w": PI / swing,
		"wobble_d": log(1.0 / WOBBLE_DECAY) / swing,
		"end": rise + fall + maxf(log(maxf(bounce_amp / BOUNCE_CUTOFF, 1.0)) / bounce_d,
			log(maxf(absf(wobble) / deg_to_rad(WOBBLE_CUTOFF_DEG), 1.0)) * swing / log(1.0 / WOBBLE_DECAY)),
		"lift": float(REACTION_LIFT[tier]) * float(style.lift) * vary.call(VARY_LIFT),
		"pitch": (float(REACTION_PITCH_DEG[tier]) + vary.call(VARY_PITCH_DEG)) * float(style.tilt),
		"yaw": float(REACTION_YAW_DEG[tier]) * float(style.yaw) * vary.call(VARY_YAW) * yaw_sign,
		# How far the face's centre is from the edge it pivots on, along `normal` (the shadow's height).
		"reach": absf(normal.x) * HALF_FACE.x + absf(normal.z) * HALF_FACE.y,
	}

## The hit's shape at `t`, 1 at the top of the jump: the snap (0 -> 1 in `rise`), the FALL (1 - k^2 over `fall`), then
## the SETTLE: amp e^(-d b) |sin(w b)|, bounces that never go below 0 (the card never tips the other way), faded to
## exactly 0 at `end`. This drives the TIP; the lift is reaction_lift().
static func reaction_spring(t: float, p: Dictionary) -> float:
	var rise: float = p.rise
	var end: float = p.end
	if t <= 0.0 or t >= end:
		return 0.0
	if t < rise:
		return _ease_out(t / rise)
	var u: float = t - rise
	var fall: float = p.fall
	var value: float
	if u < fall:
		var k: float = u / fall
		value = 1.0 - k * k
	else:
		var b: float = u - fall
		value = float(p.bounce_amp) * exp(-float(p.bounce_d) * b) * absf(sin(float(p.bounce_w) * b))
	return value * (1.0 - smoothstep(end - REACTION_FADE, end, t))

## The whole card's height, 1 at the top of the jump: the snap and the fall, and 0 once it has landed. The settle
## only rocks the card on its bottom edge; it never lifts it off the board again.
static func reaction_lift(t: float, p: Dictionary) -> float:
	if t >= float(p.rise) + float(p.fall):
		return 0.0
	return reaction_spring(t, p)

## THE WOBBLE (radians of roll about the card's long axis; + and - are the two long edges). In the air it leans in to
## `wobble` (0 at the start of the jump, all of it at touchdown), so it comes down on ONE long edge first; from landing
## it rocks side to side, wobble e^(-d b) cos(w b): flat, onto the other edge, back, each rock WOBBLE_DECAY of the last
## (~/Desktop/Clips/damage 83-90: lands on one edge, slaps flat, other edge, first edge, still). 0 for a style without.
static func reaction_wobble(t: float, p: Dictionary) -> float:
	var amp: float = float(p.get("wobble", 0.0))
	var end: float = p.end
	if amp == 0.0 or t <= 0.0 or t >= end:
		return 0.0
	var landed: float = float(p.rise) + float(p.fall)
	var value: float
	if t < landed:
		value = amp * smoothstep(0.0, landed, t)
	else:
		var b: float = t - landed
		value = amp * exp(-float(p.wobble_d) * b) * cos(float(p.wobble_w) * b)
	return value * (1.0 - smoothstep(end - REACTION_FADE, end, t))

## STRAIGHTENING A DULLED CARD for the hit: 0 at rest, 1 by the top of the snap, held through the swings, and back to 0
## over the last UNTILT_RETURN seconds, so the card settles dulled again exactly when the spring stops.
const UNTILT_RETURN := 0.35

static func untilt_weight(t: float, p: Dictionary) -> float:
	var end: float = p.end
	if t <= 0.0 or t >= end:
		return 0.0
	return clampf(t / float(p.rise), 0.0, 1.0) * (1.0 - smoothstep(end - UNTILT_RETURN, end, t))

## The HandMesh pose at `t` for the rolled hit `p`, in the CARD'S LOCAL frame (local +Y is world up; field cards are
## turned half a turn about Y, so never convert this through the card's world basis). `scale` divides the world
## metres into local units. LIFT * YAW * TIP. The lift is reaction_lift() (the jump and fall only); the tip and turn
## follow reaction_spring() (also the settle's bounces), about the style's axis (`axis_deg`), and pivot on the edge or
## corner that stays down: the face's extreme point AGAINST the rising direction, so every other point of the face
## rises (exactly, not just for small angles: a point's height is sin(angle) * its distance along `normal`). The tip is
## never negative, so that is always the bottom edge (or a bottom corner).
##
## `untilt` is the card's dull tilt (radians about its up axis); it is turned back out for the hit (untilt_weight), so a
## dulled card is knocked loose STRAIGHT. The card's own up axis is the board's, so this undoes the tap exactly.
static func reaction_pose(t: float, far_sign: float, p: Dictionary, scale: float = 1.0, untilt: float = 0.0) -> Transform3D:
	var s := reaction_spring(t, p)
	var wobble := reaction_wobble(t, p)
	var straighten := Transform3D(Basis(Vector3.UP, -untilt * untilt_weight(t, p)), Vector3.ZERO)
	if s == 0.0 and wobble == 0.0:
		return straighten
	# ONE rotation: the style's tip plus the side-to-side wobble (a roll about the card's long axis), added as rotation
	# vectors. Turned about the face's extreme point against the side that rises, whichever way the sum points, so the
	# card hinges on its bottom edge, a corner, or the long edge it is rocking on, and no corner enters the board.
	# In the air the tip follows the style's axis; once landed the settle's kicks are on the BOTTOM EDGE only (a diagonal
	# kick would lift one long edge and muddle the side-to-side rocking). s is 0 at touchdown, so the switch is seamless.
	var airborne: bool = t < float(p.rise) + float(p.fall)
	var axis_deg: float = float(p.get("axis_deg", 0.0)) if airborne else 0.0
	var tilt_axis := Basis(Vector3.UP, deg_to_rad(axis_deg)) * Vector3.RIGHT
	var turn := tilt_axis * (deg_to_rad(float(p.pitch)) * s * far_sign) + Vector3.BACK * wobble
	var angle := turn.length()
	var tip := Transform3D.IDENTITY
	if angle > 1e-6:
		var axis := turn / angle
		var normal := Vector3.UP.cross(axis)
		var pivot := Vector3(-_sign0(normal.x) * HALF_FACE.x, 0.0, -_sign0(normal.z) * HALF_FACE.y)
		var tip_basis := Basis(axis, angle)
		tip = Transform3D(tip_basis, pivot - tip_basis * pivot)
	# Positive about world up is counter-clockwise seen from the downward-looking camera: the turn to the left. The
	# wobble rattles it a little in the plane too, alternating with the rocking.
	var yaw := Transform3D(Basis(Vector3.UP, deg_to_rad(float(p.yaw)) * s + wobble * WOBBLE_YAW), Vector3.ZERO)
	var height := float(p.lift) * reaction_lift(t, p) / scale
	return Transform3D(Basis.IDENTITY, Vector3.UP * height) * straighten * yaw * tip

## sign() with a dead zone: an axis exactly along a card edge pivots on that EDGE's midpoint line, not a corner.
static func _sign0(value: float) -> float:
	return 0.0 if absf(value) < 1e-4 else signf(value)

func _set_reaction_pose(seconds: float) -> void:
	var hand_mesh = _card.hand_mesh
	if hand_mesh == null or not is_instance_valid(hand_mesh):
		return
	if not _card.is_drawn_on_field() or _params.is_empty():
		_reset_pose()
		return
	var card_scale: float = maxf(_card.global_basis.get_scale().y, 0.0001)
	var pose := reaction_pose(seconds, _far_sign, _params, card_scale, _untilt)
	hand_mesh.transform = pose
	_apply_chrome(pose)
	_set_face_light(face_light_for(pose))
	var tip: float = deg_to_rad(float(_params.pitch))
	var reach: float = float(_params.get("reach", HALF_FACE.y))
	var height: float = pose.origin.y * card_scale + reach * absf(sin(tip * reaction_spring(seconds, _params)))
	_set_shadow(clampf(height / maxf(float(_params.lift) + reach * sin(tip), 0.001), 0.0, 1.0), height)

## Probe hook: this hit's roll.
func reaction_params() -> Dictionary:
	return _params

## How much this pose turns the face toward (+) or away from (-) the light, as the shader's `face_light`. The light
## is fixed relative to the CAMERA (above, on its side, a little to the right), so it reads the same on both seats.
func face_light_for(pose: Transform3D) -> float:
	var camera := _card.get_viewport().get_camera_3d() if _card.is_inside_tree() else null
	if camera == null:
		return 0.0
	var toward: Vector3 = camera.global_position - _card.global_position
	toward.y = 0.0
	var right: Vector3 = camera.global_basis.x
	right.y = 0.0
	var light: Vector3 = (right.normalized() * LIGHT_DIR.x + Vector3.UP * LIGHT_DIR.y + toward.normalized() * LIGHT_DIR.z).normalized()
	var normal: Vector3 = (_card.global_basis * (pose.basis * Vector3.UP)).normalized()
	return clampf((normal.dot(light) - light.y) * FACE_LIGHT_GAIN, -FACE_LIGHT_LIMIT, FACE_LIGHT_LIMIT)

func _set_face_light(value: float) -> void:
	var material = _card.mat
	if material != null:
		material.set_shader_parameter("face_light", value)

## Probe hook: the face_light currently on the card's material.
func face_light() -> float:
	var material = _card.mat
	if material == null:
		return 0.0
	var value = material.get_shader_parameter("face_light")
	return float(value) if value is float else 0.0

func _apply_chrome(pose: Transform3D) -> void:
	if not _chrome_active:
		return
	for node_name in _chrome_homes:
		var node := _card.get_node_or_null(node_name) as Node3D
		if node != null:
			node.transform = pose * (_chrome_homes[node_name] as Transform3D)
	var power_label = _card.power_label
	if power_label != null and not _power_hidden:
		power_label.transform = pose * _power_home

func _capture_chrome(hide_power: bool) -> void:
	if not _chrome_active:
		_chrome_homes.clear()
		for node_name in CHROME_NODES:
			var node := _card.get_node_or_null(node_name) as Node3D
			if node != null:
				_chrome_homes[node_name] = node.transform
		var power_label = _card.power_label
		_power_home = power_label.transform if power_label != null else Transform3D.IDENTITY
		_power_was_visible = power_label.visible if power_label != null else false
		_chrome_active = true
	if hide_power and _card.power_label != null:
		_card.power_label.visible = false
		_power_hidden = true

## `amount` 0..1 of the peak height; `height` in metres pushes the shadow out from under the card.
func _set_shadow(amount: float, height: float) -> void:
	if amount <= 0.0:
		if _shadow != null and is_instance_valid(_shadow):
			_shadow.visible = false
		return
	_ensure_shadow()
	_shadow.visible = true
	var fall := Vector3.ZERO
	var camera := _card.get_viewport().get_camera_3d()
	if camera != null:
		var right: Vector3 = camera.global_basis.x
		right.y = 0.0
		var toward: Vector3 = camera.global_position - _card.global_position
		toward.y = 0.0
		fall = (right.normalized() * SHADOW_FALL.x + toward.normalized() * SHADOW_FALL.y) * height
	_shadow.position = Vector3(0.0, SHADOW_DEPTH, 0.0) + _card.global_basis.inverse() * fall
	_shadow_mat.set_shader_parameter("strength", SHADOW_STRENGTH * clampf(amount * 1.6, 0.0, 1.0))
	_shadow_mat.set_shader_parameter("softness", lerpf(SHADOW_SOFTNESS.x, SHADOW_SOFTNESS.y, amount))

func _ensure_shadow() -> void:
	if _shadow != null and is_instance_valid(_shadow):
		return
	var face: Vector2 = _card._card_face_size()
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = SHADOW_SHADER
	# Above the board (transparent pass); the opaque card still hides it by depth.
	_shadow_mat.render_priority = 1
	_shadow_mat.set_shader_parameter("card_size", face)
	_shadow_mat.set_shader_parameter("margin", SHADOW_MARGIN)
	var plane := PlaneMesh.new()
	plane.size = face + Vector2.ONE * (2.0 * SHADOW_MARGIN)
	_shadow = MeshInstance3D.new()
	_shadow.name = "LiftShadow"
	_shadow.mesh = plane
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.position = Vector3(0.0, SHADOW_DEPTH, 0.0)
	_shadow.visible = false
	_card.add_child(_shadow)

## Probe hook: the shadow's current strength (0 when hidden or never built).
func shadow_strength() -> float:
	if _shadow == null or not is_instance_valid(_shadow) or not _shadow.visible:
		return 0.0
	var value = _shadow_mat.get_shader_parameter("strength")
	return float(value) if value is float else 0.0

func _finish() -> void:
	tween = null
	_reset_pose()

func _reset_pose() -> void:
	var hand_mesh = _card.hand_mesh
	if hand_mesh == null or not is_instance_valid(hand_mesh):
		return
	hand_mesh.position = Vector3.ZERO
	hand_mesh.rotation = Vector3.ZERO
	hand_mesh.scale = Vector3.ONE
	_set_face_light(0.0)
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.visible = false
	if _chrome_active:
		for node_name in _chrome_homes:
			var node := _card.get_node_or_null(node_name) as Node3D
			if node != null:
				node.transform = _chrome_homes[node_name]
		_chrome_homes.clear()
		var power_label = _card.power_label
		if power_label != null:
			power_label.transform = _power_home
			if _power_hidden:
				power_label.visible = _power_was_visible and _card.current_zone == Card.Zone.FIELD
		_chrome_active = false
		_power_hidden = false
