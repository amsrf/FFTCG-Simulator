import os
import re

root = '.'
files = []
for base, dirs, names in os.walk(root):
    if any(part in base for part in ('.git', '.godot', 'addons')):
        continue
    for n in names:
        if n.endswith(('.gd', '.tscn', '.tres')):
            files.append(os.path.join(base, n).replace('\\', '/'))

texts = {}
for f in files:
    try:
        texts[f] = open(f, encoding='utf-8', errors='ignore').read()
    except OSError:
        texts[f] = ''

gd_files = [f for f in files if f.endswith('.gd')]
print('gd files:', len(gd_files))
for f in sorted(gd_files):
    src = texts[f]
    m = re.search(r'^class_name\s+(\w+)', src, re.M)
    token = m.group(1) if m else os.path.basename(f)[:-3]
    path = 'res://' + f[2:] if f.startswith('./') else 'res://' + f
    hits = 0
    for other, txt in texts.items():
        if other == f:
            continue
        if re.search(r'\b' + re.escape(token) + r'\b', txt) or path in txt:
            hits += 1
    if hits == 0:
        print('UNREFERENCED', f, '| class' if m else '| path')
