# Alpine Linux na HTC ChaCha (A810e) jako terminal SSH

Minimalny Alpine Linux 3.24 (armhf) na telefonie HTC ChaCha: konsola na
framebufferze (80×26 znaków), sprzętowa klawiatura QWERTY z własnym keymapem,
WiFi (bcm4329, wext), `openssh-client`, `tmux`, autologin. Bez GUI, dotyku
ekranu, audio i telefonii. Zamiast postmarketOS (który w 2026 porzucił armhf)
używany jest czysty Alpine z własnym kernelem i initramfs.

Pełny dziennik prac, decyzji i ślepych uliczek: [NOTES.md](NOTES.md).
Wyniki rekonesansu telefonu: [recon/SUMMARY.md](recon/SUMMARY.md).

## Co działa

| | |
|---|---|
| Kernel | 2.6.39.4-chacha-alpine (faktycznie baza HTC 2.6.35), gcc 4.7 z AOSP |
| Start | z partycji boot (NAND) → initramfs → `switch_root` na kartę SD (ext4), ~60 s |
| Ekran | fbcon 480×320, Terminus 6×12 → 80×26 znaków |
| Klawiatura | keymap `chacha.map` (FN = symbole, SYM = Ctrl, zielona słuchawka = Esc) |
| Klawisze dotykowe | Home/Menu/Back/Search pod ekranem → Ctrl+B / Tab / Esc / Ctrl+R |
| WiFi | bcm4329 2.4 GHz, `wpa_supplicant -D wext`, kod kraju PL (kanały 1–13) |
| USB | RNDIS, telefon `172.16.42.1`, laptop `172.16.42.2`, SSH (klucz) + NAT |
| Brak | 5 GHz (brak anteny), dotyk ekranu, audio, telefonia, RTC (zegar przez ntpd/swclock) |

## Ostrzeżenia

- Wgranie obrazu na partycję boot zastępuje kernel Androida; CyanogenMod przestaje
  startować (do czasu przywrócenia kopii `boot.img`). System Androida na NAND zostaje.
- Wymagany odblokowany bootloader (HTCdev unlock, `*** UNLOCKED ***`). Testowane
  na `CHACHA PVT SHIP S-ON RL`, HBOOT 1.10.0000; S-ON wystarcza.
- Karta SD (partycja 1) jest w całości nadpisywana.
- Firmware WiFi (Broadcom) nie jest w repozytorium — kopiuje się go z własnego telefonu.

## Struktura repozytorium

```
README.md                 ta instrukcja
NOTES.md                  dziennik prac
recon/                    wyniki rekonesansu (bez danych identyfikujących)
kernel/                   łatka i .config dla kernela Marvellousteam/android_kernel_htc_msm7227@kk
initramfs/                /init i lista plików initramfs
config/gen-keymap.py      generator keymapu konsoli (→ /etc/keymaps/chacha.map)
config/rootfs-overlay/    pliki nakładane na rootfs (usługi OpenRC, inittab, sieć, …)
config/host-usb-nat.sh    NAT na laptopie: internet dla telefonu przez USB
tools-src/                wlpriv, chacha-touchkeys, reboot-bootloader (C)
scripts/                  fetch / build-kernel / build-bootimg / build-rootfs / write-sd
```

Katalogi `work/`, `out/`, `backup/` i surowe zrzuty z telefonu są w `.gitignore`.

---

## Krok 0. Host

Debian/Ubuntu (testowane na Debianie 13, x86_64):

```sh
sudo apt install adb fastboot mkbootimg git curl gcc make perl python3 \
    e2fsprogs qemu-user-static binfmt-support netcat-openbsd
```

`qemu-user-static` jest potrzebny do kompilacji narzędzi w chroocie armhf
(`/proc/sys/fs/binfmt_misc/qemu-arm` musi istnieć).

## Krok 1. Rekonesans i firmware (telefon z CM, root, adb)

Stary `adbd` nie ma `exec-out`, a `adb shell` zamienia LF→CRLF, więc pliki
binarne przenosi się przez base64. `su -c` wymaga cytowania całej komendy.

```sh
adb devices
mkdir -p recon/firmware
pull() { adb shell "su -c 'cat $1 | busybox base64'" | tr -d '\r' | base64 -d > "$2"; }
pull /system/etc/firmware/fw_bcm4329.bin       recon/firmware/fw_bcm4329.bin
pull /system/etc/firmware/fw_bcm4329_apsta.bin recon/firmware/fw_bcm4329_apsta.bin
adb shell "su -c 'busybox sha256sum /system/etc/firmware/fw_bcm4329*.bin'"
sha256sum recon/firmware/fw_bcm4329*.bin       # muszą się zgadzać
```

NVRAM WiFi to `/proc/calibration` (dane z HBOOT, z adresem MAC) — kernel
udostępnia go także pod Alpine, kopiować nie trzeba.

## Krok 2. Kopia partycji boot i recovery (tylko odczyt)

