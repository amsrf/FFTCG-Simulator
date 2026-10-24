"""Report member variables / constants in a GDScript file that no other line references.

Run: python3 tools/member_audit.py [file.gd]
"""
import os
import re
import sys

TARGET = sys.argv[1] if len(sys.argv) > 1 else 'battle_field.gd'
SKIP = ('.git', '.godot', 'addons')

files = []
for base, dirs, names in os.walk('.'):
    if any(part in base for part in SKIP):
        continue
    for n in names:
        if n.endswith(('.gd', '.tscn', '.tres', '.json')):
            p = os.path.join(base, n).replace('\\', '/')
            if p.startswith('./'):
                p = p[2:]
            files.append(p)

texts = {f: open(f, encoding='utf-8', errors='ignore').read() for f in files}
src = texts[TARGET]
members = []
for i, ln in enumerate(src.splitlines(), 1):
    m = re.match(r'^(?:@export[^\n]*?)?\s*(?:@onready\s+)?(?:var|const)\s+([A-Za-z_]\w*)', ln)
    if m:
        members.append((m.group(1), i))

print('%s members: %d' % (TARGET, len(members)))
for name, line in members:
    hits = []
    for f, txt in texts.items():
        for j, ln in enumerate(txt.splitlines(), 1):
            if f == TARGET and j == line:
                continue
            code = re.sub(r'"[^"]*"|\'[^\']*\'', '', ln.split('#', 1)[0])
            if re.search(r'\b' + re.escape(name) + r'\b', code):
                hits.append((f, j))
    if not hits:
        print('  UNREFERENCED %-30s line %d' % (name, line))
