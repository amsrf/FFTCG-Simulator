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


func card_broken(card: Card, cause: String = "") -> void:
	if card == null or not is_instance_valid(card):
		return
	_emit(VfxEvent.new(VfxEvent.Kind.CARD_BROKEN, [card], card.element, 0,
		null, "", "", cause))


func preset_for(event: VfxEvent) -> VfxPreset:
	if not event.status.is_empty() and _presets.has("status:" + event.status):
		return _presets["status:" + event.status]
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


func _emit(event: VfxEvent) -> void:
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


## Presentation slots are intentionally ready for the next VFX pass. Until a
## preset supplies a scene, the event still emits, is logged, and advances the
## queue in a deterministic order.
func _present(event: VfxEvent) -> void:
	event_started.emit(event)
	var preset: VfxPreset = preset_for(event)
	var scene: PackedScene = _scene_for(event, preset)
	if scene != null:
		var cue: Node = scene.instantiate()
		add_child(cue)
		if cue.has_method("play"):
			await cue.play(event)
		else:
			await get_tree().process_frame
		if is_instance_valid(cue):
			cue.queue_free()
	else:
		await get_tree().process_frame
	event_finished.emit(event)


func _scene_for(event: VfxEvent, preset: VfxPreset) -> PackedScene:
	if preset == null:
		return null
	match event.kind:
		VfxEvent.Kind.BOARD_DAMAGE:
			return preset.board_impact_scene
		VfxEvent.Kind.CARD_BROKEN:
			return preset.shard_scene
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