```sh
mkdir -p backup
dump() { adb shell "su -c 'cat /dev/mtd/$1 | busybox base64'" | tr -d '\r' | base64 -d > "backup/$2"; }
dump mtd2ro boot.img        # 3407872 B
dump mtd1ro recovery.img    # 5242880 B
adb shell "su -c 'cat /dev/mtd/mtd2ro | busybox sha256sum; cat /dev/mtd/mtd1ro | busybox sha256sum'"
sha256sum backup/boot.img backup/recovery.img   # muszą się zgadzać
```

Bez zgodnych sum nie przechodź dalej.

## Krok 3. Bootloader

```sh
adb reboot bootloader       # Vol Down + Power bywa zawodne
fastboot getvar all         # security: on, version-bootloader: 1.10.0000
fastboot reboot
```

Ekran HBOOT musi pokazywać `*** UNLOCKED ***`.

## Krok 4. Kernel i obraz boot

```sh
scripts/fetch.sh            # toolchain arm-eabi-4.7, źródła kernela, busybox-static, apk.static
scripts/build-kernel.sh     # → out/zImage, out/bcm4329.ko, out/gen_init_cpio
scripts/build-bootimg.sh    # → out/boot-alpine.img (≤ 3407872 B)
```

Łatka `kernel/chacha-alpine.patch`:
- `HAS_TLS_REG` dla ARMv6K — musl z Alpine (v6KZ) czyta TLS z rejestru TPIDRURO;
  bez tego każdy program z Alpine kończy się segfaultem (ARM1136 r1p5 ma ten rejestr),
- wyciszenie `msmfb: pan_update` w dmesg,
- `timeconst.pl` dla nowego Perla.

Ważne opcje w `kernel/chacha-alpine.config`: **`DEVTMPFS` wyłączone** (zawiesza
ten kernel na starcie), VT + `FRAMEBUFFER_CONSOLE`, `ANDROID_PARANOID_NETWORK`
wyłączone. Parametry obrazu (base `0x12c00000`, page 2048, cmdline z
`console=null`) są w `scripts/env.sh`.

## Krok 5. Rootfs

```sh
sudo scripts/build-rootfs.sh   # → out/rootfs.ext4 (512 MB) i out/rootfs.ext4.gz
```

Instaluje pakiety Alpine armhf, nakłada `config/rootfs-overlay`, generuje keymap,
kompiluje narzędzia z `tools-src/` w chroocie (qemu), kopiuje moduł i firmware,
konfiguruje usługi. Do `/root/.ssh/authorized_keys` trafia
`~/.ssh/id_ed25519.pub` (zmienna `AUTHORIZED_KEYS`).

## Krok 6. Uruchomienie z RAM i zapis karty SD

Na tym etapie nic nie jest flashowane — `fastboot boot` ładuje obraz tylko do RAM.

1. Włóż kartę microSD (≥ 1 GB). Uruchom obraz:

   ```sh
   adb reboot bootloader
   fastboot boot out/boot-alpine.img
   ```

   Bez rootfs na karcie initramfs zostaje w trybie diagnostycznym: RNDIS
   `172.16.42.1` i shell `nc 172.16.42.1 23` (bez telnetd — busybox z Alpine go nie ma).

2. Adres na laptopie. Profil NetworkManagera dla stałego MAC telefonu (raz):

   ```sh
   sudo nmcli con add type ethernet con-name chacha-usb ifname '*' \
       802-3-ethernet.mac-address 02:C4:A0:00:00:01 \
       ipv4.method manual ipv4.addresses 172.16.42.2/24 ipv4.never-default yes \
       ipv6.method disabled
   ping 172.16.42.1
   ```

   Bez tego profilu NetworkManager zdejmuje ręcznie nadany adres z `enx…`.

3. Partycja na karcie (tylko nowa karta; **kasuje kartę**):

   ```sh
   echo 'printf "o\nn\np\n1\n2048\n\nw\n" | fdisk /dev/mmcblk0; mdev -s; ls -l /dev/mmcblk0p1' | nc -q 5 172.16.42.1 23
   ```

4. Zapis obrazu przez sieć USB z weryfikacją SHA256:

   ```sh
   scripts/write-sd.sh
   ```

   (Zapis przez USB Mass Storage z CM zamrażał telefon — dlatego przez RNDIS.)

5. Restart i start Alpine z karty (wciąż z RAM):

   ```sh
   echo 'reboot -f' | nc -q 2 172.16.42.1 23
   adb wait-for-device; adb reboot bootloader
   fastboot boot out/boot-alpine.img
   ssh root@172.16.42.1        # po ~60 s
   ```

   Przy pierwszym starcie `/etc/local.d/resize-rootfs.start` powiększa ext4 na całą partycję.

## Krok 7. Wgranie na partycję boot

Dopiero gdy krok 6 działa:

```sh
ssh root@172.16.42.1 reboot-bootloader      # z Alpine prosto do fastboot
fastboot flash boot out/boot-alpine.img
fastboot reboot
```

