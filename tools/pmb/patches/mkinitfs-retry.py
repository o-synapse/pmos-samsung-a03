# Make pmbootstrap retry mkinitfs: this Mac is Intel, so the aarch64 rootfs runs under qemu-user,
# where mkinitfs (Go) crashes at random (fork/exec "bad address", SIGSEGV). Applied in the Dockerfile.
import re
p = "/opt/pmbootstrap/pmb/chroot/initfs.py"
t = open(p).read()
t = t.replace('''    pmb.chroot.root(["mkinitfs"], chroot)
''', '''    run_mkinitfs(chroot)


def run_mkinitfs(chroot: Chroot) -> None:
    for attempt in range(8):
        try:
            pmb.chroot.root(["mkinitfs"], chroot)
            return
        except CommandFailedError:
            if attempt == 7:
                raise
            logging.info(f"({chroot}) mkinitfs crashed under qemu, retrying")
''', 1)
open(p, "w").write(t)
p = "/opt/pmbootstrap/pmb/install/_install.py"
t, n = re.subn(r'pmb\.chroot\.root\(\["mkinitfs"\], chroot\)', 'pmb.chroot.initfs.run_mkinitfs(chroot)', open(p).read())
assert n == 1, n
open(p, "w").write(t)
