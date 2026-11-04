import struct
import sys
from pathlib import Path

vpk = Path(sys.argv[1])
want = sys.argv[2]
out = Path(sys.argv[3])
data = vpk.read_bytes()
sig, version = struct.unpack_from('<II', data, 0)
if sig != 0x55AA1234:
    raise SystemExit('not a VPK')
tree_size = struct.unpack_from('<I', data, 8)[0]
header = 28 if version == 2 else 12
pos = header
end = header + tree_size

def cstr(pos):
    z = data.index(b'\x00', pos)
    return data[pos:z].decode('utf-8', 'replace'), z + 1

found = None
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
                raise SystemExit('bad entry')
            preload_data = data[pos:pos + preload]
            pos += preload
            full = (folder + '/' if folder else '') + name + ('.' + ext if ext else '')
            if full == want:
                found = (archive, offset, length, preload_data)

if not found:
    raise SystemExit('not found: ' + want)
archive, offset, length, preload = found
if archive == 0x7FFF:
    blob = preload
else:
    if preload:
        blob = preload
    else:
        if archive == 0:
            blob = data[offset:offset + length]
        else:
            part = vpk.parent / ('pak01_%03d.vpk' % archive)
            with part.open('rb') as f:
                f.seek(offset)
                blob = f.read(length)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_bytes(blob)
print('wrote %d bytes to %s (archive %d)' % (len(blob), out, archive))
