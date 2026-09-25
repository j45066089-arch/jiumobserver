import struct, lzma, tarfile, io, os

DEB = "C:/Users/shosh/JumioObserver/artifact/deb/com.maurice.jumioobserver_1.0.0_iphoneos-arm64e.deb"

data = open(DEB, 'rb').read()
print("=== DEB ist ar-Archiv ===")
print("magic:", data[:8])

# ar parsen: "!<arch>\n" dann 60-byte header je member
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
print("member:", list(members.keys()))

# data.tar.lzma entpacken
raw = members['data.tar.lzma']
dec = lzma.decompress(raw, format=lzma.FORMAT_ALONE)
tf = tarfile.open(fileobj=io.BytesIO(dec), mode='r:')
names = tf.getnames()
print("\n=== data.tar Inhalt ===")
for n in names:
    print("  ", n)

# dylib extrahieren und fat-architektur checken
for n in names:
    if n.endswith('.dylib'):
        dl = tf.extractfile(n).read()
        magic = struct.unpack_from('>I', dl, 0)[0]
        narch = struct.unpack_from('>I', dl, 4)[0]
        print(f"\n=== {n} ===")
        print(f"  magic=0x{magic:08x} nfas={narch}")
        for i in range(narch):
            cputype, cpusubtype, off, sz, align = struct.unpack_from('>IIIII', dl, 8+i*20)
            cpuname = {0x0100000C:'arm64', 0x01000002:'arm64e', 12:'arm', 7:'x86_64'}.get(cputype, hex(cputype))
            print(f"  slice[{i}]: {cpuname} subtype=0x{cpusubtype:x} off=0x{off:x} size={sz}")
    if n.endswith('.plist'):
        print(f"\n=== {n} ===")
        print(tf.extractfile(n).read().decode('utf-8', 'replace'))
