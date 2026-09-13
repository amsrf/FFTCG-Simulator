extends RefCounted
class_name Agent
## Decision seam between the game loop and whoever plays a side.
##
## The loop only ever calls these methods, so LocalAgent (human at this
## machine), AIAgent (heuristics) and a future RemoteAgent (network) are
## interchangeable. Implementations must act only through the game's public
## API and answer with game objects / ids — never reach into UI internals —
## so a networked client can answer the same questions over the wire.
##
## Two shapes are used:
##   * pull  — return the answer (decide_attacker / decide_blocker / pay_cost)
##   * drive — perform the inputs a human would have performed in the UI and let
##             the existing signal continuation run (choose_target /
##             choose_card_in_hand). LocalAgent does nothing for these: the human
##             at this machine is the one clicking.

var game: Node = null

func bind(game_root: Node) -> void:
	game = game_root

## Keeps every seam method a coroutine, so callers can `await` uniformly no
## matter which implementation is plugged in (local, AI or remote).
func _settle() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame

## Called when this side receives priority. Returns **true if this player
## performed an action** (played a card / activated an ability), false if they
## passed. The loop needs to be told rather than inferring it: the rules hand
## priority to the other player after an action, and playing a Character is an
## action that never changes the stack.
func take_priority(_player_id: int) -> bool:
	await _settle()
	return false

## Return the attacker to declare, or null to declare no attack.
func decide_attacker(_player_id: int) -> Card:
	await _settle()
	return null

## Return the blocker to declare, or null to not block.
func decide_blocker(_player_id: int, _attacker: Card) -> Card:
	await _settle()
	return null

## Pay `cost` ({element: amount, "neutral": n}) for the card being played, and
## return whether it is covered. Only used for non-local players — the human
## pays by selecting cards in the payment modal instead.
func pay_cost(_owner_id: int, _cost: Dictionary) -> bool:
	await _settle()
	return false

## Pick a target for `source`. "Drive" shape: set the target and confirm, or
## cancel. LocalAgent leaves it to the human's clicks.
func choose_target(_owner_id: int, _source: Card, _criteria: Dictionary) -> void:
	await _settle()

## Pick a card from hand for a "may"/"must" choose-card effect. "Drive" shape.
func choose_card_in_hand(_owner_id: int, _criteria: Dictionary, _required: bool) -> void:
	await _settle()
