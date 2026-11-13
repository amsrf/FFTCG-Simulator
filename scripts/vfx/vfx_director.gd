class_name VfxDirector
extends Node3D
## Central presentation hub.
##
## Rules/card effects emit semantic events here. They never preload or
## instantiate a particle scene themselves. This class resolves an element or
## status preset and is the single place that will later spawn the actual VFX.
##
## The queue is deliberately serial: a one-shot presentation owns the "stage"
## until it finishes, while persistent status visuals (such as Frozen) are
## owned by the card and are not queued here.

signal event_queued(event: VfxEvent)
signal event_started(event: VfxEvent)
signal event_finished(event: VfxEvent)
## The queue has drained and nothing is playing.
signal idle_reached
const PRESENTATION := preload("res://scripts/core/presentation.gd")
## Loaded on first use, NOT preloaded: this is an autoload, and preloading the card scene here makes it load while
## the card's own scripts are still loading - a cycle that left every card.tscn instance() returning null (the clash
## proxies vanished).
const CARD_SCENE_PATH := "res://scenes/cards/card.tscn"
const CARD_SHARDS_PATH := "res://scenes/cards/card_shards.tscn"
## Loaded on first use, like the card scenes above (an autoload must not preload into the card's own load).
const COUNTER_CUE_PATH := "res://scripts/vfx/counter_cue.gd"

const ELEMENT_PRESET_DIR := "res://assets/vfx/elements"
const STATUS_PRESET_DIR := "res://assets/vfx/status"

## Fallbacks match Card.ELEMENT_COLOURS, so an event always has a usable tint
## even before a .tres preset has been authored.
const ELEMENT_TINTS := {
	"火": Color(0.86, 0.09, 0.17),
	"氷": Color(0.55, 0.87, 0.98),
	"風": Color(0.36, 0.85, 0.44),
	"土": Color(0.90, 0.74, 0.26),
	"雷": Color(0.72, 0.45, 1.00),
	"水": Color(0.32, 0.58, 1.00),
	"光": Color(1.00, 0.95, 0.78),
	"闇": Color(0.58, 0.52, 0.86),
}

var _events: Array[VfxEvent] = []
var _pending: Array[VfxEvent] = []
var _playing: bool = false
var _presets: Dictionary = {}
## Holds taken at a break (hold_for_break) and not yet claimed by the event that shows it: instance id -> visual.
var _pending_holds: Dictionary = {}


func _ready() -> void:
	_load_presets()


func status_applied(card: Card, status: String, duration: int = 1) -> void:
	if card == null or not is_instance_valid(card):
		return
	var event := VfxEvent.new(VfxEvent.Kind.STATUS_APPLIED, [card],
		card.element, 0, null, "", status)
	event.duration = duration
	_emit(event)


func status_removed(card: Card, status: String) -> void:
	if card == null or not is_instance_valid(card):
		return
	var event := VfxEvent.new(VfxEvent.Kind.STATUS_REMOVED, [card],
		card.element, 0, null, "", status)
	_emit(event)


## `mode`: "single" (default), "multi", "sequence", "radial".
func damage(targets: Array, amount: int, element: String, source: Card = null,
		mode: String = "single", target_visuals: Dictionary = {}) -> void:
	var hits: Array = []
	for target in targets:
		if target != null and is_instance_valid(target):
			hits.append(target)
	if hits.is_empty():
		return
	var spread: String = mode
	if spread.is_empty():
		spread = "single" if hits.size() == 1 else "multi"
	var kind: VfxEvent.Kind = VfxEvent.Kind.BOARD_DAMAGE if spread == "board" else VfxEvent.Kind.DAMAGE
	var event := VfxEvent.new(kind, hits, element, amount, source, spread)
	_attach_damage_visuals(event, target_visuals)
	_emit(event)


## Whole-board damage is a distinct event so presets can choose a wave rather
## than N unrelated single-target impacts.
func board_damage(targets: Array, amount: int, element: String,
		source: Card = null, mode: String = "radial", target_visuals: Dictionary = {}) -> void:
	var hits: Array = []
	for target in targets:
		if target != null and is_instance_valid(target):
			hits.append(target)
	if hits.is_empty():
		return
	var event := VfxEvent.new(VfxEvent.Kind.BOARD_DAMAGE, hits, element, amount, source, mode)
	_attach_damage_visuals(event, target_visuals)
	_emit(event)


## The amount an EFFECT_BREAK event carries: the start of the maximum damage tier, so the cue plays its biggest hit.
const EFFECT_BREAK_AMOUNT := 9000

## Does `source`'s element stage the breaks it causes (VfxPreset.effect_break)?
func stages_effect_break(source: Card) -> bool:
	if not is_instance_valid(source):
		return false
	var preset: VfxPreset = preset_for_element(source.element)
	return preset != null and preset.effect_break and preset.impact_scene != null


