extends Node
## The phase dials (scripts/ui/phase_dial.gd): seven carved marks on one arc centred on each big button, clear of the
## Cancel button, and a pointer that turns to the current phase's mark. They replaced the phase prism.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const DIAL := preload("res://scripts/ui/phase_dial.gd")
const P := GlobalVariables.Phase

var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[PhaseDial] %s %s" % ["ok  " if ok else "FAIL", what])

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var stations = game.get_node("Assistant/ButtonStations")
	_expect(game.get_node_or_null("PhasePrism") == null, "the phase prism is gone")
	for pair in [["mine", stations.local_dial, stations.local_forward, stations.local_cancel],
			["theirs", stations.opponent_dial, stations.opponent_forward, stations.opponent_cancel]]:
		var who: String = pair[0]
		var dial: Node3D = pair[1]
		var forward: Node3D = pair[2]
		var cancel: Node3D = pair[3]
		_expect(dial != null and dial.get_parent() == forward, "%s: the dial belongs to the big button" % who)
		# Every mark on the one circle around the button, and clear of the Cancel button's housing (r 0.17 + rim).
		var cancel_local: Vector3 = forward.to_local(cancel.global_position)
		var on_circle := true
		var clear := true
		for slot in DIAL.MARKS:
			var m: Vector3 = DIAL.mark_position(slot)
			on_circle = on_circle and absf(Vector2(m.x, m.z).length() - DIAL.ARC_RADIUS) < 0.0005
			clear = clear and Vector2(m.x - cancel_local.x, m.z - cancel_local.z).length() > 0.17 + 0.10 + 0.04
		_expect(on_circle, "%s: all seven marks sit on one circle around the button (r %.2f)" % [who, DIAL.ARC_RADIUS])
		_expect(clear, "%s: no mark touches the Cancel button's housing" % who)
	# Nothing of the dial is under the board: every baked board vertex beneath the marks' arc or the pointer's ring
	# must be lower than they are (the regenerated ledge once buried the whole dial and every other check still passed).
	var board: MeshInstance3D = game.get_node("Board/MeshInstance3D")
	var verts: PackedVector3Array = board.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for pair in [["mine", stations.local_dial], ["theirs", stations.opponent_dial]]:
		var dial: Node3D = pair[1]
		var to_dial: Transform3D = dial.global_transform.affine_inverse() * board.global_transform
		var highest := -INF
		var sampled := 0
		for v in verts:
			var l: Vector3 = to_dial * v
			var r := Vector2(l.x, l.z).length()
			var a := rad_to_deg(atan2(l.z, -l.x))
			if r > 0.405 and r < 0.62 and a > DIAL.LAST_ANGLE - 8.0 and a < DIAL.FIRST_ANGLE + 8.0:
				highest = maxf(highest, l.y)
				sampled += 1
		_expect(sampled > 20 and highest < DIAL.WOOD_Y,
			"%s: the dial lies above the board (highest ground %.4f < marks %.4f, %d vertices)" \
			% [pair[0], highest, DIAL.WOOD_Y, sampled])
	# Each phase: the right mark, and the pointer aimed at it from the button's centre.
	for phase in [P.ACTIVE_PHASE, P.DRAW_PHASE, P.FIRST_MAIN_PHASE, P.ATTACK_PREPARATION_STEP,
			P.ATTACK_DECLARATION_STEP, P.BLOCKER_DECLARATION_STEP, P.DAMAGE_RESOLUTION_STEP, P.SECOND_MAIN_PHASE,
			P.END_PHASE]:
		stations.show_phase(phase)
		await get_tree().create_timer(DIAL.TURN_SECONDS + 0.15).timeout
		var want: int = DIAL.slot_for(phase)
		var aimed := true
		var glued := true
		for dial in [stations.local_dial, stations.opponent_dial]:
			var tip: Vector3 = dial.pointer_tip()
			var mark: Vector3 = DIAL.mark_position(want)
			var off := rad_to_deg(absf(Vector2(tip.x, tip.z).angle_to(Vector2(mark.x, mark.z))))
			aimed = aimed and dial.current_slot() == want and off < 0.5
			# Glued to the housing: the base touches the wall (no gap, not on top of it), on the wood.
			var base: Vector3 = dial.pointer_base()
			var wall: float = DIAL.wall_radius(DIAL.slot_angle(want))
			glued = glued and absf(Vector2(base.x, base.z).length() - wall) < 0.001 \
				and absf(base.y - DIAL.POINTER_Y) < 0.0005 and base.y < 0.115 - 0.085 - 0.02
		_expect(aimed, "%s -> mark %d, both pointers aimed at it" % [P.keys()[phase], want])
		_expect(glued, "%s: the pointer lies on the wood with its base against the housing wall" % P.keys()[phase])
	print("[PhaseDial] %d checks | failures: %d" % [_checks, _fails])
	print("[PhaseDial] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
