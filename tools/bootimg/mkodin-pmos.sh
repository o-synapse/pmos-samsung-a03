#!/bin/sh
# Build the Odin AP package for postmarketOS on the SM-A035F from pmbootstrap's --split output:
#   userdata.img = MBR with pmOS_boot (p1) and pmOS_root (p2, last so the initramfs can grow it),
#                  converted to an Android sparse image
#   boot.img     = kernel + initramfs packed by mkboot-a03.sh
#   vbmeta.img   = stock (orange state accepts the test-signed boot)
# Usage: mkodin-pmos.sh <Image> <build dir with samsung-a03-{boot,root}.img and initramfs> <name>
set -e
D=$(cd "$(dirname "$0")" && pwd)
A=$(cd "$D/../.." && pwd)
B=$(cd "$2" && pwd)
CMDLINE="console=ttyS1,115200n8 PMOS_NO_OUTPUT_REDIRECT"
"$D/mkboot-a03.sh" "$1" "$B/initramfs" "$CMDLINE" "$B/boot.img"
docker run --rm -v "$B":/b a03-bootimg sh -ec '
bs=$(stat -c %s /b/samsung-a03-boot.img); rs=$(stat -c %s /b/samsung-a03-root.img)
s1=2048; n1=$((bs / 512)); s2=$((s1 + n1)); n2=$((rs / 512))
truncate -s $(((s2 + n2) * 512)) /b/userdata.raw
printf "label: dos\n%s,%s,83\n%s,%s,83\n" $s1 $n1 $s2 $n2 | sfdisk -q /b/userdata.raw
dd if=/b/samsung-a03-boot.img of=/b/userdata.raw bs=512 seek=$s1 conv=notrunc,sparse status=none
dd if=/b/samsung-a03-root.img of=/b/userdata.raw bs=512 seek=$s2 conv=notrunc,sparse status=none
img2simg /b/userdata.raw /b/userdata.img && rm /b/userdata.raw
'
P=$(mktemp -d "$B/odin.XXXXXX")
mv "$B/boot.img" "$B/userdata.img" "$P/"; cp "$A/firmware/test/vbmeta-stock.img" "$P/vbmeta.img"
(cd "$P" && COPYFILE_DISABLE=1 tar --format ustar -cf "../$3.tar" boot.img vbmeta.img userdata.img)
O="$A/firmware/odin/$3.tar.md5"
cp "$B/$3.tar" "$O" && md5 -q "$B/$3.tar" | awk -v n="$3.tar" '{printf "%s  %s\n",$1,n}' >> "$O"
rm "$B/$3.tar"; echo "$O"; ls -l "$P"
