extends Node
## Verifies the gem button's LIGHTING SETUP, MATERIALS, TEXT FIT and — most importantly — that
## swapping it in for BigButton is safe.
##
## The environment was the root cause of the old button never looking like metal: a
## PanoramaSkyMaterial with no panorama reflects black, so nothing metallic could ever shine.
##
## The text-fit checks matter because they are the only way to judge a fit WITHOUT eyes on it: the
## label's measured extents are compared against the button's real face. A font size that fits is
## arithmetic; whether the margin looks nice is not.
##
## Run:  Godot --headless res://tests/button_probe.tscn --quit-after 300

var failures: int = 0

func _expect(ok: bool, what: String) -> void:
	if ok:
		print("[ButtonProbe]  ok  %s" % what)
	else:
		failures += 1
		print("[ButtonProbe] FAIL %s" % what)

## Environment.ReflectionSource.SKY. Spelled as a literal because the constant's name differs
## between Godot versions, while the value the .tscn stores (2) is stable.
const REFLECTION_SOURCE_SKY := 2

const TEXT_QUAD_UNITS := 2.048
const MARGIN_X := 0.10
const MARGIN_Z := 0.14

## Every node path in this scene must also exist in the replacement, because game.tscn's three
## saved instances override properties BY PATH — a missing node silently loses its override.
func _paths(root: Node, prefix: String = "") -> Array[String]:
	var out: Array[String] = []
	for child in root.get_children():
		var here: String = prefix + ("/" if prefix != "" else "") + String(child.name)
		out.append(here)
		out.append_array(_paths(child, here))
	return out

