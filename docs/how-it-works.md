# How it works

## 1. Boot chain

```
Samsung bootloader (signed, unlocked = "orange state")
  └─ verifies vbmeta (stock, untouched)
  └─ loads boot partition: header-v2 Android boot image
        kernel (Samsung 4.14, our build) + postmarketOS initramfs (gzip) + stock DT table
        + SEANDROIDENFORCE trailer + AVB hash footer (test key)
  └─ initramfs mounts userdata
        userdata = MBR with two partitions: pmOS_boot (ext4) and pmOS_root (ext4)
  └─ switch_root → OpenRC → services → greetd → phrog (login) → Phosh
```

Key points:

- **The bootloader must be unlocked** (OEM unlock). It then accepts a boot image signed with any
  AVB key, but it shows a yellow/orange warning on every boot.
- **vbmeta stays stock.** A boot image without Samsung's `SEANDROIDENFORCE` trailer and an AVB
  footer, combined with a "disabled" vbmeta, bootloops into "Sysdumping / Reset mode". With
  stock vbmeta plus a test-signed boot image it boots fine.
- **postmarketOS lives in the `userdata` partition.** Android is gone, but every other
  partition (`super` with vendor/system, `socko`, modem, etc.) is left untouched. The Wi-Fi
  driver and its config files are read from those stock partitions at runtime.

## 2. The boot image — `tools/bootimg/mkboot-a03.sh`

pmbootstrap can't produce Samsung's layout, so `deviceinfo_generate_bootimg="false"` and the
image is packed outside it:

1. `mkbootimg --header_version 2` with the stock offsets (base 0, kernel 0x8000, ramdisk
   0x01000000, tags 0x100, dtb 0x01f00000), the stock board name and the **stock DT table**
   (`unpack_bootimg` on `firmware/test/boot-stock.img`).
2. The stock `SEANDROIDENFORCE`/`SignerVer02` trailer is copied from the stock image.
3. `avbtool add_hash_footer` for the 64 MiB boot partition, signed with
   `tools/bootimg/a03-boot-test.pem`.

Kernel command line: `console=ttyS1,115200n8 PMOS_NO_OUTPUT_REDIRECT`.

`tools/bootimg/mkodin-pmos.sh` wraps that and builds a complete Odin AP package:
`boot.img` + stock `vbmeta.img` + `userdata.img` (an Android sparse image of an MBR disk with
pmbootstrap's boot and root filesystems; root last so it can grow to fill the partition).

## 3. The kernel — `tools/kbuild/`

- Source: Samsung's `SM-A035F_13_Opensource_A035FXXS9CYG1.zip` (4.14.199), built with AOSP
  clang r383902 in the `a03-kbuild` container. The tree lives in the Docker volume
  `a03-kernel` at `/k/src`; the build used for the phone is `/k/out-wifi`.
- Config: `a03_cis_open_defconfig` + `tools/kbuild/pmos.config` (devtmpfs, VT, fhandle, USB
  ECM/NCM gadgets, pstore, no Android paranoid networking).
- **Hard constraint:** Samsung's binary modules (Wi-Fi `sprdwl_ng.ko`, and the GPU/Bluetooth
  ones) only load if the kernel's symbol CRCs match the stock kernel. Anything that changes
  the layout of `task_struct`, namespaces or cgroups changes those CRCs. So `SYSVIPC`,
  `USER_NS`, the pids and devices cgroups, etc. **cannot** be turned on.
  `tools/kbuild/modcrc.py` checks a module against `Module.symvers`; it must report
  `0 CRC mismatches`.
- Patches (`tools/kbuild/patches/`):

| Patch | Why |
|---|---|
| `sprd-drm-prime-export.patch` | wlroots (phoc) needs PRIME buffer export from the display driver |
| `waitid-pidfd.patch` | Backport of `waitid(P_PIDFD)` (Linux 5.4). GLib ≥ 2.80 uses it to wait for child processes; without it gnome-session hangs and Phosh never starts |
| `faccessat2.patch` | Backport of the `faccessat2` syscall (Linux 5.8). musl 1.2.6 needs it whenever `faccessat` is called with flags; without it GLib's file checks fail and appstream segfaults, which takes down phrog/Phosh (the "spinning wheel" at boot) |
| `panel-restore-brightness.patch` | The OLED panel's init code resets the brightness; this re-sends it once the panel is on, so the screen isn't dark for ~30 s after waking |

