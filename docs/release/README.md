# Ready-built files

Everything here is built for the **SM-A035F on stock base A035FXXS9CYG1**. The binaries are
attached to the [GitHub release](https://github.com/o-synapse/pmos-samsung-a03/releases) as
single files (the folders below are only for orientation); the source files (`device/`,
`docker/`, `patches/`, `tools/`, `kernel/*.config|*.py|APKBUILD`) are copies of what's in
`tools/` in this repository. Checksums are in [`MD5SUMS`](MD5SUMS).

| Path | What it is | How to use it |
|---|---|---|
| `packages/linux-samsung-a03-4.14.199-r3.apk` | Kernel package (4.14.199 with all four patches) | `sudo apk add --allow-untrusted` on the phone, then write a boot image (see below) |
| `packages/device-samsung-a03-1-r8.apk` | Device package: Wi-Fi service, udev rules, NM config, no-audio rule, power-button override; depends on `stevia-schemas` | `sudo apk add --allow-untrusted` on the phone |
| `boot/boot-r3.img` | **Current boot image**, packed from `/boot/vmlinuz` + `/boot/initramfs` after installing the r3/r8 packages. Running on the phone, verified | `dd` to `/dev/block/by-name/boot` from the phone, or flash `odin/` with Odin |
| `boot/boot-fa2.img` | The previous image (same kernel and initramfs, hand-built before packaging). Known good; the rollback | Same as above |
| `odin/AP_boot_r3.tar.md5`, `odin/AP_boot_fa2.tar.md5` | The two boot images as Odin AP packages (boot only, keep your data) | Odin → AP slot, nothing else |
| `kernel/Image` | Raw arm64 kernel image (same as `/boot/vmlinuz` in the r3 package) | Input to `mkboot-a03.sh` / `mkodin-pmos.sh` |
| `kernel/kernel-prebuilt.tar.gz`, `kernel/APKBUILD` | What the kernel package is built from (Image, config, modules) | Goes in `tools/pmb/aports/linux-samsung-a03/` |
| `kernel/pmos.config` | Config fragment on top of `a03_cis_open_defconfig` | Kernel rebuilds |
| `kernel/modcrc.py` | Checks a binary module's CRCs against `Module.symvers` | Must report 0 mismatches before flashing a new kernel |
| `patches/*.patch` | The four kernel patches (see [how-it-works.md](../how-it-works.md#3-the-kernel--toolskbuild)) | Apply to Samsung's A035FXXS9CYG1 kernel source |
| `device/` | Sources of the device package (APKBUILD, deviceinfo, Wi-Fi service, rules, override) | Goes in `tools/pmb/aports/device-samsung-a03/` |
| `docker/` | `crun-a03` wrapper, `docker-setup.sh`, `panel-install.sh`, `wings-install.sh` | See [pterodactyl.md](../pterodactyl.md) |
| `tools/mkboot-a03.sh`, `tools/mkodin-pmos.sh` | Boot image / Odin package builders (copies; they need the rest of `tools/bootimg` and `firmware/test` to run) | Run from `tools/bootimg/` in the project |

Both boot images and the packaged kernel `Image` contain the byte-identical kernel; the
packaging step only puts that kernel into an apk, so `apk add` of the r3 package doesn't change
what boots.

There is no full fresh-install Odin image here: it contains the root filesystem and therefore
the `user` password, which you should choose yourself. Build it with step 4 of
[install.md](../install.md).

## Writing a boot image from the phone

```bash
scp boot/boot-r3.img user@192.168.1.160:/tmp/
```

```bash
ssh -t user@192.168.1.160 'sudo dd if=/tmp/boot-r3.img of=/dev/block/by-name/boot bs=1M conv=fsync && sync && sudo reboot'
```
