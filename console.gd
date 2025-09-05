extends Control

@onready var input_field = $TextEdit
@onready var output_log = $RichTextLabel

var commands = {}

func _ready():
	# Basic commands
	register_command("help", "Show available commands", cmd_help)
	register_command("block", "Mock opponent blocking", cmd_block)
	register_command("pass", "Mock opponent passing", cmd_pass)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.2, 0.9)
	panel_style.border_color = Color(0.3, 0.3, 0.4)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	$Panel.add_theme_stylebox_override("panel", panel_style)
	
	# Text styling)
	output_log.add_theme_font_size_override("normal_font_size", 16)
	output_log.add_theme_color_override("default_color", Color(0.8, 0.8, 1.0))
	
	#hide()  # Start hidden

func _input(event):
	if event.is_action_pressed("toggle_console"):
		visible = !visible
		if visible:
			input_field.grab_focus()

func register_command(name, description, callback):
	commands[name] = {
		"description": description,
		"callback": callback
	}

func _on_TextEdit_text_entered(new_text):
	output_log.append_text("> " + new_text + "\n")
	process_command(new_text)
	input_field.clear()

func process_command(command):
	var parts = command.split(" ", false)
	var cmd = parts[0].to_lower()
	
	if commands.has(cmd):
		commands[cmd].callback.call(parts.slice(1))
	else:
		output_log.append_text("Unknown command. Type 'help' for list.\n")

# Command implementations
func cmd_help(_args):
	output_log.append_text("Available commands:\n")
	for cmd in commands:
		output_log.append_text("  %s - %s\n" % [cmd, commands[cmd].description])

func cmd_block(args):
	if args.size() == 0:
		# Block with first available creature
		var blockers = get_tree().get_first_node_in_group("game_manager").get_available_blockers()
		if blockers.size() > 0:
			output_log.append_text("Opponent blocks with %s\n" % blockers[0].name)
			# Call your game's block handling function here
		else:
			output_log.append_text("No available blockers\n")
	else:
		# Block with specific creature ID
		output_log.append_text("Opponent blocks with creature %s\n" % args[0])
		# Call your game's block handling function with specific creature

func cmd_pass(_args):
	output_log.append_text("Opponent chooses not to block\n")
	# Call your game's pass handling function
