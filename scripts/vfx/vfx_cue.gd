class_name VfxCue
extends Node3D
## Base for one-shot presentation scenes owned by the VfxDirector.
##
## A cue receives the full semantic event, including its targets, element,
## amount, mode, source, and deterministic seed. It should finish when the
## animation is over; the director frees it afterwards.
##
## Persistent status visuals should NOT be VfxCue: they are owned by the card
## status lifecycle instead (see Card.refresh_frozen_overlay()).


func play(_event: VfxEvent) -> void:
	await get_tree().process_frame


## Optional hard stop when a presentation is interrupted.
func cancel() -> void:
	queue_free()
