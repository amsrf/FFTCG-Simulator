import json
import re

db = json.load(open('assets/card_database.json', encoding='utf-8'))['cards']
eff = json.load(open('assets/card_effects.json', encoding='utf-8'))

KEYWORD_ONLY = re.compile(r'^\s*(Haste|Brave|First Strike)\s*$', re.IGNORECASE)

done, vanilla, todo, no_text = [], [], [], []
for i, c in enumerate(db[:100], 1):
    text = (c.get('text_en') or '').strip()
    entry = eff.get(str(i))
    label = '#%d %s %s [%s]' % (i, c.get('code'), c.get('name_en'), c.get('type_en'))
    if entry is not None:
        done.append((label, sorted(entry.keys())))
    elif text == '' or KEYWORD_ONLY.match(text):
        # Cards whose whole text is a keyword we already support (haste/brave/first_strike) still need a data entry!
        if text == '':
            no_text.append(label)
        else:
            todo.append((label, 'KEYWORD-ONLY: ' + text))
    else:
        todo.append((label, text))

print('=== SUMMARY (ids 1-100) ===')
print('entries in card_effects :', len(done))
print('no text at all          :', len(no_text))
print('text but no entry       :', len(todo))
print('total                   :', len(done) + len(no_text) + len(todo))
print()
print('=== IMPLEMENTED (%d) ===' % len(done))
for label, keys in done:
    print(' ', label, '->', ', '.join(keys))
print()
print('=== PLAIN / NO TEXT (%d) ===' % len(no_text))
for label in no_text:
    print(' ', label)
print()
print('=== TO DO (%d) ===' % len(todo))
for label, text in todo:
    print('-' * 100)
    print(label)
    print('  ' + text.replace('\n', '\n  '))
