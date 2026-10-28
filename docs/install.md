# Installing on a fresh Galaxy A03 (SM-A035F)

> ⚠️ This wipes the phone completely, trips Knox permanently, and voids the warranty. Only the
> **SM-A035F** (Unisoc T606) is supported — not the A035M/A035G or the A03s/A03 Core, which are
> different hardware.

## What you need

- The phone, a USB cable, and a **Windows PC with Odin3 v3.14.4** (Heimdall does not work
  from macOS for this phone).
- A build machine with **Docker** (this project was built on an Intel Mac with Docker
  Desktop; Linux works too). About 30 GB free disk space.
- This repository, plus two things it doesn't contain (Samsung's, not ours to redistribute):
  the stock firmware **A035FXXS9CYG1** in `firmware/stock/` (download it with
  [Bifrost](https://github.com/zacharee/SamloaderKotlin) or a similar tool, model SM-A035F)
  and, only to rebuild the kernel, Samsung's kernel source
  `SM-A035F_13_Opensource_A035FXXS9CYG1.zip` from
  [opensource.samsung.com](https://opensource.samsung.com) in `source/`.
- A Wi-Fi network (2.4 GHz or 5 GHz, WPA2).

The ready-built packages, kernel and boot images are attached to the
[GitHub release](https://github.com/o-synapse/pmos-samsung-a03/releases) (see [`release/README.md`](release/README.md)); with
them, you don't need to compile the kernel. Put `kernel-prebuilt.tar.gz` into
`tools/pmb/aports/linux-samsung-a03/` and `Image` into `build/` before step 4.

## 1. Flash stock firmware A035FXXS9CYG1

The Wi-Fi service is tied to this exact stock build (see [quirks.md](quirks.md)). If the
phone runs anything else, flash it first:

1. Boot into Download mode: power off, hold **Volume Up + Volume Down**, plug in USB, then
   press Volume Up to continue.
2. In Odin, load the five files from `firmware/stock/`: `BL_…`, `AP_…`, `CP_…`, and `CSC_…`
   (the full CSC wipes; `HOME_CSC` keeps data — use the full CSC on a fresh install).
3. Start, wait for PASS, let Android boot once.

## 2. Unlock the bootloader

1. In Android: Settings → About phone → Software information → tap **Build number** 7 times.
2. Settings → Developer options → enable **OEM unlocking** (needs Wi-Fi/internet once on some
   firmwares).
3. Power off, enter Download mode (Vol Up + Vol Down + USB). **Long-press Volume Up** at the
   warning screen to unlock. The phone wipes itself and reboots.
4. Let Android start, skip setup, check Developer options again: OEM unlocking must stay on
   (greyed out). From now on every boot shows the yellow/orange unlocked warning.

## 3. Prepare the build containers (once)

The boot image tools need the stock `boot.img` and `vbmeta.img` as templates. Extract them
from the AP package (a plain tar):

```bash
mkdir -p firmware/test && tar -xf firmware/stock/AP_*.tar.md5 -C firmware/test boot.img vbmeta.img
```

```bash
mv firmware/test/boot.img firmware/test/boot-stock.img && mv firmware/test/vbmeta.img firmware/test/vbmeta-stock.img
```

The boot images are signed with `tools/bootimg/a03-boot-test.pem`; `mkboot-a03.sh` generates
a new RSA-4096 key there on first use (the unlocked bootloader accepts any key).

Then, from the project root:

```bash
docker build -t a03-bootimg tools/bootimg
```

```bash
docker build -t a03-pmb tools/pmb
```

```bash
docker volume create a03-pmb
```

```bash
docker run --rm -v a03-pmb:/pmb a03-pmb sh -c 'sudo chown pmos:pmos /pmb && cd /pmb && git clone -q --depth 1 https://gitlab.postmarketos.org/postmarketOS/pmaports.git && mkdir -p work && echo 8 > work/version'
```

Only if you want to rebuild the kernel yourself (otherwise skip to step 4):

```bash
docker build -t a03-kbuild tools/kbuild
```

Then unpack `source/SM-A035F_13_Opensource_A035FXXS9CYG1.zip` into `/k/src` in the
`a03-kernel` volume, apply `tools/kbuild/patches/*.patch`, configure with
`a03_cis_open_defconfig` + `tools/kbuild/pmos.config`, build with
`KOUT=/k/out-wifi tools/kbuild/kmake.sh -j8 Image modules`, check Wi-Fi compatibility with
`modcrc.py` (must be 0 mismatches), and repack `kernel-prebuilt.tar.gz` — see
[how-it-works.md](how-it-works.md#3-the-kernel--toolskbuild). The AOSP clang r383902
toolchain must be in the `a03-toolchain` volume.

## 4. Build the postmarketOS image

The device and kernel packages in `tools/pmb/aports/` are picked up automatically by
`pmb.sh`. Build the root filesystem split into boot and root images (choose your own password
for the `user` account; you'll need it for sudo):

```bash
mkdir -p build/pmos
```

```bash
PMB_OUT="$PWD/build/pmos" tools/pmb/pmb.sh -y install --split --password 'choose-a-password'
```

This produces `build/pmos/samsung-a03-boot.img`, `samsung-a03-root.img` and `initramfs`.
(On an Intel Mac this takes a while; aarch64 runs under emulation.)

Pack them into an Odin package, with the kernel `Image` from the release:

```bash
tools/bootimg/mkodin-pmos.sh build/Image build/pmos AP_pmos_fresh
```

That writes `firmware/odin/AP_pmos_fresh.tar.md5` (boot + stock vbmeta + userdata).

## 5. Flash postmarketOS

1. Download mode on the phone (Vol Up + Vol Down + USB, then Vol Up).
2. In Odin, put **only** `AP_pmos_fresh.tar.md5` in the **AP** slot. Leave BL/CP/CSC empty.
   Options: Auto Reboot on, F. Reset Time on, Re-Partition **off**.
3. Start. After PASS the phone reboots into postmarketOS. The first boot takes longer (the root
   partition is grown to fill userdata). The screen stays black during boot — there's no text
   console — so give it a couple of minutes.

## 6. First login over USB

Plug the phone into the Mac/PC. It appears as a USB Ethernet (CDC-ECM) adapter.

```bash
ssh user@172.16.42.1
```

## 7. Wi-Fi

The image already contains `device-samsung-a03`, so the Wi-Fi driver loads at boot. Without
NetworkManager (fresh `ui=none` image), the service connects using wpa_supplicant:

```bash
sudo sh -c 'wpa_passphrase "YOUR-SSID" > /etc/wpa_supplicant/wpa_supplicant.conf'
```

(it prompts for the passphrase), then:

```bash
sudo rc-service samsung-a03-wifi restart
```

Check with `ip -4 addr show wlan0`. Optionally give the phone a fixed address in your router
(the docs assume `192.168.1.160`).

## 8. Phosh

```bash
sudo apk add postmarketos-ui-phosh stevia-schemas
```

Then switch networking to NetworkManager (Phosh's Wi-Fi settings use it) and connect:

```bash
sudo rc-update add networkmanager default
```

```bash
sudo rc-update del wpa_supplicant default
```

```bash
sudo rc-service networkmanager start
```

```bash
sudo nmcli --ask dev wifi connect "YOUR-SSID"
```

Reinstall the device package once so its post-install hook sees NetworkManager and sets up the
rendering variables (or check that `/etc/environment` contains `WLR_RENDERER=pixman` and
`GSK_RENDERER=cairo`):

```bash
sudo apk fix device-samsung-a03
```

```bash
sudo reboot
```

The phone now boots to the phrog login screen; log in with the password from step 4.

## 9. Updating the kernel later

Kernel updates don't flash themselves (`generate_bootimg="false"`). After installing a new
`linux-samsung-a03`, pack and write the boot image yourself:

1. Copy `/boot/vmlinuz` and `/boot/initramfs` from the phone to `build/`.
2. Pack:

   ```bash
   tools/bootimg/mkboot-a03.sh build/vmlinuz build/initramfs "console=ttyS1,115200n8 PMOS_NO_OUTPUT_REDIRECT" build/boot-new.img
   ```

3. Copy it to the phone and write it (keep the old image as a rollback):

   ```bash
   sudo dd if=/tmp/boot-new.img of=/dev/block/by-name/boot bs=1M conv=fsync
   ```

4. `sync`, then `sudo reboot`. If it doesn't come back, flash a known-good boot image with Odin
   (an AP tar containing just `boot.img`, e.g. `AP_boot_r3.tar.md5` from the release).

## 10. Optional: Docker + Pterodactyl

See [pterodactyl.md](pterodactyl.md).

## Recovery

- **Stuck/bootloop:** hold Volume Down + Power for ~10 s to force a reboot, then immediately
  Vol Up + Vol Down with USB plugged in to reach Download mode, and flash a working boot image
  (or the stock firmware) with Odin.
- **Back to Android:** flash the full stock firmware from `firmware/stock/` with Odin.
