extends Node3D
## ONE POWER DOWN, the power-up's mirror: where three red swords RISE out of a powered-up card, here one OBSIDIAN
## sword with a violet edge comes DOWN and STABS it; the flash, sparks and orbs share its violet palette. Spawned by Card.power_fx under the card that lost power, or driven by drain_death_cue.gd on
## a stand-in when the loss is lethal. (The file keeps its "drain" name: the power is still what leaves the card.)
##
##   0.00 s  the sword pops in above the card, point down (the power-up's glyph turned over), born lilac-white, in a
##           bloom of violet mist (the power-up's gas, recoloured).
##   0.12 s  WINDUP: it draws back up a little.
##   0.26 s  STAB: it drives down until its point is in the card's centre; violet streaks fall past it.
##   0.36 s  IMPACT: a mini light explosion at the point - a flash bloom, sparks and a burst of violet mist - and SPLASH_COUNT
##           orbs of light burst out of the card and hop away radially on parabolas, fading as they land. Colour
##           leaves the art in soft blobs (card.gdshader `drain_blobs`) and comes back. NUMBER_START: the readout
##           deflates, turns red and counts down (power_display.animate_power_down). The sword stays in for a beat,
##           then fades.
##
## LETHAL (`lethal = true`): the sword stays in, and the art goes fully cold (`drain_amount`) and stays so - the caller
## (drain_death_cue.gd) turns the card cyan and shatters it at LETHAL_LEAD, and the sword fades as it cracks.
##
## The sword, flash and sparks are laid out in the CAMERA's screen plane in card heights, like power_up_burst.gd; the
## orbs hop in WORLD space (height is world up, outward in the card's own plane). `sample(t)` is deterministic from
## the seed, so a probe or a cue can drive it frame by frame; it frees itself after its lifetime only when it drives
## itself (`set_process`).

const SHADER := preload("res://shaders/power_drain.gdshader")
const SWORD_SHADER := preload("res://shaders/power_up_sword.gdshader")
const POWER_UP_BURST := preload("res://scripts/vfx/power_up_burst.gd")
## The power-up's gas (smoke puffs + streak lines), recoloured violet.
const GAS_SHADER := preload("res://shaders/power_up_gas.gdshader")
const GAS_RIM := Color(0.22, 0.03, 0.38)
const GAS_CORE := Color(0.70, 0.22, 1.0)

## The moment the point goes in. Everything after it is the rupture.
const IMPACT_AT := 0.36
const NUMBER_START := IMPACT_AT
## How long a lethal one runs before the card turns cyan (drain_death_cue.gd).
const LETHAL_LEAD := 0.75

## The sword (card heights, screen plane). Its point sits this far from the quad's centre (the SVG blade tip is at
## y = 8 of 220): turned over, the point is BELOW the centre.
const SWORD_HEIGHT := 0.62
const SWORD_ASPECT := 120.0 / 220.0
const SWORD_TIP := 0.5 - 8.0 / 220.0
const SWORD_APPEAR := 0.12
const WINDUP_AT := 0.12
const STAB_AT := 0.26
## Where the point is: popping in, drawn back, driven in (slightly past the centre).
const TIP_START := 0.62
const TIP_WINDUP := 0.74
const TIP_IN := -0.06
const SWORD_HOLD := 0.22
const SWORD_FADE := 0.20

## The mini light explosion at the impact.
const FLASH_SECONDS := 0.24
const FLASH_SIZE := Vector2(0.25, 1.05)
const SPARK_SECONDS := 0.26
## The orbs: SPLASH_COUNT of them, each hopping SPLASH_DISTANCE out and SPLASH_HEIGHT up over SPLASH_SECONDS.
const SPLASH_COUNT := 6
const SPLASH_SECONDS := 0.60
const SPLASH_DISTANCE := Vector2(0.80, 1.00)
const SPLASH_HEIGHT := Vector2(0.40, 0.55)
const SPLASH_SIZE := 0.26
## The violet mist, mirroring the power-up's red gas: a haze around the sword as it appears, streaks falling with the
## stab, a burst of mist at the impact, and a small puff behind the number as it starts to count.
const HAZE_PUFFS := 9
const IMPACT_PUFFS := 11
const NUMBER_PUFFS := 6
const STREAKS := 6
## A non-lethal one is over this long after it starts (the impact mist is the last thing to clear).
const LIFETIME := IMPACT_AT + 0.95
## Per damage tier (VfxEvent.damage_tier_for of the loss): sparks in the explosion, how much of the art loses colour.
const TIER_SPARKS: Array[int] = [6, 8, 11, 14]
const TIER_BLOBS: Array[float] = [0.55, 0.62, 0.70, 0.78]
const LETHAL_COLD := 0.85

