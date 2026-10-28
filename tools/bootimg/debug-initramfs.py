# Patches an unpacked pmOS initramfs (cwd) for debug-initramfs.sh.
import os

def patch(f, old, new):
    t = open(f).read()
    assert old in t, (f, old)
    open(f, "w").write(t.replace(old, new, 1))

# USB serial function next to the network function, added before the gadget is bound
anchor = "\t# If an argument was supplied then skip writing to the UDC"
patch("init_functions.sh", anchor, """\t# debug-initramfs.sh: USB serial shell
\tmkdir $CONFIGFS/g1/functions/acm.GS0 && ln -s $CONFIGFS/g1/functions/acm.GS0 $CONFIGFS/g1/configs/c.1

""" + anchor)

serial_loop = """i=0
while [ ! -c /dev/ttyGS0 ] && [ $i -lt 30 ]; do sleep 1; i=$((i + 1)); done
[ -c /dev/ttyGS0 ] || mknod /dev/ttyGS0 c $(tr : " " </sys/class/tty/ttyGS0/dev)
while true; do setsid sh -c "exec sh -i </dev/ttyGS0 >/dev/ttyGS0 2>&1"; sleep 1; done"""

with open("init_functions.sh", "a") as f:
    f.write("\nstart_debug_serial() {\n\t(\n%s\n\t) &\n}\n" % serial_loop)

# init jumps straight to init_2nd.sh when there is no separate initramfs-extra
patch("init_2nd.sh", "\nsetup_usb_network\n", "\nsetup_usb_network\nstart_debug_serial\n")

# switch_root kills the initramfs shell: start a new one from the real rootfs before its init,
# and keep the initramfs log there
patch("init_2nd.sh", 'init="/sbin/init"\n', '''init="/sbin/init"
# debug-initramfs.sh: ttyGS0 shell in the real system, initramfs log in /pmOS_init.log
cat > /sysroot/dbginit.sh <<'DBG'
#!/bin/sh
(
%s
) &
exec /sbin/init "$@"
DBG
chmod +x /sysroot/dbginit.sh
init=/dbginit.sh
''' % serial_loop)
patch("init_2nd.sh", "exec switch_root", "cp /pmOS_init.log /sysroot/pmOS_init.log; sync\nexec switch_root")

# macOS gets no traffic through to the 4.14 NCM gadget (phone rx_packets stays 0): try CDC-ECM
with open("usr/share/deviceinfo/deviceinfo", "a") as f:
    f.write('deviceinfo_usb_network_function="ecm.usb0"\n')

os.makedirs("hooks", exist_ok=True)
open("hooks/10-verbose-initfs.sh", "w").close()
