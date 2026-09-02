#!/usr/bin/env bash
# Copy the Swift runtime the binary actually needs into the bundle, thin it to
# armv7, and ad-hoc sign everything.
#
#   bundle-runtime.sh <App.app> <runtime-dir>
#
# Only the transitive closure is copied, not all 41 dylibs: dyld needs every
# @rpath entry present or the app dies at launch with no crash log, and it needs
# nothing else.  The originals are fat (armv7 + armv7s + arm64), and the slices
# this device cannot load are most of the bytes -- hence the lipo pass.
set -uo pipefail
APP="${1:?usage: bundle-runtime.sh <App.app> <runtime-dir>}"
RUNTIME="${2:?usage: bundle-runtime.sh <App.app> <runtime-dir>}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$APP/$(basename "$APP" .app)"
V=/Volumes/SystemRoot
LIPO="$V$HOME/legacy-ios9/toolchain/xc12/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/lipo"

mkdir -p "$APP/Frameworks"
python3 - "$RUNTIME" "$APP/Frameworks" "$BIN" <<'PY'
import os, shutil, struct, sys

def deps(path):
    """@rpath dylibs the armv7 slice of this Mach-O loads."""
    data = open(path, 'rb').read()
    magic, = struct.unpack_from('>I', data, 0)
    offsets = []
    if magic == 0xCAFEBABE:
        count, = struct.unpack_from('>I', data, 4)
        for i in range(count):
            offset, = struct.unpack_from('>I', data, 8 + i * 20 + 8)
            cpu, = struct.unpack_from('<I', data, offset + 4)
            if cpu == 12:
                offsets = [offset]
                break
    else:
        offsets = [0]
    if not offsets:
        return []
    base = offsets[0]
    ncmds, = struct.unpack_from('<I', data, base + 16)
    pointer = base + 28
    out = []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<2I', data, pointer)
        if cmd == 0x0c:
            offset, = struct.unpack_from('<I', data, pointer + 8)
            start = pointer + offset
            out.append(data[start:data.index(b'\0', start)].decode())
        pointer += size
    return out

def rpaths(path):
    data = open(path, 'rb').read()
    ncmds, = struct.unpack_from('<I', data, 16)
    pointer, out = 28, []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<2I', data, pointer)
        if cmd == 0x8000001c:
            offset, = struct.unpack_from('<I', data, pointer + 8)
            start = pointer + offset
            out.append(data[start:data.index(b'\0', start)].decode())
        pointer += size
    return out

source, destination, binary = sys.argv[1], sys.argv[2], sys.argv[3]

# Without this rpath, every @rpath/libswift*.dylib below is unreachable and the
# app dies before main() with "Library not loaded". The driver only adds
# /usr/lib/swift, which is the iOS 12.2+ OS-resident runtime and absent here.
if '@executable_path/Frameworks' not in rpaths(binary):
    print('  BINARY HAS NO @executable_path/Frameworks RPATH -- it will not launch.',
          file=sys.stderr)
    print('  Link with: -Xlinker -rpath -Xlinker @executable_path/Frameworks',
          file=sys.stderr)
    sys.exit(1)

pending = [d for d in deps(binary) if d.startswith('@rpath/')]
seen, missing = set(), []
while pending:
    name = pending.pop().split('/')[-1]
    if name in seen:
        continue
    seen.add(name)
    path = os.path.join(source, name)
    if not os.path.exists(path):
        missing.append(name)
        continue
    shutil.copy2(path, os.path.join(destination, name))
    pending += [d for d in deps(path) if d.startswith('@rpath/')]
if missing:
    print('  MISSING from the runtime: ' + ', '.join(missing), file=sys.stderr)
    sys.exit(1)
print('  runtime: %d dylibs (%s)' % (
    len(seen),
    ', '.join(sorted(n.replace('libswift', '').replace('.dylib', '') for n in seen))))
PY
[ $? -eq 0 ] || exit 1

for f in "$APP"/Frameworks/*.dylib; do
    darling shell "$LIPO" -thin armv7 "$V$(readlink -f "$f")" -output "$V$(readlink -f "$f").thin" >/dev/null 2>&1
    [ -s "$f.thin" ] && mv "$f.thin" "$f"
done

# Ad-hoc signature on every Mach-O. amfid on a jailbroken device accepts it;
# with no signature at all the process is killed before dyld runs.
#
# The main binary additionally carries Keychain entitlements: without them
# securityd rejects every Keychain call with -34018 and sign-in cannot persist.
# Only the executable needs them; the dylibs are signed bare.
ENTITLEMENTS="$REPO/scripts/legacy/Opaline.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    ldid -S"$ENTITLEMENTS" "$BIN"
else
    echo "  WARNING: no entitlements file; Keychain will fail with -34018" >&2
    ldid -S "$BIN"
fi
for f in "$APP"/Frameworks/*.dylib; do ldid -S "$f"; done
echo "  signed $(( $(ls "$APP"/Frameworks/*.dylib 2>/dev/null | wc -l) + 1 )) Mach-O file(s)"
