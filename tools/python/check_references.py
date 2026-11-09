"""Every res:// path written in the project's text files must point to a file that exists.

    python tools/python/check_references.py [project_root]

Scans scenes, resources, scripts, shaders, project.godot, export_presets.cfg and .import files. Paths built at run
time (containing % or {) are skipped. Prints each missing reference with where it was found; exit code 1 if any.
"""
import os, re, sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", ".."))
EXTS = (".tscn", ".tres", ".gd", ".gdshader", ".godot", ".cfg", ".import")
SKIP_DIRS = {".git", ".godot", "probe_logs", "__pycache__"}
# A quoted path is read to its closing quote (file names can contain spaces); an unquoted one (in a comment) to the
# first space or bracket.
REF = re.compile(r'"(res://[^"]*)"|\'(res://[^\']*)\'|(res://[^"\'\s\)\],`]+)')

missing, checked = [], 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for name in filenames:
        if not name.endswith(EXTS):
            continue
        path = os.path.join(dirpath, name)
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for match in REF.finditer(text):
            ref = next(g for g in match.groups() if g).rstrip(".:;")
            if "%" in ref or "{" in ref or ref.endswith("/") or ref == "res://":
                continue
            # .import files also name their imported cache copies (res://.godot/imported/...): not project files.
            if ref.startswith("res://.godot/"):
                continue
            checked += 1
            target = os.path.join(ROOT, ref[len("res://"):])
            if not os.path.exists(target):
                missing.append((os.path.relpath(path, ROOT), ref))

for where, ref in sorted(set(missing)):
    print(f"MISSING {ref}   (in {where})")
print(f"checked {checked} references, {len(set(missing))} missing")
sys.exit(1 if missing else 0)
