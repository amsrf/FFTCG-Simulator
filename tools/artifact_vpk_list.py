import struct
import sys
import re
from pathlib import Path

path = Path(sys.argv[1])
pattern = re.compile(sys.argv[2], re.I) if len(sys.argv) > 2 else None
data = path.read_bytes()
sig, version = struct.unpack_from('<II', data, 0)
if sig != 0x55AA1234:
    raise SystemExit('not a VPK')
if version == 2:
    tree_size = struct.unpack_from('<I', data, 8)[0]
    header = 28
else:
    tree_size = struct.unpack_from('<I', data, 8)[0]
    header = 12
pos = header
end = header + tree_size
entries = []

def cstr(pos):
    z = data.index(b'\x00', pos)
    return data[pos:z].decode('utf-8', 'replace'), z + 1

while pos < end:
    ext, pos = cstr(pos)
    if not ext:
        break
    while True:
        folder, pos = cstr(pos)
        if not folder:
            break
        while True:
            name, pos = cstr(pos)
            if not name:
                break
            crc, preload, archive, offset, length = struct.unpack_from('<IHHII', data, pos)
            pos += 16
            term = struct.unpack_from('<H', data, pos)[0]
            pos += 2
            if term != 0xFFFF:
                raise SystemExit('bad entry terminator at %x' % (pos - 2))
            preload_data = data[pos:pos + preload]
            pos += preload
            full = (folder + '/' if folder else '') + name + ('.' + ext if ext else '')
            entries.append((full, archive, offset, length, preload_data))

for full, archive, offset, length, preload in entries:
    if pattern is None or pattern.search(full):
        print('%s\tarchive=%d\toffset=%d\tlength=%d\tpreload=%d' % (
            full, archive, offset, length, len(preload)))
print('ENTRIES', len(entries), file=sys.stderr)