func _ready() -> void:
	print("[ButtonProbe] ---- lighting environment ----")
	var game_scene: PackedScene = load("res://scenes/game/game.tscn")
	_expect(game_scene != null, "game.tscn loads (so the ; comments in it parse)")
	if game_scene != null:
		var game: Node = game_scene.instantiate()
		# Read it without adding it to the tree: nothing has to run for these values to be real.
		var we: WorldEnvironment = game.get_node_or_null("WorldEnvironment")
		_expect(we != null and we.environment != null, "game.tscn has a WorldEnvironment")
		if we != null and we.environment != null:
			var env: Environment = we.environment
			var sky_ok: bool = env.sky != null
			_expect(sky_ok, "the environment has a Sky")
			var mat_ok: bool = sky_ok and env.sky.sky_material is ProceduralSkyMaterial
			_expect(mat_ok,
				"the sky is a ProceduralSkyMaterial (NOT an empty PanoramaSkyMaterial)")
			_expect(env.ambient_light_sky_contribution > 0.0,
				"ambient_light_sky_contribution > 0 (was 0.0, discarding the sky)")
			print("[ButtonProbe] reflected_light_source = %d (2 = Sky)"
				% env.reflected_light_source)
			_expect(env.reflected_light_source == REFLECTION_SOURCE_SKY,
				"reflections come from the Sky")
			if mat_ok:
				var pm: ProceduralSkyMaterial = env.sky.sky_material
				print("[ButtonProbe] sky top %s | horizon %s | ground %s" % [
					pm.sky_top_color, pm.sky_horizon_color, pm.ground_bottom_color])
				# A studio sky is bright overhead and dark underfoot; if those two ever converge the
				# metal loses its top/bottom split and reads flat again.
				var top_lum: float = pm.sky_top_color.get_luminance()
				var ground_lum: float = pm.ground_bottom_color.get_luminance()
				print("[ButtonProbe] luminance: top %.3f | ground %.3f (ratio %.1fx)"
					% [top_lum, ground_lum, top_lum / maxf(ground_lum, 0.001)])
				_expect(top_lum > ground_lum * 5.0,
					"the sky is much brighter above than below (that gradient IS the gloss)")
		game.free()

	print("[ButtonProbe] ---- the preview must represent the game ----")
	var preview: PackedScene = load("res://scenes/previews/GemButtonPreview.tscn")
	_expect(preview != null, "GemButtonPreview.tscn loads")
	if preview != null:
		var pv: Node = preview.instantiate()
		var pwe: WorldEnvironment = pv.get_node_or_null("WorldEnvironment")
		if pwe != null and pwe.environment != null and pwe.environment.sky != null:
			var pmat: ProceduralSkyMaterial = pwe.environment.sky.sky_material
			var gscene: PackedScene = load("res://scenes/game/game.tscn")
			var genv: Environment = null
			if gscene != null:
				var g: Node = gscene.instantiate()
				var gwe: WorldEnvironment = g.get_node_or_null("WorldEnvironment")
				if gwe != null:
					genv = gwe.environment
				g.free()
			if pmat != null and genv != null and genv.sky != null:
				var gmat: ProceduralSkyMaterial = genv.sky.sky_material
				var same: bool = gmat != null and gmat.sky_top_color.is_equal_approx(pmat.sky_top_color)
				_expect(same, "the preview's sky is the same studio sky the game uses")
		var btn_in_preview: Node = pv.get_node_or_null("Button")
		_expect(btn_in_preview != null, "the preview instantiates the real button")
		pv.free()

	print("[ButtonProbe] ---- the button scene ----")
	var gem_scene: PackedScene = load("res://scenes/ui/GemButton.tscn")
	_expect(gem_scene != null, "GemButton.tscn loads")
	if gem_scene != null:
		var gem: Node = gem_scene.instantiate()
		_expect(gem is BigButton, "GemButton is a BigButton (so assistant.gd's typing still holds)")
		var required: Array[String] = [
			"Area3D",
			"Area3D/CollisionShape3D",
			"ButtonTextViewport",
			"ButtonTextViewport/Control",
			"ButtonTextViewport/Control/CenterContainer",
			"ButtonTextViewport/Control/CenterContainer/Label",
			"TextDisplay",
			"Background",
			"Background/MeshInstance3D",
		]
		for path in required:
			_expect(gem.get_node_or_null(path) != null, "has %s" % path)
		var label: Label = gem.get_node_or_null("ButtonTextViewport/Control/CenterContainer/Label")
		_expect(label != null and label.text != "", "the label has text the button can show")
		var holder: MeshInstance3D = gem.get_node_or_null("Background/MeshInstance3D")
		_expect(holder != null and holder.mesh != null,
			"the Background placeholder has a real mesh (an index-check error otherwise)")
		_expect(holder != null and holder.get_surface_override_material(0) == null,
			"the placeholder carries no material, so the shared metal cannot be mutated")
		var model: Node = gem.get_node_or_null("Background/Model")
		_expect(model != null, "has the Model node")
		if model != null:
			model.apply_materials()
			_expect(model.get("frame_material") != null and model.get("stone_material") != null,
				"the model's frame and stone meshes both got their material")
		gem.free()

	print("[ButtonProbe] ---- text fits inside the button (the whole point) ----")
	if gem_scene != null:
		var btn: Node = gem_scene.instantiate()
		# _ready() is called directly rather than by adding the button to the tree: it is the code
		# path under test (BigButton only fitted when set_text() was called, so a button whose text
		# came from the scene kept the scene's size), and calling it here avoids being unable to
		# free an in-tree node at the end of this block.
		btn._ready()
		var b_label: Label = btn.get_node_or_null("ButtonTextViewport/Control/CenterContainer/Label")
		var center: CenterContainer = btn.get_node_or_null("ButtonTextViewport/Control/CenterContainer")
		_expect(b_label != null and center != null, "the label and its CenterContainer exist")
		_expect(center != null
			and is_equal_approx(center.anchor_left, 0.0)
			and is_equal_approx(center.anchor_right, 1.0)
			and is_equal_approx(center.anchor_bottom, 1.0),
			"the text container fills the viewport, so the label is centred")
		if b_label != null and btn.has_method("face_size"):
			# _ready() just fitted it; re-running the fit makes the assertion below explicit.
			btn.set_text(b_label.text)
			var face: Vector2 = btn.face_size()
			var font: Font = b_label.get_theme_font("font")
			var size: int = b_label.get_theme_font_size("font_size")
			var measured: Vector2 = font.get_string_size(b_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
			var line: float = font.get_height(size)
			var px_per_unit: float = float(1024) / TEXT_QUAD_UNITS
			var face_px := Vector2(face.x * px_per_unit, face.y * px_per_unit)
			print("[ButtonProbe] face %.3f x %.3f m (%.0f x %.0f px) | font %d px | text %.0f x %.0f px"
				% [face.x, face.y, face_px.x, face_px.y, size, measured.x, line])
			print("[ButtonProbe] margins available: %.0f px horizontally, %.0f px vertically"
				% [face_px.x - measured.x, face_px.y - line])
			print("[ButtonProbe] the text height is %.0f%% of the button's height"
				% (100.0 * line / face_px.y))
			_expect(measured.x <= face_px.x * (1.0 - 2.0 * MARGIN_X) + 0.5,
				"the text is narrower than the button minus a %.0f%% margin each side"
				% (MARGIN_X * 100.0))
			_expect(line <= face_px.y * (1.0 - 2.0 * MARGIN_Z) + 0.5,
				"the text is shorter than the button minus a %.0f%% margin each side"
				% (MARGIN_Z * 100.0))
			_expect(measured.x < face_px.x * 0.85, "there is real horizontal air, not a tight squeeze")
		btn.free()

	print("[ButtonProbe] ---- face size agrees with the click box (drift check) ----")
	if gem_scene != null:
		var g3: Node = gem_scene.instantiate()
		var shape_node: CollisionShape3D = g3.get_node_or_null("Area3D/CollisionShape3D")
		if shape_node != null and shape_node.shape is BoxShape3D and g3.has_method("face_size"):
			var box: Vector3 = (shape_node.shape as BoxShape3D).size
			var face3: Vector2 = g3.face_size()
			print("[ButtonProbe] collision box %.3f x %.3f x %.3f | face %.3f x %.3f"
				% [box.x, box.y, box.z, face3.x, face3.y])
			_expect(absf(box.x - face3.x) < 0.05 and absf(box.z - face3.y) < 0.05,
				"the click box still matches the model's face (x and z)")
		g3.free()

	print("[ButtonProbe] ---- swap safety: every BigButton path must exist in GemButton ----")
	var old_scene: PackedScene = load("res://scenes/ui/BigButton.tscn")
	if old_scene != null and gem_scene != null:
		var old: Node = old_scene.instantiate()
		var new: Node = gem_scene.instantiate()
		var missing: Array[String] = []
		for path in _paths(old):
			if new.get_node_or_null(NodePath(path)) == null:
				missing.append(path)
		print("[ButtonProbe] BigButton has %d node paths; missing from GemButton: %s"
			% [_paths(old).size(), missing])
		_expect(missing.is_empty(),
			"no node path is lost, so game.tscn's saved instance overrides all still resolve")
		old.free()
		new.free()

	print("[ButtonProbe] ---- the match buttons must fit side by side ----")
	if game_scene != null and gem_scene != null:
		var g4: Node = game_scene.instantiate()
		# They live under Assistant/ButtonRack, not on the root — looking in the wrong place is why
		# this check once reported "not present" while the buttons were sitting right there.
		var names: Array[String] = [
			"Assistant/ButtonRack/ConfirmButton", "Assistant/ButtonRack/CancelButton",
			"Assistant/ButtonRack/PassPhaseButton"]
		var nodes: Array[Node3D] = []
		for n in names:
			var b: Node3D = g4.get_node_or_null(n)
			if b != null:
				nodes.append(b)
		_expect(nodes.size() == 3, "all three match buttons are present (under the rack)")
		# ONE OWNER FOR THE SHARED POSITION. The buttons hold only their slot offset, so the shared
		# x/height cannot drift between them and moving the rack moves all three. This is the
		# structural version of the main-slot rule asserted further down.
		if nodes.size() == 3:
			var rack: Node = nodes[0].get_parent()
			print("[ButtonProbe] the buttons' parent is '%s' at %s" % [rack.name, str(rack.position)])
			_expect(rack.name == "ButtonRack" and nodes[1].get_parent() == rack
				and nodes[2].get_parent() == rack,
				"all three buttons hang off the one ButtonRack that owns their shared position")
		# THE BUTTONS ARE DISCS IN BOARD SOCKETS (DiscButton -> DiscSocket). Confirm and Pass share the one large
		# coin (LocalForward) on purpose, so the layout never jumps when a modal closes; Cancel has its own socket,
		# and the two wells must not overlap. The radius is ASKED OF THE SOCKET, never written here.
		if nodes.size() == 3:
			var sockets: Array[Node3D] = []
			for btn in nodes:
				sockets.append(btn.get_node_or_null(btn.get("socket_path")) as Node3D)
			print("[ButtonProbe] sockets: Confirm %s | Cancel %s | PassPhase %s" % [
				sockets[0].name if sockets[0] else "-", sockets[1].name if sockets[1] else "-",
				sockets[2].name if sockets[2] else "-"])
			_expect(sockets[0] != null and sockets[1] != null and sockets[2] != null,
				"every match button claims a socket on the board")
			if sockets[0] != null and sockets[1] != null and sockets[2] != null:
				_expect(sockets[0] == sockets[2],
					"the pass-phase button shares Confirm's coin, leaving Cancel's socket on its own")
				_expect(sockets[1] != sockets[0], "Cancel keeps a socket of its own")
				var d: float = Vector2(sockets[0].position.x - sockets[1].position.x,
					sockets[0].position.z - sockets[1].position.z).length()
				var reach: float = float(sockets[0].get("radius")) + float(sockets[1].get("radius"))
				print("[ButtonProbe] Confirm/Cancel centres %.3f m apart, radii sum %.3f m" % [d, reach])
				_expect(d > reach, "the Confirm and Cancel wells do not overlap")
		g4.free()

	print("[ButtonProbe] ---- materials ----")
	# The frame is a SHADER now, not a StandardMaterial3D. Reason: a flat mirror reflects exactly one
	# direction, so flat metal under a smooth sky returns a single uniform colour — and uniform reads
	# as plastic. It stays metallic (METALLIC = 1 in the shader, so sky reflections and fresnel still
	# apply) and gains the reference's baked top-to-bottom ramp.
	var frame: ShaderMaterial = load("res://shaders/materials/gem_button_metal.tres")
	_expect(frame != null and frame.shader != null, "gem_button_metal.tres loads with its shader")
	if frame != null and frame.shader != null:
		var metalness: float = float(frame.get_shader_parameter("metalness"))
		var top: Color = frame.get_shader_parameter("metal_top")
		var bottom: Color = frame.get_shader_parameter("metal_bottom")
		var r_top: float = float(frame.get_shader_parameter("roughness_top"))
		var r_bottom: float = float(frame.get_shader_parameter("roughness_bottom"))
		var f_spread: float = float(frame.get_shader_parameter("side_spread"))
		var f_lift: float = float(frame.get_shader_parameter("lift_strength"))
		print("[ButtonProbe] frame: metalness %.2f | top lum %.3f -> bottom lum %.3f | roughness %.2f -> %.2f | side_spread %.2f | lift %.2f"
			% [metalness, top.get_luminance(), bottom.get_luminance(), r_top, r_bottom, f_spread, f_lift])
		_expect(is_equal_approx(metalness, 1.0),
			"the frame is a FULL metal (metalness 1.0) — the old glb exported 0.465")
		# The ramp IS the look. If the two ends ever converge the button goes back to flat plastic.
		_expect(top.get_luminance() > bottom.get_luminance() * 6.0,
			"the frame falls off steeply from a bright top to a nearly black bottom")
		# The falloff is VERTICAL-DOMINANT. The frame spans the whole capsule, so a large side spread
		# would drag its ends down along with the bottom; a low one keeps the ends lit while the bottom
		# still darkens — which is the look being asked for.
		_expect(f_spread > 0.0 and f_spread <= 1.0,
			"the frame's falloff is vertical-dominant, so its ends stay lit as the bottom darkens")
		# Near-black at the bottom is WANTED; PURE black is not. A metal's albedo only tints its
		# reflection, so the one thing that can guarantee a floor is emitted light — hence a small
		# non-zero lift. An earlier version asserted an absolute luminance floor of 0.15, which was
		# correct when the bottom was meant to be a mid grey; the requirement changed.
		_expect(f_lift > 0.0 and f_lift <= 0.1,
			"a small lift keeps the bottom just short of pure black")
		_expect(r_top <= 0.2 and r_bottom <= 0.5 and r_top < r_bottom,
			"the frame is polished at the top and slightly satin toward the bottom")

	var stone: ShaderMaterial = load("res://shaders/materials/gem_button_stone.tres")
	_expect(stone != null and stone.shader != null, "gem_button_stone.tres loads with its shader")
	if stone != null and stone.shader != null:
		var e: float = float(stone.get_shader_parameter("emission_strength"))
		var top: Color = stone.get_shader_parameter("stone_top")
		var deep: Color = stone.get_shader_parameter("stone_deep")
		var grey: float = float(stone.get_shader_parameter("grey_mix"))
		print("[ButtonProbe] stone: emission %.2f | top lum %.3f -> deep lum %.3f | grey_mix %.2f"
			% [e, top.get_luminance(), deep.get_luminance(), grey])
		_expect(e > 0.0, "the stone emits (the reference glow)")
		# The gem IS a vertical ramp — dark bottom, bright top. A radial "bright core" with a wide
		# spread used to cover most of the face, and a UV-driven axis rendered it upside down.
		_expect(top.get_luminance() > deep.get_luminance() * 3.0,
			"the stone's ramp is genuinely bright at the top and dark at the bottom")
		_expect(is_equal_approx(grey, 0.0), "the shipped stone starts lit, not grey")
		# The reference is a COOL TEAL, not a grass green: blue must be close to green and both well
		# above red at the ramp's dark end.
		_expect(deep.b > deep.g * 0.7 and deep.g > deep.r * 4.0,
			"the stone's dark end is a saturated teal, matching the reference rather than a grass green")
		# "Vivid" is the thing being tuned, so it gets numbers rather than an opinion. The BODY stop
		# carries the requirement: it is the colour the gem reads as, and the one that kept coming out
		# too pale. The stops sit deliberately darker than the reference's finished pixels, because the
		# board's ambient, the emission and the specular sheen are all added on top of them.
		var mid: Color = stone.get_shader_parameter("stone_mid")
		var upper: Color = stone.get_shader_parameter("stone_upper")
		var sat: float = float(stone.get_shader_parameter("saturation"))
		var shear: float = float(stone.get_shader_parameter("sheen"))
		print("[ButtonProbe] stone ramp saturation: top %.2f | upper %.2f | mid %.2f | deep %.2f (boost %.2f, sheen %.2f)"
			% [top.s, upper.s, mid.s, deep.s, sat, shear])
		_expect(mid.s > 0.85, "the body colour is a saturated teal, not a pale mint")
		_expect(sat >= 1.0, "saturation pushes colours away from grey rather than washing them out")
		_expect(shear <= 0.5, "the specular is a tight gem highlight, not a broad white sheen")

	print("[ButtonProbe] ---- the ramp axis both shaders assume ----")
	if game_scene != null and gem_scene != null:
		var g8: Node = game_scene.instantiate()
		var cam: Camera3D = g8.get_node_or_null("Camera3D")
		var btn8: Node3D = g8.get_node_or_null("Assistant/ButtonRack/ConfirmButton")
		_expect(cam != null and btn8 != null, "the match has the camera and the confirm button")
		if cam != null and btn8 != null:
			# The shaders ramp along the MESH's +Z. Background adds no rotation, so the mesh's +Z is
			# the button's +Z, and the buttons in game.tscn are unrotated — so it is world +Z. What
			# "top of the button" means on screen is the camera's own up axis (basis.y). This is the
			# assertion that would have caught the upside-down ramp, which came from trusting a UV
			# convention instead: Blender writes V-up and the glTF exporter flips V.
			var screen_up: Vector3 = cam.transform.basis.y.normalized()
			var button_up: Vector3 = btn8.transform.basis.z.normalized()
			var align: float = screen_up.dot(button_up)
			print("[ButtonProbe] camera up %s vs the model's +Z %s -> alignment %+.3f"
				% [str(screen_up), str(button_up), align])
			_expect(align > 0.5,
				"the model's +Z points up on screen — the axis both shaders ramp along")
		# And the ramp's span constant has to match the mesh, or the gradient is compressed: this is
		# the same class of staleness as the Background offset, which went unnoticed for a while.
		if stone != null and btn8 != null:
			var model8: Node = btn8.get_node_or_null("Background/Model")
			if model8 != null and btn8.has_method("_meshes"):
				model8.call("apply_materials")
				var span: float = 0.0
				for m in btn8.call("_meshes", model8):
					if m.get_surface_override_material(0) == null:
						continue
					if m.get_surface_override_material(0).shader == stone.shader:
						span = m.get_aabb().size.z
				var declared: float = float(stone.get_shader_parameter("face_span"))
				print("[ButtonProbe] stone mesh spans %.3f in z; the material declares face_span %.3f"
					% [span, declared])
				# 0.01, not 0.05: the rim's profile change moved this from 0.826 to 0.776, and a 0.05
				# tolerance let that pass before the re-import, when the cached mesh still had the old
				# extent. A tolerance wide enough to hide the error it exists to catch is no guard.
				_expect(span > 0.0 and absf(declared - span) < 0.01,
					"the ramp's face_span matches the stone mesh, so the gradient is not compressed")
		g8.free()

	print("[ButtonProbe] ---- the plate's top face must land on y = 0 ----")
	if gem_scene != null:
		var g7: Node = gem_scene.instantiate()
		if g7.has_method("face_height"):
			var face_y: float = g7.call("face_height")
			print("[ButtonProbe] the model's top face sits at y = %+.4f in the button's space" % face_y)
			_expect(absf(face_y) < 0.005,
				"the top face lands on y = 0 — the contract the text quad is placed against")
		g7.free()

	# (The slide-in and stagger checks went with the floating GemButton: the match buttons are now discs set into
	# the board, whose press/flip motion pass_button_probe covers.)

	print("[ButtonProbe] ---- the board's sky must not be black underfoot ----")
	if game_scene != null:
		var g5: Node = game_scene.instantiate()
		var we5: WorldEnvironment = g5.get_node_or_null("WorldEnvironment")
		if we5 != null and we5.environment != null and we5.environment.sky != null:
			var pm5: ProceduralSkyMaterial = we5.environment.sky.sky_material
			var ground_lum: float = pm5.ground_bottom_color.get_luminance()
			print("[ButtonProbe] sky ground luminance %.3f (was 0.022 — everything facing down mirrored that and went black)"
				% ground_lum)
			_expect(ground_lum > 0.05,
				"the sky's ground is a dark grey, not black, so the button's lower band is not crushed")
		g5.free()

	print("[ButtonProbe] ---- disabled greys the gem, and ONLY the gem ----")
	if gem_scene != null:
		var g6: Node = gem_scene.instantiate()
		var model6: Node = g6.get_node_or_null("Background/Model")
		if model6 != null and g6.has_method("stone_material"):
			# `_model` is an @onready var, so on an instance that was never added to a tree it is
			# still null and every accessor on the button returns null. Point it at the model
			# explicitly — that is all _ready() would have done — so the button's own code paths
			# (rather than a hand-rolled copy of them) are what gets exercised below.
			g6.set("_model", model6)
			model6.apply_materials()
			var frame_before: Material = g6.call("frame_material")
			var gem_before: float = float(g6.call("stone_material").get_shader_parameter("grey_mix"))
			# The state property is set directly: BigButton.set_disabled() also touches its Area3D
			# and starts scale tweens, which need a tree. What is being tested here is the gem —
			# and setting the property runs the same setter the tween would have driven.
			g6.set("_disabled_t", 1.0)
			var gem_after: float = float(g6.call("stone_material").get_shader_parameter("grey_mix"))
			var emission: float = float(g6.call("stone_material").get_shader_parameter("emission_strength"))
			print("[ButtonProbe] stone grey_mix %.2f -> %.2f | emission now %.2f"
				% [gem_before, gem_after, emission])
			_expect(is_equal_approx(gem_before, 0.0) and is_equal_approx(gem_after, 1.0),
				"disabling the button turns the stone grey")
			_expect(emission < 0.2, "the grey stone stops glowing")
			_expect(g6.call("frame_material") == frame_before,
				"the frame is untouched — the gem alone greys, per the design decision")
			# Perception check: the greying must LAND on the resource the button renders with.
			var gem_mesh: MeshInstance3D = null
			for node in g6.call("_meshes", model6):
				if node.get_surface_override_material(0) == g6.call("stone_material"):
					gem_mesh = node
			_expect(gem_mesh != null,
				"the greyed material is the one actually assigned to the stone mesh")
			# And the per-model duplicate is what stops that leaking into the other two buttons.
			var other: Node = gem_scene.instantiate()
			var other_model: Node = other.get_node_or_null("Background/Model")
			if other_model != null:
				other.set("_model", other_model)
				other_model.apply_materials()
				var other_grey: float = float(other.call("stone_material").get_shader_parameter("grey_mix"))
				_expect(is_equal_approx(other_grey, 0.0),
					"a second button's stone is unaffected (materials are duplicated per model)")
			other.free()
		g6.free()

	print("[ButtonProbe] ---- the model ----")
	var glb: PackedScene = load("res://Blender/gem_button.glb")
	_expect(glb != null, "gem_button.glb is imported")

	print("[ButtonProbe] RESULT: %s" % ("all checks passed" if failures == 0 else "%d check(s) FAILED" % failures))
	get_tree().quit()
