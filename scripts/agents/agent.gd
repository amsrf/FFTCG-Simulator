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

## The attackers this player declares, in party order. A single attack is a list of one, so every caller can treat
## parties and single attacks the same way. The default forwards decide_attacker(), which keeps MockAgent and any
## future agent working without knowing about parties.
func decide_attackers(player_id: int) -> Array:
	var one: Card = await decide_attacker(player_id)
	var out: Array = []
	if one != null:
		out.append(one)
	return out

## Return the blocker to declare, or null to not block.
func decide_blocker(_player_id: int, _attacker: Card) -> Card:
	await _settle()
	return null

## How a BLOCKER's power is divided across the members of the party it blocked, in 1000-point increments, summing to
## `total`. One entry per party member, in party order.
##
## Default is the greedy split: chunks of 1000 go to the strongest member first, then the next, and round again if
## there is enough damage — which maximises the chance of breaking something. `LocalAgent` will override this with
## the arrow window (up/down per card) so the human can choose; until then a human gets the same greedy answer as
## the AI rather than an unanswerable prompt.
func choose_party_damage_split(_player_id: int, party: Array, total: int) -> Array:
	await _settle()
	return greedy_party_split(party, total)

func greedy_party_split(party: Array, total: int) -> Array:
	var out: Array = []
	if party.is_empty():
		return out
	out.resize(party.size())
	out.fill(0)
	var order: Array = []
	for i in range(party.size()):
		order.append(i)
	order.sort_custom(func(a, b): return party[a].power > party[b].power)
	var left: int = maxi(total, 0)
	var k: int = 0
	while left > 0:
		var chunk: int = mini(1000, left)
		out[order[k % order.size()]] += chunk
		left -= chunk
		k += 1
	return out

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

## Pick which card this player discards from their own hand. "Pull" shape: return the card, or null to discard
## nothing.
##
## A discard is the OWNER'S choice, which is why this is a seam rather than something the effect decides. The rules
## layer asks the seat that owns the hand and takes whatever comes back — LocalAgent opens the hand UI, AIAgent
## picks heuristically, and a RemoteAgent answers over the network. None of that is visible to Game.
##
## Returning null is always safe: the caller stops discarding and carries on.
func choose_discard(_owner_id: int, _cards: Array) -> Card:
	await _settle()
	return null
