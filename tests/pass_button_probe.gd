extends Node
## The shared priority coin shows whose input is needed and turns over when pressed.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const DISC_SOCKET := preload("res://scripts/ui/disc_socket.gd")
const COIN := preload("res://scripts/ui/priority_coin.gd")

var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[PassButton] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _settle() -> void:
	await get_tree().create_timer(DISC_SOCKET.FULL_TURN_SECONDS + DISC_SOCKET.SETTLE_SECONDS + 0.1).timeout

func _check_coin_fit(pivot: Node3D) -> void:
	var sweep_radius := 0.0
	var lowest := INF
	var rim_rise := 0.0
	var rim_inner := INF
	var rim_outer := 0.0
	for part in ["CopperCap", "GoldRim"]:
		var mesh_instance := pivot.get_node(part) as MeshInstance3D
		var vertices: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			sweep_radius = maxf(sweep_radius, (vertex * pivot.scale).length())
			if part == "GoldRim":
				var r := Vector2(vertex.x, vertex.z).length()
				rim_rise = maxf(rim_rise, vertex.y - COIN._front_height(r))
				rim_inner = minf(rim_inner, r)
				rim_outer = maxf(rim_outer, r)
		for i in range(25):
			var angle := PI * float(i) / 12.0
			var height := COIN.axle_height(angle)
			for vertex in vertices:
				var y := vertex.y * pivot.scale.y * cos(angle) - vertex.z * pivot.scale.z * sin(angle)
				lowest = minf(lowest, height + y)
	var sweep_clearance := COIN.BORE_RADIUS - sweep_radius
	_expect(sweep_clearance > 0.016 and sweep_clearance < 0.032,
		"the moving cap leaves room to see inside the opening and clears it through the flip")
	_expect(lowest > COIN.WELL_FLOOR_Y, "the coin clears the recess floor through the flip")
	_expect((rim_outer - rim_inner) * pivot.scale.x >= 0.045 and rim_rise > 0.003 and rim_rise < 0.006,
		"the wider brass band follows the curved face with a shallow raised edge")

func _check_cosmos_coin(theirs: Node3D) -> void:
	# The Cosmos coin is the SAME lathe coin in the Cosmos colours: every part exists and every material says so.
	var pivot := theirs.get_node("Pivot") as Node3D
	var parts: Array[MeshInstance3D] = [pivot.get_node("CopperCap"), pivot.get_node("GoldRim"),
		theirs.get_node("CopperSocket"), theirs.get_node("RecessWall"), theirs.get_node("OuterBezel")]
	var all_cosmos := true
	for part in parts:
		all_cosmos = all_cosmos and bool((part.material_override as ShaderMaterial).get_shader_parameter("cosmos"))
	_expect(theirs.coin_style == "cosmos" and all_cosmos and pivot.scale.is_equal_approx(COIN.COIN_SCALE),
		"the opponent's coin is the Chaos coin's shape in the Cosmos colours")

func _coin_is_cosmos(socket: Node3D) -> bool:
	var cap := socket.get_node("Pivot").get_node("CopperCap") as MeshInstance3D
	return bool((cap.material_override as ShaderMaterial).get_shader_parameter("cosmos"))

