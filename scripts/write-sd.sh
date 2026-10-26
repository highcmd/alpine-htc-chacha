#!/bin/bash
# Write out/rootfs.ext4 to the phone's SD card (/dev/mmcblk0p1) over USB RNDIS.
# The phone must be running the initramfs shell: boot out/boot-alpine.img with
# `fastboot boot` while the SD card has no rootfs (or "rdshell" on the cmdline),
# and the card must already have an MBR with partition 1 (see README).
# DESTROYS the contents of /dev/mmcblk0p1.
set -e
. "$(dirname "$0")/env.sh"
IMG=$OUT/rootfs.ext4
[ -f "$IMG.gz" ] || die "run scripts/build-rootfs.sh first"

ph() {	# run a command in the phone's nc shell
	printf '%s\n' "$1" | timeout "${2:-15}" nc -q 2 "$PHONE" 23
}

ph 'test -b /dev/mmcblk0p1 && echo PART-OK' | grep -q PART-OK || die "no /dev/mmcblk0p1 on the phone"
ph 'rm -f /tmp/dd.log; setsid sh -c "nc -l -s '"$PHONE"' -p 1234 | gunzip | dd of=/dev/mmcblk0p1 bs=65536 2>/tmp/dd.log; sync; echo DONE >> /tmp/dd.log" </dev/null >/dev/null 2>&1 &'
sleep 2
echo ">> sending $(stat -c %s "$IMG.gz") bytes"
cat "$IMG.gz" > "/dev/tcp/$PHONE/1234"

echo ">> waiting for dd to finish"
until ph 'cat /tmp/dd.log' 8 | grep -q DONE; do sleep 10; done
ph 'cat /tmp/dd.log'

echo ">> verifying sha256 on the card"
blocks=$(( $(stat -c %s "$IMG") / 65536 ))
ph 'rm -f /tmp/sha; setsid sh -c "dd if=/dev/mmcblk0p1 bs=65536 count='"$blocks"' 2>/dev/null | sha256sum > /tmp/sha" </dev/null >/dev/null 2>&1 &'
until ph 'cat /tmp/sha' 6 | grep -q ' -'; do sleep 10; done
want=$(cut -d' ' -f1 "$IMG.sha256")
got=$(ph 'cat /tmp/sha' 6 | cut -d' ' -f1)
echo "image $want"
echo "card  $got"
[ "$want" = "$got" ] || die "checksum mismatch"
echo "OK - reboot the phone (ph 'reboot -f') and boot out/boot-alpine.img again"
