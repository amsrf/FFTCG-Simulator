extends Node
## The phase prism (scripts/ui/phase_prism.gd): one phase name at a time on the up face of a lying TRIANGULAR crystal
## that turns FORWARD 120 degrees to the next phase (the name written on the face coming up), blue on your turn and
## red on the opponent's, the Attack face naming its step.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const PRISM := preload("res://scripts/ui/phase_prism.gd")
const P := GlobalVariables.Phase

var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[PhasePrism] %s %s" % ["ok  " if ok else "FAIL", what])

func _only_up_readable(prism) -> bool:
	var up: int = prism.up_face()
	for f in 3:
		var a: float = prism.label_alpha(f)
		if (f == up and a < 0.99) or (f != up and a > 0.01):
			return false
	return true

func _settle(prism) -> void:
	var t := 0.0
	while prism.is_rolling() and t < 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await get_tree().process_frame

func _tint(prism) -> Color:
	return (prism.get_node("Prism").material_override as ShaderMaterial).get_shader_parameter("tint")

func _has_rest_tilt(prism) -> bool:
	var mesh := prism.get_node("Prism") as MeshInstance3D
	var normal := mesh.basis * PRISM.face_normal(prism.up_face())
	return normal.z < 0.0 and normal.is_equal_approx(Vector3.UP.rotated(Vector3.RIGHT, PRISM.REST_TILT))

func _check_crystal_fit(prism) -> void:
	var mesh: ArrayMesh = prism.get_node("Prism").mesh
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sweep_radius := 0.0
	for vertex in vertices:
		sweep_radius = maxf(sweep_radius, Vector2(vertex.y, vertex.z).length())
	_expect(prism.position.y + mesh.get_aabb().end.y > PRISM.CRADLE_TOP_Y,
		"the crystal crown stands above the lip")
	_expect(prism.position.y - sweep_radius > PRISM.CAVITY_FLOOR_Y,
		"the crystal clears the floor throughout the roll")
	var side_clearance := PRISM.CAVITY_WIDTH * 0.5 - sweep_radius
	var end_clearance := (PRISM.CAVITY_LENGTH - mesh.get_aabb().size.x) * 0.5
	_expect(side_clearance > 0.0 and side_clearance < 0.012 and end_clearance > 0.0 and end_clearance < 0.015,
		"the cavity mouth fits closely around the crystal's sweep and tips")
	var body_radius := 0.0
	var tip_radius := 0.0
	for vertex in vertices:
		var radius := Vector2(vertex.y, vertex.z).length()
		if is_equal_approx(absf(vertex.x), PRISM.LENGTH * 0.5):
			tip_radius = maxf(tip_radius, radius)
		else:
			body_radius = maxf(body_radius, radius)
	_expect(tip_radius > 0.0 and tip_radius < body_radius, "both tips taper down from the full crystal body")

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	for i in 10:
		await get_tree().process_frame
	var prism = game.get("phase_prism")
	_expect(prism != null and prism.visible, "the game builds the phase prism and shows it")
	_check_crystal_fit(prism)
	_expect(game.get_node("PhaseText").text.find("PHASE") < 0, "the debug phase line is gone from PhaseText")
	var slot_now: int = PRISM.slot_for(game.phase)
	_expect(prism.shown_slot() == slot_now and prism.shown_text() == PRISM.NAMES[slot_now],
		"it shows the game's current phase on its up face ('%s')" % prism.shown_text())
	await get_tree().process_frame
	_expect(_only_up_readable(prism), "one name at a time: only the up face is readable")
	_expect(_has_rest_tilt(prism), "the first reading face rests tilted toward the camera")

	# Drive it directly from here on: every phase, in order, on your turn.
	prism.show_phase(P.ACTIVE_PHASE, true)
	await _settle(prism)
	var angle: float = prism.get("_angle")
	var forward := true
	var order := [P.DRAW_PHASE, P.FIRST_MAIN_PHASE, P.ATTACK_PREPARATION_STEP, P.ATTACK_DECLARATION_STEP,
		P.BLOCKER_DECLARATION_STEP, P.DAMAGE_RESOLUTION_STEP, P.SECOND_MAIN_PHASE, P.END_PHASE]
	for ph in order:
		var was_rolling_from: float = prism.get("_angle")
		prism.show_phase(ph, true)
		await _settle(prism)
		var a: float = prism.get("_angle")
		if a < angle - 0.001:
			forward = false
		angle = a
		var slot: int = PRISM.slot_for(ph)
		var step: int = PRISM.step_for(ph)
		var want: String = PRISM.STEP_NAMES[step] if step >= 0 else PRISM.NAMES[slot]
		_expect(prism.shown_text() == want and _only_up_readable(prism),
			"%s: '%s' on the up face, alone" % [game.phase_to_string(ph), prism.shown_text()])
	_expect(forward, "the roll only ever goes forward")
	prism.show_phase(P.ATTACK_DECLARATION_STEP, true)
	await _settle(prism)
	_expect(prism.shown_text() == "Attack Declaration Step", "the Attack face names its step, by the rules' name")
	var before_step: float = prism.get("_angle")
	prism.show_phase(P.BLOCKER_DECLARATION_STEP, true)
	_expect(prism.is_rolling(), "a step change inside the Attack Phase turns it too")
	# Overshoot then settle: sample the turn and look for the angle passing the target and coming back.
	var target_step: float = before_step + TAU / 3.0
	var peak := -INF
	while prism.is_rolling():
		peak = maxf(peak, float(prism.get("_angle")))
		await get_tree().process_frame
	await get_tree().process_frame
	var settled: float = prism.get("_angle")
	_expect(peak > target_step + deg_to_rad(5.0), "the turn overshoots the face (by %.1f deg)" % rad_to_deg(peak - target_step))
	_expect(absf(settled - target_step) < 0.001, "and settles exactly on it (%.3f deg off)" % rad_to_deg(settled - target_step))
	_expect(prism.shown_text() == "Block Declaration Step", "showing Block Declaration Step")
	_expect(_has_rest_tilt(prism), "the same tilt is applied after the crystal rolls")
	prism.show_phase(P.SECOND_MAIN_PHASE, true)
	await _settle(prism)
	_expect(prism.shown_text() == "Main Phase 2", "phases use the Comprehensive Rules' names (Main Phase 2)")

	# End -> Active on the OPPONENT's turn: one more step forward (not a spin back), and the crystal turns red.
	prism.show_phase(P.END_PHASE, true)
	await _settle(prism)
	var before: float = prism.get("_angle")
	_expect(_tint(prism).b > _tint(prism).r, "blue on your turn")
	prism.show_phase(P.ACTIVE_PHASE, false)
	await get_tree().create_timer(0.1).timeout
	_expect(prism.is_rolling(), "a phase change rolls the prism (not a snap)")
	await _settle(prism)
	await get_tree().create_timer(0.5).timeout
	var after: float = prism.get("_angle")
	_expect(absf(after - before - TAU / 3.0) < 0.01, "End -> Active is one 120-degree turn forward (%.1f deg)" % rad_to_deg(after - before))
	_expect(_tint(prism).r > _tint(prism).b, "red on the opponent's turn")
	_expect(prism.shown_text() == "Active Phase" and _only_up_readable(prism), "and it reads Active Phase")

	print("[PhasePrism] %d checks | failures: %d" % [_checks, _fails])
	print("[PhasePrism] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
