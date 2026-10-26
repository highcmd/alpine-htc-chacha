# NOTES — postmarketOS na HTC ChaCha

## 2026-10-25 — Etap 1: rekonesans
- Urządzenie widoczne: `<serial> product:htc_chacha model:Chacha_A810e`. Root OK, busybox w /system/xbin.
- Problem: `adb shell su -c cmd args` gubi argumenty („Unknown id”) → używać `adb shell "su -c '...'"`.
- Problem: brak `adb exec-out` (stary adbd), `adb shell` psuje binaria (CRLF) → `busybox base64` w potoku, sprawdzanie sha256.
- `busybox base64 /proc/plik` czyta tylko pierwszy blok procfs → dla /proc używać `cat /proc/x | busybox base64`.
- Działa kernel 2.6.36.1-Simplicit-ULTiMATE (CM11 flux), nie stock 2.6.35.
- NAND/MTD, boot = mtd2 (3.25 MB), recovery = mtd1 (5 MB). Page size 4096.
- WiFi BCM4329, sterownik bcm4329.ko (wext), NVRAM z /proc/calibration.
- Klawiatura bez Ctrl/Esc/cyfr — keymap do zaprojektowania w Etapie 4.
- Decyzja: nie kopiuję /data/misc/wifi/wpa_supplicant.conf (prywatne hasła).
- Szczegóły: recon/SUMMARY.md

## 2026-10-25 — stan bootloadera
- Vol Down + Power nie wszedł do HBOOT (uruchomił CM). Zadziałało `adb reboot bootloader`.
- Ekran HBOOT: `*** UNLOCKED ***` / `CHACHA PVT SHIP S-ON RL` / HBOOT-1.10.0000 (HTCdev unlock). W trybie fastboot USB ID 0bb4:0ff0.
- **S-ON** + UNLOCKED (HTCdev). Konsekwencje: flash boot/recovery tylko przez fastboot; `fastboot boot` do sprawdzenia; zapis mtd z poziomu działającego systemu/recovery dla boot może być blokowany przez S-ON.
- fastboot na hoście: brak, wymaga `sudo apt install fastboot` (pakiet 1:34.0.5-12).
- fastboot zainstalowany (34.0.5-debian). `fastboot getvar all` → recon/fastboot_getvar_all.txt
  (security: on, platform HBOOT-7227, partition-layout HTC, version-main 1.57.0.0). Plik zawiera IMEI — nie udostępniać.

## 2026-10-25 — Etap 2: backup
- boot (mtd2ro) i recovery (mtd1ro) zrzucone do backup/, 2 odczyty + sha256 na telefonie: zgodne. Szczegóły backup/README.md.
- Nagłówek boot.img: **page size 2048** (nie 4096 — `androidboot.pagesize=4096` w cmdline to coś innego),
  kernel @0x12c08000, ramdisk @0x13c00000, tags @0x12c00100 → base 0x12c00000, offsety kernel 0x8000, ramdisk 0x1000000, tags 0x100.
  cmdline w obrazie: `no_console_suspend=1 console=null androidboot.hardware=chacha` (resztę dokleja HBOOT).
- boot: kernel 2.0 MB + ramdisk LZMA 221 KB, wolne 1.1 MB. recovery: wolne 1.4 MB (ramdisk 1.7 MB).
  → budżet na kernel+initramfs pmOS w boot: ~3.3 MB łącznie. Kernel ma RD_GZIP i RD_LZMA.
- Recovery (mtd1) ma tę samą bazę i kernel ~tej samej wielkości (to jakiś custom recovery; nie identyfikowałem).
- WiFi ładowany przez libhardware_legacy:
  `insmod bcm4329.ko firmware_path=/system/etc/firmware/fw_bcm4329.bin nvram_path=/proc/calibration iface_name=wlan0`
  wpa_supplicant w CM: `-Dnl80211,wext` (faktycznie działa wext). Parametry modułu: clockoverride, dhd_oob_gpio_num.

