#!/usr/bin/env python3
"""air_from_metallib.py FILE OUTDIR: find the metallib in FILE (a .metallib, or a program that embeds one) and
write each function's AIR bitcode module to OUTDIR/fNN.bc. A metallib holds one module per function, each in an
LLVM bitcode wrapper (magic 0x0B17C0DE, then version, offset and size, little-endian)."""
import os
import struct
import sys

data = open(sys.argv[1], 'rb').read()
out = sys.argv[2]
at = data.find(b'MTLB')
if at < 0:
    sys.exit('no metallib in ' + sys.argv[1])
lib = data[at:at + struct.unpack_from('<Q', data, at + 16)[0]]
n = i = 0
while (i := lib.find(b'\xde\xc0\x17\x0b', i)) >= 0:
    offset, size = struct.unpack_from('<II', lib, i + 8)
    with open(os.path.join(out, 'f%02d.bc' % n), 'wb') as f:
        f.write(lib[i:i + offset + size])
    n += 1
    i += 4
if not n:
    sys.exit('no AIR modules in the metallib')
print('    %d AIR modules' % n)
