#!/bin/bash
# Guided installation of Alpine Linux on an HTC ChaCha (A810e).
#
#   scripts/chacha-install.sh <step>
#
# Steps, in order (each one prints the next):
#   check       host tools and the phone (Android running, adb + root)
#   backup      copy the WiFi firmware and the boot/recovery partitions (read-only)
#   build       kernel, boot image and SD card rootfs (asks for sudo)
#   boot        boot Alpine from RAM with "fastboot boot" (nothing is written)
#   sd-format   create one partition on the SD card        (ERASES the card)
#   sd-write    write the rootfs to the SD card            (ERASES the card)
#   flash       write the boot image to the boot partition (replaces Android's kernel)
#   restore     put the backed-up Android boot image back
#
# Nothing is written to the phone without typing a confirmation word, and
# boot/flash refuse to run without a verified backup. See README.md.
set -e
. "$(dirname "$0")/env.sh"

BACKUP=$TOP/backup
BOOT_IMG=$OUT/boot-alpine.img
BOOT_SIZE=3407872		# mtd2 "boot"
RECOVERY_SIZE=5242880		# mtd1 "recovery"

say() { printf '\n\033[1m>> %s\033[0m\n' "$*"; }
next() { printf '\nNext: scripts/chacha-install.sh %s\n' "$*"; }

confirm() {	# confirm WORD "what will happen"
	printf '\n\033[1;31m%s\033[0m\nType %s to continue: ' "$2" "$1"
	read -r answer
	[ "$answer" = "$1" ] || die "cancelled"
}

need() {	# need CMD PACKAGE (mkfs.ext4 lives in sbin, outside a user's PATH)
	PATH=$PATH:/usr/sbin:/sbin command -v "$1" >/dev/null || missing="$missing $2"
}

# ---------------------------------------------------------------- phone access

adb_su() {	# run a command as root on Android
	adb shell "su -c '$1'" | tr -d '\r'
}

adb_pull() {	# adb_pull REMOTE LOCAL: binary-safe (old adbd: no exec-out, CRLF)
	adb shell "su -c 'cat $1 | busybox base64'" | tr -d '\r' | base64 -d > "$2"
}

phone_sha() { adb_su "cat $1 | busybox sha256sum" | cut -d' ' -f1; }

ph() {	# run a command in the Alpine initramfs rescue shell (nc port 23)
	printf '%s\n' "$1" | timeout "${2:-15}" nc -q 2 "$PHONE" 23
}

wait_fastboot() {
	echo "waiting for the phone in fastboot mode (HBOOT shows FASTBOOT USB)..."
	for _ in $(seq 60); do
		fastboot devices | grep -q fastboot && return 0
		sleep 2
	done
	die "no fastboot device (reboot to the bootloader: adb reboot bootloader, or Vol Down + Power)"
}

to_bootloader() {	# from Android (adb) or Alpine (ssh); else ask the user
	if fastboot devices | grep -q fastboot; then
		return
	elif adb get-state 2>/dev/null | grep -q device; then
		adb reboot bootloader
	elif ssh -o ConnectTimeout=5 -o BatchMode=yes root@"$PHONE" true 2>/dev/null; then
		ssh root@"$PHONE" reboot-bootloader || true
	else
		echo "Put the phone into the bootloader (Vol Down + Power), then FASTBOOT."
	fi
	wait_fastboot
}

backup_ok() {
	[ -f "$BACKUP/SHA256SUMS" ] && (cd "$BACKUP" && sha256sum --quiet -c SHA256SUMS) ||
		die "no verified backup in $BACKUP: run scripts/chacha-install.sh backup first"
}

# ---------------------------------------------------------------- steps

step_check() {
	say "host tools"
	missing=
	need adb adb; need fastboot fastboot; need mkbootimg mkbootimg
	need git git; need curl curl; need gcc gcc; need make make; need perl perl
	need python3 python3; need mkfs.ext4 e2fsprogs; need nc netcat-openbsd
	need sha256sum coreutils; need base64 coreutils
	[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] || missing="$missing qemu-user-static binfmt-support"
	if [ -n "$missing" ]; then
		echo "missing:$missing"
		echo "Debian/Ubuntu: sudo apt install$missing"
		exit 1
	fi
	echo "all present"

	say "phone"
	if fastboot devices | grep -q fastboot; then
		fastboot getvar product 2>&1 | grep -i product || true
		echo "The phone is in fastboot mode. For the backup it has to run Android: fastboot reboot"
		exit 0
	fi
	adb get-state 2>/dev/null | grep -q device ||
		die "no adb device: start Android, enable USB debugging, accept the prompt"
	model=$(adb shell getprop ro.product.device | tr -d '\r')
	echo "device: $model"
	[ "$model" = chacha ] || die "this is not an HTC ChaCha (ro.product.device=$model)"
	adb_su id | grep -q 'uid=0' || die "no root: the backup needs su (rooted Android, e.g. CyanogenMod)"
	adb_su 'busybox true' >/dev/null 2>&1 && adb_su 'busybox base64 </dev/null' >/dev/null ||
		die "busybox with base64 is needed on the phone"
	echo "Android with root and busybox: OK"
	echo
	echo "The bootloader must be unlocked (HTCdev): the HBOOT screen shows *** UNLOCKED ***."
	echo "S-ON is fine. Check it with: adb reboot bootloader (then fastboot reboot)."
	next backup
}

