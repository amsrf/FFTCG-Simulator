extends RefCounted

class_name Parser

func parse(instruction: String) -> Instruction:
	# Step 1: Remove ALL text inside [[...]] brackets (including the brackets)
	var clean_text = instruction.replace("[[ex]]EX BURST[[/]]", "").strip_edges()
	# Step 2: Parse the remaining text
	var first_word = clean_text.split(" ", true, 1)[0].to_lower()  # Split on first space only
	print('first word', first_word)
	
	match first_word:
		"choose":
			return _parse_choose(clean_text)
		"deal":
			return _parse_deal(clean_text)
		_:
			push_error("Unknown instruction: ", instruction)
			return Instruction.new("nothing", "game")
func parse_conditional(text: String) -> Dictionary:
	# Step 1: Remove ALL text inside [[...]] brackets (including the brackets)
	var clean_text = text.replace("[[ex]]EX BURST[[/]]", "").strip_edges()
	# Step 2: Parse the remaining text
	var first_word = clean_text.split(" ", true, 1)[0].to_lower()
	
	match first_word:
		"when":
			return _parse_when(clean_text)
		_:
			return {}
func parse_card(full_text: String):
	var blocks = split_text_blocks(full_text)
	
	
func split_text_blocks(full_text: String) -> Array[String]:
	# Split the text at each [[br]] marker
	var blocks = full_text.split("[[br]]", false)
	
	# Trim whitespace from each block and remove any empty strings
	var result: Array[String] = []
	for block in blocks:
		var trimmed = block.strip_edges()
		if trimmed != "":
			result.append(trimmed)
	
	return result
	

func get_summon_instructions(text: String) -> Array[Instruction]:
	var raw_commands = text.split(".", false)
	var instructions: Array[Instruction] = []
	for command in raw_commands:
		var ins: Instruction = parse(command)
		instructions.append(parse(command))
	instructions.append(Instruction.new("pop_stack", "game"))
	instructions.append(Instruction.new("enforce_game_state_rules", "game"))
	return instructions
	
func get_character_block_instructions(text_block: String) -> Array[Instruction]:
	# First normalize the text by replacing all whitespace sequences with single spaces
	var normalized_text = text_block.replace("\n", " ").replace("\t", " ").replace("  ", " ").strip_edges()
	
	# Then split by either periods or commas, but properly handle the sequential splitting
	var raw_commands = []
	var instructions: Array[Instruction] = []
	var current_split = normalized_text.split(".", false)
	
	for part in current_split:
		# Further split each part by commas
		var sub_parts = part.split(",", false)
		for sub_part in sub_parts:
			var trimmed = sub_part.strip_edges()
			if trimmed != "":
				raw_commands.append(trimmed)
	for command in raw_commands:
		var ins: Instruction = parse(command)
		instructions.append(parse(command))
	instructions.append(Instruction.new("pop_stack", "game"))
	instructions.append(Instruction.new("enforce_game_state_rules", "game"))
	return instructions

	
func _parse_choose(text):
	var regex = RegEx.new()
	regex.compile("(?i)^choose\\s+(?<count>\\d+)\\s+(?<criteria>\\w+)")
	var result = regex.search(text)  # Example input

	if result:
		var count = result.get_string("count").to_int()
		var criteria:String = result.get_string("criteria")  # "Forward" in this case
		var targeting_criteria = [[
			[  
				["is_type", [criteria]]  # Convert to lowercase if needed
			]
		]] #Extra brackets for callv call
		return Instruction.new("request_target", "game", targeting_criteria)
	else:
		push_error("Failed to parse Choose")
	
func _parse_deal(text):
	var regex = RegEx.new()
	print(text,'ALO')
	regex.compile("^Deal\\s+it\\s+(?<damage>\\d+)\\s+damage$")
	var result = regex.search(text)
	var damage = int(result.get_string("damage"))
	
	if result:
		return Instruction.new("damage_forward", "game", damage)
	else:
		push_error("Failed to parse Deal")

func _parse_when(text):
	pass
	
