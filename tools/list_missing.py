import json
import re

database = json.load(open('assets/card_database.json', encoding='utf-8'))['cards']
effects = json.load(open('assets/card_effects.json', encoding='utf-8'))

missing = []
for card_id in range(1, 101):
    card = database[card_id - 1]
    text = (card.get('text_en') or '').strip()
    if not text or str(card_id) in effects:
        continue
    clean = re.sub(r'\[\[/?[a-z]*\]\]', ' ', text)
    clean = re.sub(r'\s+', ' ', clean)
    print('%3d %-9s %-8s %-12s cost %-3s pow %-5s | %s' % (
        card_id, card.get('code'), card.get('type_en'), str(card.get('element')),
        card.get('cost'), card.get('power'), clean[:160]))
    missing.append(card_id)

print()
print('missing', len(missing), missing)
