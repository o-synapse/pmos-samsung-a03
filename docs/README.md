# postmarketOS on the Samsung Galaxy A03 (SM-A035F)

This project turns a Samsung Galaxy A03 (SM-A035F, Unisoc T606, 3 GB RAM) from an Android phone
into a small Linux computer that runs **postmarketOS** (an Alpine Linux based distribution for
phones) with the **Phosh** touch interface. On top of that it runs **Docker** and the
**Pterodactyl** game server panel, so the phone can host Minecraft servers on the home network.

Nobody had ported postmarketOS to this phone before, so all of it was built from scratch: the
boot image format, the kernel configuration, the Wi-Fi bring-up, the fixes Phosh needed, and
the work-arounds for Docker on an old Android kernel.

## Why

- The phone was spare and is too slow to be pleasant on Android 13, but it still has a working
  screen, battery, Wi-Fi and 32 GB of storage.
- A normal Linux userland on it means SSH, a package manager (apk), real services and
  containers: a low-power, always-on home server with its own built-in UPS (the battery).
- Calls and SMS were explicitly not a goal. Only Wi-Fi was required.

## What works

| Feature | State | Notes |
|---|---|---|
| Boot (unlocked bootloader, stock vbmeta) | ✅ | Orange/yellow "unlocked" warning on every boot, can't be removed (drawn by Samsung's signed bootloader) |
| Display + touch | ✅ | 720×1600 OLED via the stock `sprd` DRM driver, software rendering |
| Wi-Fi | ✅ | Samsung's binary driver from the `socko` partition, patched against a TX stall |
| Phosh + phrog login screen | ✅ | Needed three kernel backports (see [journey.md](journey.md)) |
| Sleep / wake with the power button | ✅ | Backlight restore patch and a settings-daemon override |
| SSH over USB and Wi-Fi | ✅ | USB uses CDC-ECM (`172.16.42.1`) |
| Docker | ✅ | Via a `crun` wrapper; host networking only |
| Pterodactyl Panel + Wings | ✅ | Panel at `http://192.168.1.160`, game ports 25565–25570 |
| Audio | ❌ | Opening any PCM crashes the stock audio driver, so it is disabled on purpose |
| GPU acceleration | ❌ | Mali GPU has no open driver for this kernel; everything renders on the CPU |
| Calls, SMS, mobile data | ➖ | Not attempted (not a goal) |
| Bluetooth, camera, GPS | ➖ | Not attempted |

## The documents

| File | What's in it |
|---|---|
| [install.md](install.md) | Step-by-step: putting this on a fresh A03 |
| [how-it-works.md](how-it-works.md) | Architecture: boot chain, boot image, kernel, Wi-Fi, graphics, packages |
| [journey.md](journey.md) | What we ran into on the way and how each problem was solved |
| [quirks.md](quirks.md) | The phone's quirks and limitations, as a quick reference |
| [pterodactyl.md](pterodactyl.md) | Docker + Pterodactyl on the phone: setup, use, limits |
| [release/](release/README.md) | The ready-built files (packages, kernel, boot images, Odin packages), attached to the [GitHub release](https://github.com/o-synapse/pmos-samsung-a03/releases) |

## Project layout

```
A03/
├── docs/                    this documentation (+ release/: list of the built files)
├── firmware/
│   ├── stock/               Samsung stock firmware A035FXXS9CYG1 (Odin BL/AP/CP/CSC)   [not in git]
│   ├── test/                stock boot + vbmeta used as templates                     [not in git]
│   └── odin/                Odin AP packages built by mkodin-pmos.sh                   [not in git]
├── source/                  Samsung's kernel source (A035FXXS9CYG1)                    [not in git]
├── tools/
│   ├── bootimg/             mkboot-a03.sh (boot image), mkodin-pmos.sh (Odin package), debug initramfs
│   ├── kbuild/              kernel build container, kmake.sh, pmos.config, patches/, modcrc.py
│   ├── pmb/                 pmbootstrap container, pmb.sh, aports/ (device + kernel packages)
│   ├── docker/              crun-a03 wrapper, Pterodactyl panel + wings installers
│   ├── heimdall/            Heimdall (doesn't work on macOS for this phone)            [not in git]
│   └── bifrost/             Bifrost (firmware downloader)                              [not in git]
└── build/                   scratch output (kernel Images, boot images, logs)          [not in git]
```

## Current versions

- Stock firmware base: **A035FXXS9CYG1** (Android 13, August 2025 patch). The Wi-Fi patch and
  the vendor partition offsets are specific to this build.
- Kernel: Samsung 4.14.199 (`4.14.199-27193134-abA035FXXS9CYG1`), package `linux-samsung-a03-4.14.199-r3`.
- Device package: `device-samsung-a03-1-r8`.
- postmarketOS: edge, OpenRC, Phosh UI with the phrog greeter.
- Pterodactyl Panel v1.15.2, Wings v1.13.4, Docker 29.