Weryfikacja zapisu (na telefonie; `dd` na mtd daje EINVAL, stąd `cat`):

```sh
ssh root@172.16.42.1 "cat /dev/mtd2ro | head -c $(stat -c %s out/boot-alpine.img) | sha256sum"
cat out/boot-alpine.img.sha256
```

Powrót do CyanogenModa:

```sh
ssh root@172.16.42.1 reboot-bootloader
fastboot flash boot backup/boot.img
fastboot reboot
```

---

## Użytkowanie

### Klawiatura

| Klawisz | Działanie |
|---|---|
| FN + klawisz | znak z nadruku: cyfry 1–9, `( ) ! £ $ % & @ / _ - + = € ' " :` |
| FN + SYM / `,` / `?` / `.` / Tab | `0` / `#` / `;` / `:` / `*` |
| Shift+FN + Q A W S E D | `[ ] { } < >` |
| Shift+FN + T G U J K | `\| \ ~ ` ^` |
| SYM | Ctrl |
| zielona słuchawka | Esc |
| czerwona słuchawka | Alt (Meta) |
| Facebook | `\|` |
| FN + strzałki | PgUp / PgDn / Home / End |
| Shift + ↑/↓, Vol± | przewijanie konsoli |
| FN + DEL | Delete |

Zmiany: `config/gen-keymap.py` → `python3 config/gen-keymap.py > chacha.map`,
skopiuj do `/etc/keymaps/` i `loadkeys /etc/keymaps/chacha.map`.

### Klawisze dotykowe

`/etc/conf.d/chacha-touchkeys` — kody klawiszy Linuksa, `+` łączy w kombinację
(183 = SYM/Ctrl, 231 = Esc, 15 = Tab). `chacha-touchkeys -d …` pokazuje surowe
współrzędne dotyku (próg paska klawiszy: `-y 700`).

### chacha-config

`chacha-config` (konsola lub SSH) to menu do konfiguracji telefonu. Pozycje wybiera się literami, bo cyfry wymagają FN; Enter cofa.

- `w`: skanowanie WiFi, wybór sieci, hasło i połączenie. Sieć jest zapisywana w
  `wpa_supplicant.conf`, a potem odnawiana dzierżawa DHCP. `1` służy do sieci ukrytej.
  Obsługiwane są sieci WPA/WPA2-PSK i otwarte.
- `z`: lista zapisanych sieci z możliwością ich usuwania. `s`: status połączenia.
- `f`: czcionka terminala. Do wyboru jest Terminus (zwykły lub pogrubiony, ISO 8859-2,
  od 6x12 do 16x32) albo kilka klasycznych czcionek; przy każdej widać, ile mieści się
  kolumn i wierszy. Wybrana czcionka od razu pojawia się na tty1. Jeśli nie potwierdzisz
  jej `t` w ciągu 20 s, wraca poprzednia. Wybór trafia do `/etc/conf.d/consolefont`.

### WiFi ręcznie

```sh
wpa_passphrase "SSID" >> /etc/wpa_supplicant/wpa_supplicant.conf   # wpisz hasło
rc-service wpa_supplicant-chacha restart
wpa_cli -i wlan0 status
```

Tylko 2.4 GHz. Kraj: `/etc/conf.d/wifi-country` (`wlpriv wlan0 COUNTRY PL`).
Sterownik zaczyna skanować dopiero po starcie `wpa_supplicant`; nie używaj
`iwpriv wlan0 STOP/START` (psuje SDIO do przeładowania modułu).

### Internet przez USB

Na laptopie (po każdym restarcie laptopa): `sudo config/host-usb-nat.sh`.
Telefon ma trasę domyślną przez `172.16.42.2` z metryką 500 (WiFi ma pierwszeństwo).

### Ratunek

- Shell bez SSH: `nc 172.16.42.1 23` (startuje przed OpenRC).
- Do fastboot z Alpine: `reboot-bootloader`.
- Zawieszony kernel: odłączenie zasilania (Power nie resetuje).

## Najważniejsze pułapki (szczegóły w NOTES.md)

1. postmarketOS usunął armhf (VI 2026) → czysty Alpine.
2. Źródła „2.6.39.4” to w rzeczywistości 2.6.35 z podbitym numerem wersji.
3. musl/TLS → `HAS_TLS_REG`; `DEVTMPFS` → zawieszenie; printk na fbcon → zakleszczenie (`console=null`).
4. Brak `getrandom()` → `haveged` przed OpenRC, inaczej sshd i start wiszą minutami.
5. OpenRC na 2.6.35: `checkpath` przez symlink `/var/run` i ambient capabilities nie działają
   → własne usługi `wpa_supplicant-chacha` i `ntpd-legacy`; `rc_cgroup_mode="legacy"`.
6. Brak RTC → initramfs ustawia zegar z pliku swclock, potem ntpd.
7. Wyszukiwanie słowa w `/proc/cmdline`: HBOOT dodaje `board_chacha.debug_uart=…`.
