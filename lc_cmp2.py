import struct, lzma, tarfile, io

DEB = "C:/Users/shosh/JumioObserver/probe_artifact/probe-deb/com.maurice.jumioprobe_1.0.0_iphoneos-arm64e.deb"
data = open(DEB, 'rb').read()

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

# fat header: slice 0 = arm64
nf = struct.unpack_from('>I', dl, 4)[0]
cputype, cpusubtype, s_off, s_sz, align = struct.unpack_from('>IIIII', dl, 8)
bin64 = dl[s_off:s_off+s_sz]

ncmds = struct.unpack_from('<I', bin64, 16)[0]
off = 32
print(f"arm64 slice: ncmds={ncmds}")
for i in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', bin64, off)
    tag = {
        0x1c:'LC_ID_DYLIB', 0x1d:'LC_LOAD_DYLIB', 0xe:'LC_LOAD_WEAK_DYLIB',
        0x1f:'LC_REEXPORT_DYLIB', 0x8000001c:'LC_RPATH',
        0x1b:'LC_ENCRYPT_INFO_64', 0x32:'LC_BUILD_VERSION', 0x2a:'LC_SOURCE_VERSION',
        0x2c:'LC_VERSION_MIN', 0xc:'LC_DYSYMTAB', 0x26:'LC_FUNCTION_STARTS',
        0x29:'LC_DATA_IN_CODE', 0xb:'LC_DYSYMTAB', 0x1c:'LC_ID_DYLIB',
    }.get(cmd, hex(cmd))
    detail = ""
    if cmd in (0x1c, 0x1d, 0xe, 0x1f, 0x8000001c):
        stroff = struct.unpack_from('<I', bin64, off+8)[0]
        detail = bin64[off+stroff:off+cmdsize].split(b'\0')[0].decode('utf-8','replace')
    print(f"  [{i:2d}] {tag:22s} {detail}")
    off += cmdsize
