extends "res://scripts/effects/ability_spec.gd"
## A code-owned activated ability.
##
## The metadata fields inherited from AbilitySpec still let the engine answer "can this be activated?" and show the
## ability before it runs. The BEHAVIOUR is separate code:
##
##   on_activation(ctx) -> bool   optional. Return false to cancel before the effect reaches the stack.
##   on_resolve(ctx)    -> void   what the ability actually does when the stack object resolves.
##
## The default activation accepts and the default resolution does nothing, so a card only writes what it needs.
var _owner = null


func _init(owner = null) -> void:
	super({})
	_owner = owner
	# Compatibility for probes/old call sites that still ask for a Callable handler.
	run = Callable(self, "on_resolve")


func on_activation(_ctx) -> bool:
	return true


func on_resolve(_ctx) -> void:
	pass


## The single entry point the stack uses.
func resolve(ctx) -> void:
	await on_resolve(ctx)
