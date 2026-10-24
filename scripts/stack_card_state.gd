# StackCardState.gd
extends CardState
class_name StackCardState
## A card sitting in the stack.
##
## Its only interaction is a click: that selects it, which raises it in the fan and puts ITS
## targeting on display (see Stack.select_card). A stack object is resolved by the game rather
## than played by a player, so there is nothing else to do to it — no dragging, no payment.
##
## ONE EXCEPTION: while a targeting session asks for a STACK card (Summoner 53 countering a Summon), a click on a
## legal candidate means "choose this", not "raise this". `is_valid_target` is the same flag every other candidate
## uses, and the Field owns the session, so this branch only forwards the click.
var card: Card
var stack: Stack

func _init(card_ref: Card):
	card = card_ref
	stack = card.get_parent() as Stack

func handle_grabbed():
	if stack == null:
		return
	if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET and card.is_valid_target:
		var field = stack.get_parent().get("field")
		if field != null:
			field.set_target_card(card)
			var target_viewport: Viewport = card.get_viewport()
			if target_viewport != null:
				target_viewport.set_input_as_handled()
			return
	stack.select_card(card)
	# Mark the event handled so the "a click anywhere else returns the display to the top of the
	# stack" fallback cannot immediately undo the selection the player just made.
	var viewport: Viewport = card.get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()

func handle_released():
	pass
