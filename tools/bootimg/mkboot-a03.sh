#!/bin/sh
# Pack an SM-A035F boot image in the stock Samsung layout:
#   header v2 boot image (stock offsets, stock DT table), then the stock
#   SEANDROIDENFORCE/SignerVer02 trailer, then an AVB hash footer for the 64 MiB boot partition.
# The footer is signed with a03-boot-test.pem, which only an unlocked (orange state) bootloader accepts.
# Any RSA-4096 key works; one is generated on first use (it is not in the repository).
# Needs firmware/test/boot-stock.img (the stock boot.img from the AP package).
# Usage: mkboot-a03.sh <Image> <initramfs> <cmdline> <out.img>
set -e
D=$(cd "$(dirname "$0")" && pwd)
F="$D/../../firmware"
[ -f "$D/a03-boot-test.pem" ] || openssl genrsa -out "$D/a03-boot-test.pem" 4096 2>/dev/null
for a in "$1" "$2"; do [ -f "$a" ] || { echo "missing $a" >&2; exit 1; }; done
mkdir -p "$D/../../build"; W=$(mktemp -d "$D/../../build/mkboot.XXXXXX")  # under $HOME so Docker can mount it
cp "$1" "$W/Image"; cp "$2" "$W/initramfs"
docker run --rm -v "$W":/w -v "$F/test":/stock:ro -v "$D/a03-boot-test.pem":/key.pem:ro a03-bootimg sh -ec '
unpack_bootimg --boot_img /stock/boot-stock.img --out /tmp/stock >/dev/null
mkbootimg --header_version 2 --pagesize 2048 --base 0 --kernel_offset 0x8000 \
	--ramdisk_offset 0x01000000 --tags_offset 0x100 --dtb_offset 0x01f00000 \
	--os_version 11.0.0 --os_patch_level 2025-08 --board SRPUH31A009 \
	--kernel /w/Image --ramdisk /w/initramfs --dtb /tmp/stock/dtb --cmdline "$1" -o /w/boot.img
python3 - <<P
b = open("/stock/boot-stock.img", "rb").read()
i = b.find(b"SEANDROIDENFORCE")
open("/w/boot.img", "ab").write(b[i:0x1774a10])
P
avbtool add_hash_footer --image /w/boot.img --partition_size 67108864 --partition_name boot \
	--algorithm SHA256_RSA4096 --key /key.pem
avbtool info_image --image /w/boot.img | sed -n "1,4p"
' mkboot "$3"
mv "$W/boot.img" "$4"; rm -rf "$W"
