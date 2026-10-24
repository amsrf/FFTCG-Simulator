import json

BLOCK = r'''
	"9":{
		"conditional_power":[{"condition":{"is_type":"Forward","controller":"player","is_category":"VII","exclude":{"is_named":"Cloud"}},"value":2000}],
		"when_enter_field":{
			"choose_target":{"is_type":"Forward","controller":"opponent"},
			"instructions":[{"name":"damage_targets","author":"game","argument":[2000]}]
		}
	},
	"20":{
		"cost_aura":{"for":"Summon","name":"Bahamut","from":"own","delta":-2},
		"when_attack":{"instructions":[{"name":"add_status_effect","author":"card","argument":["first_strike",1]}]}
	},
	"28":{
		"ex_burst":"when_enter_field",
		"when_enter_field":{"instructions":[{"name":"search_deck","author":"game","argument":[{"is_named":"Lann"}]}]},
		"skill":[
			{
				"cost":{"火":1,"neutral":1},
				"tap":true,
				"text":"《Fire》《1》《Dull》: Choose 1 Lann. It gains +1000 power until the end of the turn.",
				"choose_target":{"is_named":"Lann"},
				"instructions":[{"name":"power_change_targets","author":"game","argument":[1000,1]}]
			}
		]
	},
	"58":{
		"when_cause_damage_to_player":{
			"choose_target":{"is_type":"Forward","is_tapped":true},
			"instructions":[{"name":"damage_targets","author":"game","argument":[7000]}]
		},
		"skill":[
			{
				"s_cost":true,
				"cost":{"氷":2},
				"text":"Desperado 《S》《Ice》《Ice》: Choose 1 dull Forward. Deal it 9000 damage.",
				"choose_target":{"is_type":"Forward","is_tapped":true},
				"instructions":[{"name":"damage_targets","author":"game","argument":[9000]}]
			}
		]
	},
	"59":{
		"ex_burst":"when_enter_field",
		"when_enter_field":{
			"choose_target":{"is_type":"Forward","controller":"opponent"},
			"instructions":[
				{"name":"dull_targets","author":"game","argument":[]},
				{"name":"add_status_to_targets","author":"game","argument":["frozen",1],"condition":"controls:Squall"}
			]
		},
		"conditional_power":[{"condition":{"is_named":"Squall","controller":"player"},"value":2000}]
	},
	"61":{
		"ex_burst":"when_cast",
		"when_cast":{
			"choose_target":{"is_type":"Forward","is_cost_at_least":5},
			"instructions":[{"name":"break_targets","author":"game","argument":[]}]
		}
	},
	"79":{
		"ex_burst":"when_enter_field",
		"when_enter_field":{"instructions":[{"name":"search_deck","author":"game","argument":[{"is_named":"Hope"}]}]}
	},
	"80":{
		"ex_burst":"when_enter_field",
		"when_enter_field":{"instructions":[{"name":"untap_all_matching","author":"game","argument":[{"is_character":true,"controller":"player","is_element":"風"}]}]}
	}
'''

path = 'assets/card_effects.json'
text = open(path, encoding='utf-8').read().rstrip()
if '"9"' in text and '"damage_double"' in text:
    pass
if '"is_category"' in text:
    raise SystemExit('block already applied')
index = text.rfind('}')
text = text[:index] + ',' + BLOCK + text[index:] + '\n'
data = json.loads(text)
open(path, 'w', encoding='utf-8').write(text)
print('valid, entries', len(data), '| added:', [k for k in ('9', '20', '28', '58', '59', '61', '79', '80') if k in data])
