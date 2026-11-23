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
##       --scene res://scenes/ui/crystal_cost.tscn --cost "fire:1,neutral:1" --studio 0 \
##       --out tools/shots/cost_row.png
##
## Options, all after the bare "--":
##   --scene <res>    what to shoot (default res://scenes/ui/crystal_cost.tscn)
##   --field-card <id[,id...]>  render actual field cards in isolation
##   --field-columns <n>       wrap the field-card preview into a grid
##   --preset <name>  boot the real GAME through MatchSetup instead (ai / standard / debug)
##   --pay <spec>     with --preset: open the crystal payment modal at that cost, e.g. "火:1,neutral:1",
##                    so a shot can show the payment UI mid-selection without a human clicking
##   --phase <name>   with --preset: turn both phase dials to that phase
##   --frame-width <m>  with --preset: board camera frame width (zoom out = larger; default 8.0)
##   --elevation <deg>  with --preset: board camera elevation (90 = straight down; default 67)
##   --fov <deg>      with --preset: board camera lens (default 30; frame width is kept, so only perspective changes)
##   --hold <i>       with --preset: hold hand card i in the cast stance (--armed 0 = pointer over the hand band)
##   --stack-card <ids>  put cards on the Stack in order (oldest first); "o:<id>" = an opponent's card
##   --badge <id>     with --preset: click my field card <id>; a single ability shows its badge
##   --activate <id>  with --preset: activate my field card <id>'s ability as a click does, printing its pose per frame
##   --raise <id>[:flash]  with --preset: raise my field card <id> as while paying for its ability (":flash" = at the flash)
##   --damage <n>     with --preset: put n cards straight into both damage zones (checks a long row's reach)
##   --hit <n>        with --preset: real damage to me (--opponent-hit <n>: to them); the reveal, zoom and absorb
##   --life-break <n> with --preset: n more damage on MY side, broken by the life crown with its animation (use --seconds)
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

