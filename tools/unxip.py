#!/usr/bin/env python3
"""unxip.py XIP OUTDIR [PATTERN]: stream an Xcode .xip and write only the entries whose path contains
PATTERN (default: the iPhoneOS SDKs) under OUTDIR. A .xip is a xar archive whose "Content" file is a pbzx
stream (chunks of xz) of an odc cpio archive; nothing else of Xcode is written to disk.
Files shared between SDKs are hard links: one entry of a (dev, ino) group carries the bytes, the others hold a
"NULLcanary" placeholder (Xcode 27.2: 2332 of the iPhoneOS SDK's files, their bytes under AppleTVOS, XROS, ...).
So two passes: the first finds the groups the SDK needs, the second writes their bytes wherever they appear."""
import lzma
import os
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

XIP, OUT = sys.argv[1], os.path.abspath(sys.argv[2])
PATTERN = sys.argv[3] if len(sys.argv) > 3 else 'Platforms/iPhoneOS.platform/Developer/SDKs/'


def inside(dest):
    """dest, after checking that it and the folder it goes in (symlinks resolved) stay under OUT."""
    real = os.path.realpath(os.path.dirname(dest))
    assert real == OUT or real.startswith(OUT + os.sep), ('escapes OUT', dest)
    return dest

f = open(XIP, 'rb')
magic, hsize, _ver, toc_c, _toc_u, _alg = struct.unpack('>4sHHQQI', f.read(28))
assert magic == b'xar!', magic
f.seek(hsize)
toc = ET.fromstring(zlib.decompress(f.read(toc_c)))
heap = hsize + toc_c
content = None
for node in toc.iter('file'):
    if node.findtext('name') == 'Content':
        content = node.find('data')
assert content is not None, 'no Content in the xar'
off, length = int(content.findtext('offset')), int(content.findtext('length'))
f.seek(heap + off)
end = heap + off + length
assert f.read(4) == b'pbzx', 'not pbzx'
f.read(8)


def chunks():
    while f.tell() < end:
        _flags, size = struct.unpack('>QQ', f.read(16))
        data = f.read(size)
        yield data if data[:6] != b'\xfd7zXZ\x00' else lzma.decompress(data)


class Stream:
    def __init__(self, it):
        self.it, self.buf, self.total = it, bytearray(), 0

    def read(self, n):
        while len(self.buf) < n:
            try:
                self.buf += next(self.it)
            except StopIteration:
                break
        out = bytes(self.buf[:n])
        del self.buf[:n]
        self.total += len(out)
        return out


def entries():
    """(dev+ino, mode, name, data) of every cpio entry, from a fresh read of the Content stream."""
    f.seek(heap + off + 4 + 8)
    st = Stream(chunks())
    while True:
        head = st.read(76)
        if len(head) < 76:
            return
        assert head[:6] == b'070707', head[:6]
        mode = int(head[18:24], 8)
        namesize = int(head[59:65], 8)
        filesize = int(head[65:76], 8)
        name = st.read(namesize)[:-1].decode('utf-8', 'replace')
        data = st.read(filesize)
        if name == 'TRAILER!!!':
            return
        yield head[6:18], mode, name, data


# Pass 1: the hard-link groups the SDK needs (its placeholders).
need = {}
for ino, mode, name, data in entries():
    if PATTERN in name and mode & 0o170000 == 0o100000 and data[:10] == b'NULLcanary':
        need.setdefault(ino, []).append(name)
print(f'pass 1: {sum(len(v) for v in need.values())} placeholders in {len(need)} hard-link groups', flush=True)
s = Stream(chunks())
written = files = 0
f.seek(heap + off + 4 + 8)
while True:
    head = s.read(76)
    if len(head) < 76:
        break
    assert head[:6] == b'070707', head[:6]
    mode = int(head[18:24], 8)
    namesize = int(head[59:65], 8)
    filesize = int(head[65:76], 8)
    name = s.read(namesize)[:-1].decode('utf-8', 'replace')
    data = s.read(filesize)
    if name == 'TRAILER!!!':
        break
    ino = head[6:18]
    if ino in need and mode & 0o170000 == 0o100000 and data[:10] != b'NULLcanary':
        for target in need.pop(ino):   # the group's bytes, for the SDK's placeholders
            t = target[target.find(PATTERN) + len(PATTERN):]
            dest = os.path.abspath(os.path.join(OUT, t))
            assert dest.startswith(OUT + os.sep), ('escapes OUT', target)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(inside(dest), 'wb') as o:
                o.write(data)
            os.chmod(dest, mode & 0o777)
            files += 1
            written += len(data)
    i = name.find(PATTERN)
    if i < 0:
        continue
    rel = name[i + len(PATTERN):]
    dest = os.path.abspath(os.path.join(OUT, rel))
    assert dest == OUT or dest.startswith(OUT + os.sep), ('escapes OUT', name)   # path join guard
    kind = mode & 0o170000
    if kind == 0o040000:
        os.makedirs(dest, exist_ok=True)
    elif kind == 0o120000:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.lexists(dest):
            os.remove(dest)
        os.symlink(data.decode(), dest)
    elif kind == 0o100000:
        if data[:10] == b'NULLcanary':
            continue   # written from its hard-link group
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(inside(dest), 'wb') as o:
            o.write(data)
        os.chmod(dest, mode & 0o777)
        files += 1
        written += len(data)
    if s.total >> 30 != (s.total - 76 - namesize - filesize) >> 30:
        print(f'{s.total >> 30} GiB read, {files} files ({written >> 20} MiB) written', flush=True)
print(f'done: {s.total >> 20} MiB read, {files} files, {written >> 20} MiB written to {OUT}; '
      f'{sum(len(v) for v in need.values())} placeholders without bytes')
