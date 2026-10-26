#!/bin/sh
# Download toolchain, kernel source, Alpine busybox-static, apk.static and keys.
set -e
. "$(dirname "$0")/env.sh"
mkdir -p "$WORK/dl"
cd "$WORK"

if [ ! -x "$TOOLCHAIN_DIR/bin/arm-eabi-gcc" ]; then
	echo ">> toolchain arm-eabi-4.7 (AOSP prebuilts)"
	mkdir -p "$TOOLCHAIN_DIR"
	curl -fL "$TOOLCHAIN_URL" | tar xz -C "$TOOLCHAIN_DIR"
fi

if [ ! -d "$KERNEL_SRC/.git" ]; then
	echo ">> kernel source $KERNEL_REPO@$KERNEL_BRANCH"
	git clone --depth 1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_SRC"
fi
[ "$(git -C "$KERNEL_SRC" rev-parse HEAD)" = "$KERNEL_COMMIT" ] ||
	echo "warning: kernel HEAD is not $KERNEL_COMMIT (branch moved?)" >&2

fetch_apk() {	# fetch_apk <repo> <arch> <name> <destdir>
	url=$ALPINE_MIRROR/$ALPINE_BRANCH/$1/$2
	f=$(curl -fs "$url/" | grep -o "\"$3-[0-9][^\"]*\.apk\"" | tr -d '"' | head -1)
	[ -n "$f" ] || die "$3 not found in $url"
	[ -f "dl/$f" ] || curl -fso "dl/$f" "$url/$f"
	mkdir -p "$4"
	tar xzf "dl/$f" -C "$4" 2>/dev/null
}

echo ">> Alpine busybox-static (armhf) for the initramfs"
fetch_apk main armhf busybox-static "$WORK/busybox"
echo ">> apk.static (x86_64) and Alpine signing keys"
fetch_apk main x86_64 apk-tools-static "$WORK/apk-static"
fetch_apk main armhf alpine-keys "$WORK/alpine-keys"

ls -l "$TOOLCHAIN_DIR/bin/arm-eabi-gcc" "$WORK/busybox/bin/busybox.static" "$WORK/apk-static/sbin/apk.static"