const DEFAULT_SCENE := "res://scenes/ui/crystal_cost.tscn"
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
		var game: Node = load("res://scenes/game/game.tscn").instantiate()
		# --frame-width <m>: the board camera's visible width (BoardCameraRig.frame_width, default 8.0).
		# Set before add_child so the rig's _ready() and every layout that reads the camera see it.
		if _args.has("frame-width"):
			var rig: Node = game.get_node_or_null("Camera3D")
			if rig != null:
				rig.set("frame_width", float(_args["frame-width"]))
		if _args.has("elevation"):
			var rig_e: Node = game.get_node_or_null("Camera3D")
			if rig_e != null:
				rig_e.set("elevation_deg", float(_args["elevation"]))
		if _args.has("fov"):
			var rig_f: Node = game.get_node_or_null("Camera3D")
			if rig_f != null:
				rig_f.set("fov_deg", float(_args["fov"]))
		add_child(game)
		if _args.has("hover-priority"):
			await get_tree().create_timer(1.0).timeout
			game.assistant.passPhaseButton._on_hover(true)
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
		# --damage <n>: put n cards straight into BOTH damage zones (no flight, no zoom), so a shot can check what a long
		# damage row reaches, e.g. the stack beside the opponent's row.
		if _args.has("damage"):
			await _settle(3)
			for side_name in ["Player", "Opponent"]:
				var zone: Node = game.get_node_or_null(side_name + "/DamageZone")
				if zone == null:
					continue
				for i in range(int(_args["damage"])):
					var dc = game.call("create_card", 101 + i, "player" if side_name == "Player" else "opponent")
					if dc != null:
						game.add_child(dc)
						zone.call("add_card_to_tree", dc)
				zone.call("update_card_positions")
			await _settle(30)
		# --life-break <n>: put n more cards into MY damage zone and let the life crown break them with its animation
		# (no zoom), so `--seconds` can catch a crystal mid-burst. `--life-break 6 --seconds 3` = only the centre left.
		if _args.has("life-break"):
			await _settle(3)
			var lzone: Node = game.get_node_or_null("Player/DamageZone")
			for i in range(int(_args["life-break"])):
				var lc = game.call("create_card", 151 + i, "player")
				if lc != null and lzone != null:
					game.add_child(lc)
					lzone.call("add_card_to_tree", lc)
			if lzone != null:
				lzone.call("update_card_positions")
			var crown = game.get("life_crown")
			if crown != null:
				crown.sync(true)
		# --hit <n> / --opponent-hit <n>: REAL damage (PlayerSide.take_damage): the reveal, the zoom, then the card flying
		# into its life crystal. Pair with --seconds to catch a moment.
		if _args.has("hit") or _args.has("opponent-hit"):
			await _settle(3)
			var hit_side = game.get("player") if _args.has("hit") else game.get("opponent")
			hit_side.take_damage(int(_args.get("hit", _args.get("opponent-hit", 1))))
		# --stack-card <id[,id...]>: put real cards on the Stack so the stack presentation can be
		# captured without playing a match. Uses the same add_card_to_tree() the game uses.
		if _args.has("stack-card"):
			await _settle(3)
			var stack_node: Node = game.get("stack")
			var ids: PackedStringArray = str(_args["stack-card"]).split(",", false)
			var added: int = 0
			for id_text in ids:
				# "o:<id>" puts an OPPONENT's card on the stack (the chain layout puts the two sides in different columns).
				var spec := id_text.strip_edges()
				var who := "opponent" if spec.begins_with("o:") else "player"
				var cid: int = int(spec.trim_prefix("o:"))
				var c = game.call("create_card", cid, who)
				if stack_node != null and c != null:
					game.add_child(c)
					stack_node.call("add_card_to_tree", c)
					added += 1
			if stack_node != null:
				stack_node.call("update_card_positions")
			await _settle(10)
			print("[Shot] stack cards added: %d" % added)
			# The top card's face corners on screen, to compare its size, lean and perspective with a reference frame.
			var stack_cards: Array = stack_node.get("cards") if stack_node != null else []
			if not stack_cards.is_empty():
				await get_tree().create_timer(0.5).timeout   # the 0.3 s layout tween must have landed
				var top_card = stack_cards.back()
				var face: Vector2 = top_card.call("_card_face_size")
				var cam: Camera3D = get_viewport().get_camera_3d()
				var corners := []
				for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
					corners.append(cam.unproject_position(top_card.to_global(Vector3(c.x * face.x, 0, c.z * face.y) * 0.5)))
				print("[Shot] stack top corners (screen px): %s" % str(corners))
		# --activate <id>: click-activate my field card <id>'s ability (Field.begin_skill_activation, as a click does) and
		# print its rotation / lift for a second, to watch the activation pose on the real path.
		if _args.has("activate"):
			await _settle(3)
			var act_id: int = int(_args["activate"])
			for fc in game.get_node("Field").call("get_all_cards"):
				if fc.id == act_id and fc.controller == "player":
					game.get_node("Field").call("begin_skill_activation", fc, -1)
					for f in range(40):
						await get_tree().process_frame
						if f % 4 == 0:
							print("[Shot] f%02d rot %s up %s lift %.2f tapped %s" % [f, str(fc.rotation_degrees.snapped(Vector3.ONE * 0.1)),
								str(fc.global_basis.y.normalized().snapped(Vector3.ONE * 0.01)), fc.activation_fx.lift_amount(), str(fc.tapped)])
					break
		# --badge <id>: click my field card <id> as a player would (Field.try_activate_from_field): one ability shows its badge.
		if _args.has("badge"):
			await _settle(3)
			for fc in game.get_node("Field").call("get_all_cards"):
				if fc.id == int(_args["badge"]) and fc.controller == "player":
					game.get_node("Field").call("try_activate_from_field", fc)
					break
			await _settle(4)
			var shown = game.get_node("Field").call("ability_badge")
			print("[Shot] badge: %s" % (str(shown.call("plate_rect")) + " " + str(shown.call("shown_text")) if shown != null else "none"))
		# --raise <id>[:flash]: raise the local player's field card <id> as while its ability is being paid for
		# (card_activation_fx.gd); ":flash" shoots it at the flash's peak instead.
		if _args.has("raise"):
			await _settle(3)
			var spec := str(_args["raise"])
			var raise_id: int = int(spec.get_slice(":", 0))
			for fc in game.get_node("Field").call("get_all_cards"):
				if fc.id == raise_id and fc.controller == "player":
					if spec.ends_with(":flash"):
						await fc.activation_fx.flash()
					else:
						fc.activation_fx.raise()
						await get_tree().create_timer(0.4).timeout
					break
		# --local-summon <id>: MY Summon, staged and committed as tools/opponent_summon_demo.gd does (the printed card's
		# fade, then the stack card's flight). With --film <dir> every frame is saved from the commit on.
		if _args.has("local-summon"):
			await _settle(3)
			var local_hand: Node = game.get_node("Player/Hand")
			var stack_node: Node = game.get_node("Stack")
			var mine = game.call("create_card", int(_args["local-summon"]), "player")
			local_hand.call("add_card", mine)
			local_hand.call("set_hovered", mine, true)
			local_hand.call("begin_character_drag", mine)
			var view: Vector2 = get_viewport().get_visible_rect().size
			local_hand.set("_character_drag_start_pointer_y", view.y * 0.95)
			local_hand.call("update_character_drag", mine, view * Vector2(0.5, 0.6))
			local_hand.call("remove_card", mine)
			local_hand.set("charging_card", mine)
			stack_node.call("_on_hand_charge_start", mine)
			local_hand.call("begin_character_charge", mine)
			await _settle(30)
			stack_node.call("_commit_summon_to_stack")
			if _args.has("film"):
				var local_dir: String = str(_args["film"])
				DirAccess.make_dir_recursive_absolute(local_dir)
				for n in int(_args.get("film-frames", 60)):
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [local_dir, n])
				print("[Shot] filmed %s" % local_dir)
		# --water-draw <id>: a Water card's effect makes its controller draw 1 (Game.draw_cards with that source), so
		# the deck-top splash (water_splash.gd) can be filmed. Add --water-seat 2 for the opponent's deck.
		if _args.has("water-draw"):
			await _settle(3)
			var seat: int = int(_args.get("water-seat", 1))
			var water_src = game.call("create_card", int(_args["water-draw"]), "player" if seat == 1 else "opponent")
			game.add_child(water_src)
			water_src.visible = false
			var ctx = preload("res://scripts/effects/effect_context.gd").new(game, water_src, "shot")
			ctx.draw(seat, 1)
			if _args.has("film"):
				var water_dir: String = str(_args["film"])
				DirAccess.make_dir_recursive_absolute(water_dir)
				for n in int(_args.get("film-frames", 60)):
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [water_dir, n])
				print("[Shot] filmed %s" % water_dir)
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
				# Commit it as a paid cast (as tools/opponent_summon_demo.gd does): charging alone leaves it waiting
				# face down in the hand for a payment nobody makes, so the flight never starts.
				if started:
					game.get_node("Stack").call("_commit_summon_to_stack")
					# --film <dir>: save every frame of the flight (use --fixed-fps 60, so frame n is n/60 s).
					if _args.has("film"):
						var film_dir: String = str(_args["film"])
						DirAccess.make_dir_recursive_absolute(film_dir)
						for n in int(_args.get("film-frames", 60)):
							await RenderingServer.frame_post_draw
							get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [film_dir, n])
						print("[Shot] filmed %s" % film_dir)
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
		# --opponent-coin: raise the opponent's priority coin (as when they hold priority) so its face shows.
		if _args.has("opponent-coin"):
			await _settle(3)
			game.get_node("Assistant/ButtonStations").set_opponent_priority(true)
			# --opponent-flip <s>: once it is up, take their priority away and shoot <s> seconds into the turn.
			if _args.has("opponent-flip"):
				await get_tree().create_timer(2.0).timeout
				game.get_node("Assistant/ButtonStations").set_opponent_priority(false)
				await get_tree().create_timer(float(_args["opponent-flip"])).timeout
			if _args.has("opponent-hover"):
				await _settle(30)
				game.get_node("Assistant/ButtonStations/OpponentForward").set_hovered(true)
		# --focus x,y,z [--focus-dist d] [--focus-fov f]: keep the board camera's direction but frame a close-up
		# of that world point (a board fixture such as a coin, at full resolution).
		if _args.has("focus"):
			await _settle(3)
			var fcam: Camera3D = get_viewport().get_camera_3d()
			var xyz: PackedStringArray = str(_args["focus"]).split(",")
			var point := Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
			fcam.global_position = point + fcam.global_transform.basis.z * float(_args.get("focus-dist", 2.0))
			fcam.fov = float(_args.get("focus-fov", 30.0))
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
							   str(c.get("lit")), str(c.call("display_colour") if c.has_method("display_colour") else c.call("colour_now"))])
		# --phase <GlobalVariables.Phase name>: turn both phase dials' pointers there; add --seconds to catch the turn.
		if _args.has("phase"):
			await _settle(3)
			game.get_node("Assistant/ButtonStations").show_phase(GlobalVariables.Phase[str(_args["phase"])])
		# --hold <hand index>: press and hold that hand card into the cast stance, with the pointer over the wood
		# (--armed 1, default) or over the hand band (--armed 0), so the landing-slot ghost and the slab rim can be
		# seen without a human holding the mouse. Driven through the Hand's own drag entry points, like drop_area_probe.
		if _args.has("hold"):
			await _settle(3)
			var hand3 = game.get_node_or_null("Player/Hand")
			var idx: int = int(_args["hold"])
			if hand3 != null and idx < hand3.cards.size():
				var held: Card = hand3.cards[idx]
				var vp: Vector2 = get_viewport().get_visible_rect().size
				var pointer := Vector2(vp.x * 0.5, vp.y * 0.95)
				if str(_args.get("armed", "1")) != "0":
					pointer = get_viewport().get_camera_3d().unproject_position(Vector3(0.0, 0.065, -0.6))
				# No held.begin_drag(): with no mouse button down the card's own drag would release at once.
				hand3.begin_character_drag(held, vp.y * 0.95)
				hand3.update_character_drag(held, hand3._character_drag_start_pointer)
				hand3._update_character_hold(Hand.HOLD_SECONDS)
				hand3._update_character_hold(Hand.STANCE_SECONDS)
				hand3.update_character_drag(held, pointer)
				var ghost = hand3.slot_ghost()
				print("[Shot] held %s (%s) armed=%s ghost=%s" % [held.card_name, held.type, hand3.cast_armed(),
					("showing at %s" % str(ghost.global_position)) if ghost != null and ghost.is_showing() else "none"])
	elif _args.has("field-card"):
		_build_field_cards(str(_args["field-card"]).split(",", false))
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