## 2026-10-25 — Etap 3: ŚLEPA ULICZKA — pmOS porzucił armhf
- pmbootstrap 3.12.1 (git ff954a6) w tools/pmbootstrap, link w ~/.local/bin. Doinstalowane: tmux, kpartx.
- sudo dla pmbootstrap przez PMB_SUDO=wrapper z askpass w scratchpadzie (usunąć po pracy).
- `pmbootstrap init` (edge, htc, chacha, downstream) → kreator NIE oferuje armhf.
- Przyczyna: pmaports 1bbc034e24 „pmaports.cfg: remove armhf” + 0067fbb609 „cross/*-armhf: drop”
  (2026-06-23, issue #4615, MR 8884). Ostatni commit z armhf: ad2ce6bc6a.
  Repo binarne pmOS main/armhf zamrożone 2026-06-22; v24.06–v26.06 też bez armhf w supported_arches.
- Alpine nadal wspiera armhf (latest-stable = v3.24.3, edge — APKINDEX OK).
- Init przerwany w połowie kreatora (nic nie wygenerowano).
- Kandydaci na kernel (GitHub): Marvellousteam/android_kernel_htc_msm7227 @kk (2.6.39.4, 2014-07, board-chacha.c),
  Where-No-Man-Has-Gone-Before/kernel_htc_chacha-CHS (HTCdev 2.6.35.10), benjamingwynn|beta1993/android_kernel_htc_msm7227 (2.6.35.13).
  Źródła działającego 2.6.36.1-Simplicit-ULTiMATE (flux) — nie znalezione.

## 2026-10-25 — Etap 3 (zmieniony): Alpine armhf zamiast pmOS
Decyzja użytkownika: czysty Alpine armhf v3.24 na SD, kernel kandydat 1, karta 8 GB (SDHC, widoczna jako mmcblk0, pusta — sektor 0 zerowy).
- Kernel: src/kernel-msm7227 = Marvellousteam/android_kernel_htc_msm7227 @kk (028b0793), lokalna gałąź chacha-alpine.
  **Faktycznie baza 2.6.35** (brak evict_inode w fs.h), Makefile podaje fałszywe 2.6.39.4. Działający „2.6.36.1” to zapewne ten sam trik.
  .config prawie identyczny z działającym kernelem (różnice: LOCALVERSION, governor, XZ vs LZMA, yaffs).
- Toolchain: AOSP prebuilts arm-eabi-4.7 (tag android-4.4.4_r1) w tools/arm-eabi-4.7 — ta sama wersja gcc co kernel flux.
- Poprawki: kernel/timeconst.pl (defined(@val) vs nowy Perl), YAFFS_FS off (nie kompiluje się przez fałszywą wersję, niepotrzebny).
- Konfig: +DEVTMPFS(+MOUNT), VT, VT_CONSOLE, FRAMEBUFFER_CONSOLE, FONT_6x11/8x16; -VGA_CONSOLE, -ANDROID_PARANOID_NETWORK, -LOCALVERSION_AUTO.
  Zapis: src/chacha-alpine.config, łatka: src/chacha-alpine.patch.
- **Problem: busybox-static z Alpine (v6KZ, musl) → Segmentation fault na obecnym kernelu** (test z tmpfs /mnt/obb, bez zapisu na partycje).
  Diagnoza: musl dla v6K czyta TLS przez `mrc p15,0,rX,c13,c0,3` (TPIDRURO); kernel bez CONFIG_HAS_TLS_REG
  nie ustawia tego rejestru (tylko kuser 0xffff0ff0). ARM1136 r1p5 ma TPIDRURO (od r1p0).
  Poprawka: arch/arm/mm/Kconfig HAS_TLS_REG `default y if ... || CPU_32v6K`. Do zweryfikowania na sprzęcie.
- USB: HTC composite, RNDIS przez `echo 1 > /sys/class/usb_composite/rndis/enable` (nie configfs).
- msm_fb: fillrect/copyarea/imageblit wołają msmfb_update → fbcon powinien się odświeżać.
- Obraz testowy: initramfs/out/boot-stage3.img (2.66 MB; zImage 1.94 MB + initramfs 0.7 MB),
  base 0x12c00000, page 2048, cmdline `console=tty0 no_console_suspend=1 androidboot.hardware=chacha`.
  init: RNDIS 172.16.42.1, udhcpd → host 172.16.42.2, telnetd, sh na tty1.
- Narzędzia hosta doinstalowane: fastboot, mkbootimg, tmux, kpartx.

## 2026-10-25 — test 1: boot-stage3.img (fastboot boot, za zgodą)
- `fastboot boot` przy S-ON: DZIAŁA (OKAY, Booting).
- Wynik: biały ekran HTC, brak re-enumeracji USB (kernel nie doszedł do sterowników), Power nie resetuje → wyjęta bateria.
  Telefon wstał normalnie do CM (flash nietknięty). /proc/last_kmsg brak (bateria skasowała RAM).
- Hipotezy: (1) dekompresor XZ (backport w drzewie; działający kernel używa LZMA), (2) HAS_TLS_REG.
- Przygotowane: out/boot-A-lzma.img (XZ→LZMA, reszta bez zmian; sha 13c233a8…),
  out/boot-B-lzma-notls.img (A bez HAS_TLS_REG; sha cb9e9804…).

## 2026-10-25 — test 2: boot-A-lzma.img
- Wysłany o ~23:27 (komenda przerwana przez użytkownika w trakcie czekania, ale fastboot boot zdążył się wykonać).
- Wynik identyczny jak test 1: biały ekran HTC, brak re-enumeracji USB, bootloader nie odpowiada.
- Wniosek: XZ nie jest (jedyną) przyczyną. Następny: B (bez HAS_TLS_REG).
- Uwaga proceduralna: dzielić na krótkie komendy (osobno reboot bootloader / fastboot boot / obserwacja).

## 2026-10-26 — bisekcja zawieszeń (fastboot boot, RAM)
| obraz | DEVTMPFS | TLS | VT/fbcon | ramdisk | wynik |
|---|---|---|---|---|---|
| stage3/A/B/C1/E/E-hyb/H-hyb | tak | różnie | różnie | różne | wisi przed USB |
| D (running .config, bez yaffs) | nie | nie | nie | CM | adb OK |
| I (D + TLS + PARANOID off) | nie | tak | nie | hybryda | adb OK, **musl busybox działa** |
| J (I + VT/fbcon) console=tty0 | nie | tak | tak | v2 | **obraz na ekranie**, stop po diagchar_init |
- **CONFIG_DEVTMPFS zawiesza ten kernel** → wyłączone; /dev = tmpfs + mdev -s.
- HAS_TLS_REG potwierdzone na ARM1136 r1p5: Alpine busybox (musl, v6KZ) działa przez adb shell.
- J: fbcon 60x20 (8x16) działa; printk→fbcon z kontekstu z wyłączonymi IRQ (SMD) prawdopodobnie zakleszcza msmfb_update.
  Test J2: ten sam obraz z console=null (printk nie na ekran).
- Ramdisk hybrydowy (CM ramdisk + Alpine busybox jako /system/bin/sh) = świetne narzędzie diagnostyczne (adb shell bez /system).
- Wyjście z działającego testu: `adb reboot bootloader` (bez wyjmowania baterii). Zawieszenie → bateria.
- Dmesg z I: tests/dmesg-I-hybrid.txt

## 2026-10-26 — Etap 3 ZAKOŃCZONY: boot do initramfs + shell po USB
- J2 (console=null): bootuje, fbcon OK, RNDIS OK (host: rndis_host, enx<losowy MAC>), ping 0.3 ms.
  console=null rozwiązało zakleszczenie printk→fbcon (hipoteza z SMD potwierdzona pośrednio).
- Alpine busybox-static NIE ma telnetd/udhcpd (są w busybox-extras) → shell przez `nc -lk -s 172.16.42.1 -p 23 -e /bin/sh`.
  Host: `ip addr add 172.16.42.2/24 dev enx...` ręcznie (MAC RNDIS losowy przy każdym boocie — do ustalenia na stałe).
- J3: root shell przez nc działa; `reboot -f` zdalnie → telefon wraca do CM (bez baterii).
- Klawiatura: litery działają na tty1; brak warstwy Fn/Alt (symbole, cyfry) → Etap 4 keymap.
- fbcon 60x20 (FONT_8x16 domyślnie); karta SD widoczna jako /dev/mmcblk0. RAM: 7.7 MB zajęte / 425 MB.
- Szum w dmesg: `[DISP]msmfb: pan_update in state(1)` przy każdym update — do wyciszenia.
- Artefakty: src/chacha-alpine.config (kernel J), src/chacha-alpine.patch (timeconst + HAS_TLS_REG),
  initramfs/out/boot-stage3-working.img (sha b753e508…), initramfs/root/init, initramfs/out/initramfs.list.
- Dmesg: tests/dmesg-J3.txt

## 2026-10-26 — Alpine 3.24 z karty SD DZIAŁA
- Zapis karty przez CM USB Mass Storage → zamrożenie CM w trakcie mkfs (porzucone).
- Zamiast tego: obraz ext4 512 MB budowany na hoście (images/rootfs.ext4, cechy zgodne z 2.6.35:
  bez metadata_csum/64bit/orphan_file, z uninit_bg), wysłany gzip przez RNDIS: host `cat > /dev/tcp/...`,
  telefon `nc -l | gunzip | dd of=/dev/mmcblk0p1`. SHA256 z karty zgodne. Potem resize2fs online → 7.1 GB.
- Pułapki: (1) NetworkManager zdejmuje statyczny IP z enx* → `nmcli dev set <if> managed no`;
  (2) host netcat-traditional urywa strumień → bash /dev/tcp; (3) busybox nc w telefonie: `nc -q 2` kończy sesję przed długim wynikiem;
  (4) `grep chacha.debug /proc/cmdline` łapał `board_chacha.debug_uart=0` z HBOOT → słowo kluczowe zmienione na `rdshell`.
  (5) grep -v "\[" ukrywał sshd ([listener] w tytule procesu OpenSSH 10).
- inittab: pierwsza linia startuje ratunkowy shell `nc -lk -s 172.16.42.1 -p 23` (w tle) przed OpenRC.
- OpenRC: pierwszy start długi (gendepends na 600 MHz). Usługi OK: devfs(tmpfs), mdev, networking (usb0 172.16.42.1),
  consolefont (ter-112n), syslog, sshd (tylko klucz id_ed25519), getty tty1/tty2.
- SSH z hosta: `ssh root@172.16.42.1` działa. RAM: 12 MB zajęte.
- Obraz bootowalny (nadal tylko fastboot boot, NIE wgrany): initramfs/out/boot-alpine-sd.img

## 2026-10-26 — Etap 4: keymap + WiFi
### Keymap (config/gen-keymap.py → config/chacha.map → /etc/keymaps/chacha.map, usługa loadkeys w boot)
- FN (56) = AltGr: symbole z nadruku (z chacha-keypad.kcm CM). Shift+FN: [ ] { } < > | \ ~ ` ^ (na Q A W S E D T G U J K).
- SYM (183, KEY_F13) = Control; FN+SYM = 0. Zielona słuchawka (231) = Esc. Czerwona (107) = Alt. Facebook (184) = |.
- FN+strzałki = PgUp/PgDn/Home/End; Shift+góra/dół i Vol± = przewijanie; FN+DEL = Delete.
### Entropia
- Kernel bez getrandom(): OpenSSL 3 czeka na /dev/random; entropy_avail spadało do ~34 → sshd wisiał na „banner exchange”.
  Naprawa: haveged (boot). Paczki armhf przenoszone: apk.static fetch na hoście → scp / nc.
### WiFi (bcm4329_204 z naszego drzewa, firmware i NVRAM jak w CM)
- insmod OK, wlan0 MAC z /proc/calibration; ale iwlist scan → 0 AP.
- STOP/START przez iwpriv → SDIO reset fail (-110) — NIE używać; rmmod/insmod czyści stan.
- **Skan działa dopiero po starcie wpa_supplicant -D wext** (wysyła disassoc → „disassoc client!”) → 3 AP.
- Brak AP na kanałach 12/13 (prawdopodobnie domyślny kraj firmware = US) — do rozwiązania (COUNTRY przez SIOCSIWPRIV).
- Brak 5 GHz (NVRAM aa5g=0).
- Trwałe: /etc/modules (bcm4329), /etc/modprobe.d/bcm4329.conf, /etc/conf.d/wpa_supplicant (-D wext), wlan0 dhcp, wpa_supplicant w boot.
  Skrypt: config/wifi-setup.sh. Busybox depmod wymaga pustego modules.builtin.

## 2026-10-26 — „zrób wszystko”: NAT, autologin, MAC, msmfb, kraj WiFi, touchkeys, backup
- Internet przez USB: config/host-usb-nat.sh (iptables MASQUERADE + DOCKER-USER, nietrwałe). Telefon: usb0 post-up default via 172.16.42.2 metric 500.
- Stały MAC RNDIS: cmdline `u_ether.host_addr=02:c4:a0:00:00:01 u_ether.dev_addr=02:c4:a0:00:00:02` → host enx02c4a0000001,
  profil NM „chacha-usb” (172.16.42.2/24, never-default) — host konfiguruje się sam.
- msmfb: DLOG miał na sztywno `| SUSPEND_RESUME` → łatka w msm_fb.c (src/chacha-alpine.patch).
- Autologin tty1: `getty -n -l /usr/local/bin/autologin` (exec login -f root).
- Zegar: telefon startuje w 1980 → TLS w apk pada. RTC bez /dev/rtc (Android /dev/alarm) → swclock (boot) + ntpd.
  Stock ntpd: „Could not set iab” (OpenRC ambient capabilities, brak w 2.6.35) → własna usługa ntpd-legacy.
- Stock wpa_supplicant: `checkpath /var/run/...` → „Symbolic link loop” na 2.6.35 → własna usługa wpa_supplicant-chacha (czeka na wlan0).
- Kod kraju: tools-src/wlpriv.c (SIOCSIWPRIV „COUNTRY PL”) + usługa wifi-country (ponawia, bo przy skanie driver odmawia).
  Po PL widać kanał 12.
- Touchkeys: tools-src/chacha-touchkeys.c (cy8c MT protocol A → uinput), usługa chacha-touchkeys, /etc/conf.d (domyślnie Ctrl+B, Tab, Esc, Ctrl+R).
  Próg Y=700 (surowe) wyliczony z virtualkeys — NIEZWERYFIKOWANY dotykiem.
- build-base zainstalowane na telefonie (gcc 15 na ARMv6 kompiluje małe programy w ~1 s).
- Overlay plików systemowych: config/rootfs-overlay/. Backup całego rootfs z karty: backup/sd/rootfs-20261026.tar.gz (91 MB).
- Obraz finalny (test RAM OK): initramfs/out/boot-alpine-final.img (= boot-M).

## 2026-10-26 — szybki start (10 min → 55 s)
- Przyczyna: `openrc sysinit` przelicza deptree przy każdym boocie (/run to tmpfs); depend() usługi sshd woła `sshd -G`,
  które blokuje się na /dev/random (entropia ~40, haveged startował dopiero w boot) → minuty.
- Naprawa: haveged z inittab przed `openrc sysinit` (usunięty z runlevelu boot).
- Dodatkowo: initramfs ustawia zegar z mtime /var/lib/misc/openrc-shutdowntime (swclock) przed switch_root;
  crond co 15 min dotyka ten plik (na wypadek odcięcia zasilania).
- reboot-bootloader (tools-src/reboot-bootloader.c, RESTART2 "bootloader"): z Alpine prosto do fastboot — DZIAŁA.
- Obraz finalny: initramfs/out/boot-alpine-final.img (= boot-N), test RAM: SSH po 55 s, wszystkie usługi OK.

## 2026-10-26 — WGRANE na partycję boot (za zgodą użytkownika)
- `fastboot flash boot initramfs/out/boot-alpine-final.img` → OKAY. Odczyt mtd2ro (cat | head -c 2779136): sha256 7074eefd… = obraz.
- Telefon sam startuje do Alpine z flasha: SSH po 61 s. CM już się nie uruchamia (system CM na NAND nietknięty).
- Wejście do fastboot z Alpine: `reboot-bootloader`. Powrót do CM: `fastboot flash boot backup/boot.img` (sha d09d95cc…).
- busybox dd na /dev/mtdNro → EINVAL; czytać przez cat.

## 2026-10-26 — repozytorium git
- Odtwarzalna ścieżka: scripts/{fetch,build-kernel,build-bootimg,build-rootfs,write-sd}.sh, instrukcja w README.md.
- Przetestowane od zera (czysty work/): fetch + kernel + bootimg OK (łatka nakłada się na świeży klon @028b0793).
- Poza repo (.gitignore): kopie partycji, backup SD, firmware Broadcom, zrzuty z IMEI/numerem seryjnym/MAC, katalogi robocze.
- Keymap generowany przy budowie rootfs (config/gen-keymap.py), nie trzymany w repo.
- Nowa karta: partycja przez fdisk z initramfs (busybox), zapis obrazu przez RNDIS (write-sd.sh),
  powiększenie ext4 przy pierwszym starcie (/etc/local.d/resize-rootfs.start).

## 2026-10-26 — kolory w konsoli
- msm_fb (HTC) wypełniał pseudo palette na sztywno: PP[0]=czarny, PP[1..15]=biały, brak fb_setcolreg → konsola monochromatyczna.
- Łatka: msmfb_setcolreg (układ pikseli jak w msmfb_set_par: 32 bpp R|G<<8|B<<16, 16 bpp RGB565) + domyślna paleta VGA w setup_fb_info.
- Test RAM (fastboot boot): 16 kolorów OK (paleta VGA w zrzucie /dev/fb0). Tło tylko 8 kolorów (ograniczenie konsoli Linuksa).
- Brak 256/truecolor: przybliżanie 38;5;n w konsoli dopiero od kernela 3.16.
- Zrzut ekranu: `head -c 614400 /dev/fb0` (480x320x4, pan 0,0) → PIL frombytes RGBA. Przy wygaszonej konsoli fb jest czarny.

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