Build commands (from the project root):

```bash
KOUT=/k/out-wifi tools/kbuild/kmake.sh -j8 Image modules
docker run --rm -v a03-kernel:/k -v "$PWD":/w -w /w a03-kbuild python3 tools/kbuild/modcrc.py /k/out-wifi/Module.symvers build/socko/sprdwl_ng.ko
```

The resulting `Image`, `.config`, `kernel.release` and modules go into
`tools/pmb/aports/linux-samsung-a03/kernel-prebuilt.tar.gz`; the `linux-samsung-a03` package
only unpacks that (the kernel is not compiled inside pmbootstrap).

## 4. Packages — `tools/pmb/aports/`

`tools/pmb/pmb.sh` runs pmbootstrap in the `a03-pmb` container (state in the `a03-pmb`
volume) and copies these two packages into pmaports' `device/testing` first.

**`linux-samsung-a03`** — the prebuilt kernel described above, installs `/boot/vmlinuz`,
`/boot/config` and `/lib/modules/…`. Installing it does **not** write the boot partition.

**`device-samsung-a03`** —

| File | Purpose |
|---|---|
| `deviceinfo` | Device description; gzip initramfs, ext4 boot fs, ECM USB networking, no boot image generation |
| `60-samsung-a03-by-name.rules` | Android-style `/dev/block/by-name/*` links (the Wi-Fi driver loads modem firmware from them) |
| `samsung-a03-wifi.initd` | OpenRC service: mounts vendor (from `super`, by offset) and `socko`, binary-patches and loads `sprdwl_ng.ko` |
| `50-samsung-a03-networkmanager.conf` | Keep the real MAC (the binary driver dislikes random MACs), leave `usb0` alone |
| `72-samsung-a03-no-audio.rules` | Make PCM devices root-only so PulseAudio can't open them (doing so crashes the phone) |
| `20_samsung-a03.gschema.override` | `power-button-action='nothing'` — Phosh handles the power key itself |
| post-install/upgrade | Enable the Wi-Fi service, set `WLR_RENDERER=pixman` and `GSK_RENDERER=cairo` in `/etc/environment`, disable the standalone wpa_supplicant when NetworkManager is in use |

It depends on `stevia-schemas` (Phosh's on-screen keyboard settings; without them the keyboard
aborts and the phrog session gives up).

## 5. Wi-Fi

There is no source code for the Wi-Fi driver. The only driver is Samsung's binary
`sprdwl_ng.ko` in the `socko` partition. The `samsung-a03-wifi` service:

1. Loop-mounts the `vendor` logical partition straight out of `super` (sector 8288256, length
   1592312 sectors for A035FXXS9CYG1) to get `/vendor/etc/wcn/*.ini`.
2. Mounts `socko`, copies `sprdwl_ng.ko` to `/run`, and **binary-patches** it (only if the
   bytes match the known build):
   - `0x1d980`: `b.gt` → `b` in `sprdwl_fw_power_down_ack` — always refuse the firmware's
     request to power down. Without this, TX stalls forever under load ("fw_awake = 0").
   - `0x36f48`: wake check in `sprdwl_tx_work_queue` — a second, belt-and-braces fix.
3. `insmod`s it and waits for `wlan0`. NetworkManager (Phosh) then connects; without
   NetworkManager the service starts wpa_supplicant + udhcpc itself from
   `/etc/wpa_supplicant/wpa_supplicant.conf`.

## 6. Graphics and the UI

- Display: stock `sprd` DRM driver, DSI panel (nl9911c), 720×1600, no framebuffer console.
- The Mali GPU has no Mesa driver usable with this kernel, so everything is software
  rendered: `WLR_RENDERER=pixman` for phoc (the compositor) and `GSK_RENDERER=cairo` for GTK 4.
  These are set in `/etc/environment`, which pam_env passes to greetd sessions.
- Stack: `greetd` → `phrog-greetd-session` → `phoc` → `gnome-session --session=phrog` →
  `phrog` (the login screen). After login the same stack runs Phosh.
- Audio is disabled (see [quirks.md](quirks.md)).

## 7. Docker and Pterodactyl

See [pterodactyl.md](pterodactyl.md). In short: runc can't run on 4.14, so Docker uses `crun`
through a wrapper that strips the container features this kernel can't provide, and all
containers use host networking.
