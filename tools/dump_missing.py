import json
import re

ids = [int(x) for x in open('tools/_missing.txt', encoding='utf-8').read().split()]
database = json.load(open('assets/card_database.json', encoding='utf-8'))['cards']

for card_id in ids:
    card = database[card_id - 1]
    text = re.sub(r'\[\[/?[a-z]*\]\]', ' / ', card.get('text_en') or '')
    text = re.sub(r'\s+', ' ', text).strip()
    print('### %d %s | %s | cost %s | power %s | %s' % (
        card_id, card.get('code'), card.get('type_en'), card.get('cost'), card.get('power'), card.get('element')))
    print(text)
    print()