const RENDER_GAS := 18
const RENDER_STREAK := 20
const RENDER_SPARK := 21
const RENDER_ORB := 22
const RENDER_SWORD := 23
const RENDER_FLASH := 24

var lethal := false
var _card: Node3D
var _t := 0.0
var _tier := 0
var _lifetime := LIFETIME
var _seed := 0.0
var _sword: Dictionary = {}
var _flash: Dictionary = {}
var _sparks: Array = []   # {node, mat, angle, reach, size}
var _splashes: Array = [] # {node, mat, angle, distance, height}
var _puffs: Array = []    # {node, mat, start, life, from, drift, size0, size1, peak, at_label}
var _streaks: Array = []  # {node, mat, start, x, y, roll}
## CPU copies of what is drawn, for probes (the headless renderer keeps nothing it can be asked about).
var _tip := TIP_START
var _sword_alpha := 0.0
var _flash_size := 0.0
var _splash_distances: Array = []
var _blobs := 0.0
## The last place the card was: a lethal one outlives its card (the stand-in goes at the shatter).
var _centre := Vector3.ZERO
var _h := 0.0
var _axis_x := Vector3.RIGHT
var _axis_z := Vector3.BACK


func setup(card: Node3D, drain_seed: int, tier: int, is_lethal: bool = false) -> void:
	_card = card
	lethal = is_lethal
	_tier = clampi(tier, 0, TIER_SPARKS.size() - 1)
	_lifetime = maxf(LIFETIME, LETHAL_LEAD + SWORD_FADE + 0.05) if lethal else LIFETIME
	top_level = true
	var rng := RandomNumberGenerator.new()
	rng.seed = drain_seed
	_seed = rng.randf_range(0.0, 20.0)
	var smat := ShaderMaterial.new()
	smat.shader = SWORD_SHADER
	smat.render_priority = RENDER_SWORD
	smat.set_shader_parameter("sword_tex", POWER_UP_BURST.obsidian_sword_texture())
	smat.set_shader_parameter("flash_color", Color(0.93, 0.82, 1.0))
	smat.set_shader_parameter("intensity", 0.0)
	_sword = {"node": _quad("Sword", smat), "mat": smat}
	var fmat := _material(RENDER_FLASH)
	fmat.set_shader_parameter("shape", 1.0)
	_flash = {"node": _quad("Flash", fmat), "mat": fmat}
	var sparks: int = TIER_SPARKS[_tier]
	for i in sparks:
		var mat := _material(RENDER_SPARK)
		mat.set_shader_parameter("shape", 0.0)
		_sparks.append({"node": _quad("Spark", mat), "mat": mat,
			"angle": TAU * float(i) / float(sparks) + rng.randf_range(-0.25, 0.25),
			"reach": rng.randf_range(0.35, 0.60), "size": rng.randf_range(0.030, 0.045)})
	var turn: float = rng.randf() * TAU
	for i in SPLASH_COUNT:
		var mat := _material(RENDER_ORB)
		mat.set_shader_parameter("shape", 1.0)
		_splashes.append({"node": _quad("Splash", mat), "mat": mat,
			"angle": turn + TAU * float(i) / float(SPLASH_COUNT) + rng.randf_range(-0.15, 0.15),
			"distance": rng.randf_range(SPLASH_DISTANCE.x, SPLASH_DISTANCE.y),
			"height": rng.randf_range(SPLASH_HEIGHT.x, SPLASH_HEIGHT.y)})
	_build_gas(rng)
	sample(0.0)


