class_name ManaCost
extends RefCounted

var cost: Dictionary

func _init(火=0, 風=0, 土=0, 水=0, 雷=0, 闇=0, 光=0, 氷=0, neutral=0):
	cost = {
		'火': 火, '風': 風, '土': 土, '水': 水, 
		'雷': 雷, '闇': 闇, '光': 光, '氷': 氷, 
		'neutral': neutral
	}
# Returns true if ALL cost values are <= 0 (fully paid/overpaid)
func is_fully_paid() -> bool:
	for key in cost:
		if cost[key] > 0:
			return false  # Found an unpaid cost
	return true  # All costs are <= 0

# Addition operator
func add(other: ManaCost) -> ManaCost:
	var result := ManaCost.new()
	for key in cost:
		result.cost[key] = self.cost[key] + other.cost[key]
	return result	
# Custom subtraction: Neutral covers any missing elements
func sub(other: ManaCost) -> ManaCost:
	var result := ManaCost.new()
	var remaining_neutral = other.cost['neutral']  # Track neutral to deduct
	
	# Step 1: Deduct exact element matches first
	for key in cost:
		if key == 'neutral': continue  # Skip neutral for now
		var requested = other.cost[key]
		var available = self.cost[key]
		
		if available >= requested:
			result.cost[key] = available - requested
		else:
			# Use neutral to cover the shortage
			var shortage = requested - available
			if remaining_neutral >= shortage:
				result.cost[key] = 0
				remaining_neutral -= shortage
			else:
				result.cost[key] = available - requested + remaining_neutral
				remaining_neutral = 0
	
	# Step 2: Deduct remaining neutral costs (if any)
	result.cost['neutral'] = max(self.cost['neutral'] - remaining_neutral, 0)
	return result

func contains(other: ManaCost) -> bool:
	var leftover_mana = 0  # Tracks mana that can be converted to neutral
	print('contains')
	print('self', self)
	print(other)
	# 1. Check specific mana requirements
	for key in other.cost:
		if key == 'neutral':
			continue  # Handle neutral separately
			
		var available = self.cost.get(key, 0)
		var required = other.cost.get(key, 0)
		
		if available < required:
			return false  # Not enough of this specific mana
			
		# Track excess mana that can be used for neutral
		leftover_mana += (available - required)
	
	# 2. Check neutral requirement
	var neutral_needed = other.cost['neutral']
	
	# Can pay with: (available_neutral) + (leftover_mana of any type)
	return (leftover_mana) >= neutral_needed

# Optional: Pretty-print the cost
func _to_string() -> String:
	var parts := []
	for key in cost:
		if cost[key] > 0:
			parts.append("%d %s" % [cost[key], key])
	return ", ".join(parts) if parts.size() > 0 else "0"
