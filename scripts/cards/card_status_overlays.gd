extends RefCounted
## STATUS OVERLAYS for one card: the silence bubble ("loses all abilities"), the cracked-ice rim (Frozen) and the
## summoning-sickness waves. All are FIELD-only and built lazily, so an ordinary card pays nothing for them. Pure presentation — the statuses
## themselves live in Card.status_effects. Owned by Card as `card.overlays`; Card.refresh_status_visuals() calls
## refresh() after every status change.
##
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache, which is
## a parse error on every headless run.

## The silence icon is a screen-facing status bubble, not part of the card face.
const SILENCE_ICON_SCENE := preload("res://scenes/cards/silence_icon.tscn")

## Summoning sickness: dark waves rolling inward across the card (see Card.shows_summoning_sickness()).
const SICKNESS_OVERLAY := preload("res://scripts/cards/sickness_overlay.gd")

## FROSTBITE-STYLE FROZEN OVERLAY. A card-aligned additive quad that composites two original alpha masks so the
## artwork stays readable under the cracked icy rim.
const FROZEN_OVERLAY_SHADER := preload("res://shaders/frozen_overlay.gdshader")
const FROZEN_CRACKS_PATH := "res://assets/effects/frost/frost_cracks.png"
const FROZEN_OUTLINE_PATH := "res://assets/effects/frost/frost_outline.png"
const FROZEN_OVERLAY_SCALE := 1.01
## How long the frost takes to grow from the card edge to its full mask, and how long it takes to recede when Freeze
## is consumed.
const FROZEN_SPREAD_SECONDS := 1.60
const FROZEN_RECEDE_SECONDS := FROZEN_SPREAD_SECONDS

## Card is a Node3D; kept untyped so this file and card.gd do not depend on each other's class_name.
var _card: Node3D
var silence_icon: Node3D = null
var sickness_waves: Node3D = null
var frozen_overlay: MeshInstance3D = null
var _frozen_material: ShaderMaterial = null
var _frozen_tween: Tween = null
var _frozen_spread: float = 0.0
var _frozen_visual_on: bool = false

func _init(card: Node3D) -> void:
	_card = card

func refresh() -> void:
	_refresh_silence_icon()
	_refresh_frozen_overlay()
	refresh_sickness()

## Show the sickness waves while the card is waiting to act, and choose HOW they go away: Haste clears them quickly
## (the haste clock takes over), the sickness ending fades them slowly, dulling fades them (a dull card already reads as
## unable to act; it comes back if the card stands up while still sick), and leaving the field hides it at once.
## Called on every status change, tap/untap, Haste change and zone change.
func refresh_sickness() -> void:
	var wanted: bool = _card.shows_summoning_sickness()
	if wanted:
		if sickness_waves == null or not is_instance_valid(sickness_waves):
			sickness_waves = SICKNESS_OVERLAY.new()
			sickness_waves.name = "SicknessWaves"
			# Same parent as the frozen overlay and the target ring: the visible card's mesh.
			var hand_mesh = _card.hand_mesh
			var parent: Node3D = (hand_mesh as Node3D) if hand_mesh != null else _card
			parent.add_child(sickness_waves)
			sickness_waves.call("setup", _card)
		sickness_waves.call("show_waves")
		return
	if sickness_waves == null or not is_instance_valid(sickness_waves) or not sickness_waves.call("is_showing"):
		return
	if not _card.is_on_field():
		sickness_waves.call("hide_now")
	elif _card.has_haste():
		sickness_waves.call("burst")
	elif _card.tapped:
		sickness_waves.call("dismiss")
	else:
		sickness_waves.call("wake")

## Probe hook: "NONE" (never built), or the badge's state: HIDDEN / APPEARING / IDLE / LEAVING.
func sickness_state() -> String:
	if sickness_waves == null or not is_instance_valid(sickness_waves):
		return "NONE"
	return str(sickness_waves.call("state_name"))

## Show or hide the silence bubble. A card that loses its abilities and then leaves the field must not carry the icon
## into the hand, Break Zone or deck.
func _refresh_silence_icon() -> void:
	var wanted: bool = _card.current_zone == Card.Zone.FIELD and _card.status_effects.has("abilities_nullified")
	if not wanted:
		if silence_icon != null and is_instance_valid(silence_icon):
			silence_icon.call("set_active", false)
		return
	if silence_icon == null or not is_instance_valid(silence_icon):
		silence_icon = SILENCE_ICON_SCENE.instantiate()
		_card.add_child(silence_icon)
	var face: Vector2 = _card._card_face_size()
	var icon_width: float = face.x * 0.45
	silence_icon.call("set_icon_width", icon_width)
	var go_left: bool = _silence_icon_belongs_left()
	var gap: float = face.x * 0.015
	var cam: Camera3D = _card.get_viewport().get_camera_3d()
	if cam != null:
		# Place by the CAMERA's screen axes. The card's local +x is not a reliable "right" here: field cards are
		# rotated, and the same local axis can appear on either side. This puts the bubble on screen-right by
		# default, screen-left when the card is near the right edge, and lifts it slightly up the screen.
		var origin: Vector3 = _card.global_position
		var card_scale: float = _card.global_transform.basis.get_scale().x
		var horizontal: float = (face.x * 0.5 + icon_width * 0.5 + gap) * card_scale
		var vertical: float = face.y * 0.15 * card_scale
		var origin_px: Vector2 = cam.unproject_position(origin)
		# `basis.x` is not guaranteed to project to screen-right for this board camera; test it.
		var right_dir: Vector3 = cam.global_transform.basis.x.normalized()
		if cam.unproject_position(origin + right_dir * 0.10).x < origin_px.x:
			right_dir = -right_dir
		var up_dir: Vector3 = cam.global_transform.basis.y.normalized()
		if cam.unproject_position(origin + up_dir * 0.10).y > origin_px.y:
			up_dir = -up_dir
		var target_world: Vector3 = origin
		target_world += right_dir * (-horizontal if go_left else horizontal)
		target_world += up_dir * vertical
		silence_icon.global_position = target_world
	else:
		silence_icon.position = Vector3((-1.0 if go_left else 1.0) * (face.x * 0.5 + icon_width * 0.5 + gap), 0.02, 0.0)
	silence_icon.call("set_mirrored", go_left)
	silence_icon.call("set_active", true)

