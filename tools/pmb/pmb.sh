#!/bin/sh
# Run pmbootstrap for the SM-A035F port in the a03-pmb container.
# Copies tools/pmb/aports into pmaports (device/testing) first. Usage: pmb.sh <pmbootstrap args...>
# Chroots are zapped first: their /dev mounts died with the previous container, and
# pmbootstrap does not remount them. Built packages and caches are kept.
# With PMB_OUT=<dir under $HOME>, the install image(s) and initramfs are copied there afterwards.
D=$(cd "$(dirname "$0")" && pwd)
O=${PMB_OUT:-$D}
exec docker run --rm -i --privileged -v a03-pmb:/pmb -v "$D":/host:ro -v "$O":/out \
	-v "$HOME/.ssh/id_ed25519.pub":/home/pmos/.ssh/id_ed25519.pub:ro -e PMB_OUT="$PMB_OUT" a03-pmb sh -c '
mkdir -p ~/.config && cp /host/pmbootstrap_v3.cfg ~/.config/
for p in /host/aports/*; do rm -rf /pmb/pmaports/device/testing/$(basename $p); cp -r $p /pmb/pmaports/device/testing/; done
# Loop devices of a killed run stay attached in the VM; free them
for l in $(sudo losetup -a -n -O NAME 2>/dev/null); do sudo losetup -d $l; done
pmbootstrap -q -y zap >/dev/null || exit 1
pmbootstrap "$@" || exit $?
[ -n "$PMB_OUT" ] || exit 0
sudo cp /pmb/work/chroot_native/home/pmos/rootfs/samsung-a03*.img /out/ &&
sudo cp /pmb/work/chroot_rootfs_samsung-a03/boot/initramfs /out/ && sudo chown pmos /out/samsung-a03*.img /out/initramfs' pmb "$@"
