# postmarketOS on the Samsung Galaxy A03 (SM-A035F)

A from-scratch postmarketOS port for the Galaxy A03 (SM-A035F, Unisoc T606): Samsung's 4.14
kernel with four backports, Wi-Fi via the stock binary driver, the Phosh touch UI with the
phrog login screen, and Docker + Pterodactyl to host Minecraft servers on the phone.

| Works | Doesn't |
|---|---|
| Boot, display + touch, Wi-Fi, Phosh, sleep/wake, SSH (USB + Wi-Fi), Docker, Pterodactyl | Audio (disabled: crashes the stock driver), GPU acceleration; modem, Bluetooth, camera not attempted |

**Start here:** [docs/README.md](docs/README.md) · [Install on a fresh phone](docs/install.md) ·
[How it works](docs/how-it-works.md) · [The journey](docs/journey.md) ·
[Quirks](docs/quirks.md) · [Pterodactyl](docs/pterodactyl.md)

Ready-built packages, kernel and boot images: see
[Releases](https://github.com/o-synapse/pmos-samsung-a03/releases).

> Flashing this wipes the phone and trips Knox permanently. SM-A035F on stock base
> A035FXXS9CYG1 only.

Samsung's stock firmware and kernel source are not included; [install.md](docs/install.md)
says where to get them.
