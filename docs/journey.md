# The journey: what we ran into and how it was solved

The port was done in steps, each one proven on the real phone before moving on.

## Step 0 — Will the bootloader run our code at all?

**Goal:** prove that a modified boot image boots, without bricking the phone.

- The phone was OEM-unlocked (Knox already tripped). Stock firmware **A035FXXS9CYG1** was
  downloaded with Bifrost, and boot/vbmeta/socko etc. were extracted from the AP package.
- Test A: the stock boot image with *only* the command line changed (adding `a03test=1`),
  Samsung's trailer and AVB footer left in place, stock vbmeta. **Boots** (orange state),
  and `ro.boot.a03test=1` showed up in Android.
- Test B: a freshly repacked boot image without the Samsung trailer/AVB footer **plus** a
  "disabled" vbmeta (flags=3). **Bootloop** into "Sysdumping / Reset mode: abnormal mode";
  recovery unreachable, Download mode still worked, restored with Odin.
- **Flashing problem:** Heimdall on macOS fails — Apple's CDC driver grabs the phone in the
  middle of the transfer, and even the PIT download stalls. **Solution:** build Odin AP `.tar.md5` packages on the Mac and flash them with
  Odin3 v3.14.4 on a Windows PC.

**Lesson:** keep vbmeta stock and always build boot images in the stock Samsung layout
(header v2, stock DT table, `SEANDROIDENFORCE` trailer, AVB footer).

## Step 1 — Linux boots, SSH over USB

- A header-v2 pmOS boot image with a test-signed AVB footer boots.
- The 4.14 kernel can't decompress zstd and has no ext2 driver, so the initramfs must be gzip
  and the boot partition ext4 (`deviceinfo_initfs_compression`, `deviceinfo_boot_filesystem`).
- USB networking: NCM enumerates on macOS but the phone receives zero packets; macOS has no
  RNDIS driver. **CDC-ECM works** → `deviceinfo_usb_network_function="ecm.usb0"`.
- Debugging without a screen: pmOS's initramfs execs `init_2nd.sh` straight away, so that's
  the file to patch. `tools/bootimg/debug-initramfs.{sh,py}` adds a root shell on USB serial
  that survives `switch_root`.
- The build Mac is Intel, so aarch64 chroots run under qemu-user and `mkinitfs` crashes at
  random. pmbootstrap was patched to retry (`tools/pmb/patches/mkinitfs-retry.py`).
- The rootfs goes into `userdata` as an MBR disk (boot + root), sparse-converted for Odin.

## Step 2 — Display and Wi-Fi

- **Display** worked with the stock DRM driver (`modetest` drew a test pattern), but there is
  no framebuffer console.
- **Wi-Fi** was the hardest part:
  - The only driver is Samsung's binary `sprdwl_ng.ko` in the `socko` partition — no source.
  - It refused to load: the kernel's modversion CRCs must match stock. Our config had enabled
    `SYSVIPC` and `USER_NS` (useful for containers), which change core struct layouts. They had
    to go; `tools/kbuild/modcrc.py` was written to check for 0 mismatches before every flash.
  - It needs `/vendor/etc/wcn/*.ini`. The vendor partition is a logical partition inside
    `super`; it is loop-mounted by its offset in the LP metadata.
  - It loads modem firmware from `/dev/block/platform/sdio_emmc/by-name/...` → a udev rule
    creates Android-style links.
  - **TX stall under load:** large downloads froze the connection and SSH dropped. The
    firmware asks to power down after nearly every packet, the driver agrees when its queues
    *look* empty, and then often never wakes it again. Disassembling the module found the
    branch in `sprdwl_fw_power_down_ack`; patching one instruction (`b.gt` → `b`, refuse the
    power-down) fixed it. Verified with 10/10 large downloads plus an `apk upgrade`.
    The service patches the module in `/run` at every boot, only if the bytes match.
- Gotcha: `apk` keeps locally edited files in `/etc/init.d` and writes `.apk-new` instead —
  check for that after installing a new device package.

## Step 3 — Phosh

One problem after another, each hiding the next:

1. **No GPU.** There is no usable OpenGL driver for the Mali GPU on this kernel. Fix: software rendering
   (`WLR_RENDERER=pixman`, `GSK_RENDERER=cairo` in `/etc/environment`).
