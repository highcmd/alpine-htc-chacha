# NOTES — Alpine Linux on the HTC ChaCha

## 2026-10-25 — Stage 1: reconnaissance
- Device visible: `<serial> product:htc_chacha model:Chacha_A810e`. Root OK, busybox in /system/xbin.
- Problem: `adb shell su -c cmd args` loses arguments ("Unknown id") → use `adb shell "su -c '...'"`.
- Problem: no `adb exec-out` (old adbd), `adb shell` mangles binaries (CRLF) → `busybox base64` in a pipe, sha256 check.
- `busybox base64 /proc/file` reads only the first procfs block → for /proc use `cat /proc/x | busybox base64`.
- Running kernel is 2.6.36.1-Simplicit-ULTiMATE (CM11 flux), not stock 2.6.35.
- NAND/MTD, boot = mtd2 (3.25 MB), recovery = mtd1 (5 MB). Page size 4096.
- WiFi BCM4329, driver bcm4329.ko (wext), NVRAM from /proc/calibration.
- Keyboard has no Ctrl/Esc/digits — keymap to be designed in Stage 4.
- Decision: not copying /data/misc/wifi/wpa_supplicant.conf (private passwords).
- Details: recon/SUMMARY.md

## 2026-10-25 — bootloader state
- Vol Down + Power did not enter HBOOT (it started CM). `adb reboot bootloader` worked.
- HBOOT screen: `*** UNLOCKED ***` / `CHACHA PVT SHIP S-ON RL` / HBOOT-1.10.0000 (HTCdev unlock). In fastboot mode USB ID 0bb4:0ff0.
- **S-ON** + UNLOCKED (HTCdev). Consequences: flash boot/recovery only via fastboot; `fastboot boot` to be checked; writing mtd from a running system/recovery may be blocked by S-ON for boot.
- fastboot on the host: missing, needs `sudo apt install fastboot` (package 1:34.0.5-12).
- fastboot installed (34.0.5-debian). `fastboot getvar all` → recon/fastboot_getvar_all.txt
  (security: on, platform HBOOT-7227, partition-layout HTC, version-main 1.57.0.0). The file contains the IMEI — do not share.

## 2026-10-25 — Stage 2: backup
- boot (mtd2ro) and recovery (mtd1ro) dumped to backup/, 2 reads + sha256 on the phone: match. Details in backup/README.md.
- boot.img header: **page size 2048** (not 4096 — `androidboot.pagesize=4096` in cmdline is something else),
  kernel @0x12c08000, ramdisk @0x13c00000, tags @0x12c00100 → base 0x12c00000, offsets kernel 0x8000, ramdisk 0x1000000, tags 0x100.
  cmdline in the image: `no_console_suspend=1 console=null androidboot.hardware=chacha` (HBOOT appends the rest).
- boot: kernel 2.0 MB + LZMA ramdisk 221 KB, 1.1 MB free. recovery: 1.4 MB free (ramdisk 1.7 MB).
  → budget for pmOS kernel+initramfs in boot: ~3.3 MB total. Kernel has RD_GZIP and RD_LZMA.
- Recovery (mtd1) has the same base and a kernel of ~the same size (some custom recovery; not identified).
- WiFi loaded by libhardware_legacy:
  `insmod bcm4329.ko firmware_path=/system/etc/firmware/fw_bcm4329.bin nvram_path=/proc/calibration iface_name=wlan0`
  wpa_supplicant in CM: `-Dnl80211,wext` (wext is what actually works). Module parameters: clockoverride, dhd_oob_gpio_num.