func _build_field_cards(ids: PackedStringArray) -> void:
	const CARD_SCENE := preload("res://scenes/cards/card.tscn")
	const FIELD_SHADOW := preload("res://scripts/cards/card_field_shadow.gd")
	const FIELD_DROP_ZONE := preload("res://scripts/game/field_drop_zone.gd")
	const CARD_Y := FIELD_SHADOW.WOOD_Y + FIELD_SHADOW.REST_HEIGHT
	var columns := clampi(int(_args.get("field-columns", ids.size())), 1, maxi(ids.size(), 1))
	var rows := ceili(float(ids.size()) / columns)
	for index in range(ids.size()):
		var card: Card = CARD_SCENE.instantiate()
		card.initialize(int(ids[index]), Card.PLAYER)
		add_child(card)
		card.enter_zone(Card.Zone.FIELD)
		card.rotation.y = 0.0
		var row := floori(float(index) / columns)
		var row_width := mini(columns, ids.size() - row * columns)
		card.position.x = (float(index % columns) - (row_width - 1) * 0.5) * 0.58
		card.position.y = CARD_Y
		card.position.z = (float(row) - (rows - 1) * 0.5) * 0.83

	_add_environment(false)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#77716b")
	mat.roughness = 0.95
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	floor.mesh = plane
	floor.material_override = mat
	floor.position.y = FIELD_DROP_ZONE.SLAB_TOP_Y
	add_child(floor)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-49.0, -32.0, 0.0)
	key.light_energy = 0.7
	key.shadow_enabled = true
	add_child(key)
	var camera := Camera3D.new()
	camera.position = Vector3(0.19, 1.37, 0.65)
	if ids.size() > 1:
		camera.position = Vector3(0.0, 1.37, 0.65) * maxf(1.0, maxf(columns * 0.37, rows * 0.94))
	camera.position.y += CARD_Y
	camera.fov = 36.0 * float(_args.get("zoom", 1.0))
	add_child(camera)
	camera.look_at(Vector3(0.0, CARD_Y, 0.0))
	camera.current = true


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