## Cards `source`'s effect tried to break outright. `target_visuals` are the pre-break snapshots
## (capture_damage_visuals). The ones that really broke were HELD at the break (Game.break_card -> hold_for_break) and
## pick their hold up here; a card protection kept on the field is struck all the same, and survives.
func effect_break(targets: Array, source: Card, target_visuals: Dictionary) -> void:
	var hits: Array = []
	for target in targets:
		if is_instance_valid(target) and target_visuals.has(target.get_instance_id()):
			hits.append(target)
			target_visuals[target.get_instance_id()]["lethal"] = not target.is_on_field()
	if hits.is_empty() or not is_instance_valid(source):
		return
	var event := VfxEvent.new(VfxEvent.Kind.EFFECT_BREAK, hits, source.element, EFFECT_BREAK_AMOUNT, source,
		"single" if hits.size() == 1 else "multi")
	event.target_visuals = target_visuals
	_emit(event)


# --- VISUAL HOLDS ----------------------------------------------------------------------------------------------
# The rules move a card at once; its presentation may need it to stay where it was until a moment INSIDE an animation
# (a lightning break: the card is broken when the bolt lands, not when the effect resolves). A HOLD does that:
#   hold_card(card, visual)   at the rules moment - a stand-in copy of the card is left at `visual.transform` and the
#                             real card is hidden wherever the rules put it (the Break Zone pile, ...)
#   release_hold(card, visual, shatter)   at the animation's moment - the stand-in bursts into shards (or simply
#                             goes) and the real card is shown where it now lives
# A cue releases its holds itself; anything it leaves is released when its event finishes, so a hold can never strand a
# card hidden. `visual` is the event's target_visuals entry for that card.

## A BREAK THE SOURCE'S ELEMENT STAGES (Game.break_card asks this while the card is still on its slot): a stand-in
## takes the card's place, and the event that shows the break (the damage, or the effect break) claims it in _emit.
## Returns false when the break is not staged - the caller then plays the ordinary shatter.
func hold_for_break(card: Card, source: Card) -> bool:
	if not is_instance_valid(card) or not stages_effect_break(source) or not card.is_drawn_on_field():
		return false
	var visual := {"transform": card.global_transform, "floor_y": card.get_parent().global_position.y,
		"shatter": true, "lethal": true}
	hold_card(card, visual, false)
	_pending_holds[card.get_instance_id()] = visual
	# Nothing claims it (the effect showed no event)? Then it breaks at the end of this frame, as it always did.
	_release_unclaimed_holds.call_deferred()
	return true


## After the rules have moved a held card (Game.break_card): hide it where it now lives until its hold is released.
func hide_held(card: Card) -> void:
	var visual: Dictionary = _pending_holds.get(card.get_instance_id(), {})
	if visual.is_empty() or not is_instance_valid(card):
		return
	card.set_hidden(true)
	visual["hid_card"] = true


func _claim_holds(event: VfxEvent) -> void:
	if _pending_holds.is_empty():
		return
	if event.kind != VfxEvent.Kind.DAMAGE and event.kind != VfxEvent.Kind.BOARD_DAMAGE \
			and event.kind != VfxEvent.Kind.EFFECT_BREAK:
		return
	for target in event.targets:
		if not is_instance_valid(target):
			continue
		var id: int = target.get_instance_id()
		if not _pending_holds.has(id):
			continue
		var held: Dictionary = _pending_holds[id]
		_pending_holds.erase(id)
		var visual: Dictionary = event.target_visuals.get(id, {})
		for key in held:
			if key != "transform" or not visual.has("transform"):
				visual[key] = held[key]
		event.target_visuals[id] = visual


func _release_unclaimed_holds() -> void:
	for id in _pending_holds.keys():
		var visual: Dictionary = _pending_holds[id]
		_pending_holds.erase(id)
		var card = instance_from_id(id)
		release_hold(card if is_instance_valid(card) else null, visual, true)


## A STACK OBJECT IS COUNTERED. `move` is the rules move (Stack.cancel_stack_card: into its owner's Break Zone), run
## at once; the card is held on its stack spot - a stand-in wearing the same stack face - and hidden in the pile until
## the counter cue has shocked it and shattered it (VfxEvent.Kind.COUNTERED).
func countered(card: Card, move: Callable) -> void:
	var staged: bool = is_instance_valid(card) and card.is_inside_tree() and card.visible
	var visual: Dictionary = {}
	if staged:
		visual["transform"] = card.global_transform
		hold_card(card, visual, false, Card.Zone.STACK)
	move.call()
	if not staged or not is_instance_valid(card):
		return
	card.set_hidden(true)
	visual["hid_card"] = true
	var event := VfxEvent.new(VfxEvent.Kind.COUNTERED, [card], card.element, 0, null, "single")
	event.target_visuals[card.get_instance_id()] = visual
	_emit(event)


