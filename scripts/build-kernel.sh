#!/bin/sh
# Patch, configure and build the kernel (zImage + bcm4329.ko) and gen_init_cpio.
set -e
. "$(dirname "$0")/env.sh"
[ -d "$KERNEL_SRC" ] || die "run scripts/fetch.sh first"

cd "$KERNEL_SRC"
if git apply --check "$TOP/kernel/chacha-alpine.patch" 2>/dev/null; then
	echo ">> applying kernel/chacha-alpine.patch"
	git apply "$TOP/kernel/chacha-alpine.patch"
elif git apply --check -R "$TOP/kernel/chacha-alpine.patch" 2>/dev/null; then
	echo ">> patch already applied"
else
	die "kernel/chacha-alpine.patch does not apply"
fi

mkdir -p "$KERNEL_BUILD"
cp "$TOP/kernel/chacha-alpine.config" "$KERNEL_BUILD/.config"
yes '' | $KMAKE oldconfig >/dev/null
$KMAKE -j"$(nproc)" zImage modules

mkdir -p "$OUT"
cp "$KERNEL_BUILD/arch/arm/boot/zImage" "$OUT/zImage"
cp "$KERNEL_BUILD/drivers/net/wireless/bcm4329_204/bcm4329.ko" "$OUT/bcm4329.ko"
cc -O2 -o "$OUT/gen_init_cpio" "$KERNEL_SRC/usr/gen_init_cpio.c"
strings "$KERNEL_BUILD/vmlinux" | grep -m1 'Linux version'
ls -l "$OUT/zImage" "$OUT/bcm4329.ko"