func _silence_icon_belongs_left() -> bool:
	var cam: Camera3D = _card.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var screen_x: float = cam.unproject_position(_card.global_position).x
	return screen_x > _card.get_viewport().get_visible_rect().size.x * 0.70

## Show the cracked-ice rim only while this card is Frozen on the field.
func _refresh_frozen_overlay() -> void:
	var wanted: bool = _card.current_zone == Card.Zone.FIELD and _card.is_frozen()
	if wanted:
		_ensure_frozen_overlay()
		if frozen_overlay == null:
			return
		frozen_overlay.visible = true
		if not _frozen_visual_on:
			_frozen_visual_on = true
			_tween_frozen_spread(1.0, FROZEN_SPREAD_SECONDS, Tween.EASE_IN)
		return
	if _frozen_visual_on:
		_frozen_visual_on = false
		_tween_frozen_spread(0.0, FROZEN_RECEDE_SECONDS, Tween.EASE_OUT)
	elif frozen_overlay != null and is_instance_valid(frozen_overlay):
		# A settled hide, or a status that disappeared before the overlay was
		# ever shown. Do not cut a recede tween short.
		if _frozen_tween == null or not _frozen_tween.is_valid():
			frozen_overlay.visible = false

func _ensure_frozen_overlay() -> void:
	if frozen_overlay != null and is_instance_valid(frozen_overlay):
		return
	var face: Vector2 = _card._card_face_size()
	var quad := PlaneMesh.new()
	quad.size = face * FROZEN_OVERLAY_SCALE
	_frozen_material = ShaderMaterial.new()
	_frozen_material.shader = FROZEN_OVERLAY_SHADER
	_frozen_material.set_shader_parameter("frost_cracks", load(FROZEN_CRACKS_PATH))
	_frozen_material.set_shader_parameter("frost_outline", load(FROZEN_OUTLINE_PATH))
	_frozen_material.set_shader_parameter("spread", _frozen_spread)
	frozen_overlay = MeshInstance3D.new()
	frozen_overlay.name = "FrozenOverlay"
	frozen_overlay.mesh = quad
	frozen_overlay.material_override = _frozen_material
	frozen_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frozen_overlay.extra_cull_margin = 2.0
	# A hair above the face, like the target ring, so it cannot z-fight.
	frozen_overlay.position = Vector3(0.0, 0.003, 0.0)
	frozen_overlay.visible = false
	# Same parent as the target ring: the hand's hover moves/scales HandMesh,
	# and the frost must follow the visible card rather than a sibling.
	var hand_mesh = _card.hand_mesh
	var overlay_parent: Node3D = (hand_mesh as Node3D) if hand_mesh != null else _card
	overlay_parent.add_child(frozen_overlay)

## Grow the frost inward from the card edge, or let it recede when Freeze is
## consumed. `spread` is consumed by shaders/frozen_overlay.gdshader.
func _tween_frozen_spread(to: float, seconds: float, ease: Tween.EaseType) -> void:
	if frozen_overlay == null or not is_instance_valid(frozen_overlay):
		return
	if _frozen_tween != null and _frozen_tween.is_valid():
		_frozen_tween.kill()
	frozen_overlay.visible = true
	if not _card.is_inside_tree():
		_set_frozen_spread(to)
		frozen_overlay.visible = to > 0.001
		return
	_frozen_tween = _card.create_tween()
	_frozen_tween.set_trans(Tween.TRANS_CUBIC).set_ease(ease)
	_frozen_tween.tween_method(_set_frozen_spread, _frozen_spread, to, maxf(seconds, 0.01))
	_frozen_tween.tween_callback(func() -> void:
		if to <= 0.001 and not _frozen_visual_on and frozen_overlay != null:
			frozen_overlay.visible = false
	)

func _set_frozen_spread(value: float) -> void:
	_frozen_spread = clampf(value, 0.0, 1.0)
	if _frozen_material != null:
		_frozen_material.set_shader_parameter("spread", _frozen_spread)
