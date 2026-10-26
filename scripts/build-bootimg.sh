#!/bin/sh
# Pack the initramfs (Alpine busybox-static + initramfs/init) and the boot image.
set -e
. "$(dirname "$0")/env.sh"
[ -f "$OUT/zImage" ] || die "run scripts/build-kernel.sh first"
[ -f "$WORK/busybox/bin/busybox.static" ] || die "run scripts/fetch.sh first"

cd "$TOP/initramfs"
sh -n init
sed "s|@BUSYBOX@|$WORK/busybox/bin/busybox.static|" initramfs.list |
	"$OUT/gen_init_cpio" - | gzip -9n > "$OUT/initramfs.cpio.gz"

mkbootimg --kernel "$OUT/zImage" --ramdisk "$OUT/initramfs.cpio.gz" \
	$BOOTIMG_ARGS --cmdline "$BOOTIMG_CMDLINE" -o "$OUT/boot-alpine.img"

size=$(stat -c %s "$OUT/boot-alpine.img")
[ "$size" -le 3407872 ] || die "boot image ($size B) larger than the boot partition (3407872 B)"
sha256sum "$OUT/boot-alpine.img" | tee "$OUT/boot-alpine.img.sha256"
