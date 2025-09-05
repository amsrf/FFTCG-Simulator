extends Node  # Keep Node for data management

var card_database: Array
var card_effects: Dictionary

func _ready():
	load_card_database()
	load_card_effects()
	print(card_effects,'amanda')
	print('31' in card_effects)
	
func load_card_effects():
	var file_path = "res://assets/card_effects.json"
	# Open the file for reading
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_data = file.get_as_text()
		
		# Create a JSON instance and parse the data
		var json = JSON.new()  
		var parse_result = json.parse(json_data)

		if parse_result == OK:
			card_effects = json.data
			print("Card database loaded successfully.")
		else:
			print("JSON parsing error: ", json.get_error_message(), " at line: ", json.get_error_line())

		file.close()
func load_card_database():
	var file_path = "res://assets/card_database.json"
	
	# Check if the file exists
	if not FileAccess.file_exists(file_path):
		print("Card database file not found.")
		return
	
	# Open the file for reading
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_data = file.get_as_text()
		
		# Create a JSON instance and parse the data
		var json = JSON.new()  
		var parse_result = json.parse(json_data)

		if parse_result == OK:
			card_database = json.data['cards']
			print("Card database loaded successfully.")
		else:
			print("JSON parsing error: ", json.get_error_message(), " at line: ", json.get_error_line())

		file.close()