## Puff offsets are screen-plane, in card heights from the card centre (or from the readout, `at_label`).
func _build_gas(rng: RandomNumberGenerator) -> void:
	var sword_centre: float = TIP_START + SWORD_TIP * SWORD_HEIGHT
	for i in HAZE_PUFFS:
		# Around the sword where it pops in, born with it, sinking after it.
		var from := Vector2(rng.randf_range(-0.30, 0.30), sword_centre + rng.randf_range(-0.30, 0.25))
		_add_puff(rng, rng.randf_range(0.0, 0.12), rng.randf_range(0.65, 0.85), from,
			Vector2(from.x * 0.5, -rng.randf_range(0.15, 0.32)),
			rng.randf_range(0.30, 0.42), rng.randf_range(0.65, 0.90), rng.randf_range(0.40, 0.55), false)
	for i in IMPACT_PUFFS:
		# Bursting out of the wound.
		var ang: float = rng.randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		_add_puff(rng, IMPACT_AT + rng.randf_range(0.0, 0.06), rng.randf_range(0.70, 0.85),
			dir * rng.randf_range(0.02, 0.12), dir * rng.randf_range(0.28, 0.48),
			rng.randf_range(0.30, 0.42), rng.randf_range(0.75, 1.05), rng.randf_range(0.45, 0.60), false)
	if not lethal:
		for i in NUMBER_PUFFS:
			var from := Vector2(rng.randf_range(-0.28, 0.28), rng.randf_range(-0.06, 0.08))
			_add_puff(rng, NUMBER_START + 0.04 + rng.randf_range(0.0, 0.10), rng.randf_range(0.70, 0.90), from,
				Vector2(from.x * 0.6, -rng.randf_range(0.08, 0.18)),
				rng.randf_range(0.22, 0.30), rng.randf_range(0.50, 0.70), rng.randf_range(0.40, 0.55), true)
	for i in STREAKS:
		var mat := _gas_material(RENDER_STREAK)
		mat.set_shader_parameter("shape", 1.0)
		_streaks.append({"node": _quad("Streak", mat), "mat": mat, "start": rng.randf_range(0.14, 0.34),
			"x": rng.randf_range(-0.55, 0.55), "y": rng.randf_range(0.35, 1.0),
			"roll": PI + deg_to_rad(rng.randf_range(-14.0, 14.0))})


func _add_puff(rng: RandomNumberGenerator, start: float, life: float, from: Vector2, drift: Vector2,
		size0: float, size1: float, peak: float, at_label: bool) -> void:
	var mat := _gas_material(RENDER_GAS)
	mat.set_shader_parameter("shape", 0.0)
	mat.set_shader_parameter("seed", rng.randf_range(0.0, 50.0))
	_puffs.append({"node": _quad("Gas", mat), "mat": mat, "start": start, "life": life, "from": from,
		"drift": drift, "size0": size0, "size1": size1, "peak": peak, "at_label": at_label})


