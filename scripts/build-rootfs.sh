#!/bin/sh
# Build the Alpine armhf rootfs and an ext4 image for the SD card. Run as root:
#   sudo [AUTHORIZED_KEYS=~/.ssh/id_ed25519.pub] scripts/build-rootfs.sh
# Needs: qemu-user-static binfmt for ARM (chroot compile), mkfs.ext4, python3,
# out/bcm4329.ko (build-kernel.sh) and fw_bcm4329.bin in $FIRMWARE_DIR.
set -e
. "$(dirname "$0")/env.sh"
[ "$(id -u)" = 0 ] || die "run as root (sudo)"
[ -x "$WORK/apk-static/sbin/apk.static" ] || die "run scripts/fetch.sh first"
[ -f "$OUT/bcm4329.ko" ] || die "run scripts/build-kernel.sh first"
[ -f "$FIRMWARE_DIR/fw_bcm4329.bin" ] || die "copy fw_bcm4329.bin from the phone into $FIRMWARE_DIR (see README)"
[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] || die "qemu-arm binfmt not registered (apt install qemu-user-static)"
: "${AUTHORIZED_KEYS:=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/.ssh/id_ed25519.pub}"

APK="$WORK/apk-static/sbin/apk.static --root $ROOTFS --arch armhf"
REPOS="-X $ALPINE_MIRROR/$ALPINE_BRANCH/main -X $ALPINE_MIRROR/$ALPINE_BRANCH/community"

[ ! -e "$ROOTFS" ] || die "$ROOTFS exists, remove it first"
mkdir -p "$ROOTFS/etc/apk/keys"
cp "$WORK/alpine-keys/etc/apk/keys/"* "$ROOTFS/etc/apk/keys/"
printf '%s\n' "$ALPINE_MIRROR/$ALPINE_BRANCH/main" "$ALPINE_MIRROR/$ALPINE_BRANCH/community" > "$ROOTFS/etc/apk/repositories"

echo ">> installing packages"
$APK --initdb --update-cache add $ROOTFS_PACKAGES

echo ">> overlay, keymap, kernel module, firmware"
cp -a "$TOP/config/rootfs-overlay/." "$ROOTFS/"
mkdir -p "$ROOTFS/etc/keymaps"
python3 -I "$TOP/config/gen-keymap.py" > "$ROOTFS/etc/keymaps/chacha.map"
mkdir -p "$ROOTFS/lib/modules/$KVER/extra" "$ROOTFS/lib/firmware"
cp "$OUT/bcm4329.ko" "$ROOTFS/lib/modules/$KVER/extra/"
touch "$ROOTFS/lib/modules/$KVER/modules.builtin" "$ROOTFS/lib/modules/$KVER/modules.order"
cp "$FIRMWARE_DIR"/fw_bcm4329*.bin "$ROOTFS/lib/firmware/"

echo ">> compiling helper tools in an armhf chroot (qemu)"
$APK add build-base linux-headers
mkdir -p "$ROOTFS/root/src"
cp "$TOP/tools-src/"*.c "$ROOTFS/root/src/"
mount --bind /dev "$ROOTFS/dev"
mount -t proc proc "$ROOTFS/proc"
trap 'umount "$ROOTFS/proc" "$ROOTFS/dev" 2>/dev/null' EXIT
chroot "$ROOTFS" /bin/sh -c '
	set -e
	for t in wlpriv chacha-touchkeys chacha-idle reboot-bootloader; do
		gcc -O2 -Wall -o /usr/local/bin/$t /root/src/$t.c
	done
	depmod -a '"$KVER"'
'
umount "$ROOTFS/proc" "$ROOTFS/dev"
trap - EXIT
$APK del build-base linux-headers

echo ">> configuring"
sh "$TOP/scripts/configure-rootfs.sh" "$ROOTFS" "$AUTHORIZED_KEYS"

echo ">> ext4 image ($ROOTFS_IMG_SIZE) with features kernel 2.6.35 understands"
mkdir -p "$OUT"
IMG=$OUT/rootfs.ext4
rm -f "$IMG"
truncate -s "$ROOTFS_IMG_SIZE" "$IMG"
mkfs.ext4 -q -F -L chacha-root -E nodiscard \
	-O ^metadata_csum,^metadata_csum_seed,^64bit,^orphan_file,uninit_bg "$IMG"
MNT=$(mktemp -d)
mount -o loop "$IMG" "$MNT"
cp -a "$ROOTFS/." "$MNT/"
df -h "$MNT" | tail -1
umount "$MNT"
rmdir "$MNT"
e2fsck -fn "$IMG" >/dev/null
gzip -1c "$IMG" > "$IMG.gz"
sha256sum "$IMG" | tee "$IMG.sha256"
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT"