## 2026-10-25 — Stage 3: DEAD END — pmOS dropped armhf
- pmbootstrap 3.12.1 (git ff954a6) in tools/pmbootstrap, link in ~/.local/bin. Additionally installed: tmux, kpartx.
- sudo for pmbootstrap via PMB_SUDO=wrapper with askpass in the scratchpad (remove after the work).
- `pmbootstrap init` (edge, htc, chacha, downstream) → the wizard does NOT offer armhf.
- Cause: pmaports 1bbc034e24 "pmaports.cfg: remove armhf" + 0067fbb609 "cross/*-armhf: drop"
  (2026-06-23, issue #4615, MR 8884). Last commit with armhf: ad2ce6bc6a.
  pmOS binary repo main/armhf frozen 2026-06-22; v24.06–v26.06 also without armhf in supported_arches.
- Alpine still supports armhf (latest-stable = v3.24.3, edge — APKINDEX OK).
- Init aborted halfway through the wizard (nothing generated).
- Kernel candidates (GitHub): Marvellousteam/android_kernel_htc_msm7227 @kk (2.6.39.4, 2014-07, board-chacha.c),
  Where-No-Man-Has-Gone-Before/kernel_htc_chacha-CHS (HTCdev 2.6.35.10), benjamingwynn|beta1993/android_kernel_htc_msm7227 (2.6.35.13).
  Sources of the running 2.6.36.1-Simplicit-ULTiMATE (flux) — not found.

## 2026-10-25 — Stage 3 (revised): Alpine armhf instead of pmOS
User's decision: plain Alpine armhf v3.24 on SD, kernel candidate 1, 8 GB card (SDHC, visible as mmcblk0, empty — sector 0 zeroed).
- Kernel: src/kernel-msm7227 = Marvellousteam/android_kernel_htc_msm7227 @kk (028b0793), local branch chacha-alpine.
  **Actually based on 2.6.35** (no evict_inode in fs.h), the Makefile gives a fake 2.6.39.4. The running "2.6.36.1" is probably the same trick.
  .config almost identical to the running kernel (differences: LOCALVERSION, governor, XZ vs LZMA, yaffs).
- Toolchain: AOSP prebuilts arm-eabi-4.7 (tag android-4.4.4_r1) in tools/arm-eabi-4.7 — the same gcc version as the flux kernel.
- Fixes: kernel/timeconst.pl (defined(@val) vs new Perl), YAFFS_FS off (does not compile because of the fake version, not needed).
- Config: +DEVTMPFS(+MOUNT), VT, VT_CONSOLE, FRAMEBUFFER_CONSOLE, FONT_6x11/8x16; -VGA_CONSOLE, -ANDROID_PARANOID_NETWORK, -LOCALVERSION_AUTO.
  Saved: src/chacha-alpine.config, patch: src/chacha-alpine.patch.
- **Problem: busybox-static from Alpine (v6KZ, musl) → Segmentation fault on the current kernel** (test from tmpfs /mnt/obb, no writes to partitions).
  Diagnosis: musl for v6K reads TLS via `mrc p15,0,rX,c13,c0,3` (TPIDRURO); a kernel without CONFIG_HAS_TLS_REG
  does not set that register (only kuser 0xffff0ff0). ARM1136 r1p5 has TPIDRURO (since r1p0).
  Fix: arch/arm/mm/Kconfig HAS_TLS_REG `default y if ... || CPU_32v6K`. To be verified on hardware.
- USB: HTC composite, RNDIS via `echo 1 > /sys/class/usb_composite/rndis/enable` (not configfs).
- msm_fb: fillrect/copyarea/imageblit call msmfb_update → fbcon should refresh.
- Test image: initramfs/out/boot-stage3.img (2.66 MB; zImage 1.94 MB + initramfs 0.7 MB),
  base 0x12c00000, page 2048, cmdline `console=tty0 no_console_suspend=1 androidboot.hardware=chacha`.
  init: RNDIS 172.16.42.1, udhcpd → host 172.16.42.2, telnetd, sh on tty1.
- Host tools additionally installed: fastboot, mkbootimg, tmux, kpartx.

## 2026-10-25 — test 1: boot-stage3.img (fastboot boot, with consent)
- `fastboot boot` with S-ON: WORKS (OKAY, Booting).
- Result: white HTC screen, no USB re-enumeration (kernel did not reach the drivers), Power does not reset → battery pulled.
  Phone came up normally into CM (flash untouched). No /proc/last_kmsg (pulling the battery wiped RAM).
- Hypotheses: (1) XZ decompressor (backport in the tree; the running kernel uses LZMA), (2) HAS_TLS_REG.
- Prepared: out/boot-A-lzma.img (XZ→LZMA, rest unchanged; sha 13c233a8…),
  out/boot-B-lzma-notls.img (A without HAS_TLS_REG; sha cb9e9804…).

## 2026-10-25 — test 2: boot-A-lzma.img
- Sent at ~23:27 (command interrupted by the user while waiting, but fastboot boot had already run).
- Result identical to test 1: white HTC screen, no USB re-enumeration, bootloader not responding.
- Conclusion: XZ is not the (only) cause. Next: B (without HAS_TLS_REG).
- Procedural note: split into short commands (reboot bootloader / fastboot boot / observation separately).

## 2026-10-26 — hang bisection (fastboot boot, RAM)
| image | DEVTMPFS | TLS | VT/fbcon | ramdisk | result |
|---|---|---|---|---|---|
| stage3/A/B/C1/E/E-hyb/H-hyb | yes | varies | varies | various | hangs before USB |
| D (running .config, without yaffs) | no | no | no | CM | adb OK |
| I (D + TLS + PARANOID off) | no | yes | no | hybrid | adb OK, **musl busybox works** |
| J (I + VT/fbcon) console=tty0 | no | yes | yes | v2 | **picture on screen**, stops after diagchar_init |
- **CONFIG_DEVTMPFS hangs this kernel** → disabled; /dev = tmpfs + mdev -s.
- HAS_TLS_REG confirmed on ARM1136 r1p5: Alpine busybox (musl, v6KZ) works via adb shell.
- J: fbcon 60x20 (8x16) works; printk→fbcon from a context with IRQs disabled (SMD) probably deadlocks msmfb_update.
  Test J2: the same image with console=null (printk not to the screen).
- Hybrid ramdisk (CM ramdisk + Alpine busybox as /system/bin/sh) = great diagnostic tool (adb shell without /system).
- Exit from a working test: `adb reboot bootloader` (no battery pull). Hang → battery.
- Dmesg from I: tests/dmesg-I-hybrid.txt

## 2026-10-26 — Stage 3 DONE: boot to initramfs + shell over USB
- J2 (console=null): boots, fbcon OK, RNDIS OK (host: rndis_host, enx<random MAC>), ping 0.3 ms.
  console=null solved the printk→fbcon deadlock (SMD hypothesis indirectly confirmed).
- Alpine busybox-static does NOT have telnetd/udhcpd (they are in busybox-extras) → shell via `nc -lk -s 172.16.42.1 -p 23 -e /bin/sh`.
  Host: `ip addr add 172.16.42.2/24 dev enx...` manually (RNDIS MAC random on every boot — to be made fixed).
- J3: root shell via nc works; `reboot -f` remotely → phone returns to CM (no battery pull).
- Keyboard: letters work on tty1; no Fn/Alt layer (symbols, digits) → Stage 4 keymap.
- fbcon 60x20 (FONT_8x16 by default); SD card visible as /dev/mmcblk0. RAM: 7.7 MB used / 425 MB.
- Noise in dmesg: `[DISP]msmfb: pan_update in state(1)` on every update — to be silenced.
- Artefacts: src/chacha-alpine.config (kernel J), src/chacha-alpine.patch (timeconst + HAS_TLS_REG),
  initramfs/out/boot-stage3-working.img (sha b753e508…), initramfs/root/init, initramfs/out/initramfs.list.
- Dmesg: tests/dmesg-J3.txt

## 2026-10-26 — Alpine 3.24 from the SD card WORKS
- Writing the card via CM USB Mass Storage → CM froze during mkfs (abandoned).
- Instead: 512 MB ext4 image built on the host (images/rootfs.ext4, features compatible with 2.6.35:
  without metadata_csum/64bit/orphan_file, with uninit_bg), sent gzipped over RNDIS: host `cat > /dev/tcp/...`,
  phone `nc -l | gunzip | dd of=/dev/mmcblk0p1`. SHA256 from the card matches. Then online resize2fs → 7.1 GB.
- Pitfalls: (1) NetworkManager removes the static IP from enx* → `nmcli dev set <if> managed no`;
  (2) host netcat-traditional cuts the stream → bash /dev/tcp; (3) busybox nc on the phone: `nc -q 2` ends the session before long output;
  (4) `grep chacha.debug /proc/cmdline` matched `board_chacha.debug_uart=0` from HBOOT → keyword changed to `rdshell`.
  (5) grep -v "\[" hid sshd ([listener] in the OpenSSH 10 process title).
- inittab: the first line starts a rescue shell `nc -lk -s 172.16.42.1 -p 23` (in the background) before OpenRC.
- OpenRC: first start is long (gendepends at 600 MHz). Services OK: devfs(tmpfs), mdev, networking (usb0 172.16.42.1),
  consolefont (ter-112n), syslog, sshd (id_ed25519 key only), getty tty1/tty2.
- SSH from the host: `ssh root@172.16.42.1` works. RAM: 12 MB used.
- Bootable image (still only fastboot boot, NOT flashed): initramfs/out/boot-alpine-sd.img

## 2026-10-26 — Stage 4: keymap + WiFi
### Keymap (config/gen-keymap.py → config/chacha.map → /etc/keymaps/chacha.map, loadkeys service in boot)
- FN (56) = AltGr: symbols as printed on the keys (from CM's chacha-keypad.kcm). Shift+FN: [ ] { } < > | \ ~ ` ^ (on Q A W S E D T G U J K).
- SYM (183, KEY_F13) = Control; FN+SYM = 0. Green call key (231) = Esc. Red (107) = Alt. Facebook (184) = |.
- FN+arrows = PgUp/PgDn/Home/End; Shift+up/down and Vol± = scrolling; FN+DEL = Delete.
### Entropy
- Kernel without getrandom(): OpenSSL 3 waits on /dev/random; entropy_avail dropped to ~34 → sshd hung at "banner exchange".
  Fix: haveged (boot). armhf packages transferred: apk.static fetch on the host → scp / nc.
### WiFi (bcm4329_204 from our tree, firmware and NVRAM as in CM)
- insmod OK, wlan0 MAC from /proc/calibration; but iwlist scan → 0 APs.
- STOP/START via iwpriv → SDIO reset fail (-110) — do NOT use; rmmod/insmod clears the state.
- **Scanning works only after starting wpa_supplicant -D wext** (it sends disassoc → "disassoc client!") → 3 APs.
- No APs on channels 12/13 (probably the firmware's default country = US) — to be solved (COUNTRY via SIOCSIWPRIV).
- No 5 GHz (NVRAM aa5g=0).
- Persistent: /etc/modules (bcm4329), /etc/modprobe.d/bcm4329.conf, /etc/conf.d/wpa_supplicant (-D wext), wlan0 dhcp, wpa_supplicant in boot.
  Script: config/wifi-setup.sh. Busybox depmod requires an empty modules.builtin.

## 2026-10-26 — "do everything": NAT, autologin, MAC, msmfb, WiFi country, touchkeys, backup
- Internet over USB: config/host-usb-nat.sh (iptables MASQUERADE + DOCKER-USER, not persistent). Phone: usb0 post-up default via 172.16.42.2 metric 500.
- Fixed RNDIS MAC: cmdline `u_ether.host_addr=02:c4:a0:00:00:01 u_ether.dev_addr=02:c4:a0:00:00:02` → host enx02c4a0000001,
  NM profile "chacha-usb" (172.16.42.2/24, never-default) — the host configures itself.
- msmfb: DLOG had a hardcoded `| SUSPEND_RESUME` → patch in msm_fb.c (src/chacha-alpine.patch).
- Autologin tty1: `getty -n -l /usr/local/bin/autologin` (exec login -f root).
- Clock: the phone starts in 1980 → TLS in apk fails. RTC without /dev/rtc (Android /dev/alarm) → swclock (boot) + ntpd.
  Stock ntpd: "Could not set iab" (OpenRC ambient capabilities, missing in 2.6.35) → own ntpd-legacy service.
- Stock wpa_supplicant: `checkpath /var/run/...` → "Symbolic link loop" on 2.6.35 → own wpa_supplicant-chacha service (waits for wlan0).
- Country code: tools-src/wlpriv.c (SIOCSIWPRIV "COUNTRY PL") + wifi-country service (retries, because the driver refuses during a scan).
  After PL, networks on channel 12 are visible.
- Touchkeys: tools-src/chacha-touchkeys.c (cy8c MT protocol A → uinput), chacha-touchkeys service, /etc/conf.d (default Ctrl+B, Tab, Esc, Ctrl+R).
  Threshold Y=700 (raw) computed from virtualkeys — NOT VERIFIED by touch.
- build-base installed on the phone (gcc 15 on ARMv6 compiles small programs in ~1 s).
- Overlay of system files: config/rootfs-overlay/. Backup of the whole rootfs from the card: backup/sd/rootfs-20261026.tar.gz (91 MB).
- Final image (RAM test OK): initramfs/out/boot-alpine-final.img (= boot-M).

## 2026-10-26 — fast startup (10 min → 55 s)
- Cause: `openrc sysinit` recomputes the deptree on every boot (/run is tmpfs); the sshd service's depend() calls `sshd -G`,
  which blocks on /dev/random (entropy ~40, haveged only started in boot) → minutes.
- Fix: haveged from inittab before `openrc sysinit` (removed from the boot runlevel).
- Additionally: the initramfs sets the clock from the mtime of /var/lib/misc/openrc-shutdowntime (swclock) before switch_root;
  crond touches that file every 15 min (in case of power loss).
- reboot-bootloader (tools-src/reboot-bootloader.c, RESTART2 "bootloader"): from Alpine straight into fastboot — WORKS.
- Final image: initramfs/out/boot-alpine-final.img (= boot-N), RAM test: SSH after 55 s, all services OK.

## 2026-10-26 — FLASHED to the boot partition (with the user's consent)
- `fastboot flash boot initramfs/out/boot-alpine-final.img` → OKAY. Readback of mtd2ro (cat | head -c 2779136): sha256 7074eefd… = image.
- The phone boots into Alpine from flash by itself: SSH after 61 s. CM no longer starts (CM system on NAND untouched).
- Entering fastboot from Alpine: `reboot-bootloader`. Back to CM: `fastboot flash boot backup/boot.img` (sha d09d95cc…).
- busybox dd on /dev/mtdNro → EINVAL; read via cat.

## 2026-10-26 — git repository
- Reproducible path: scripts/{fetch,build-kernel,build-bootimg,build-rootfs,write-sd}.sh, instructions in README.md.
- Tested from scratch (clean work/): fetch + kernel + bootimg OK (the patch applies to a fresh clone @028b0793).
- Outside the repo (.gitignore): partition copies, SD backup, Broadcom firmware, dumps with IMEI/serial number/MAC, working directories.
- Keymap generated when building the rootfs (config/gen-keymap.py), not kept in the repo.
- New card: partition via fdisk from the initramfs (busybox), image written over RNDIS (write-sd.sh),
  ext4 grown on first boot (/etc/local.d/resize-rootfs.start).

## 2026-10-26 — console colours
- msm_fb (HTC) filled the pseudo palette with hardcoded values: PP[0]=black, PP[1..15]=white, no fb_setcolreg → monochrome console.
- Patch: msmfb_setcolreg (pixel layout as in msmfb_set_par: 32 bpp R|G<<8|B<<16, 16 bpp RGB565) + default VGA palette in setup_fb_info.
- RAM test (fastboot boot): 16 colours OK (VGA palette in a /dev/fb0 dump). Background only 8 colours (Linux console limitation).
- No 256/truecolor: approximation of 38;5;n in the console only from kernel 3.16.
- Screenshot: `head -c 614400 /dev/fb0` (480x320x4, pan 0,0) → PIL frombytes RGBA. With the console blanked the fb is black.

2026-10-26: flashed out/boot-alpine.img (colour kernel, sha256 b5fe5782…19c1) to boot;
read back from /dev/mtd2ro matches. Boots to sshd in ~50 s.

2026-10-26: chacha-config (usr/local/bin): busybox-sh menu, letters instead of digits
(digits need FN). WiFi through wpa_cli: scanned SSIDs set as P"..." (scan_results is
printf-escaped), hidden ones as hex; psk quoted; select_network, then enable_network all +
save_config; udhcpc (-b from ifup) gets SIGUSR1. Fonts: dimensions read from the PSF1/PSF2
header; preview with setfont -C /dev/tty1, auto-revert after 20 s. Terminus offered from
code page 2 (Polish); u/v have 512 glyphs, which would cut the colours to 8.
Tested: scan (ch 12 visible), preview/revert/save, failed connect cleans up.
Not tested: a successful connect (2.4 GHz network unavailable).

2026-10-26: busybox getty defaults to TERM=vt102 (no colours, so ssh sessions were monochrome);
inittab now passes "linux" as the getty TERM argument.

2026-10-26: CDDA 0.8-branch built in an armhf Alpine chroot (qemu), g++ 15 with
-std=gnu++98 -fpermissive; musl lacks execinfo.h -> stub header (backtrace returns 0).
Command-line LDFLAGS replaces the Makefile's -lncursesw, so it is passed explicitly.
Runs on the phone (main menu checked in a tmux 80x26 pane).
WiFi from the phone hotspot dropped (SCANNING) while wlan0 kept its lease and default
route (metric 211), so apk hung; worked around with a metric-100 route via usb0.

2026-10-26: backlights are microp LEDs in /sys/class/leds: keyboard-backlight (LED_GPO,
on/off only), button-backlight (PWM 0..255), sharekey (Facebook key). The
lcd-backlight-gate trigger only fires from panel early-suspend, which never happens here,
and msm_fb has no fb_blank (EINVAL), so the backlights cannot follow console blanking
without kernel work. New service chacha-backlight + /etc/conf.d/chacha-backlight
(default: keyboard on, buttons off); chacha-config "p" menu.
chacha-idle (tools-src): polls chacha-keypad + cy8c-touchscreen only (light/proximity/
compass report continuously); after the timeout saves and zeroes lcd/keyboard/button
backlights and EVIOCGRABs the inputs so the waking key is not typed; SIGTERM restores.
Console blanking disabled with ESC[9;0] in the service. Timed blank + SIGTERM restore
tested over ssh; waking with a real key press needs a person at the phone.

2026-10-26: DATA LOSS. The phone rebooted uncleanly (cause unknown: around 11:50 UTC, while
idle) and every file written since boot came back empty: init scripts, chacha-idle,
/opt/cataclysm data, the user's first CDDA save. Root cause: the HTC kernel sets
dirty_writeback_interval = 0 (mm/page-writeback.c) and only raises it to 500 in an
Android early-suspend handler, which never runs here, so dirty pages stayed in RAM
(4 MB test file still Dirty after 60 s). apk packages survived because apk syncs.
Fix: /etc/sysctl.d/chacha.conf vm.dirty_writeback_centisecs=500 (sysctl runs in boot);
verified Dirty drops to 0. Damaged files redeployed; empty save moved to save.broken.
The "BUG: sleeping function called from invalid context" warnings (tty_open,
page_alloc, ext4_remount) show up for many processes; pre-existing, not caused by
chacha-idle.

chacha-idle: power key (KEY_POWER on chacha-keypad, VoidSymbol in the console keymap):
short press toggles dark, 3 s hold execs /sbin/poweroff after printing a notice on
tty1. Tested by writing input_event structs to /dev/input/event4 (evdev injection is
delivered to the grabbing client too); the long press was tested with a fake poweroff
in a mount namespace only, not a real power-off.
chacha-config UI translated to English (confirm is now y/N).

2026-10-26: "idle froze the keyboard": tty1 output was stopped by ^S (SYM+S = Ctrl+S,
XOFF); the shell slept in n_tty_write, so nothing echoed. A power long-press then made
chacha-idle block in tty_write_lock writing its notice (the shell held the write lock).
TIOCSTI ^Q released it, and the pending poweroff ran. Fixes: chacha-idle opens the
console O_NONBLOCK (tty_write_lock uses trylock then); /etc/profile.d/chacha-console.sh
runs stty -ixon on the local consoles. (TCXONC TCOON does not help: it only undoes TCOOFF.)

## Battery readout in chacha-config
/sys/class/power_supply/battery: batt_vol (mV), batt_current (mA), batt_temp (0.1 C),
status, capacity (htc_battery percent from the factory 1250 mAh curve, meaningless with
the user's custom larger cell). chacha-config shows voltage in the main menu and a
"b) battery" screen refreshing every 5 s. Sign/direction of batt_current not verified.
Also deployed the ^S fixes (chacha-idle O_NONBLOCK, profile.d/chacha-console.sh).

## Cataclysm 0.A replaces 0.8
build-cdda.sh takes the version (default 0.A); sources in work/cdda/src-VERSION. 0.A
builds with the same flags as 0.8 except src/game.cpp defines its own std::abs(float),
which clashes with libstdc++ 15; the script deletes that line. On the phone /opt/cataclysm
is now 0.A (menu shows "Version: 0.A"); the 0.8 save dirs moved to /root/cataclysm-0.8-saves.

## Cataclysm 0.D installed (0.I still building)
User: any version is fine as long as it works. Latest stable is 0.I-1 (0.I-branch, Sep 2026,
111 MB data); built in parallel with 0.D (2019, 42 MB data, first with Android builds).
build-cdda.sh changes: one bind mount per version (/src-VER) so builds can run together;
modern flags TILES= SOUND= (0.D tests "ifdef TILES", so TILES=0 meant tiles), LOCALIZE=0,
BACKTRACE=0, RELEASE=1 (-Os), WARNINGS=-w RELEASE_FLAGS= (drop -Werror);
CXX='g++ -include musl-compat.h -fpermissive -Wno-template-body'. musl-compat.h adds
strtoll_l/strtoull_l (0.I flatbuffers) and <cstdint> etc. (0.D relied on transitive includes);
-Wno-template-body: GCC 14 checks uninstantiated template bodies (0.D src/optional.h).
0.D on the phone: menu RSS 23 MB; "Play Now!" world load ~2.5 min, VmHWM 121 MB, idle CPU 0%,
moving works, save and quit works (~900 KB). Needs LANG=C.UTF-8 (plain ssh has no LANG; it
warns and waits for a key) -> wrapper /usr/local/bin/cataclysm now in the overlay.
0.A removed from the phone; /opt/cataclysm is 0.D.
0.I build stopped at the user's request ("I don't need newer versions") after ~330 of
~400 objects; musl-compat.h is now C++-only because 0.I compiles zstd's C with $(CXX) -x c.
build-cdda.sh default is 0.D. work/cdda/src-0.I (1.2 GB) left in place.

## Held-key repeat (chacha-idle)
chacha-keypad capabilities/ev=3 (no EV_REP), so the kernel never autorepeats and kbdrate is
useless. chacha-idle now opens the input devices O_RDWR and, while awake, writes EV_KEY value 2
(+SYN) for the last pressed non-modifier key into the keypad's evdev; input_handle_event passes
value 2 to handlers when the key is down, and the console kbd handler treats it as a repeat.
Its own value-2 events come back on the same fd and are ignored for tracking; any release
stops repeat (as in the kernel); no catch-up after stalls (bursts overshoot in games).
Excluded: 42 Shift, 56 FN, 183 SYM, 107 red call (Alt), 116 power. Options -r DELAY -p PERIOD,
conf.d KEY_REPEAT_DELAY/KEY_REPEAT_PERIOD (400/100), chacha-config "r) key repeat".
Measured via an evdev reader: first repeat 402 ms after press, then 99-101 ms apart.
MISTAKE: tested by injecting keys while the user was playing CDDA on tty1 (~20 moves west,
opened "Use item"). Check /dev/vcs1 / ps for tty1 before injecting anything.

## Screen brightness
lcd-backlight (0..255) via chacha-config p -> e (10/25/50/75/100% = 26/64/128/192/255),
preview + confirm y within 15 s else revert. Saved as SCREEN in conf.d/chacha-backlight
(empty = leave kernel value); chacha-backlight start writes it, stop leaves the screen lit.
chacha-idle saves/restores whatever value is current, so it keeps the choice.
Deployed 2026-10-27 with the FN+v keymap (loadkeys -C /dev/tty1, dumpkeys shows keycode 47
= +v +V asciicircum currency); files replaced via mv because chacha-config was running on
tty1. Menus render; lowest usable level on the panel still to be judged by the user.

## Audio / FM (dropped) and vibrator
Audio: no ALSA; HTC qdsp5_comp driver. /dev/msm_pcm_out plays (AUDIO_SET_CONFIG, write two
4800-byte buffers BEFORE AUDIO_START, else -EIO); /dev/msm_snd only has SND_SET_DEVICE /
SND_SET_VOLUME (no endpoint list; ids from the modem table). A 440 Hz test tone ran through
DSP/audmgr without errors; whether/where it was audible never confirmed. Headset detect:
/sys/class/switch/h2w. FM: BCM4329 over HCI on /dev/ttyHS0, no kernel FM driver. User dropped
audio and FM ("they are not needed"); test tools removed from the phone.
Vibrator: /sys/class/timed_output/vibrator/enable (ms) works; chacha-config "v) vibration test".
