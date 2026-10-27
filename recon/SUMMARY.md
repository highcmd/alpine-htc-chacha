# HTC ChaCha (A810e) — reconnaissance summary (Stage 1)

Date: 2026-10-25. Everything collected via `adb shell su -c` in read-only mode
(no temporary files on the phone; binaries via `busybox base64` in a pipe,
because the old adbd has no `exec-out`, and `adb shell` converts LF→CRLF).

## System and kernel
| | |
|---|---|
| ROM | CyanogenMod 11 (4.4.4 KTU84Q) UNOFFICIAL, by "flux", 2014-07-21 |
| Kernel | **2.6.36.1-Simplicit-ULTiMATE** #21 PREEMPT, gcc 4.7 — *not* stock 2.6.35 |
| SoC | MSM7227, ARMv6 (ARM1136 rev5, `6TEJ`), VFP, `CONFIG_MACH_CHACHA` |
| RAM seen by Linux | 428 MB (`Memory: 425128k available`) |
| HBOOT | 1.10.0000, CID `HTC__032`, MID `PH0611000`, baseband 7.51.35.19 |
| Kernel compression | `CONFIG_KERNEL_LZMA=y` |
| `CONFIG_PHYS_OFFSET` | `0x00200000` (important for the offsets in `deviceinfo`) |
| Built-in CMDLINE | `mem=75M console=ttyMSM2,115200n8` (not forced; HBOOT passes its own) |
| `/proc/config.gz` | present → `kernel.config` (2217 lines) |
| Modules | only `bcm4329.ko` |

Cmdline from HBOOT: `... androidboot.emmc=false androidboot.pagesize=4096 ... console=null androidboot.hardware=chacha`
→ **page size 4096**.

## Mass storage / partitions (raw NAND, MTD — no eMMC)
Samsung NAND (ID `0x6600BCEC`), driver `msm_nand`, file system yaffs2.

| mtd | name | size | notes |
|---|---|---|---|
| mtd0 | misc | 1 MB | |
| mtd1 | recovery | 5 MB (0x500000) | |
| mtd2 | **boot** | **3.25 MB (0x340000)** | small! |
| mtd3 | system | 260 MB | yaffs2 |
| mtd4 | cache | 35 MB | yaffs2 |
| mtd5 | userdata | 150 MB | yaffs2 |
| mtd6 | devlog | 10 MB | |

Erase size 256 KiB. SD card: `mmc1` (SD slot). `mmc0` = SDIO for WiFi.

## Framebuffer
- `/dev/fb0`, name `msmfb302_0`, **MDDI** Renesas panel (`mddi_renesas_0000_1531`), MDP 3.02
- 480×320, 32 bpp, stride 1920, `virtual_size 480,640` (double buffer, panning `pan: 0,320`)
- Driver: `CONFIG_FB_MSM` + `FB_MSM_LEGACY_MDP` + `FB_EARLYSUSPEND` (Android early-suspend!)
- Backlight: LED class `lcd-backlight`
- 480×320 with a 6×12 font → 80×26 characters (Terminus has `ter-112n` = 6×12 → exactly the target).

## Keyboard
- Device `chacha-keypad` (`/dev/input/event4`), HTC driver `gpio_event`
  (`GPIO Matrix Keypad Driver` + `GPIO Input Driver`), `CONFIG_INPUT_GPIO=y`
- Returns standard `KEY_*` codes (46 keys): letters A–Z, BACKSPACE, TAB, ENTER,
  LEFTSHIFT, LEFTALT, SPACE, COMMA, DOT, arrows, END, VOL±, POWER,
  and `KEY_F13` (183), `KEY_F14` (184), `KEY_QUESTION` (214), `KEY_SEND` (231).
- **No physical Ctrl or Esc keys and no digit row** — digits/symbols are on the Alt layer
  (see `keylayout/chacha-keypad.kcm`). For SSH/tmux we will need to map e.g.
  F13/F14/SEND/QUESTION to Ctrl/Esc — to be decided from the physical labels on the keys.
- Other inputs (not needed): `h2w headset`, `cy8c-touchscreen`, `compass`, sensors, "projector".
- `CONFIG_MAGIC_SYSRQ=y`, `INPUT_KEYRESET` (reset by key combination).

## WiFi
- **Broadcom BCM4329** chip on SDIO (`mmc0`), driver **`bcm4329.ko` (old dhd, out-of-tree)**
- API: **wext** — `CONFIG_WIRELESS_EXT=y`, `# CONFIG_CFG80211 is not set` → `wpa_supplicant -D wext`
- Firmware: `/system/etc/firmware/fw_bcm4329.bin` (+ `_apsta`), NVRAM: **`/proc/calibration`**
  (generated from calibration data passed by HBOOT, contains the MAC `macaddr=...`)
- Power via the board file (`chacha_wifi_power`, `chacha_wifi_set_carddetect`)
- Copied to `firmware/`: `fw_bcm4329.bin`, `fw_bcm4329_apsta.bin`, `bcm4329.ko`,
  `nvram_calibration.bin` (838 B), `bcm4329.hcd` (BT), `yamato_*.fw` (GPU).
  All SHA256 match the phone (`firmware_sha256_phone.txt`).
  The file `/data/misc/wifi/wpa_supplicant.conf` (the user's WiFi passwords) was deliberately NOT copied.

## USB
`USB_GADGET_MSM_72K` + Android composite (`USB_ANDROID_ADB`, `_RNDIS`, `_ECM`,
`_MASS_STORAGE`, `_SERIAL`). No configfs — debugging over USB requires support for
the old `android_usb` in the pmOS initramfs (not the standard configfs path).

## Key kernel options vs. pmOS requirements
| Option | State | Needed for |
|---|---|---|
| `DEVTMPFS` | **missing** | pmOS initramfs / udev — must be enabled |
| `VT`, `VT_CONSOLE`, `FRAMEBUFFER_CONSOLE` | **missing** | fbcon — must be enabled |
| `CFG80211` | missing | not needed (wext) |
| `BLK_DEV_INITRD`, `RD_GZIP` | present | initramfs |
| `TMPFS`, `EXT4_FS`, `SIGNALFD`, `EPOLL`, `INOTIFY_USER`, `UNIX98_PTYS` | present | |
| `IKCONFIG_PROC` | present | |
| `AUTOFS4`, `POSIX_MQUEUE`, `FHANDLE` | missing | systemd-only, does not apply to us (OpenRC) |

## Conclusions / risks
1. **The boot partition is only 3.25 MB.** LZMA kernel + pmOS initramfs must fit.
   Recovery is 5 MB. Very likely: kernel+minimal initramfs in boot,
   pmOS rootfs on the **SD card (ext4)** — NAND/yaffs2 is not suitable for a pmOS rootfs.
2. Kernel 2.6.36 is very old compared to modern Alpine/musl/OpenRC.
   musl and busybox should work, but some programs may need newer
   syscalls — a risk to check in Stage 3/4. Alpine `armhf` = ARMv6+VFP → fits.
3. Best candidate for kernel sources: the same one that runs now
   (2.6.36.1 "Simplicit-ULTiMATE", flux, CM11) — we know WiFi/FB/keyboard work.
   We have the starting config from `/proc/config.gz`.
4. `fastboot` **is not installed on the host** (only adb) — to be installed.
5. Bootloader: **S-ON, *** UNLOCKED *** (HTCdev)**, HBOOT 1.10.0000. `fastboot flash boot` should work; `fastboot boot` to be tested.
