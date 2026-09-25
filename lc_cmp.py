import struct, lzma, tarfile, io

DEB = "C:/Users/shosh/JumioObserver/probe_artifact/probe-deb/com.maurice.jumioprobe_1.0.0_iphoneos-arm64e.deb"
data = open(DEB, 'rb').read()

# ar parsen
off = 8
members = {}
while off < len(data):
    hdr = data[off:off+60]
    if len(hdr) < 60: break
    name = hdr[:16].strip().decode()
    size = int(hdr[48:58].strip() or 0)
    moff = off + 60
    members[name] = data[moff:moff+size]
    off = moff + size + (size % 2)

dec = lzma.decompress(members['data.tar.lzma'], format=lzma.FORMAT_ALONE)
tf = tarfile.open(fileobj=io.BytesIO(dec), mode='r:')
dl = None
for n in tf.getnames():
    if n.endswith('.dylib'):
        dl = tf.extractfile(n).read()

def parse_load_commands(bin_data):
    """parse Mach-O load commands, return list of (cmd, details)"""
    magic = struct.unpack_from('>I', bin_data, 0)[0]
    is64 = magic == 0xfeedfacf or magic == 0xcafebabe  # thin 64 or fat header
    out = []
    if magic == 0xcafebabe:
        # fat: skip to first slice header
        nf = struct.unpack_from('>I', bin_data, 4)[0]
        # slice 0 = arm64
        cputype, cpusubtype, s_off, s_sz, align = struct.unpack_from('>IIIII', bin_data, 8)
        return parse_load_commands(bin_data[s_off:s_off+s_sz])
    # thin 64-bit
    ncmds = struct.unpack_from('<I', bin_data, 16)[0]
    cmdtypes = {0x1:'LC_SEGMENT',0x2:'LC_SYMTAB',0x19:'LC_SEGMENT_64',
                0x1c:'LC_ID_DYLIB',0x1d:'LC_LOAD_DYLIB',0xe:'LC_LOAD_WEAK_DYLIB',
                0x1f:'LC_REEXPORT_DYLIB',0x8000001c:'LC_RPATH'}
    off = 32
    for i in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', bin_data, off)
        name = cmdtypes.get(cmd, hex(cmd))
        detail = ""
        if cmd == 0x1c or cmd == 0x1d or cmd == 0xe or cmd == 0x1f:
            # lc_str offset
            stroff = struct.unpack_from('<I', bin_data, off+8)[0]
            s = bin_data[off+stroff:].split(b'\0')[0].decode('utf-8','replace')
            detail = s
        elif cmd == 0x8000001c:  # LC_RPATH
            stroff = struct.unpack_from('<I', bin_data, off+8)[0]
            s = bin_data[off+stroff:].split(b'\0')[0].decode('utf-8','replace')
            detail = s
        out.append((name, detail))
        off += cmdsize
    return out

print("=== JumioProbe.dylib Load Commands (arm64 slice) ===")
for cmd, detail in parse_load_commands(dl):
    print(f"  {cmd:20s} {detail}")
