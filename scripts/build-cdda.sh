#!/bin/sh
# Build Cataclysm: Dark Days Ahead (ncurses) for the phone in an Alpine armhf
# chroot (qemu-user). Run as root:  sudo scripts/build-cdda.sh [VERSION]
# VERSION is the upstream branch without "-branch" (default 0.I, the latest stable;
# 0.8, 0.A and 0.D also build).
# Output: out/cataclysm-VERSION-armhf.tar.gz (unpack on the phone into /opt).
set -e
. "$(dirname "$0")/env.sh"
[ "$(id -u)" = 0 ] || die "run as root (sudo)"
[ -x "$WORK/apk-static/sbin/apk.static" ] || die "run scripts/fetch.sh first"
[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] || die "qemu-arm binfmt not registered (apt install qemu-user-static)"

CDDA_REPO=https://github.com/CleverRaven/Cataclysm-DDA.git
CDDA_VER=${1:-0.I}
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
		add alpine-baselayout busybox build-base ncurses-dev gettext-dev linux-headers zlib-dev
	cp /etc/resolv.conf "$CH/etc/"
fi
# musl has no backtrace(); debug.cpp only uses it to log a stack on errors
mkdir -p "$CH/usr/local/include"
cat > "$CH/usr/local/include/execinfo.h" <<'EOF'
static inline int backtrace(void **b, int n) { (void)b; (void)n; return 0; }
static inline char **backtrace_symbols(void *const *b, int n) { (void)b; (void)n; return 0; }
EOF
# musl has no strtoll_l/strtoull_l (0.I's flatbuffers wants them); its integer
# parsing does not depend on the locale anyway. Also forced into 0.D and later.
cat > "$CH/usr/local/include/musl-compat.h" <<'EOF'
#include <stdlib.h>
#include <locale.h>
static inline long long strtoll_l(const char *s, char **e, int b, locale_t l) { (void)l; return strtoll(s, e, b); }
static inline unsigned long long strtoull_l(const char *s, char **e, int b, locale_t l) { (void)l; return strtoull(s, e, b); }
#ifdef __cplusplus
/* older code relied on these arriving through other libstdc++ headers */
#include <cstdint>
#include <cstring>
#include <limits>
#include <algorithm>
#include <stdexcept>
#endif
EOF

# 0.A: its own std::abs(float) clashes with the one libstdc++ now provides
[ -f "$SRC/src/game.cpp" ] && sed -i '/^namespace std { float abs(float a)/d' "$SRC/src/game.cpp"

# one mount point per version, so two versions can build at the same time
B=/src-$CDDA_VER
mkdir -p "$CH$B"
mount --bind "$SRC" "$CH$B"
P=
mountpoint -q "$CH/proc" || { mount -t proc proc "$CH/proc"; P="$CH/proc"; }
trap 'umount $P "$CH$B" 2>/dev/null' EXIT

"$WORK/apk-static/sbin/apk.static" --root "$CH" --arch armhf add zlib-dev linux-headers

echo ">> compiling (qemu, slow)"
case $CDDA_VER in
0.[89A])
	# 2013-14 code: g++ 15 defaults to C++17, which rejects some of it
	MAKE_ARGS="-j$(nproc) LOCALIZE=1 DEBUG= WARNINGS=-w \
		OTHERS='-O2 -std=gnu++98 -fpermissive' LDFLAGS='-lncursesw -lintl'" ;;
*)
	# 0.D and later: curses build, English only; musl has no backtrace(); a g++
	# under qemu can take 1.5 GB, so fewer jobs than CPUs (JOBS overrides)
	MAKE_ARGS="-j${JOBS:-$(( $(nproc) * 3 / 4 ))} cataclysm RELEASE=1 TILES= SOUND= \
		LOCALIZE=0 BACKTRACE=0 LINTJSON=0 ASTYLE=0 TESTS=0 PCH=0 \
		WARNINGS=-w CXX_WARNINGS= RELEASE_FLAGS= \
		CXX='g++ -include /usr/local/include/musl-compat.h -fpermissive -Wno-template-body'" ;;
esac
chroot "$CH" /bin/sh -c "
	set -e
	cd $B
	make $MAKE_ARGS
	strip cataclysm
"

echo ">> packaging"
D=$WORK/cdda/pkg-$CDDA_VER/cataclysm
rm -rf "$WORK/cdda/pkg-$CDDA_VER"
mkdir -p "$D"
cp -a "$SRC/cataclysm" "$SRC/data" "$SRC/README.md" "$SRC/LICENSE.txt" "$D/"
mkdir -p "$OUT"
tar -C "$WORK/cdda/pkg-$CDDA_VER" -czf "$OUT/cataclysm-$CDDA_VER-armhf.tar.gz" cataclysm
chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT/cataclysm-$CDDA_VER-armhf.tar.gz"
ls -l "$OUT/cataclysm-$CDDA_VER-armhf.tar.gz"
