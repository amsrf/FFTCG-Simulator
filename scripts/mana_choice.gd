extends Node3D
## A radial mana picker for a Backup that can produce more than one colour.
##
## The crystals are real ManaCrystal nodes arranged in a circle in the camera plane. They are deliberately
## small, static (no idle/paid spin and no glow pulse), and act as buttons: hover grows one, click chooses its
## element. The chosen element is reported to Field, which records it alongside the selected source so a refund
## returns exactly the colour that was generated.

signal chosen(element: String)
signal cancelled

const CRYSTAL := preload("res://mana_crystal.tscn")

@export var crystal_height_m: float = 0.11
## Direct ring radius in metres. 0 keeps the automatic face-based radius; set a positive value to tune it.
@export var ring_radius_m: float = 0.42
## How far toward the camera the whole ring sits, so it draws above the Backup instead of under it.
@export var plane_offset_m: float = 0.10
## Starting orientation of each picker crystal around its own vertical axis.
@export var spin_angle_degrees: float = 60.0
@export var radius_padding_m: float = 0.10
@export var hover_scale: float = 1.24
@export var hover_seconds: float = 0.10

var card: Card = null
var crystals: Array = []
var _elements: Array = []
var _tweens: Dictionary = {}
var _closed: bool = false


func open(target: Card, elements: Array) -> void:
	card = target
	_elements = elements.duplicate()
	if card == null or _elements.is_empty() or not is_inside_tree():
		queue_free()
		return
	_build()
	GlobalVariables.player_mode_change.connect(_on_mode_changed)


func _build() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var right: Vector3 = cam.global_transform.basis.x.normalized()
	var up: Vector3 = -cam.global_transform.basis.y.normalized()
	var cam_basis: Basis = cam.global_transform.basis
	var toward_camera: Vector3 = cam.global_transform.basis.z.normalized()
	var center: Vector3 = card.get_global_face_centre() + toward_camera * plane_offset_m
	var card_scale: Vector3 = card.global_transform.basis.get_scale()
	var face: float = maxf(0.429 * card_scale.x, 0.6 * card_scale.z)
	var radius: float = ring_radius_m
	if radius <= 0.0:
		radius = face * 0.55 + crystal_height_m * 0.5 + radius_padding_m
	var count: int = _elements.size()
	for i in range(count):
		var angle: float = -PI * 0.5 + TAU * float(i) / float(count)
		var pos: Vector3 = center + right * (cos(angle) * radius) + up * (sin(angle) * radius)
		var crystal = CRYSTAL.instantiate()
		add_child(crystal)
		crystal.set("element", str(_elements[i]))
		crystal.set("lit", true)
		crystal.set("height_m", crystal_height_m)
		crystal.set("spin_deg_per_sec", 0.0)
		crystal.set("idle_spin_deg_per_sec", 0.0)
		crystal.set("glow_pulse", 0.0)
		crystal.global_transform = Transform3D(cam_basis, pos)
		crystal.call("set_spin_angle", spin_angle_degrees)
		_add_button(crystal, str(_elements[i]))
		crystals.append(crystal)


func _add_button(crystal: Node3D, element: String) -> void:
	var area := Area3D.new()
	area.name = "PickArea"
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var width: float = maxf(float(crystal.call("slot_width_m")), 0.05)
	box.size = Vector3(width, crystal_height_m, 0.06)
	shape.shape = box
	shape.position = Vector3(0.0, crystal_height_m * 0.5, 0.0)
	area.add_child(shape)
	crystal.add_child(area)
	area.mouse_entered.connect(_set_hover.bind(crystal, true))
	area.mouse_exited.connect(_set_hover.bind(crystal, false))
	area.input_event.connect(_on_crystal_input.bind(crystal, element))


func _set_hover(crystal: Node3D, on: bool) -> void:
	if crystal == null or not is_instance_valid(crystal):
		return
	var old: Tween = _tweens.get(crystal)
	if old != null and old.is_valid():
		old.kill()
	var target: Vector3 = Vector3.ONE * (hover_scale if on else 1.0)
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(crystal, "scale", target, hover_seconds)
	_tweens[crystal] = tween


func _on_crystal_input(_camera, event: InputEvent, _pos: Vector3, _normal: Vector3,
		_shape_idx: int, _crystal: Node3D, element: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	choose(element)


## Public so a probe (or a remote input adapter) can choose without synthesising a physics click.
func choose(element: String) -> void:
	if _closed:
		return
	_closed = true
	chosen.emit(element)
	_close()


func close() -> void:
	if _closed:
		return
	_closed = true
	cancelled.emit()
	_close()


func _close() -> void:
	if is_inside_tree():
		queue_free()


func _on_mode_changed(mode: int) -> void:
	if mode != GlobalVariables.Player_Mode.PAYING_COST:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			close()
			get_viewport().set_input_as_handled()
