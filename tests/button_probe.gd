extends Node
## Verifies the gem button's LIGHTING SETUP, MATERIALS and — most importantly — that swapping it in
## for BigButton is safe.
##
## The environment was the root cause of the old button never looking like metal: a
## PanoramaSkyMaterial with no panorama reflects black, so nothing metallic could ever shine. These
## checks fail loudly if that comes back.
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
	var game_scene: PackedScene = load("res://game.tscn")
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
	var preview: PackedScene = load("res://GemButtonPreview.tscn")
	_expect(preview != null, "GemButtonPreview.tscn loads")
	if preview != null:
		var pv: Node = preview.instantiate()
		var pwe: WorldEnvironment = pv.get_node_or_null("WorldEnvironment")
		if pwe != null and pwe.environment != null and pwe.environment.sky != null:
			var pmat: ProceduralSkyMaterial = pwe.environment.sky.sky_material
			var gscene: PackedScene = load("res://game.tscn")
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
		var btn: Node = pv.get_node_or_null("Button")
		_expect(btn != null, "the preview instantiates the real button")
		pv.free()

	print("[ButtonProbe] ---- the button scene ----")
	var gem_scene: PackedScene = load("res://GemButton.tscn")
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
		# The placeholder must not carry a material: an override would point at the shared
		# gem_button_metal.tres and BigButton's albedo tween would dim every button at once.
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

	print("[ButtonProbe] ---- swap safety: every BigButton path must exist in GemButton ----")
	var old_scene: PackedScene = load("res://BigButton.tscn")
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

	print("[ButtonProbe] ---- materials ----")
	var metal: StandardMaterial3D = load("res://gem_button_metal.tres")
	_expect(metal != null, "gem_button_metal.tres loads")
	if metal != null:
		print("[ButtonProbe] metal: metallic %.2f | roughness %.2f | albedo %s"
			% [metal.metallic, metal.roughness, metal.albedo_color])
		_expect(is_equal_approx(metal.metallic, 1.0),
			"the frame is a FULL metal (metallic 1.0) — the old glb exported 0.465")
		_expect(metal.roughness <= 0.2, "the frame is polished (roughness <= 0.2)")

	var stone: ShaderMaterial = load("res://gem_button_stone.tres")
	_expect(stone != null and stone.shader != null, "gem_button_stone.tres loads with its shader")
	if stone != null and stone.shader != null:
		var e: float = float(stone.get_shader_parameter("emission_strength"))
		print("[ButtonProbe] stone: emission %.2f | roughness %s"
			% [e, str(stone.get_shader_parameter("roughness_value"))])
		_expect(e > 0.0, "the stone emits (the reference glow)")

	print("[ButtonProbe] ---- the model ----")
	var glb: PackedScene = load("res://Blender/gem_button.glb")
	_expect(glb != null, "gem_button.glb is imported")

	print("[ButtonProbe] RESULT: %s" % ("all checks passed" if failures == 0 else "%d check(s) FAILED" % failures))
	get_tree().quit()
