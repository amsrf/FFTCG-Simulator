extends "res://scripts/vfx/vfx_cue.gd"
## Presentation for a `STATUS_APPLIED` event with status "unbreakable": a card GAINED "cannot be broken". The event is
## raised by Card._sync_status_vfx() when the status appears.
##
## Each card on the field gets one protect_shell.gd. The shells live under the tree root and free themselves; the cue
## holds the presentation queue only until the shell has closed around the card.

const SHELL := preload("res://scripts/vfx/protect_shell.gd")

var _shell_count: int = 0


func play(event: VfxEvent) -> void:
	for entry in event.targets:
		# Untyped first: assigning a FREED card to a `Card` variable is itself an error.
		if not is_instance_valid(entry) or not (entry is Card):
			continue
		var card: Card = entry
		if not card.is_drawn_on_field():
			continue
		var shell: Node3D = SHELL.new()
		shell.name = "ProtectShell"
		get_tree().root.add_child(shell)
		shell.call("setup", card)
		_shell_count += 1
	if _shell_count == 0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(SHELL.APPEAR_SECONDS).timeout


## Probe hook: how many shells this cue started.
func shell_count() -> int:
	return _shell_count
