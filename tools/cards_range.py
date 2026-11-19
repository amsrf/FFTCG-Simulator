"""Print a compact table for a card-id range: id | code | name | type | element | cost | power | text."""
import json
import re
import sys

first = int(sys.argv[1]) if len(sys.argv) > 1 else 100
last = int(sys.argv[2]) if len(sys.argv) > 2 else 216

db = json.load(open('assets/card_database.json', encoding='utf-8'))['cards']
import os
code_ids = {int(os.path.basename(p)[5:-3]) for p in __import__('glob').glob('assets/effects/card_*.gd') if os.path.basename(p)[5:-3].isdigit()}


def clean(text):
    text = re.sub(r'\[\[/?[a-zA-Z]+\]\]', ' ', text or '')
    return re.sub(r'\s+', ' ', text).strip()


for i in range(first, min(last, len(db)) + 1):
    c = db[i - 1]
    elem = c.get('element')
    if isinstance(elem, list):
        elem = ''.join(str(x) for x in elem)
    mark = '*' if i in code_ids else ' '
    print('%s%3d|%s|%s|%s|%s|c%s|p%s|%s' % (
        mark, i, c.get('code', ''), c.get('name_en', ''), c.get('type_en', ''),
        elem, c.get('cost', ''), c.get('power', ''), clean(c.get('text_en', ''))))