2. **Phone reboots when the greeter starts.** PulseAudio opens the sound card; configuring any
   PCM oopses Samsung's ASoC driver in `__memset_io` and the phone resets. Fix: udev rule making
   PCM devices root-only. No audio, but a stable phone.
3. **phrog session gave up.** The on-screen keyboard (stevia) aborts without its GSettings
   schemas, and gnome-session treats that as fatal. Fix: install `stevia-schemas` (now a
   dependency of the device package).
4. **NetworkManager vs wpa_supplicant** fighting over `wlan0`. Fix: disable the standalone one
   when NM is enabled; NM config keeps the real MAC (the binary driver dislikes MAC
   randomisation) and ignores `usb0`.
5. **gnome-session hung, Phosh never appeared.** GLib ≥ 2.80 sees that `pidfd_open` works
   (Samsung backported it for Android's lmkd) and assumes `waitid(P_PIDFD)` works too. It
   doesn't on 4.14, so every child-exit watch silently fails and gnome-session waits forever
   for `xdg-user-dirs-update`. Fix: backported `waitid(P_PIDFD)` from Linux 5.4
   (`waitid-pidfd.patch`).
6. **Power button: screen woke, then went black again.** Both Phosh and gnome-settings-daemon
   acted on the key. Fix: gsd override `power-button-action='nothing'`.
7. **Screen dark for ~30 s after wake.** The panel's power-up sequence resets brightness, and
   Phosh's brightness write lands just before the panel is ready (fails with `-ENXIO`).
   Brightness only came back at the next change — Phosh's idle-dim, 30 s later. Fix:
   `panel-restore-brightness.patch` re-sends the brightness once the panel is enabled.
8. **Spinning wheel at boot, phrog dead.** phrog (and Phosh) segfaulted inside appstream every
   time. Root cause, three layers down: GLib 2.90 checks files with
   `faccessat(..., AT_SYMLINK_NOFOLLOW)`; musl 1.2.6 implements that via the `faccessat2`
   syscall (439), which only exists since Linux 5.8; on 4.14 it returns `EINVAL`; appstream
   doesn't expect the check to fail and crashes loading its catalogue. Fix: backported
   `faccessat2` (`faccessat2.patch`).

**Lesson:** a modern userland (GLib, musl) on a 4.14 kernel breaks in ways that look like app
bugs. When something segfaults deep in GLib/appstream, check for missing newer syscalls first.

## Step 4 — Docker and Pterodactyl

Goal: host Minecraft servers. Every container feature ran into the kernel:

| Problem | Cause | Fix |
|---|---|---|
| runc panics | runc 1.5 / libpathrs needs `/proc/thread-self` (Linux 3.17+, missing here) | Use `crun` |
| `bpf create` error | No BPF device cgroup on 4.14 | Wrapper deletes the device rules from the OCI spec |
| mqueue mount fails | No `SYSVIPC`/POSIX mqueue (can't enable, breaks Wi-Fi CRCs) | Wrapper drops the mqueue mount |
| `clone: EINVAL` | No PID/IPC namespaces available with this config | Wrapper drops the pid/ipc namespaces |
| `io.max` missing | cgroup v2 has only `io`/`memory` controllers | Wrapper drops blockIO, cpu, pids limits |
| No bridge networking | No bridge/iptables support | `bridge: none`, `iptables: false`; Wings uses host networking |
| MariaDB init fails | `fill_help_tables.sql` not found | `mariadb-install-db --basedir=/usr` |
| composer refuses the lock file | Alpine's composer defaults to php85, which lacks the extensions | Run it with `php83 composer.phar` |
| Redis exits | Redis refuses to start on arm64 4.14 because of a known fork/COW kernel bug | `ignore-warnings ARM64-COW-BUG` and no persistence (no fork) |

The result is a working Panel + Wings, with the Java container image verified.

## Things worth remembering

- Ask before every flash, keep the previous boot image as a rollback.
- Verify every kernel with `modcrc.py` (0 mismatches) — otherwise no Wi-Fi, which means no SSH.
- `udevadm trigger` with no filter re-runs the USB gadget setup and switches it to NCM, which
  kills USB networking on macOS. Use Wi-Fi SSH, or trigger only what you need.
- `logread` (logbookd) has a small ring buffer — grab logs quickly.
