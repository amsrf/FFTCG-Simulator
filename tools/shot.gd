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
		# --hover-field <index>: open the field's hover preview on a battlefield card so a shot can show it.
		# The preview only appears on hover and a screenshot harness cannot hover, which meant every claim about
		# its rounded corners, its bottom line and where it lands was unverifiable until a person looked — and
		# several of those claims turned out to be wrong in ways no boot could reveal.
		# This drives the SAME entry point the pointer drives, so what it shows is what a player sees.
		if _args.has("hover-field"):
			await _settle(4)
			var hover_field: Node = game.get("field")
			if hover_field == null:
				print("[Shot] no field to hover")
			else:
				var fronts: Array = hover_field.get("front_cards")
				var idx: int = int(_args["hover-field"])
				if idx >= 0 and idx < fronts.size():
					hover_field.call("show_card_preview", fronts[idx])
					await _settle(4)
					print("[Shot] hover preview on '%s' | visible=%s" % [
						fronts[idx].get("card_name"), hover_field.call("preview_visible")])
				else:
					print("[Shot] --hover-field %d is out of range (the board has %d)" % [idx, fronts.size()])
		# --hover-hand <index>: drive the hand's REAL hover so the hovered card's size and fit can be
		# captured without a pointer. Uses the same set_hovered() the mouse does.
		if _args.has("hover-hand"):
			await _settle(3)
			var hand_node: Node = game.get("hand")
			var hand_idx: int = int(_args["hover-hand"])
			var hand_cards: Array = hand_node.get("cards") if hand_node != null else []
			if hand_idx >= 0 and hand_idx < hand_cards.size():
				hand_node.call("set_hovered", hand_cards[hand_idx], true)
				await _settle(8)
				print("[Shot] hand hover on index %d | scale %.2f" % [
					hand_idx, hand_cards[hand_idx].scale.x])
			else:
				print("[Shot] --hover-hand %d is out of range" % hand_idx)
		# --character-stance <index>: drive a real Character drag into its latched cast
		# stance so the pose (screen-facing, -15 deg X, lifted above the fan) can be captured.
		# Add --character-charge to release it and show mana charging.
		if _args.has("character-stance"):
			await _settle(3)
			var stance_hand: Node = game.get("hand")
			var stance_cards: Array = stance_hand.get("cards") if stance_hand != null else []
			var stance_card: Card = null
			var wanted_index: int = int(_args["character-stance"])
			if wanted_index >= 0 and wanted_index < stance_cards.size():
				stance_card = stance_cards[wanted_index]
			else:
				for c in stance_cards:
					if c != null and c.type != "Summon":
						stance_card = c
						break
			if stance_card != null:
				stance_hand.call("begin_character_drag", stance_card)
				stance_card.call("begin_drag")
				var stance_vp: Vector2 = get_viewport().get_visible_rect().size
				var latched: bool = bool(stance_hand.call("update_character_drag", stance_card,
					Vector2(stance_vp.x * 0.5, stance_vp.y * 0.1)))
				print("[Shot] character stance '%s' latched=%s pos=%s basis=%s" % [
					stance_card.card_name, str(latched), str(stance_card.global_position),
					str(stance_card.global_basis)])
				if _args.has("character-charge"):
					stance_card.call("release_drag")
					await _settle(4)
					print("[Shot] character charge started=%s" % str(stance_hand.get("charging_card") != null))
			await _settle(4)
		# --stack-card <id[,id...]>: put real cards on the Stack so the stack presentation can be
		# captured without playing a match. Uses the same add_card_to_tree() the game uses.
		if _args.has("stack-card"):
			await _settle(3)
			var stack_node: Node = game.get("stack")
			var ids: PackedStringArray = str(_args["stack-card"]).split(",", false)
			var added: int = 0
			for id_text in ids:
				var cid: int = int(id_text.strip_edges())
				var c = game.call("create_card", cid, "player")
				if stack_node != null and c != null:
					game.add_child(c)
					stack_node.call("add_card_to_tree", c)
					added += 1
			if stack_node != null:
				stack_node.call("update_card_positions")
			await _settle(10)
			print("[Shot] stack cards added: %d" % added)
		# --opponent-summon <id>: drive one opponent Summon cast so the hand-to-stack flight can
		# be captured without waiting for the AI. Calls the same Hand.charge() the AI uses.
		if _args.has("opponent-summon"):
			await _settle(3)
			var opponent_hand: Node = game.get_node("Opponent/Hand")
			var summon = game.call("create_card", int(_args["opponent-summon"]), "opponent")
			if opponent_hand != null and summon != null:
				opponent_hand.call("add_card", summon)
				opponent_hand.call("stage_cast_card_at_middle", summon)
				await _settle(4)
				var started: bool = bool(opponent_hand.call("charge", summon))
				print("[Shot] opponent summon %d charge=%s" % [
					int(_args["opponent-summon"]), str(started)])
			await _settle(2)
		# --camera <name>: shoot THROUGH a named Camera3D in the scene instead of whichever one happens to be
		# active. Installing a camera means answering "what will it actually see", and the honest way to answer
		# that is to look through the candidate rather than to reason about its transform.
		#
		# Note game.tscn marks NEITHER of its two cameras `current`, so Godot activates the first in the tree and
		# the second is inert. Setting `current` is also what makes a candidate switchable live in the running
		# game from the editor's Remote tab, which is the fastest way to dial one in.
		if _args.has("camera"):
			await _settle(3)
			var wanted: String = str(_args["camera"])
			var chosen: Camera3D = game.find_child(wanted, true, false) as Camera3D
			if chosen == null:
				print("[Shot] --camera '%s' not found in the scene" % wanted)
			else:
				chosen.current = true
				await _settle(2)
				print("[Shot] shooting through '%s' | projection=%s size=%.3f fov=%.1f pos=%s" % [
					chosen.name,
					"orthographic" if chosen.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective",
					chosen.size, chosen.fov, str(chosen.global_position)])
		# --proj perspective: replace the board camera's framing with a perspective candidate WITHOUT
		# touching the scene, so composition can be judged before the hand/layout migration lands.
		#   --elev <deg>          camera elevation above the board (default 60)
		#   --fov <deg>           vertical field of view (default 32)
		#   --frame <metres>      visible width at the board centre (default 7.2)
		#   --target-y/z <m>      look-at point on the board (default 0.35 / -0.25)
		#   --hide-hands 1        hide both hand fans, which are still ortho-only and would mislead the shot
		if _args.has("proj"):
			await _settle(3)
			var pv: Camera3D = get_viewport().get_camera_3d()
			if pv != null:
				var elev: float = deg_to_rad(float(_args.get("elev", "60")))
				var pfov: float = float(_args.get("fov", "32"))
				var frame_w: float = float(_args.get("frame", "7.2"))
				var focus := Vector3(0.0, float(_args.get("target-y", "0.35")),
					float(_args.get("target-z", "-0.25")))
				var vp2: Vector2 = get_viewport().get_visible_rect().size
				var aspect2: float = vp2.x / maxf(vp2.y, 1.0)
				var dist: float = frame_w / (2.0 * aspect2 * tan(deg_to_rad(pfov) * 0.5))
				pv.projection = Camera3D.PROJECTION_PERSPECTIVE
				pv.keep_aspect = Camera3D.KEEP_HEIGHT
				pv.fov = pfov
				pv.global_position = focus + Vector3(0.0, dist * sin(elev), -dist * cos(elev))
				pv.look_at(focus, Vector3.UP)
				if str(_args.get("hide-hands", "0")) == "1":
					for path in ["Player/Hand", "Opponent/Hand"]:
						var h: Node3D = game.get_node_or_null(path) as Node3D
						if h != null:
							h.visible = false
				for path in ["Player/Hand", "Opponent/Hand"]:
					var fan: Node = game.get_node_or_null(path)
					if fan != null and fan.has_method("update_card_positions"):
						fan.call("update_card_positions")
				await _settle(2)
				print("[Shot] perspective candidate | elev=%.1f fov=%.1f frame=%.2f m | pos=%s | d=%.2f m" % [
					rad_to_deg(elev), pfov, frame_w, str(pv.global_position), dist])
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
				# --commit: FINISH the payment, so code that runs only when the mana is actually spent can be
				# reached at all. Selecting sources is not enough — the crystal row shatters on commit, and
				# without this the harness could not see that path even exist.
				if _args.has("commit"):
					assistant.call("on_charge_complete")
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

	# --seconds <t>: wait REAL seconds before shooting. `--frames` counts engine FRAMES, and this harness runs
	# uncapped — so its frames are a few milliseconds each and "20 frames" is not a fifth of a second. Anything
	# time-based (a burst in flight, a tween, a rotation) needs this to be reproducible, and without it such things
	# could only be described rather than shown.
	if _args.has("seconds"):
		await get_tree().create_timer(float(_args["seconds"])).timeout
	await _settle(int(_args.get("frames", 20)))
	await _save(out)

func _build_subject() -> void:
	var subject: Node = load(str(_args.get("scene", DEFAULT_SCENE))).instantiate()
	add_child(subject)
	_apply_exports(subject)
	# Wait before measuring: a subject may build its children in a setter (the cost row constructs its
	# badges that way) and camera-facing scripts need a _process to have run.
	await _settle(3)
	# --as-scene: leave the subject's OWN camera and environment alone, so the shot is exactly what pressing F6 on
	# that scene shows.
	#
	# Without it the harness adds its own studio sky and framing camera, which is right for asset shots and
	# misleading for a preview: a scene can render perfectly here and still be a blank grey window in the editor,
	# because the harness was supplying the two things the scene itself was missing. That is exactly how
	# CrystalShardsPreview.tscn shipped broken — verified with a camera and a sky it did not own.
	if str(_args.get("as-scene", "0")) == "1":
		print("[Shot] --as-scene: keeping the subject's own camera and environment")
	else:
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
