extends "res://scripts/effects/card_effect.gd"
## Mime 1-173C
##
## "When your Attack Phase starts, name 1 Element other than Light and Dark. Until the end of the turn, the Element of
## Mime becomes the named one."
##
## The Element is a temporary override, not a printed-property edit. Card.current_elements() consults the status when
## it is asked, and turn_end() expires it. The party-attack draw remains on the JSON path until that hook is migrated.

const CHOOSABLE: Array[String] = ["火", "氷", "風", "土", "雷", "水"]


func handlers() -> Dictionary:
	return {
		EVENTS.Event.PARTY_ATTACK: Callable(self, "when_party_attack"),
		EVENTS.Event.ATTACK_PHASE_START: Callable(self, "attack_phase_start"),
	}


func attack_phase_start(ctx) -> void:
	# The event fires for both players' Attack Phases; only Mime's controller gets to name an Element.
	if int(ctx.event_data.get("player_id", 0)) != ctx.owner_id:
		return
	var chosen: String = await ctx.choose_element(CHOOSABLE, "Name an Element")
	if chosen != "":
		ctx.set_element_until_end_of_turn(ctx.source, chosen)

func when_party_attack(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
