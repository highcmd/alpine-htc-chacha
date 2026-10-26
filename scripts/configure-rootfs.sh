#!/bin/sh
# Configure an Alpine armhf rootfs for HTC ChaCha. Run as root on the host:
#   configure-rootfs.sh <rootfs> <authorized_keys file>
# Files come from config/rootfs-overlay; this script does the in-place edits.
set -e
R=$1
KEYS=$2
[ -d "$R/etc" ] || { echo "usage: $0 <rootfs> <authorized_keys>" >&2; exit 2; }
cd "$R"

# Kernel 2.6.35: no cgroup2
sed -i 's/^#\?rc_cgroup_mode=.*/rc_cgroup_mode="legacy"/; s/^#\?rc_controller_cgroups=.*/rc_controller_cgroups="NO"/' etc/rc.conf

# Console font: Terminus 6x12 -> 80x26 on 480x320; keymap for the QWERTY pad
sed -i 's/^consolefont=.*/consolefont="ter-112n.psf.gz"/' etc/conf.d/consolefont
sed -i 's|^keymap=.*|keymap="/etc/keymaps/chacha.map"|' etc/conf.d/loadkeys

# Modules loaded at boot (bcm4329 options in /etc/modprobe.d/bcm4329.conf)
for m in af_packet ipv6 bcm4329; do
	grep -qx "$m" etc/modules 2>/dev/null || echo "$m" >> etc/modules
done

# root: no password on the local console (tty1 autologin), ssh by key only
sed -i 's/^root:[^:]*:/root::/' etc/shadow
mkdir -p root/.ssh && chmod 700 root/.ssh
if [ -n "$KEYS" ] && [ -f "$KEYS" ]; then
	cat "$KEYS" > root/.ssh/authorized_keys
	chmod 600 root/.ssh/authorized_keys
fi
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/; s/^#\?PasswordAuthentication.*/PasswordAuthentication no/' etc/ssh/sshd_config

chmod 600 etc/wpa_supplicant/wpa_supplicant.conf
find etc/init.d usr/local/bin etc/local.d -type f -exec chmod 755 {} +
mkdir -p var/lib/misc

# Runlevels. Replacements for stock services that fail on 2.6.35:
#   wpa_supplicant-chacha (checkpath on /var/run symlink), ntpd-legacy (ambient caps).
# haveged is started from inittab, before OpenRC.
add() { mkdir -p etc/runlevels/$2; ln -sf /etc/init.d/$1 etc/runlevels/$2/$1; }
for s in devfs dmesg mdev; do add $s sysinit; done
for s in bootmisc hostname modules sysctl syslog seedrng swclock networking consolefont loadkeys wpa_supplicant-chacha; do add $s boot; done
for s in sshd local wifi-country chacha-touchkeys chacha-backlight chacha-idle ntpd-legacy crond; do add $s default; done
for s in killprocs mount-ro savecache; do add $s shutdown; done
echo "rootfs configured"
