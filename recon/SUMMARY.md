# HTC ChaCha (A810e) — podsumowanie rekonesansu (Etap 1)

Data: 2026-10-25. Wszystko zebrane przez `adb shell su -c` tylko w trybie odczytu
(bez plików tymczasowych na telefonie; binaria przez `busybox base64` w potoku,
bo stary adbd nie ma `exec-out`, a `adb shell` zamienia LF→CRLF).

## System i kernel
| | |
|---|---|
| ROM | CyanogenMod 11 (4.4.4 KTU84Q) UNOFFICIAL, autor „flux”, 2014-07-21 |
| Kernel | **2.6.36.1-Simplicit-ULTiMATE** #21 PREEMPT, gcc 4.7 — *nie* stock 2.6.35 |
| SoC | MSM7227, ARMv6 (ARM1136 rev5, `6TEJ`), VFP, `CONFIG_MACH_CHACHA` |
| RAM widziana przez Linux | 428 MB (`Memory: 425128k available`) |
| HBOOT | 1.10.0000, CID `HTC__032`, MID `PH0611000`, baseband 7.51.35.19 |
| Kompresja kernela | `CONFIG_KERNEL_LZMA=y` |
| `CONFIG_PHYS_OFFSET` | `0x00200000` (ważne dla offsetów w `deviceinfo`) |
| Wbudowany CMDLINE | `mem=75M console=ttyMSM2,115200n8` (nie wymuszony; HBOOT podaje własny) |
| `/proc/config.gz` | jest → `kernel.config` (2217 linii) |
| Moduły | tylko `bcm4329.ko` |

Cmdline od HBOOT: `... androidboot.emmc=false androidboot.pagesize=4096 ... console=null androidboot.hardware=chacha`
→ **page size 4096**.

## Pamięć masowa / partycje (raw NAND, MTD — brak eMMC)
NAND Samsung (ID `0x6600BCEC`), sterownik `msm_nand`, system plików yaffs2.

| mtd | nazwa | rozmiar | uwagi |
|---|---|---|---|
| mtd0 | misc | 1 MB | |
| mtd1 | recovery | 5 MB (0x500000) | |
| mtd2 | **boot** | **3.25 MB (0x340000)** | mały! |
| mtd3 | system | 260 MB | yaffs2 |
| mtd4 | cache | 35 MB | yaffs2 |
| mtd5 | userdata | 150 MB | yaffs2 |
| mtd6 | devlog | 10 MB | |

Erase size 256 KiB. Karta SD: `mmc1` (slot SD). `mmc0` = SDIO dla WiFi.

## Framebuffer
- `/dev/fb0`, nazwa `msmfb302_0`, panel **MDDI** Renesas (`mddi_renesas_0000_1531`), MDP 3.02
- 480×320, 32 bpp, stride 1920, `virtual_size 480,640` (podwójny bufor, panning `pan: 0,320`)
- Sterownik: `CONFIG_FB_MSM` + `FB_MSM_LEGACY_MDP` + `FB_EARLYSUSPEND` (Android early-suspend!)
- Podświetlenie: LED class `lcd-backlight`
- 480×320 z czcionką 6×12 → 80×26 znaków (Terminus ma `ter-112n` = 6×12 → dokładnie cel).

## Klawiatura
- Urządzenie `chacha-keypad` (`/dev/input/event4`), sterownik HTC `gpio_event`
  (`GPIO Matrix Keypad Driver` + `GPIO Input Driver`), `CONFIG_INPUT_GPIO=y`
- Zwraca standardowe kody `KEY_*` (46 klawiszy): litery A–Z, BACKSPACE, TAB, ENTER,
  LEFTSHIFT, LEFTALT, SPACE, COMMA, DOT, strzałki, END, VOL±, POWER,
  oraz `KEY_F13` (183), `KEY_F14` (184), `KEY_QUESTION` (214), `KEY_SEND` (231).
- **Brak fizycznych klawiszy Ctrl, Esc i rzędu cyfr** — cyfry/symbole są na warstwie Alt
  (patrz `keylayout/chacha-keypad.kcm`). Dla SSH/tmux trzeba będzie zmapować np.
  F13/F14/SEND/QUESTION na Ctrl/Esc — do ustalenia z fizycznymi napisami na klawiszach.