func _check_rim_light(socket: Node3D, pivot: Node3D) -> void:
	var rim := pivot.get_node("GoldRim") as MeshInstance3D
	var rim_radius := rim.get_aabb().end.x
	var rim_vertices: PackedVector3Array = rim.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var edge_height := -INF
	for vertex in rim_vertices:
		if is_equal_approx(Vector2(vertex.x, vertex.z).length(), rim_radius):
			edge_height = maxf(edge_height, vertex.y)
	var edge_y := pivot.position.y + edge_height * pivot.scale.y
	var ring := socket.get_node("RingGlow") as MeshInstance3D
	var ring_material := ring.material_override as ShaderMaterial
	var ring_radius := float(ring_material.get_shader_parameter("ring_radius"))
	var plane_width := (ring.mesh as PlaneMesh).size.x
	ring_radius *= plane_width
	var housing := socket.get_node("CopperSocket") as MeshInstance3D
	var face_fraction := ring_radius / housing.get_aabb().end.x
	var core_color: Color = ring_material.get_shader_parameter("core_color")
	var glow_color: Color = ring_material.get_shader_parameter("glow_color")
	_expect(is_equal_approx(ring_radius, rim_radius * pivot.scale.x)
		and absf(ring.position.y - edge_y) < 0.010
		and float(ring_material.get_shader_parameter("core_width")) * plane_width >= 0.018
		and face_fraction > 0.63 and face_fraction < 0.67 and core_color.b > glow_color.b + 0.3,
		"the pale ring defines the edge of the smaller brass button")
	var housing_vertices: PackedVector3Array = housing.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sphere_center_y := COIN.SOCKET_EDGE_Y - sqrt(pow(COIN.SOCKET_SPHERE_RADIUS, 2) - pow(COIN.SOCKET_FOOTPRINT, 2))
	var crown_error := 0.0
	var opening_radius := INF
	for vertex in housing_vertices:
		opening_radius = minf(opening_radius, Vector2(vertex.x, vertex.z).length())
		crown_error = maxf(crown_error,
			absf(vertex.distance_to(Vector3(0.0, sphere_center_y, 0.0)) - COIN.SOCKET_SPHERE_RADIUS))
	_expect(crown_error < 0.0001 and is_equal_approx(opening_radius, COIN.RUBY_INNER_RADIUS),
		"the faceted ruby follows the spherical housing and seats under the collar")
	var wall := socket.get_node("RecessWall") as MeshInstance3D
	var wall_vertices: PackedVector3Array = wall.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bore := INF
	var outer := 0.0
	for vertex in wall_vertices:
		var radius := Vector2(vertex.x, vertex.z).length()
		bore = minf(bore, radius)
		outer = maxf(outer, radius)
	_expect(is_equal_approx(bore, COIN.BORE_RADIUS) and wall.get_aabb().end.y - edge_y > 0.025
		and is_equal_approx(wall.get_aabb().position.y, COIN.WELL_FLOOR_Y),
		"the bronze sleeve defines the opening down to the recess floor")
	var bezel := socket.get_node("OuterBezel") as MeshInstance3D
	_expect(is_equal_approx(outer, COIN.COLLAR_OUTER_RADIUS) and outer > opening_radius
		and outer - bore > 0.030 and bezel.material_override == wall.material_override,
		"the thick bronze collar and outer bezel frame the uninterrupted ruby ring")
	var rise := socket.get_node("RingLightRise") as MultiMeshInstance3D
	var rise_material := rise.material_override as ShaderMaterial
	var last_layer := rise.multimesh.get_instance_transform(rise.multimesh.instance_count - 1)
	_expect(is_equal_approx(rise.position.y, ring.position.y)
		and is_equal_approx(float(rise_material.get_shader_parameter("ring_radius")), ring_radius)
		and last_layer.origin.y > ring_radius and float(rise_material.get_shader_parameter("intensity")) > 0.0,
		"the active brass ring emits a column of light above its circumference")

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	for _i in range(4):
		await get_tree().process_frame
	var assistant = game.assistant
	var button = assistant.passPhaseButton
	var stations = assistant.button_stations
	var mine = stations.local_forward
	var theirs = stations.opponent_forward
	var pivot: Node3D = mine.get_node("Pivot")
	var cap := pivot.get_node("CopperCap") as MeshInstance3D
	var cap_material := cap.material_override as ShaderMaterial
	_check_cosmos_coin(theirs)
	# Seat 2 (forest) is the Cosmos side: whoever sits there gets the Cosmos coin, and the other seat the Chaos one.
	stations.configure_seat(2)
	await get_tree().process_frame
	_expect(mine.coin_style == "cosmos" and _coin_is_cosmos(mine) and theirs.coin_style == "chaos"
		and not _coin_is_cosmos(theirs), "at seat 2 my coin is the Cosmos coin and the opponent's is the Chaos coin")
	stations.configure_seat(1)
	await get_tree().process_frame
	pivot = mine.get_node("Pivot")
	cap = pivot.get_node("CopperCap") as MeshInstance3D
	cap_material = cap.material_override as ShaderMaterial
	_expect(mine.coin_style == "chaos" and not _coin_is_cosmos(mine) and _coin_is_cosmos(theirs),
		"back at seat 1 the coins swap back")
	_check_cosmos_coin(theirs)

	GlobalVariables.refresh_mode()
	game.turn_owner = 1
	game.priority_holder = 1
	_expect(button.visible and button.get_text().is_empty(), "a Main Phase 1 pass without a Forward keeps the crystal")
	game._place_field_cards([{"id": 1}], false)
	game.priority_holder = 1
	await _settle()
	_expect(button.visible and mine.label_text().is_empty() and not cap_material.get_shader_parameter("use_imprint")
		and int(cap_material.get_shader_parameter("stamp_kind")) == COIN.Stamp.CROSSED_SWORDS,
		"a Main Phase 1 pass into the Attack Phase shows the crossed-swords stamp")
	var effect: Card = game.create_card(4, Card.PLAYER)
	game.stack.add_child(effect)
	game.stack.cards.append(effect)
	game.priority_holder = 1
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(button.visible and button.get_text().is_empty()
		and int(cap_material.get_shader_parameter("stamp_kind")) == COIN.Stamp.CRYSTAL,
		"a pass with an effect on the stack uses the crystal even in Main Phase 1")
	game.stack.cards.erase(effect)
	effect.queue_free()
	game.priority_holder = 1
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(int(cap_material.get_shader_parameter("stamp_kind")) == COIN.Stamp.CROSSED_SWORDS,
		"crossed swords return when the stack clears")
	game.phase = GlobalVariables.Phase.SECOND_MAIN_PHASE
	game.priority_holder = 1
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(mine.is_active() and is_zero_approx(pivot.rotation.x) and mine.label_text().is_empty()
		and not cap_material.get_shader_parameter("use_imprint")
		and int(cap_material.get_shader_parameter("stamp_kind")) == COIN.Stamp.CRYSTAL,
		"the crystal-stamped cap faces up during Main Phase 2 priority")
	_expect(mine.get_node("RingGlow").get_parent() == mine
		and is_equal_approx(mine.glow_intensity(), DISC_SOCKET.COIN_READY_GLOW),
		"the fixed socket light marks available priority")
	_expect(not theirs.wants_active(), "the opponent's coin is inactive")
	_expect(not stations.local_cancel.wants_active() and not stations.opponent_cancel.wants_active(),
		"the Cancel discs are inactive with no prompt open")
	_check_coin_fit(pivot)
	_check_rim_light(mine, pivot)

	assistant.set_declare_attack_button(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(mine.label_text().is_empty() and not cap_material.get_shader_parameter("use_imprint")
		and int(cap_material.get_shader_parameter("stamp_kind")) == COIN.Stamp.SECOND_MAIN
		and not button.visible and assistant.confirmButton.is_active(),
		"declaring no attacker offers the stamped Roman numeral II")
	_expect(is_zero_approx(pivot.rotation.x), "changing the active claim within one frame leaves the coin seated")
	assistant.set_declare_attack_button(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(mine.label_text() == "Attack" and bool(cap_material.get_shader_parameter("use_imprint"))
		and int(cap_material.get_shader_parameter("stamp_kind")) == COIN.Stamp.CRYSTAL,
		"selecting an attacker switches the coin to Attack")
	assistant.set_declare_attack_button(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(int(cap_material.get_shader_parameter("stamp_kind")) == COIN.Stamp.SECOND_MAIN,
		"clearing the attacker restores the Roman numeral II")
	assistant.show_modal("Confirm target")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(mine.label_text() == "Confirm target" and bool(cap_material.get_shader_parameter("use_imprint"))
		and int(cap_material.get_shader_parameter("stamp_kind")) == COIN.Stamp.CRYSTAL,
		"the shared coin displays confirmation prompts")
	assistant.hide_buttons()
	assistant.show_pass_priority_button()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(button.visible and mine.label_text().is_empty() and not cap_material.get_shader_parameter("use_imprint"),
		"ordinary priority restores the crystal stamp")

	game.priority_holder = 2
	_expect(not button.visible, "when the opponent holds priority my button cannot be pressed")
	await _settle()
	_expect(not mine.is_active() and is_equal_approx(pivot.rotation.x, PI) and is_zero_approx(mine.glow_intensity()),
		"my coin is reverse-up with its light out")
	_expect(theirs.is_active() and is_equal_approx(theirs.glow_intensity(), DISC_SOCKET.COIN_READY_GLOW),
		"the opponent's coin and socket light indicate their priority")

	game.priority_holder = 1
	await _settle()
	var ruby := (mine.get_node("CopperSocket") as MeshInstance3D).material_override as ShaderMaterial
	var their_glow: float = theirs.glow_intensity()
	var hit := (button._area.get_child(0) as CollisionShape3D).shape as CylinderShape3D
	_expect(hit.radius >= COIN.SOCKET_FOOTPRINT and is_zero_approx(float(ruby.get_shader_parameter("ruby_glow"))),
		"the resting ruby is unlit and its outer edge is inside the hover area")
	button._on_hover(true)
	await get_tree().create_timer(0.25).timeout
	_expect(mine.glow_intensity() > DISC_SOCKET.COIN_READY_GLOW, "hover brightens the ring")
	_expect(is_equal_approx(float(ruby.get_shader_parameter("ruby_glow")), 1.0)
		and is_equal_approx(theirs.glow_intensity(), their_glow), "hover lights only the local ruby")
	button._on_hover(false)
	await get_tree().create_timer(0.25).timeout
	_expect(is_zero_approx(float(ruby.get_shader_parameter("ruby_glow"))), "the ruby fades when the pointer leaves")
	mine.pulse()
	await get_tree().create_timer(0.15).timeout
	var early: float = pivot.rotation.x
	_expect(early > 0.25 and early < PI - 0.25 and pivot.position.y > COIN.AXLE_Y,
		"pressing turns the coin forward and lifts it clear of the floor")
	button._sync()
	_expect(mine.is_busy() and not button._area.input_ray_pickable and not button.press_from_key(),
		"the shared disc rejects mouse and keyboard input during the flip")

	var flip_seconds := DISC_SOCKET.COIN_PRESS_TURN_SECONDS + DISC_SOCKET.SETTLE_SECONDS
	await get_tree().create_timer(flip_seconds - 0.15 + 0.03).timeout
	_expect(is_equal_approx(pivot.rotation.x, PI) and mine.is_busy() and mine.wants_active(),
		"the press settles on the reverse in one half-turn and briefly holds there")
	mine.pulse()
	await _settle()
	_expect(not mine.is_busy() and mine.is_active() and is_zero_approx(pivot.rotation.x),
		"the coin releases and turns face-up when still offered")

	button.hide_button()
	mine.pulse()
	await get_tree().create_timer(flip_seconds + DISC_SOCKET.COIN_PRESS_HOLD_SECONDS + 0.1).timeout
	_expect(not mine.is_active() and is_equal_approx(pivot.rotation.x, PI)
		and is_zero_approx(mine.glow_intensity()), "after passing away priority the coin stays reverse-up and dark")

	game.match_over = true
	game.priority_holder = 1
	_expect(not button.visible, "no pass button once the match is over")
	game.priority_holder = 2
	_expect(not theirs.wants_active(), "the opponent's coin is also inactive once the match is over")

	print("[PassButton] %d checks | failures: %d" % [_checks, _fails])
	print("[PassButton] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
