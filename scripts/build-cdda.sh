#!/bin/sh
# Build Cataclysm: Dark Days Ahead (ncurses) for the phone in an Alpine armhf
# chroot (qemu-user). Run as root:  sudo scripts/build-cdda.sh [VERSION]
# VERSION is the upstream branch without "-branch" (default 0.A; 0.8 also builds).
# Output: out/cataclysm-VERSION-armhf.tar.gz (unpack on the phone into /opt).
set -e
. "$(dirname "$0")/env.sh"
[ "$(id -u)" = 0 ] || die "run as root (sudo)"
[ -x "$WORK/apk-static/sbin/apk.static" ] || die "run scripts/fetch.sh first"
[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] || die "qemu-arm binfmt not registered (apt install qemu-user-static)"

CDDA_REPO=https://github.com/CleverRaven/Cataclysm-DDA.git
CDDA_VER=${1:-0.A}
CDDA_BRANCH=$CDDA_VER-branch
CH=$WORK/cdda/chroot
SRC=$WORK/cdda/src-$CDDA_VER

[ -d "$SRC" ] || git clone --depth 1 -b $CDDA_BRANCH $CDDA_REPO "$SRC"

if [ ! -x "$CH/usr/bin/g++" ]; then
	echo ">> armhf build chroot"
	mkdir -p "$CH/etc/apk/keys"
	cp "$WORK/alpine-keys/etc/apk/keys/"* "$CH/etc/apk/keys/"
	printf '%s\n' "$ALPINE_MIRROR/$ALPINE_BRANCH/main" "$ALPINE_MIRROR/$ALPINE_BRANCH/community" > "$CH/etc/apk/repositories"
	"$WORK/apk-static/sbin/apk.static" --root "$CH" --arch armhf --initdb --update-cache \
		add alpine-baselayout busybox build-base ncurses-dev gettext-dev
	cp /etc/resolv.conf "$CH/etc/"
fi
# musl has no backtrace(); debug.cpp only uses it to log a stack on errors
mkdir -p "$CH/usr/local/include"
cat > "$CH/usr/local/include/execinfo.h" <<'EOF'
static inline int backtrace(void **b, int n) { (void)b; (void)n; return 0; }
static inline char **backtrace_symbols(void *const *b, int n) { (void)b; (void)n; return 0; }
EOF

# 0.A: its own std::abs(float) clashes with the one libstdc++ now provides
[ -f "$SRC/src/game.cpp" ] && sed -i '/^namespace std { float abs(float a)/d' "$SRC/src/game.cpp"

mkdir -p "$CH/src"
mount --bind "$SRC" "$CH/src"
mount -t proc proc "$CH/proc"
trap 'umount "$CH/proc" "$CH/src" 2>/dev/null' EXIT

echo ">> compiling (qemu, slow)"
# 2013-14 code: g++ 15 defaults to C++17, which rejects some of it
chroot "$CH" /bin/sh -c "
	set -e
	cd /src
	make -j$(nproc) LOCALIZE=1 DEBUG= WARNINGS=-w \
		OTHERS='-O2 -std=gnu++98 -fpermissive' LDFLAGS='-lncursesw -lintl'
	strip cataclysm
"

echo ">> packaging"
D=$WORK/cdda/pkg/cataclysm
rm -rf "$WORK/cdda/pkg"
mkdir -p "$D"
cp -a "$SRC/cataclysm" "$SRC/data" "$SRC/README.md" "$SRC/LICENSE.txt" "$D/"
mkdir -p "$OUT"
tar -C "$WORK/cdda/pkg" -czf "$OUT/cataclysm-$CDDA_VER-armhf.tar.gz" cataclysm
chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT/cataclysm-$CDDA_VER-armhf.tar.gz"
ls -l "$OUT/cataclysm-$CDDA_VER-armhf.tar.gz"