step_backup() {
	adb get-state 2>/dev/null | grep -q device || die "no adb device (Android must be running)"
	[ ! -e "$BACKUP/boot.img" ] || die "$BACKUP/boot.img exists; move the old backup away first"
	mkdir -p "$BACKUP" "$FIRMWARE_DIR"

	say "WiFi firmware (stays on your disk, it is not redistributable)"
	for f in fw_bcm4329.bin fw_bcm4329_apsta.bin; do
		adb_pull /system/etc/firmware/$f "$FIRMWARE_DIR/$f"
		[ "$(phone_sha /system/etc/firmware/$f)" = "$(sha256sum < "$FIRMWARE_DIR/$f" | cut -d' ' -f1)" ] ||
			die "$f: checksum mismatch, run backup again"
		echo "$f OK"
	done

	say "boot and recovery partitions (read-only device nodes)"
	for p in "mtd2ro boot.img $BOOT_SIZE" "mtd1ro recovery.img $RECOVERY_SIZE"; do
		set -- $p
		adb_pull /dev/mtd/$1 "$BACKUP/$2"
		size=$(stat -c %s "$BACKUP/$2")
		[ "$size" = "$3" ] || die "$2: $size bytes, expected $3"
		want=$(phone_sha /dev/mtd/$1)
		got=$(sha256sum < "$BACKUP/$2" | cut -d' ' -f1)
		[ "$want" = "$got" ] || die "$2: checksum mismatch, run backup again"
		echo "$want  $2" >> "$BACKUP/SHA256SUMS.new"
		echo "$2 OK ($size bytes)"
	done
	mv "$BACKUP/SHA256SUMS.new" "$BACKUP/SHA256SUMS"
	chmod 600 "$BACKUP"/*
	echo
	echo "Backup in $BACKUP (verified against the phone). Keep a copy somewhere safe."
	next build
}

step_build() {
	[ -f "$FIRMWARE_DIR/fw_bcm4329.bin" ] || die "no WiFi firmware: run the backup step first"
	key=${AUTHORIZED_KEYS:-$HOME/.ssh/id_ed25519.pub}
	[ -f "$key" ] || die "no SSH public key $key (ssh-keygen -t ed25519, or AUTHORIZED_KEYS=file)"
	say "downloads"
	"$TOP/scripts/fetch.sh"
	say "kernel"
	"$TOP/scripts/build-kernel.sh"
	say "boot image"
	"$TOP/scripts/build-bootimg.sh"
	say "rootfs (needs root for the chroot and loop mount)"
	sudo AUTHORIZED_KEYS="$key" "$TOP/scripts/build-rootfs.sh"
	ls -l "$BOOT_IMG" "$OUT/rootfs.ext4.gz"
	next boot
}

step_boot() {
	backup_ok
	[ -f "$BOOT_IMG" ] || die "run the build step first"
	say "boot Alpine from RAM (the phone's flash is not changed)"
	to_bootloader
	fastboot boot "$BOOT_IMG"
	echo
	echo "Without a rootfs on the SD card the phone stays in the initramfs rescue"
	echo "shell; with one, Alpine starts in about 60 s. Then, on this computer:"
	echo "  the USB network interface needs 172.16.42.2/24 (see README, NetworkManager)"
	echo "  rescue shell: nc $PHONE 23      Alpine: ssh root@$PHONE"
	echo
	echo "First install: sd-format (new card), then sd-write."
}

step_sd_format() {
	ph 'echo PING' 5 | grep -q PING || die "no rescue shell on $PHONE:23 (run the boot step with no rootfs on the card)"
	ph 'cat /proc/partitions' | grep mmcblk0 || die "no SD card in the phone"
	confirm ERASE "This creates a new partition table on the phone's SD card: everything on it is lost."
	ph 'printf "o\nn\np\n1\n2048\n\nw\n" | fdisk /dev/mmcblk0; mdev -s; ls -l /dev/mmcblk0p1' 30
	next sd-write
}

step_sd_write() {
	[ -f "$OUT/rootfs.ext4.gz" ] || die "run the build step first"
	confirm ERASE "This overwrites partition 1 of the phone's SD card with the Alpine rootfs."
	"$TOP/scripts/write-sd.sh"
	ph 'reboot -f' 3 || true
	echo
	echo "The phone restarts into Android; run the boot step again to start Alpine"
	echo "from the card. When it works (ssh root@$PHONE), make it permanent:"
	next flash
}

step_flash() {
	backup_ok
	[ -f "$BOOT_IMG" ] || die "run the build step first"
	size=$(stat -c %s "$BOOT_IMG")
	[ "$size" -le "$BOOT_SIZE" ] || die "boot image too large ($size > $BOOT_SIZE)"
	confirm FLASH "This replaces Android's kernel on the boot partition with Alpine's. Android will not start until 'restore'."
	to_bootloader
	fastboot flash boot "$BOOT_IMG"
	fastboot reboot
	echo
	echo "Alpine starts from the card in about 60 s. To check what was written:"
	echo "  ssh root@$PHONE \"head -c $size /dev/mtd2ro | sha256sum\""
	echo "  cat $BOOT_IMG.sha256"
}

step_restore() {
	backup_ok
	confirm RESTORE "This writes your backed-up Android boot image back to the boot partition."
	to_bootloader
	fastboot flash boot "$BACKUP/boot.img"
	fastboot reboot
	echo "Android starts again; the SD card keeps Alpine for later."
}

case $1 in
check) step_check ;;
backup) step_backup ;;
build) step_build ;;
boot) step_boot ;;
sd-format) step_sd_format ;;
sd-write) step_sd_write ;;
flash) step_flash ;;
restore) step_restore ;;
*) sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
