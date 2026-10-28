#!/bin/sh
# Make a debug copy of a pmOS initramfs for the SM-A035F (patches in debug-initramfs.py):
#   - adds a USB serial function (acm.GS0) to the gadget next to the network function
#   - runs a respawning root shell on /dev/ttyGS0 right after USB setup in init_2nd.sh (Mac: /dev/cu.usbmodem*)
#   - starts the real rootfs through /dbginit.sh, which keeps a ttyGS0 shell after switch_root
#   - copies the initramfs log to /pmOS_init.log on the rootfs
#   - enables the initramfs's own set -x tracing (/hooks/10-verbose-initfs.sh)
# Usage: debug-initramfs.sh <initramfs> <out>
set -e
D=$(cd "$(dirname "$0")" && pwd)
B=$(cd "$(dirname "$1")" && pwd)
O=$(cd "$(dirname "$2")" && pwd)
docker run --rm -v "$B":/in:ro -v "$O":/out -v "$D/debug-initramfs.py":/patch.py:ro a03-bootimg sh -ec '
mkdir /r && cd /r && gzip -dc "/in/$1" | cpio -idm --quiet
python3 /patch.py
grep -n "start_debug_serial\|acm.GS0\|dbginit\|pmOS_init.log; sync" init_2nd.sh init_functions.sh
find . | sort | cpio -o -H newc -R 0:0 --quiet | gzip -9 > "/out/$2"
' dbg "$(basename "$1")" "$(basename "$2")"
ls -l "$2"