func hold_card(card: Card, visual: Dictionary, hide: bool = true, zone: Card.Zone = Card.Zone.FIELD) -> void:
	if not is_instance_valid(card) or not visual.has("transform") or visual.has("stand_in"):
		return
	var stand_in: Card = (load(CARD_SCENE_PATH) as PackedScene).instantiate()
	stand_in.initialize(card.id, card.controller)
	# Under the Game, like the clash's proxies (Card code looks for its Game among its ancestors).
	var host: Node = card.get_parent()
	while host != null and not host.has_method("break_card"):
		host = host.get_parent()
	(host if host != null else self).add_child(stand_in)
	stand_in.name = "HeldCard"
	stand_in.enter_zone(zone, card.stack_face_wording if zone == Card.Zone.STACK else "")
	stand_in.global_transform = visual.transform
	stand_in.hide_power_display()
	stand_in.set_hidden(false)
	stand_in.process_mode = Node.PROCESS_MODE_DISABLED
	var area: Area3D = stand_in.get_node_or_null("CardArea3D") as Area3D
	if area != null:
		area.input_ray_pickable = false
		area.collision_layer = 0
		area.collision_mask = 0
	visual["stand_in"] = stand_in
	if hide and card.visible:
		card.set_hidden(true)
		visual["hid_card"] = true


func release_hold(card: Card, visual: Dictionary, shatter: bool = false) -> void:
	var stand_in = visual.get("stand_in", null)
	visual.erase("stand_in")
	if is_instance_valid(stand_in):
		if shatter:
			var shards: Node3D = (load(CARD_SHARDS_PATH) as PackedScene).instantiate()
			stand_in.get_parent().add_child(shards)
			shards.set("free_when_done", true)
			shards.set("floor_world_y", float(visual.get("floor_y", (stand_in as Node3D).global_position.y)))
			shards.call("burst_from_card", stand_in)
		stand_in.queue_free()
	if visual.get("hid_card", false):
		visual.erase("hid_card")
		if is_instance_valid(card):
			card.set_hidden(false)


func _release_leftover_holds(event: VfxEvent) -> void:
	for target in event.targets:
		if not is_instance_valid(target):
			continue
		var visual: Dictionary = event.target_visuals.get(target.get_instance_id(), {})
		if visual.has("stand_in") or visual.get("hid_card", false):
			release_hold(target, visual, bool(visual.get("shatter", false)))


func card_broken(card: Card, cause: String = "") -> void:
	if card == null or not is_instance_valid(card):
		return
	_emit(VfxEvent.new(VfxEvent.Kind.CARD_BROKEN, [card], card.element, 0,
		null, "", "", cause))


func preset_for(event: VfxEvent) -> VfxPreset:
	if not event.status.is_empty() and _presets.has("status:" + event.status):
		return _presets["status:" + event.status]
	# A STATUS event looks only for a status preset. Falling through to the card's ELEMENT preset played that
	# element's damage cue for every status change: an Ice Forward attacking (status "attacking") or arriving with
	# summoning sickness dropped an ice projectile on itself in the middle of combat.
	if event.kind == VfxEvent.Kind.STATUS_APPLIED or event.kind == VfxEvent.Kind.STATUS_REMOVED:
		return null
	if _presets.has(event.element):
		return _presets[event.element]
	return null


## Position-only snapshots let an impact stay at the hit location after a
## defeated card moves to the Break Zone. They never delay rules or break FX.
func capture_damage_visuals(targets: Array) -> Dictionary:
	var snapshots: Dictionary = {}
	for target in targets:
		if is_instance_valid(target) and target is Card and target.is_drawn_on_field():
			snapshots[target.get_instance_id()] = {"transform": target.global_transform,
				"floor_y": target.get_parent().global_position.y}
	return snapshots

func _attach_damage_visuals(event: VfxEvent, snapshots: Dictionary) -> void:
	var positions := capture_damage_visuals(event.targets) if snapshots.is_empty() else snapshots
	for target: Card in event.targets:
		var id := target.get_instance_id()
		if positions.has(id):
			var visual: Dictionary = positions[id].duplicate()
			visual["lethal"] = not target.is_drawn_on_field()
			event.target_visuals[id] = visual

func owns_damage_reaction(source: Card) -> bool:
	if not is_instance_valid(source):
		return false
	var preset: VfxPreset = preset_for_element(source.element)
	return preset != null and preset.owns_damage_reaction


func preset_for_element(element: String) -> VfxPreset:
	return _presets.get(element, null)


func tint_for(event: VfxEvent) -> Color:
	var preset: VfxPreset = preset_for(event)
	if preset != null:
		return preset.tint
	return ELEMENT_TINTS.get(event.element, Color.WHITE)


