extends Node
## Typed target definitions: CardQuery says WHICH cards, TargetRequest says where/how many, TargetSequence says stages.

const GAME_SCENE := preload("res://game.tscn")
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
const TARGET_SEQUENCE := preload("res://scripts/effects/target_sequence.gd")

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Targets] ok   ", what)
	else:
		_fails += 1
		print("[Targets] FAIL ", what)


func _ready() -> void:
	var query = CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT) \
		.tapped(false).cost_at_most(4).cost_at_least(1).excluding_source()
	var block: Dictionary = query.to_block()
	_expect(block.get("is_type") == "Forward", "CardQuery types a Forward filter")
	_expect(block.get("controller") == "opponent", "and a typed relative controller")
	_expect(block.get("is_tapped") == false, "and an active-card filter")
	_expect(int(block.get("is_cost_at_most", -1)) == 4 and int(block.get("is_cost_at_least", -1)) == 1,
		"and both cost bounds")
	_expect(block.get("is_source") == false, "excluding_source converts to is_source=false")

	var request = TARGET_REQUEST.field(query).up_to(3)
	var legacy: Dictionary = request.to_legacy()
	_expect(int(legacy.get("count", 0)) == 3 and legacy.get("is_type") == "Forward",
		"TargetRequest carries the query and max count")
	var stack_request = TARGET_REQUEST.stack(CARD_QUERY.new().of_type("Summon"))
	_expect(stack_request.to_legacy().get("in") == "stack", "TargetRequest types the stack domain")

	var sequence = TARGET_SEQUENCE.new([
		TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")).exactly(1),
		TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup")).exactly(1),
	])
	var stages: Array = sequence.to_legacy()
	_expect(stages.size() == 2 and stages[0].get("is_type") == "Forward" and stages[1].get("is_type") == "Backup",
		"TargetSequence keeps ordered stages")

	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.field
	var source: Card = game.create_card(8, "player")
	game.add_child(source)
	field.play_card(source, false, false)
	_expect(field.has_viable_target(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")), source, "Ability"),
		"Field accepts a typed TargetRequest directly")

	var spec = load("res://assets/effects/card_8.gd").new().activated_abilities()[0]
	var bridge: Dictionary = spec.as_skill_dict()
	var criteria: Dictionary = bridge.get("choose_target", {})
	_expect(criteria.get("is_type") == "Forward" and int(criteria.get("is_cost_at_most", -1)) == 3,
		"CardAbility converts its typed target to the legacy activation block")

	var filter_query = CARD_QUERY.new().of_type("Forward").of_category("VII").with_job("SOLDIER").power_at_least(5000)
	var filter_dict: Dictionary = filter_query.to_filter()
	_expect(filter_dict.get("type") == "Forward" and filter_dict.get("category") == "VII"
		and filter_dict.get("job") == "SOLDIER" and int(filter_dict.get("min_power", 0)) == 5000,
		"CardQuery also produces a deck-search filter")
	var ctx = source.make_effect_context()
	_expect(not ctx.cards_in("field", CARD_QUERY.new().of_type("Forward")).is_empty(),
		"cards_in accepts a typed CardQuery filter")
	_expect(CARD_QUERY.new().named("Tifa").to_filter().has("exact_name"),
		"named() keeps the exact-search spelling")
	_expect(CARD_QUERY.new().name_contains("Tifa").to_filter().get("name") == "Tifa",
		"name_contains() keeps the substring-search spelling")

	print("[Targets] %d checks | failures: %d" % [_checks, _fails])
	print("[Targets] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
