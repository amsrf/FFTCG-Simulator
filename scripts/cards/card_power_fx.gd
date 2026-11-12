extends RefCounted
## POWER-UP PRESENTATION for one card (reference: Desktop/Clips/powerup.mp4). When a Forward on the field gains
## power, three red swords rise around it in a burst of red gas, and then the power readout counts up while it swells.
## Pure presentation — the power itself is Card.recompute_power(). Owned by Card as `card.power_fx`.
##
## recompute_power() reports every change here instead of driving the label itself, and this COALESCES a frame's
## worth of changes: one continuous refresh can grant and revoke in the same frame, and an expiry plus a re-grant can
## net to zero. Only the NET change, measured against what the readout is heading for, decides the look.
##
## Preloaded by PATH (no class_name), like card_damage_fx.gd.

const PRESENTATION := preload("res://scripts/core/presentation.gd")
const POWER_UP_BURST := preload("res://scripts/vfx/power_up_burst.gd")

## A card that has only just arrived takes its buffs WITHOUT the fanfare: setup boards, a Forward entering under an
## aura, and a teleport-in all land their continuous power in the arrival frames, and celebrating those would set
## off swords on half the board at the start of a match.
const ARRIVAL_GRACE_MS := 400

## Card is a Node3D; kept untyped so this file and card.gd do not depend on each other's class_name.
var _card: Node3D
var _flush_queued := false
var _field_since_ms := -1
var _burst: Node3D = null


func _init(card: Node3D) -> void:
	_card = card


## Card.enter_zone() calls this for every zone change.
func on_enter_zone(is_field: bool) -> void:
	_field_since_ms = Time.get_ticks_msec() if is_field else -1
	normalize()


## Stop a running burst and put the readout back at rest.
func normalize() -> void:
	if _burst != null and is_instance_valid(_burst):
		_burst.queue_free()
	_burst = null
	var label = _card.power_label if _card != null else null
	if label != null and label.has_method("cancel_power_up"):
		label.cancel_power_up()


## recompute_power() changed `power`. The label is updated at the end of the frame, with the net change.
func notice_power_change() -> void:
	if _flush_queued:
		return
	_flush_queued = true
	_flush.call_deferred()


func is_playing() -> bool:
	return _burst != null and is_instance_valid(_burst)


func burst() -> Node3D:
	return _burst if is_playing() else null


func _flush() -> void:
	_flush_queued = false
	if _card == null or not is_instance_valid(_card):
		return
	var label = _card.power_label
	if label == null:
		return
	var final_power: int = int(_card.power)
	var heading: int = int(label.target_power)
	if final_power == heading:
		return
	if final_power > heading and can_celebrate():
		_play(final_power)
	else:
		label.changePower(final_power)


## Is this a moment the player should SEE a power-up? A Forward drawn on its field slot with the readout up, settled
## there for a moment, and not a fast (rules-only) run.
func can_celebrate() -> bool:
	if PRESENTATION.fast_mode:
		return false
	if not _card.is_inside_tree() or not _card.is_on_field() or not _card.is_drawn_on_field():
		return false
	var label = _card.power_label
	if label == null or not label.visible or not _card.visible:
		return false
	if _field_since_ms < 0 or Time.get_ticks_msec() - _field_since_ms < ARRIVAL_GRACE_MS:
		return false
	return _card.get_viewport() != null and _card.get_viewport().get_camera_3d() != null


func _play(final_power: int) -> void:
	var label = _card.power_label
	if is_playing():
		# A second buff during the swords: keep the one burst and re-aim the count at the new total.
		label.animate_power_up(final_power, maxf(0.0, POWER_UP_BURST.NUMBER_START - _burst.call("elapsed")))
		return
	_burst = POWER_UP_BURST.new()
	_burst.name = "PowerUpBurst"
	_card.add_child(_burst)
	_burst.call("setup", _card, int(_card.get_instance_id()))
	label.animate_power_up(final_power, POWER_UP_BURST.NUMBER_START)
