# card_state.gd
class_name CardState  # Makes it globally available
extends RefCounted   # Lightweight base (not a Node)

func handle_click():
	push_error("Not implemented! Override this method.")