- Inne wejścia (niepotrzebne): `h2w headset`, `cy8c-touchscreen`, `compass`, czujniki, „projector”.
- `CONFIG_MAGIC_SYSRQ=y`, `INPUT_KEYRESET` (reset kombinacją klawiszy).

## WiFi
- Chip **Broadcom BCM4329** na SDIO (`mmc0`), sterownik **`bcm4329.ko` (stary dhd, out-of-tree)**
- API: **wext** — `CONFIG_WIRELESS_EXT=y`, `# CONFIG_CFG80211 is not set` → `wpa_supplicant -D wext`
- Firmware: `/system/etc/firmware/fw_bcm4329.bin` (+ `_apsta`), NVRAM: **`/proc/calibration`**
  (generowany z danych kalibracyjnych przekazywanych przez HBOOT, zawiera MAC `macaddr=...`)
- Zasilanie przez board file (`chacha_wifi_power`, `chacha_wifi_set_carddetect`)
- Skopiowane do `firmware/`: `fw_bcm4329.bin`, `fw_bcm4329_apsta.bin`, `bcm4329.ko`,
  `nvram_calibration.bin` (838 B), `bcm4329.hcd` (BT), `yamato_*.fw` (GPU).
  Wszystkie SHA256 zgodne z telefonem (`firmware_sha256_phone.txt`).
  Pliku `/data/misc/wifi/wpa_supplicant.conf` (Twoje hasła WiFi) celowo NIE kopiowałem.

## USB
`USB_GADGET_MSM_72K` + Android composite (`USB_ANDROID_ADB`, `_RNDIS`, `_ECM`,
`_MASS_STORAGE`, `_SERIAL`). Brak configfs — debug przez USB wymaga obsługi
starego `android_usb` w initramfs pmOS (nie standardowej ścieżki configfs).

## Kluczowe opcje kernela vs. wymagania pmOS
| Opcja | Stan | Potrzebne do |
|---|---|---|
| `DEVTMPFS` | **brak** | pmOS initramfs / udev — trzeba włączyć |
| `VT`, `VT_CONSOLE`, `FRAMEBUFFER_CONSOLE` | **brak** | fbcon — trzeba włączyć |
| `CFG80211` | brak | niepotrzebne (wext) |
| `BLK_DEV_INITRD`, `RD_GZIP` | jest | initramfs |
| `TMPFS`, `EXT4_FS`, `SIGNALFD`, `EPOLL`, `INOTIFY_USER`, `UNIX98_PTYS` | jest | |
| `IKCONFIG_PROC` | jest | |
| `AUTOFS4`, `POSIX_MQUEUE`, `FHANDLE` | brak | systemd-only, nas nie dotyczy (OpenRC) |

## Wnioski / ryzyka
1. **Partycja boot ma tylko 3.25 MB.** Kernel LZMA + initramfs pmOS musi się zmieścić.
   Recovery ma 5 MB. Bardzo prawdopodobne: kernel+minimalny initramfs w boot,
   rootfs pmOS na **karcie SD (ext4)** — NAND/yaffs2 nie nadaje się na rootfs pmOS.
2. Kernel 2.6.36 jest bardzo stary względem współczesnego Alpine/musl/OpenRC.
   musl i busybox powinny działać, ale niektóre programy mogą wymagać nowszych
   syscalli — ryzyko do sprawdzenia w Etapie 3/4. Alpine `armhf` = ARMv6+VFP → pasuje.
3. Najlepszy kandydat na źródła kernela: ten sam, który działa teraz
   (2.6.36.1 „Simplicit-ULTiMATE”, flux, CM11) — wiemy, że WiFi/FB/klawiatura działają.
   Konfig startowy mamy z `/proc/config.gz`.
4. `fastboot` **nie jest zainstalowany na hoście** (tylko adb) — do doinstalowania.
5. Bootloader: **S-ON, *** UNLOCKED *** (HTCdev)**, HBOOT 1.10.0000. `fastboot flash boot` powinien działać; `fastboot boot` do przetestowania.
