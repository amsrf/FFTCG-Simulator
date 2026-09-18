extends Node
## Screenshot harness — boots a scene WITH RENDERING, lets it settle, saves a PNG and quits.
##
## WHY IT EXISTS: headless runs use a dummy renderer, so nothing in this project could be checked by eye
## except by launching the game and looking at it. That was the one thing the assistant could not do,
## and it is why so many changes ended with "this part needs your eyes". This closes the loop: the shot
## comes back as a PNG that can be inspected directly, and the editor stays closed exactly as for the
## headless probes.
##
## Run it WITHOUT --headless (a real rendering device is the whole point), with the editor closed:
##
##   godot --resolution 1280x720 res://tools/shot.tscn --quit-after 300 -- \
##       --scene res://crystal_cost.tscn --cost "fire:1,neutral:1" --studio 0 \
##       --out tools/shots/cost_row.png
##
## Options, all after the bare "--":
##   --scene <res>    what to shoot (default res://crystal_cost.tscn)
##   --preset <name>  boot the real GAME through MatchSetup instead (ai / standard / debug)
##   --pay <spec>     with --preset: open the crystal payment modal at that cost, e.g. "火:1,neutral:1",
##                    so a shot can show the payment UI mid-selection without a human clicking
##   --out <path>     PNG to write (default tools/shots/shot.png)
##   --cost <spec>    e.g. "fire:1,neutral:1" — set on the subject if it has a `cost`
##   --element <e>    set on the subject if it has an `element` (a lone badge)
##   --number <n>     set on the subject if it has a `number` (a lone numeral badge)
##   --frames <n>     frames to settle before shooting (default 20)
##   --zoom <f>       framing margin multiplier (default 1.35)
##   --studio <0|1>   studio sky + key light (default 1). 0 gives a flat grey background instead, which
##                    is better for asset shots: the bright sky swallows the pale light-element glyph.
##
## --quit-after is a BACKSTOP only. The harness quits itself as soon as the PNG is written, so a window
## appears for a couple of seconds and closes on its own.

const DEFAULT_SCENE := "res://crystal_cost.tscn"
const DEFAULT_OUT := "tools/shots/shot.png"

var _args: Dictionary = {}

func _ready() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var out: String = str(_args.get("out", DEFAULT_OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))

	var preset: String = str(_args.get("preset", ""))
	if preset != "":
		# The real game: it brings its own camera, environment and lights, so the harness only boots it
		# and waits. MatchSetup is an autoload, which is exactly why this is a scene rather than --script.
		MatchSetup.config = MatchSetup.build_config(preset)
		var game: Node = load("res://game.tscn").instantiate()
		add_child(game)
		# --cam-zoom <f>: multiply the game's camera size (or fov) so a small detail can be inspected at
		# full resolution. With a payment up, the camera also centres on the readout — zooming about the
		# screen centre alone would push a readout that sits low on the screen straight out of frame.
		if _args.has("cam-zoom"):
			await _settle(3)
			var cam: Camera3D = get_viewport().get_camera_3d()
			if cam != null:
				var f: float = float(_args["cam-zoom"])
				if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
					cam.size *= f
				else:
					cam.fov *= f
				# Aim at where the readout WILL be — the hand plus the Assistant's offset — rather than at
				# the readout node itself. Its own _process only places it while it is visible, so reading
				# its position before a payment starts returns the Assistant's origin, and the camera ends
				# up framing whatever happens to be there (in practice: cards).
				var assistant2: Node = game.get_node_or_null("Assistant")
				var hand2: Node3D = game.get_node_or_null("Player/Hand")
				if assistant2 != null and hand2 != null:
					var off: Vector3 = assistant2.get("cost_readout_offset")
					cam.global_position = hand2.global_position + off + cam.global_transform.basis.z * 6.0
		if _args.has("pay"):
			# Open the payment modal at a KNOWN cost by calling the Assistant's own signal handler. Driving
			# real clicks would depend on which card happened to be in hand, and a shot needs to be
			# reproducible. Key spelling: ASCII is safest through a Windows command line, and the badges
			# accept "fire" exactly as readily as "火".
			var cost: Dictionary = {}
			for part in str(_args["pay"]).split(",", false):
				var bits: PackedStringArray = part.split(":", false)
				if bits.size() == 2:
					cost[bits[0].strip_edges()] = int(bits[1].strip_edges())
			var assistant: Node = game.get_node_or_null("Assistant")
			if assistant != null:
				assistant.call("_on_field_card_activated_ability", cost)
				# State what the readout actually contains, rather than inferring it from pixels. A
				# screenshot is good for placement and colour, but a numeral can be lost in a downscaled
				# view — so "is it built but not drawn" and "was it never built" have to be told apart here.
				# Optionally pay part of the cost, so the row can be seen with crystals LIT and not only owed:
				# --charge "fire:1" is one fire source selected. This is the state that matters most — a white
				# crystal turning red and shining — and without input it cannot be reached at all.
				if _args.has("charge"):
					for bits in str(_args["charge"]).split(",", false):
						var pair: PackedStringArray = bits.split(":")
						if pair.size() >= 2:
							assistant.call("charge", int(pair[1].strip_edges()), pair[0].strip_edges())
				var readout: Node = assistant.get("cost_readout")
				if readout != null:
					print("[Shot] readout visible=%s" % readout.visible)
					for c in readout.get_children():
						# Duck-typed, not `is ManaCrystal`: a new class_name is not in Godot's global class
						# cache until the editor rescans it, so naming the class here can fail headlessly even
						# though the script itself loads fine.
						if not c.has_method("colour_now"):
							continue
						print("[Shot]   crystal for='%s' paid_by='%s' lit=%s colour=%s"
							% [str(c.get("element")), str(c.get("paid_element")),
							   str(c.get("lit")), str(c.call("colour_now"))])
	else:
		await _build_subject()

	await _settle(int(_args.get("frames", 20)))
	await _save(out)