func _gas_material(priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GAS_SHADER
	mat.render_priority = priority
	mat.set_shader_parameter("rim_color", GAS_RIM)
	mat.set_shader_parameter("core_color", GAS_CORE)
	mat.set_shader_parameter("intensity", 0.0)
	return mat


func puff_count() -> int:
	return _puffs.size()


## Probes: how many mist puffs are showing right now.
func visible_puffs() -> int:
	var n := 0
	for p in _puffs:
		if (p["node"] as MeshInstance3D).visible:
			n += 1
	return n


func elapsed() -> float:
	return _t


func lifetime() -> float:
	return _lifetime


func spark_count() -> int:
	return _sparks.size()


func splash_count() -> int:
	return _splashes.size()


## Probes: where the sword's point is now, screen-up from the card centre in card heights (it ends just past 0).
func sword_tip() -> float:
	return _tip


func sword_alpha() -> float:
	return _sword_alpha


## Probes: the impact flash's diameter right now (card heights; 0 = not there).
func flash_size() -> float:
	return _flash_size


## Probes: each live orb's distance from the card centre in the card's plane, in card heights (they go out).
func visible_splash_distances() -> Array:
	return _splash_distances.duplicate()


func blob_amount() -> float:
	return _blobs


func _process(delta: float) -> void:
	_t += delta
	if _t >= _lifetime or _card == null or not is_instance_valid(_card):
		queue_free()
		return
	sample(_t)


func _exit_tree() -> void:
	# One that ends early (the card left, a newer change superseded it) must not leave the art drained.
	if not lethal:
		_apply_card(0.0, 0.0)


func sample(t: float) -> void:
	_t = t
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	if _card != null and is_instance_valid(_card):
		var face: Vector2 = _card.call("_card_face_size")
		var card_basis: Basis = _card.global_basis
		_h = face.y * card_basis.z.length()
		_axis_x = card_basis.x.normalized()
		_axis_z = card_basis.z.normalized()
		_centre = _card.call("get_global_face_centre") if _card.has_method("get_global_face_centre") \
			else _card.global_position
	elif _h <= 0.0:
		return
	var right: Vector3 = cam.global_basis.x.normalized()
	var up: Vector3 = cam.global_basis.y.normalized()
	var back: Vector3 = cam.global_basis.z.normalized()
	_sample_sword(t, right, up, back)
	_sample_flash(t, right, up, back)
	for s in _sparks:
		_sample_spark(s, t, right, up, back)
	_splash_distances.clear()
	for s in _splashes:
		_sample_splash(s, t, right, up, back)
	var label: Node3D = _card.get("power_label") if _card != null and is_instance_valid(_card) else null
	var label_pos: Vector3 = label.global_position if label != null else _centre - up * _h * 0.6
	for p in _puffs:
		_sample_puff(p, t, label_pos if p["at_label"] else _centre, right, up, back)
	for s in _streaks:
		_sample_streak(s, t, right, up, back)

	var amount: float = TIER_BLOBS[_tier] * smoothstep(IMPACT_AT - 0.02, IMPACT_AT + 0.16, t)
	var cold := 0.0
	if lethal:
		amount = maxf(amount, smoothstep(IMPACT_AT + 0.05, LETHAL_LEAD, t))
		cold = LETHAL_COLD * smoothstep(IMPACT_AT, LETHAL_LEAD, t)
	else:
		amount *= 1.0 - smoothstep(IMPACT_AT + 0.25, IMPACT_AT + 0.70, t)
	_apply_card(amount, cold)


func _sample_sword(t: float, right: Vector3, up: Vector3, back: Vector3) -> void:
	var node: MeshInstance3D = _sword["node"]
	var mat: ShaderMaterial = _sword["mat"]
	var alpha := 1.0
	var flash := 0.0
	var size_k := 1.0
	var tip := TIP_START
	if t < SWORD_APPEAR:
		var u: float = t / SWORD_APPEAR
		size_k = lerpf(0.45, 1.0, POWER_UP_BURST._ease_out_back(u))
		alpha = smoothstep(0.0, 0.6, u)
		flash = 1.0 - u
	elif t < STAB_AT:
		tip = lerpf(TIP_START, TIP_WINDUP, smoothstep(WINDUP_AT, STAB_AT, t))
	elif t < IMPACT_AT:
		# Accelerating all the way in: the stab has no ease-out, it lands.
		var u: float = (t - STAB_AT) / (IMPACT_AT - STAB_AT)
		tip = lerpf(TIP_WINDUP, TIP_IN, u * u)
	else:
		tip = TIP_IN
		flash = maxf(0.0, 1.0 - (t - IMPACT_AT) / 0.10)
		var fade_at: float = LETHAL_LEAD if lethal else IMPACT_AT + SWORD_HOLD
		var e: float = clampf((t - fade_at) / SWORD_FADE, 0.0, 1.0)
		alpha = 1.0 - e * e
		# Fading, it sinks a little further in.
		tip -= 0.06 * e
	_tip = tip
	_sword_alpha = alpha
	if alpha <= 0.001:
		node.visible = false
		return
	node.visible = true
	var height: float = SWORD_HEIGHT * size_k * _h
	var centre_y: float = tip * _h + SWORD_TIP * height
	_place(node, _centre + up * centre_y + back * 0.02 * _h, right, up, back, PI, height * SWORD_ASPECT, height)
	mat.set_shader_parameter("intensity", alpha)
	mat.set_shader_parameter("flash", flash)


func _sample_flash(t: float, right: Vector3, up: Vector3, back: Vector3) -> void:
	var node: MeshInstance3D = _flash["node"]
	var mat: ShaderMaterial = _flash["mat"]
	var k: float = (t - IMPACT_AT) / FLASH_SECONDS
	if k <= 0.0 or k >= 1.0:
		_flash_size = 0.0
		node.visible = false
		return
	node.visible = true
	_flash_size = lerpf(FLASH_SIZE.x, FLASH_SIZE.y, 1.0 - pow(1.0 - k, 3.0))
	_place(node, _centre + back * 0.04 * _h, right, up, back, 0.0, _flash_size * _h, _flash_size * _h)
	mat.set_shader_parameter("intensity", pow(1.0 - k, 1.5))
	mat.set_shader_parameter("flash", 1.0 - k)


func _sample_spark(s: Dictionary, t: float, right: Vector3, up: Vector3, back: Vector3) -> void:
	var node: MeshInstance3D = s["node"]
	var mat: ShaderMaterial = s["mat"]
	var k: float = (t - IMPACT_AT) / SPARK_SECONDS
	if k <= 0.0 or k >= 1.0:
		node.visible = false
		return
	node.visible = true
	var a: float = s["angle"]
	var dir := Vector2(cos(a), sin(a))
	var travel: float = float(s["reach"]) * (1.0 - pow(1.0 - k, 2.0))
	var pos: Vector2 = dir * (0.05 + travel)
	var size: float = float(s["size"])
	# The streak's head (local +Y) points outward.
	_place(node, _centre + (right * pos.x + up * pos.y) * _h + back * 0.03 * _h, right, up, back,
		atan2(-dir.x, dir.y), size * _h, size * (5.0 - 3.0 * k) * _h)
	mat.set_shader_parameter("intensity", 1.0 - smoothstep(0.55, 1.0, k))


func _sample_splash(s: Dictionary, t: float, right: Vector3, up: Vector3, back: Vector3) -> void:
	var node: MeshInstance3D = s["node"]
	var mat: ShaderMaterial = s["mat"]
	var k: float = (t - IMPACT_AT) / SPLASH_SECONDS
	if k <= 0.0 or k >= 1.0:
		node.visible = false
		return
	node.visible = true
	# A true parabola: constant speed outward in the card's plane, a hop in world height that lands on the face.
	var a: float = s["angle"]
	var out: Vector3 = (_axis_x * cos(a) + _axis_z * sin(a)) * float(s["distance"]) * _h * k
	var lift: float = 4.0 * float(s["height"]) * _h * k * (1.0 - k)
	_splash_distances.append(float(s["distance"]) * k)
	var size: float = SPLASH_SIZE * lerpf(1.0, 0.65, k) * _h
	_place(node, _centre + out + Vector3.UP * lift, right, up, back, 0.0, size, size)
	mat.set_shader_parameter("intensity", smoothstep(0.0, 0.06, k) * (1.0 - smoothstep(0.65, 1.0, k)))
	mat.set_shader_parameter("flash", maxf(0.0, 1.0 - k * 4.0))


func _sample_puff(p: Dictionary, t: float, origin: Vector3, right: Vector3, up: Vector3, back: Vector3) -> void:
	var node: MeshInstance3D = p["node"]
	var mat: ShaderMaterial = p["mat"]
	var k: float = (t - float(p["start"])) / float(p["life"])
	if k <= 0.0 or k >= 1.0:
		node.visible = false
		return
	node.visible = true
	var ease_k: float = 1.0 - pow(1.0 - k, 2.0)
	var where: Vector2 = Vector2(p["from"]) + Vector2(p["drift"]) * ease_k
	var size: float = lerpf(float(p["size0"]), float(p["size1"]), ease_k) * _h
	_place(node, origin + (right * where.x + up * where.y) * _h, right, up, back, 0.0, size, size)
	var env: float = smoothstep(0.0, 0.14, k) * pow(1.0 - k, 1.3)
	# Thin over the art (it must tint the card, not paint over it); denser behind the number.
	var gain: float = 1.2 if p["at_label"] else 0.9
	mat.set_shader_parameter("intensity", env * float(p["peak"]) * gain)
	mat.set_shader_parameter("age", k)


## A thin line falling past the sword as it stabs (the power-up's rising streaks, turned over).
func _sample_streak(s: Dictionary, t: float, right: Vector3, up: Vector3, back: Vector3) -> void:
	var node: MeshInstance3D = s["node"]
	var mat: ShaderMaterial = s["mat"]
	var k: float = (t - float(s["start"])) / 0.30
	if k <= 0.0 or k >= 1.0:
		node.visible = false
		return
	node.visible = true
	var roll: float = s["roll"]
	var dir := Vector2(-sin(roll), cos(roll))
	var where: Vector2 = Vector2(s["x"], s["y"]) + dir * k
	_place(node, _centre + (right * where.x + up * where.y) * _h, right, up, back, roll, 0.022 * _h, 0.40 * _h)
	mat.set_shader_parameter("intensity", sin(k * PI) * 0.9)


func _apply_card(amount: float, cold: float) -> void:
	_blobs = amount
	if _card == null or not is_instance_valid(_card):
		return
	var mat: ShaderMaterial = _card.get("mat") as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("drain_blobs", amount)
		mat.set_shader_parameter("drain_seed", _seed)
		mat.set_shader_parameter("drain_amount", cold)


## A camera-facing quad, rolled in the screen plane (+roll turns its up toward screen-left).
func _place(node: MeshInstance3D, pos: Vector3, right: Vector3, up: Vector3, back: Vector3, roll: float,
		width: float, height: float) -> void:
	var r: Vector3 = right * cos(roll) + up * sin(roll)
	var u: Vector3 = up * cos(roll) - right * sin(roll)
	node.global_transform = Transform3D(Basis(r * width, u * height, back), pos)


func _material(priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = priority
	mat.set_shader_parameter("intensity", 0.0)
	return mat


func _quad(node_name: String, mat: ShaderMaterial) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 1.0
	node.visible = false
	add_child(node)
	return node