func get_events() -> Array:
	return _events.duplicate()


func clear_events() -> void:
	_events.clear()


## Queue the animation of a rules change that has ALREADY happened. The rules carry on immediately; `presenter`
## (a coroutine: reparent, fly, lay out) runs when its turn in the queue comes.
func present(presenter: Callable) -> void:
	var event := VfxEvent.new()
	event.kind = VfxEvent.Kind.PRESENT
	event.presenter = presenter
	event.timestamp_ms = Time.get_ticks_msec()
	_emit(event)

## A presentation may NEVER stall the game. Decisions wait for this queue (Agent._settle), so one cue that errors
## mid-play or never returns would freeze every later decision of the match. The watchdog gives each entry a generous
## cap; past it, the queue warns and moves on (the animation may still finish on its own).
const MAX_PRESENT_SECONDS := 8.0

## Wakes _await_with_watchdog: emitted when a job finishes (synchronously, so the queue moves on in the same instant
## — frame-stepped tools rely on that) or when its time cap runs out.
signal _job_settled

func _await_with_watchdog(job: Callable, label: String) -> void:
	var state := {"done": false, "timed_out": false}
	# A METHOD, not a lambda: a lambda left suspended mid-await when the game shuts down can crash the engine on exit.
	_run_job(job, state)
	if state["done"]:
		return
	get_tree().create_timer(MAX_PRESENT_SECONDS).timeout.connect(func() -> void:
		if not state["done"]:
			state["timed_out"] = true
			_job_settled.emit())
	while not state["done"] and not state["timed_out"]:
		await _job_settled
	if state["timed_out"] and not state["done"]:
		push_warning("[Vfx] %s did not finish within %.0f s; the queue moves on so the game cannot freeze" % [
			label, MAX_PRESENT_SECONDS])

func _run_job(job: Callable, state: Dictionary) -> void:
	await job.call()
	state["done"] = true
	_job_settled.emit()

func is_idle() -> bool:
	return not _playing and _pending.is_empty()

## THE SCREEN CATCHES UP BEFORE ANYONE DECIDES. Agent._settle() awaits this before every decision, so no prompt can
## appear while the board is still animating what led to it. Fast mode (no one watching) does not wait.
func idle() -> void:
	if PRESENTATION.fast_mode:
		return
	while not is_idle():
		await idle_reached

func _emit(event: VfxEvent) -> void:
	# Before anything can play it: the queue may start this event synchronously.
	_claim_holds(event)
	_events.append(event)
	event_queued.emit(event)
	_pending.append(event)
	_pump()


func _pump() -> void:
	if _playing or _pending.is_empty():
		return
	_playing = true
	while not _pending.is_empty():
		var event: VfxEvent = _pending.pop_front()
		await _present(event)
	_playing = false
	idle_reached.emit()


## Presentation slots are intentionally ready for the next VFX pass. Until a
## preset supplies a scene, the event still emits, is logged, and advances the
## queue in a deterministic order.
func _present(event: VfxEvent) -> void:
	event_started.emit(event)
	if event.kind == VfxEvent.Kind.PRESENT:
		if event.presenter.is_valid():
			await _await_with_watchdog(event.presenter, "presentation")
		event_finished.emit(event)
		return
	var cue: Node = null
	if event.kind == VfxEvent.Kind.COUNTERED:
		cue = (load(COUNTER_CUE_PATH) as Script).new()
	else:
		var scene: PackedScene = _scene_for(event, preset_for(event))
		if scene != null:
			cue = scene.instantiate()
	if cue != null:
		add_child(cue)
		if cue.has_method("play"):
			await _await_with_watchdog(cue.play.bind(event), "cue %s" % cue.name)
		else:
			await get_tree().process_frame
		if is_instance_valid(cue):
			cue.queue_free()
	else:
		await get_tree().process_frame
	_release_leftover_holds(event)
	event_finished.emit(event)


func _scene_for(event: VfxEvent, preset: VfxPreset) -> PackedScene:
	if preset == null:
		return null
	match event.kind:
		VfxEvent.Kind.BOARD_DAMAGE:
			return preset.board_impact_scene
		VfxEvent.Kind.CARD_BROKEN:
			return preset.shard_scene
		VfxEvent.Kind.STATUS_REMOVED:
			# A status preset's impact_scene presents GAINING the status; losing it has no cue yet.
			return null
		_:
			return preset.impact_scene


func _load_presets() -> void:
	_presets.clear()
	_load_preset_dir(ELEMENT_PRESET_DIR)
	_load_preset_dir(STATUS_PRESET_DIR)


func _load_preset_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var resource = load(path + "/" + file)
		if resource is VfxPreset:
			var preset: VfxPreset = resource
			if not preset.element.is_empty():
				_presets[preset.element] = preset
			if preset.is_status():
				_presets["status:" + preset.status] = preset
