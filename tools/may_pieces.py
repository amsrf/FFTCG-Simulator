import re

# ---- scripts/Instruction.gd: may fields ---------------------------------------------------------------
p = 'scripts/Instruction.gd'
s = open(p, encoding='utf-8').read()
s = s.replace('''var condition: String = ""

func _init(p_action: String, p_executor: String, p_value = null, p_condition: String = "") -> void:
	action = p_action
	executor = p_executor
	value = p_value
	condition = p_condition''', '''var condition: String = ""

## OPTIONAL INSTRUCTION ("you may ..."). The choice is made when the instruction is REACHED, i.e. at resolution and
## after targets are locked, which is the rule. `may_by == "opponent"` hands the decision to the other player
## (Leon 60), and `may_prompt` is the confirm button's short text ("Deal 6000").
var may: bool = false
var may_by: String = ""
var may_prompt: String = ""

func _init(p_action: String, p_executor: String, p_value = null, p_condition: String = "",
		p_may: bool = false, p_may_by: String = "", p_may_prompt: String = "") -> void:
	action = p_action
	executor = p_executor
	value = p_value
	condition = p_condition
	may = p_may
	may_by = p_may_by
	may_prompt = p_may_prompt''')
open(p, 'w', encoding='utf-8').write(s)
print('Instruction updated')

# ---- card.gd: parse the new keys -----------------------------------------------------------------------
p = 'scripts/card.gd'
s = open(p, encoding='utf-8').read()
s = s.replace('''		var condition: String = json_instruction.get("condition", "")
		ans.append(Instruction.new(action, executor, value, condition))''', '''		var condition: String = json_instruction.get("condition", "")
		var may_use: bool = bool(json_instruction.get("may", false))
		var may_by: String = str(json_instruction.get("may_by", ""))
		var may_prompt: String = str(json_instruction.get("may_prompt", ""))
		ans.append(Instruction.new(action, executor, value, condition, may_use, may_by, may_prompt))''')
open(p, 'w', encoding='utf-8').write(s)
print('Card parsing updated')

# ---- agent.gd: confirm_optional + choose_hand_card_to_play ---------------------------------------------
p = 'scripts/agents/agent.gd'
s = open(p, encoding='utf-8').read()
anchor = '''## CHOOSE A CARD FROM A ZONE'''
add = '''## "YOU MAY ..." The instruction asks its controller (or the opponent, for Leon 60) when it is reached.
## Default TRUE: an AI or a mock takes every optional effect, and nothing can hang waiting for one.
func confirm_optional(_player_id: int, _prompt: String) -> bool:
	await _settle()
	return true

## Choose a card from HAND to play for free (Vaan 63, Leon 60). Returns a card id, or -1.
func choose_hand_card_to_play(_owner_id: int, ids: Array, _filter: Dictionary) -> int:
	await _settle()
	return int(ids[0]) if not ids.is_empty() else -1

'''
s = s.replace(anchor, add + anchor, 1)
open(p, 'w', encoding='utf-8').write(s)
print('Agent updated')

# ---- local_agent.gd: the two-button confirm and the hand picker ----------------------------------------
p = 'scripts/agents/local_agent.gd'
s = open(p, encoding='utf-8').read()
anchor = '''## THE BREAK ZONE SEARCH IS THE DECK SEARCH.'''
add = '''## CONFIRM / REFUSE for a "you may" instruction. The confirm button carries the short prompt ("Deal 6000"), so the
## player can see what they are agreeing to; Refuse is the cancel button.
##
## The answers live on MEMBERS because GDScript lambdas capture locals by value — assigning to a local inside the
## callback would never reach this function.
var _optional_answer: bool = false
var _optional_settled: bool = false

func confirm_optional(_player_id: int, prompt: String) -> bool:
	var assistant: Assistant = game.assistant
	_optional_settled = false
	_optional_answer = false
	var text: String = prompt if prompt != "" else "Confirm"
	assistant.show_modal(text, "Refuse",
		func():
			_optional_answer = true
			_optional_settled = true,
		func():
			_optional_answer = false
			_optional_settled = true,
		true, true)
	while not _optional_settled:
		await game.get_tree().process_frame
	assistant.hide_buttons()
	return _optional_answer

## Free play from hand — the same window, over the hand instead of a zone.
func choose_hand_card_to_play(_owner_id: int, ids: Array, filter: Dictionary) -> int:
	if ids.is_empty():
		return -1
	var window = DECK_SEARCH.instantiate()
	game.add_child(window)
	window.open(ids, filter, "Choose a card in your hand to play.")
	return await window.finished

'''
s = s.replace(anchor, add + anchor, 1)
open(p, 'w', encoding='utf-8').write(s)
print('LocalAgent updated')

# ---- hand.gd: remove a card from hand for a free play ---------------------------------------------------
p = 'scripts/hand.gd'
s = open(p, encoding='utf-8').read()
anchor = '''func discard_card(card: Card) -> void:'''
add = '''## TAKE A CARD OUT OF HAND TO PLAY IT, without charging for it (Vaan / Leon: "play ... from your hand").
## The card itself is reparented by Field.play_card(); this only stops the hand owning it, exactly like discard_card.
func remove_for_play(card: Card) -> void:
	cards.erase(card)
	update_card_positions()

'''
s = s.replace(anchor, add + anchor, 1)
open(p, 'w', encoding='utf-8').write(s)
print('Hand updated')

for f in ('scripts/Instruction.gd', 'scripts/card.gd', 'scripts/agents/agent.gd',
          'scripts/agents/local_agent.gd', 'scripts/hand.gd'):
    d = open(f, 'rb').read().replace(b'\r\n', b'\n')
    open(f, 'wb').write(d)
