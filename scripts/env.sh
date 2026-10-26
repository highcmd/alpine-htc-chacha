# Common settings for the build scripts (sourced, not executed).

TOP=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$TOP/work}
OUT=${OUT:-$TOP/out}

ALPINE_MIRROR=${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}
ALPINE_BRANCH=${ALPINE_BRANCH:-v3.24}

KERNEL_REPO=https://github.com/Marvellousteam/android_kernel_htc_msm7227.git
KERNEL_BRANCH=kk
KERNEL_COMMIT=028b0793add83073b4f60a13ccc10ef81227c1fd
KERNEL_SRC=${KERNEL_SRC:-$WORK/kernel-msm7227}
KERNEL_BUILD=${KERNEL_BUILD:-$WORK/build-kernel}
KVER=2.6.39.4-chacha-alpine

# Same compiler as the CM11 kernel that ran on the phone ("gcc version 4.7")
TOOLCHAIN_URL=https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.7/+archive/refs/tags/android-4.4.4_r1.tar.gz
TOOLCHAIN_DIR=$WORK/arm-eabi-4.7

# Android boot image layout of the stock boot partition (mtd2, 3.25 MB)
BOOTIMG_ARGS="--base 0x12c00000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 --tags_offset 0x00000100 --pagesize 2048"
# console=null: printk to fbcon deadlocks msm_fb (MDP waits for an IRQ)
BOOTIMG_CMDLINE="console=null no_console_suspend=1 androidboot.hardware=chacha u_ether.host_addr=02:c4:a0:00:00:01 u_ether.dev_addr=02:c4:a0:00:00:02"

ROOTFS=${ROOTFS:-$WORK/rootfs}
ROOTFS_IMG_SIZE=${ROOTFS_IMG_SIZE:-512M}
ROOTFS_PACKAGES="alpine-base openssh-client openssh-server tmux wpa_supplicant wireless-tools kbd font-terminus e2fsprogs e2fsprogs-extra haveged"
# Firmware copied from the phone's /system/etc/firmware (not redistributable)
FIRMWARE_DIR=${FIRMWARE_DIR:-$TOP/recon/firmware}

PHONE=${PHONE:-172.16.42.1}

KMAKE="make -C $KERNEL_SRC O=$KERNEL_BUILD ARCH=arm CROSS_COMPILE=$TOOLCHAIN_DIR/bin/arm-eabi-"

die() {
	echo "error: $*" >&2
	exit 1
}

# sudo only when not root already
SUDO=
[ "$(id -u)" = 0 ] || SUDO=sudo
