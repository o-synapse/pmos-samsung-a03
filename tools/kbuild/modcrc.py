# Compare the symbol CRCs a vendor .ko was built against with our kernel's Module.symvers.
# Usage (in a03-kbuild): python3 modcrc.py <Module.symvers> <module.ko>...
import struct, subprocess, sys

sym = {}
for l in open(sys.argv[1]):
    c, n = l.split()[:2]
    sym[n] = int(c, 16)

def versions(p):
    d = open(p, "rb").read()
    for l in subprocess.check_output(["aarch64-linux-gnu-readelf", "-SW", p]).decode().splitlines():
        if "__versions" in l:
            f = l.split("]")[1].split()
            off, sz = int(f[3], 16), int(f[4], 16)
            for i in range(off, off + sz, 64):
                yield d[i + 8:i + 64].split(b"\0")[0].decode(), struct.unpack("<Q", d[i:i + 8])[0]

for m in sys.argv[2:]:
    v = list(versions(m))
    bad = [n for n, c in v if n in sym and sym[n] != c]
    missing = [n for n, c in v if n not in sym]
    print("%s: %d syms, %d CRC mismatches, missing %s" % (m.split("/")[-1], len(v), len(bad), missing))
    print("   ", " ".join(bad))