func _build_subject() -> void:
	var subject: Node = load(str(_args.get("scene", DEFAULT_SCENE))).instantiate()
	add_child(subject)
	_apply_exports(subject)
	# Wait before measuring: a subject may build its children in a setter (the cost row constructs its
	# badges that way) and camera-facing scripts need a _process to have run.
	await _settle(3)
	_add_environment(str(_args.get("studio", "1")) != "0")
	_add_camera(_bounds(subject), float(_args.get("zoom", 1.35)))

## Sets whichever of the subject's known properties were asked for. Done dynamically so the harness
## needs no knowledge of any particular scene.
func _apply_exports(subject: Node) -> void:
	var spec: String = str(_args.get("cost", ""))
	if not spec.is_empty() and "cost" in subject:
		var cost: Dictionary = {}
		for part in spec.split(",", false):
			var bits: PackedStringArray = part.split(":", false)
			if bits.size() == 2:
				cost[bits[0].strip_edges()] = int(bits[1].strip_edges())
		subject.set("cost", cost)
	if _args.has("element") and "element" in subject:
		subject.set("element", str(_args["element"]))
	if _args.has("number") and "number" in subject:
		subject.set("number", int(_args["number"]))

func _add_environment(studio: bool) -> void:
	var env := Environment.new()
	if studio:
		# The board's own sky, so anything that reflects (the gem button) looks the way it does in play.
		var mat := ProceduralSkyMaterial.new()
		mat.sky_top_color = Color(0.92, 0.95, 1.0)
		mat.sky_horizon_color = Color(0.62, 0.66, 0.72)
		mat.ground_horizon_color = Color(0.30, 0.32, 0.36)
		mat.ground_bottom_color = Color(0.10, 0.11, 0.13)
		var sky := Sky.new()
		sky.sky_material = mat
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.6
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.32, 0.33, 0.36)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.56, 0.60)
		env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	key.light_energy = 1.1
	add_child(key)

## Orthographic, straight down -Z. That straight-on angle matters: a badge and the cost row align
## themselves to whatever camera is current, so this is what shows them face-on, and with the camera
## unrotated their local +x is world +x, which keeps the framing predictable.
func _add_camera(box: AABB, zoom: float) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	cam.size = maxf(0.01, maxf(box.size.y, box.size.x / aspect) * zoom)
	cam.position = box.get_center() + Vector3(0.0, 0.0, maxf(box.size.z, 0.5) + 1.0)
	cam.rotation = Vector3.ZERO
	add_child(cam)
	cam.current = true

## World-space bounds of everything the subject draws: mesh AABBs, plus each Label3D's text box — the
## only way the "Pay" label, which has no mesh at all, gets included in the framing instead of being
## cropped off the left edge.
func _bounds(root: Node) -> AABB:
	var out := AABB()
	var have: bool = false
	for n in _descendants(root):
		var box := AABB()
		var ok: bool = false
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			box = n.global_transform * n.get_aabb()
			ok = true
		elif n is Label3D:
			var l: Label3D = n
			var s: Vector2 = l.font.get_string_size(
				l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size) * l.pixel_size
			var size := Vector3(maxf(s.x, 0.01), maxf(s.y, 0.01), 0.02)
			box = AABB(l.global_position - size * 0.5, size)
			ok = true
		if ok:
			out = box if not have else out.merge(box)
			have = true
	return out if have else AABB(Vector3(-0.2, -0.2, -0.2), Vector3(0.4, 0.4, 0.4))

func _descendants(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_descendants(c))
	return out

func _settle(frames: int) -> void:
	for i in maxi(1, frames):
		await get_tree().process_frame

func _save(out: String) -> void:
	# The viewport's texture is only filled once the frame has actually been drawn.
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(out)
	print("[Shot] wrote %s  %dx%d  err=%d" % [out, img.get_width(), img.get_height(), err])
	get_tree().quit()

## Everything after a bare "--", as key -> value. A flag with nothing after it reads as "1".
func _parse(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < argv.size():
		var a: String = argv[i]
		if a.begins_with("--"):
			var key: String = a.substr(2)
			var val: String = "1"
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				val = argv[i + 1]
				i += 1
			out[key] = val
		i += 1
	return out
