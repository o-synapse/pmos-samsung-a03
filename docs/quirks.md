# Quirks of the Galaxy A03 (SM-A035F) under Linux

A quick reference. The background for most of these is in [journey.md](journey.md).

## Bootloader and flashing

- **Yellow/orange "unlocked" warning on every boot.** Drawn by Samsung's signed bootloader;
  it can't be removed. Only the logo after it could be changed.
- **Keep vbmeta stock.** A "disabled" vbmeta plus a boot image without Samsung's trailer
  bootloops into "Sysdumping / Reset mode". Recovery can't be reached from there; Download
  mode still works and Odin can restore it (`firmware/odin/AP_stock_boot_restore.tar.md5`).
- **Boot images need Samsung's layout:** header v2, stock DT table, `SEANDROIDENFORCE`
  trailer, AVB hash footer (any key, because the bootloader is unlocked). Use
  `tools/bootimg/mkboot-a03.sh`.
- **Heimdall doesn't work from macOS** (the Apple CDC driver takes the device mid-transfer).
  Use Odin3 on Windows with `.tar.md5` AP packages. Once Linux runs, new kernels can be
  `dd`'d to `/dev/block/by-name/boot` from the phone itself.
- **Download mode:** power off, hold Volume Up + Volume Down and plug in USB.

## Kernel (Samsung 4.14)

- **Binary modules pin the kernel config.** The Wi-Fi driver only loads if the kernel's symbol
  CRCs match stock. Can't enable: `SYSVIPC`, `USER_NS`, pids/devices cgroups, PID/IPC
  namespaces in practice, bridge/iptables. Check with `tools/kbuild/modcrc.py`.
- **Missing newer syscalls** that a modern userland expects. Already backported:
  `waitid(P_PIDFD)` and `faccessat2`. Still missing, for example: `/proc/thread-self`,
  `clone3`, `close_range`, `openat2`. If a modern program fails with odd `EINVAL`/`ENOSYS`
  errors or segfaults, suspect this first.
- **No zstd, no ext2:** initramfs must be gzip, the boot partition ext4.
- **Redis** warns about (and by default refuses to run because of) an arm64 fork/COW kernel
  bug on this version. Run it without persistence.

## Hardware

| Part | State |
|---|---|
| Display | Works (stock `sprd` DRM, 720×1600). No framebuffer console, so no text on screen during boot |
| Brightness | Panel resets brightness on power-up; fixed by a kernel patch |
| GPU (Mali) | No usable driver → software rendering. The UI is usable but not fast; scrolling and animations stutter |
| Wi-Fi | Binary driver only, patched against a TX stall. Needs real MAC (no randomisation) |
| Audio | **Disabled.** Opening any PCM crashes the stock ASoC driver and reboots the phone |
| Modem (calls/SMS/data) | Not attempted |
| Bluetooth, camera, GPS, sensors | Not attempted |
| USB | Gadget networking with CDC-ECM works on macOS (NCM doesn't, RNDIS isn't supported by macOS) |
| Storage | ~20.6 GB root filesystem for postmarketOS (in `userdata`) |
| RAM | 3 GB (about 2.7 GB usable) — enough for one small Minecraft server |

## The Wi-Fi bring-up depends on the stock firmware version

The service has the **vendor partition's offset inside `super`** and the **byte offsets of the
driver patch** hard-coded for firmware **A035FXXS9CYG1**. On a phone running a different stock
build:

- the vendor mount will fail or mount garbage → Wi-Fi config files missing;
- the patch check won't match and the driver loads unpatched (works, but stalls under load).

Flash A035FXXS9CYG1 first (see [install.md](install.md)), or re-derive both values.

## Userland

- **sudo asks for the password**, also over SSH. Use `sudo -S` to pipe it in scripts.
- **`udevadm trigger` without filters** switches the USB gadget to NCM and kills USB networking
  until reboot. Use Wi-Fi SSH, or filter the trigger.
- **`apk` won't overwrite files you edited in `/etc`** (it writes `*.apk-new` next to them).
  Check after upgrading the device package: `find /etc -name '*.apk-new'`.
- **`logread`'s buffer is small.** Read logs soon after the event.
- **busybox `ps`** has no `-p`; use `ps | grep` or `pgrep`.
- **Software rendering env:** `/etc/environment` must contain `WLR_RENDERER=pixman` and
  `GSK_RENDERER=cairo` (the device package adds them).

## Docker on this kernel

- Only via `crun` and the `crun-a03` wrapper, which removes PID/IPC namespaces, mqueue, device
  rules and pids/cpu/blkio limits from every container.
- **Containers are less isolated than usual:** they share the host PID namespace and network,
  and device access isn't restricted by a cgroup. Only run images you trust.
- Memory limits work (the memory cgroup exists); CPU limits don't.
- Host networking only: every game server must use its own port.
