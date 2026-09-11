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
## Phase 2 covers priority and attack/block declaration. Targeting, mana
## payment and hand choices still run through the local UI path; routing them
## here is the next step (needed before an AI can actually play cards).

var game: Node = null

func bind(game_root: Node) -> void:
	game = game_root

## Keeps every seam method a coroutine, so callers can `await` uniformly no
## matter which implementation is plugged in (local, AI or remote).
func _settle() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame

## Called when this side receives priority. Return once done deciding; the
## priority loop detects stack growth itself, so acting is optional.
func take_priority(_player_id: int) -> void:
	await _settle()

## Return the attacker to declare, or null to declare no attack.
func decide_attacker(_player_id: int) -> Card:
	await _settle()
	return null

## Return the blocker to declare, or null to not block.
func decide_blocker(_player_id: int, _attacker: Card) -> Card:
	await _settle()
	return null
