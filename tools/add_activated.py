import json

BLOCK = r'''
	"22":{
		"skill":[
			{
				"cost":{"neutral":1},
				"text":"《1》: Firion gains First Strike until the end of the turn.",
				"instructions":[{"name":"add_status_effect","author":"card","argument":["first_strike",1]}]
			},
			{
				"cost":{"neutral":1},
				"text":"《1》: Firion gains Brave until the end of the turn.",
				"instructions":[{"name":"add_status_effect","author":"card","argument":["brave",1]}]
			},
			{
				"cost":{"neutral":2},
				"text":"《2》: Choose 1 Forward. Deal it 1000 damage.",
				"choose_target":{"is_type":"Forward"},
				"instructions":[{"name":"damage_targets","author":"game","argument":[1000]}]
			},
			{
				"cost":{"neutral":2},
				"text":"《2》: Firion gains +1000 power until the end of the turn.",
				"instructions":[{"name":"power_change","author":"card","argument":[1000,1]}]
			}
		]
	},
	"84":{
		"skill":[
			{
				"cost":{"風":1},
				"text":"《Wind》: Choose 1 Forward. Deal it 1000 damage.",
				"choose_target":{"is_type":"Forward"},
				"instructions":[{"name":"damage_targets","author":"game","argument":[1000]}]
			},
			{
				"tap":true,
				"cost":{},
				"text":"《Dull》: Choose 1 Forward. Deal it 2000 damage.",
				"choose_target":{"is_type":"Forward"},
				"instructions":[{"name":"damage_targets","author":"game","argument":[2000]}]
			}
		]
	}
'''

path = 'assets/card_effects.json'
text = open(path, encoding='utf-8').read().rstrip()
if '"Firion gains First Strike' in text:
    raise SystemExit('already applied')
index = text.rfind('}')
text = text[:index] + ',' + BLOCK + text[index:] + '\n'
data = json.loads(text)
open(path, 'w', encoding='utf-8').write(text)
print('valid, entries', len(data), '| 22 skills', len(data['22']['skill']), '| 84 skills', len(data['84']['skill']))
