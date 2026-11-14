# nethunter-kmods — Kali NetHunter kernel features for Nothing Phone (3)

*[Українською →](README.uk.md)*

A Magisk / KernelSU module that adds the kernel-level features Kali NetHunter needs to the **Nothing Phone (3)** — **without replacing the kernel**. External USB Wi-Fi (monitor mode + injection), USB Bluetooth, the phone's **built-in** Bluetooth and Wi-Fi monitor mode (plus packet injection on the built-in Wi-Fi through an optional second module), USB-serial, USB-net and CAN are delivered as loadable kernel modules plus a few userspace helpers, all built against the stock Google GKI kernel.

> **Device:** Nothing Phone (3) (codename *Metroid*, platform `sun`)
> **Firmware this build targets:** Nothing OS C5.0 (`ab15756704`), kernel `6.6.127-android15-8-gf0987337fa35-ab15756704-4k`
> After a Nothing OS update that changes the kernel build, the modules must be rebuilt — see [Building from source](#building-from-source).

---

## Why modules instead of a custom kernel

This is an Android 15+ GKI kernel with `CONFIG_MODULE_SIG_PROTECT=y`. Google's own modules in `system_dlkm` (bluetooth, can, usbnet, zram…) are signed with the key of that exact Google build. A kernel signed with any other key would treat them as unsigned, and unsigned modules are forbidden from using "protected" symbols (`kernel/module/main.c`) — so Bluetooth, CAN, USB networking and zram would stop loading. Shipping the NetHunter drivers as **modules that load into the unmodified Google kernel** avoids this entirely.

Compatibility is proven against real artifacts, not by trial and error:

| Check | Result |
|---|---|
| Kernel inside the stock `boot.img` vs Google CI build `ab15756704` | byte-identical |
| Device kernel config (`/proc/config.gz`) reproduced from ACK source `@f0987337fa35` | identical (except compiler version string) |
| KMI: CRC of all 9535 exported vmlinux + GKI-module symbols after adding the drivers | **0 differences** vs Google's `Module.symvers` |
| Qualcomm Wi-Fi stack (`cfg80211.ko`, `mac80211.ko` from the device `vendor_dlkm`) | CRCs match: 111/111 and 74/74 |
| Simulated GKI load rules (`resolve_symbol()`, protected exports, duplicates) per module | **62/62 pass** |

Key finding: `cfg80211`/`mac80211` on the device are Qualcomm's, not Google's. Their headers match ACK but the config differs — `CONFIG_NL80211_TESTMODE=y` (otherwise `wiphy_new_nm`/`ieee80211_alloc_hw_nm` CRCs mismatch and drivers refuse to load) and `CONFIG_MAC80211_RC_MINSTREL` is **off** (Qualcomm's mac80211 has no rate-control algorithm, so USB adapters won't start). `minstrel_ht` is therefore built as a standalone module and made the default at load time. Reference: [NothingOSS/android_kernel_msm-6.6_nothing_sm8735](https://github.com/NothingOSS/android_kernel_msm-6.6_nothing_sm8735), branch `sm8735/b/mr`, `arch/arm64/configs/vendor/sun_perf.config`.

---

## Feature status

Legend: ✅ verified live on the device · 🟡 built & loads, not exercised with hardware · ❌ not possible on the stock kernel.

### Works

| Feature | Status | Notes |
|---|---|---|
| 62 driver modules load into the stock kernel | ✅ | `loaded=62 failed=0`, no kernel errors, autoloads on boot |
| Built-in Bluetooth as Linux `hci0` (`nh-bt` + `nh-btbridge`) | ✅ | classic inquiry + LE scan; works under SELinux Enforcing |
| Built-in Wi-Fi **monitor mode** (`nh-wlan`) | ✅ | capture on 2.4/5 GHz, channel switching; receive-only with the stock driver |
| Built-in Wi-Fi **packet injection** (`nh-wlan-driver`) | ✅ | the Wi-Fi driver rebuilt and swapped in automatically after boot, **still no custom kernel**: `aireplay-ng --test` 30/30 on 2.4 and 5 GHz, deauth + WPA2 handshake capture on 5 GHz, steady monitor RX — see [wlan-inject](wlan-inject/README.md) |
| External USB Wi-Fi: Atheros AR9271 (tested with TP-Link TL-WN722N **v1**) | ✅ | `ath9k_htc` loads on plug-in, `htc_9271` firmware loads, `wlan1` appears; monitor mode, `aireplay-ng --test` 30/30 on my AP; deauth + full WPA2 4-way handshake captured on my own network |
| USB Arsenal: HID keyboard+mouse, mass storage, ACM, ECM | ✅ | gadget functions enumerate on a host PC (stock-kernel gadget) |
| NetHunter 32-bit busybox fix (`nh-fix-nethunter`) | ✅ | 64-bit device needs a 64-bit busybox; applied every boot |
| NetHunter `su: unknown user root` fix | ✅ | custom commands with `su` now run from NetHunter Terminal |
| NetHunter wlan0 monitor custom commands | ✅ | rewritten to call `nh-wlan` |

### Built, not yet hardware-tested (🟡)

Other external USB Wi-Fi adapters (every chipset below except AR9271), USB Bluetooth dongles, USB-serial/UART adapters, CAN adapters, USB-Ethernet. Drivers and 77 firmware files are in the module; they just haven't been exercised with the physical hardware yet.

**USB Wi-Fi adapters covered:**

| Chipset | Driver | Common adapters |
|---|---|---|
| Atheros AR9271 / AR7010 | `ath9k_htc` | Alfa AWUS036NHA, TP-Link TL-WN722N **v1** — ✅ *tested* |
| Ralink RT3070/3572/5370/5572 | `rt2800usb` | Alfa AWUS036NH/NEH, Panda PAU05/09 |
| Ralink RT2501/2573 | `rt73usb`, `rt2500usb` | older Alfa/Edimax |
| Realtek RTL8187L | `rtl8187` | Alfa AWUS036H |
| MediaTek MT7610U / MT7612U | `mt76x0u` / `mt76x2u` | Alfa AWUS036ACHM / AWUS036ACM |
| MediaTek MT7921AU | `mt7921u` | Alfa AWUS036AXML (Wi-Fi 6E) |
| MediaTek MT7601U / MT7663U | `mt7601u` / `mt7663u` | cheap MT7601 dongles |
| Realtek RTL8812AU/8814AU/8188EUS | `8812au` / `8814au` / `8188eu` (out-of-tree) | Alfa AWUS036ACH / AWUS1900, TL-WN722N v2/v3 |
| Realtek RTL8822BU/8821CU/8723DU, 8xxx | `rtw88_*u`, `rtl8xxxu` | TP-Link Archer T3U/T2U |

**Recommended adapter if you don't have one:** Alfa **AWUS036ACM** (MT7612U) or **AWUS036ACHM** (MT7610U) — in-kernel drivers, stable monitor + injection, 2.4/5 GHz. For 2.4 GHz and maximum tool compatibility, **AWUS036NHA** (AR9271).

**With an external adapter:** work on `wlan1` and leave `wlan0` alone — skip `airmon-ng check kill`, it can take down the phone's own Wi-Fi. While `airodump-ng` holds the channel, run `aireplay-ng` with `--ignore-negative-one`; otherwise it waits for a beacon on "channel -1" and sends nothing.

### Not possible on the stock kernel (❌)

| Feature | Reason | Workaround |
|---|---|---|
| PostgreSQL for the Metasploit DB (`CONFIG_SYSVIPC`) | enabling it changes `task_struct` → breaks the KMI and every vendor module | msfconsole without a DB, or DB on another host |
| CAN ISO-TP / J1939 in-kernel | `can_proto_register` etc. are protected in GKI `can.ko` | userspace `python-can-isotp` / `j1939` over `can_raw` |
| BNEP (Bluetooth PAN) | `bt_sock_register` outside the KMI | — |
| USB-net `rndis_host`, `qmi_wwan`, `cdc_mbim`, `dm9601`, `mcs7830` | need protected GKI symbols | `r8152`/`asix`/`ax88179`/`cdc_ether`/`smsc95xx` work |
| `carl9170`, `zd1211rw`, `bpa10x` | rare old hardware needing non-KMI symbols | — |

---

## Install

> ⚠️ Unlocking the bootloader **erases all data**. Back up first. After unlocking, Play Integrity (strong) will fail — some banking apps and Google Wallet may stop working.

**You need:**

1. **The flashable module** `nethunter-kmods-metroid-ab15756704.zip` from [Releases](../../releases).
2. **Your stock `init_boot.img`** for *your exact* firmware build, to root with Magisk and to roll back. Nothing's factory images are mirrored by the community [nothing_archive](https://github.com/spike0en/nothing_archive) (pick the build matching `adb shell getprop ro.build.fingerprint`). This repo does **not** redistribute Nothing's proprietary images.
3. [Magisk](https://github.com/topjohnwu/Magisk/releases) (KernelSU in LKM mode also works).

**1 — Unlock the bootloader.** Enable *OEM unlocking* and *USB debugging* in Developer options, then:

```bash
adb reboot bootloader && fastboot flashing unlock
```

Confirm on the device (this wipes it), finish setup, re-enable USB debugging.

**2 — Root with Magisk.** Patch your stock `init_boot.img` in the Magisk app (*Install → Select and Patch a File*), pull the patched image and flash it:

```bash
adb reboot bootloader
fastboot flash init_boot magisk_patched-XXXXX.img
fastboot reboot
```

Rollback if the phone won't boot: `fastboot flash init_boot <stock init_boot.img>`.

**3 — Flash the module.** Push the zip, then Magisk → *Modules → Install from storage* → the zip → *Reboot*.

Everything loads automatically after the reboot: the kernel modules, and the built-in Wi-Fi injection driver ~15 s later. To check:

```bash
adb shell su -c "nh-kmod status"          # expect: all modules [+], autoload: on
adb shell su -c "nh-wlan-driver status"   # expect: driver: injection build (monitor + injection), swap on boot: on
```

Safety nets: a marker is written before each driver load and each Wi-Fi swap; if the phone reboots mid-operation, the next boot skips it (`autoload: off` / `swap on boot: off`) and keeps the stock state, so a bad build can't cause a boot loop. Re-enable with `nh-kmod autoload on` / `nh-wlan-driver autoswap on`. Emergency exit: Magisk safe mode (hold volume-down while booting), or reflash the stock `init_boot.img`.

**4 — Kali NetHunter.** Install **NetHunter Generic ARM64 (Full)** for Magisk from [kali.org](https://www.kali.org/get-kali/#kali-mobile) (there is no Phone (3)-specific image; the generic one is correct), reboot, then set up the Kali chroot in the app. The NetHunter fixes below are applied automatically when this module is installed/booted.


**Built-in Wi-Fi injection** is part of this one module and on by default: after boot it swaps the stock Wi-Fi driver **in memory** for a rebuilt one — same driver version, plus monitor-mode fixes and frame injection; the stock file in `vendor_dlkm` is untouched and comes back on any reboot without the module. It is bound to this exact firmware build (kernel, vendor build and stock driver are checked) and is skipped after a Nothing OS update until the driver is rebuilt. Turn it off with `nh-wlan-driver autoswap off`. Test results, limits and safety nets: [wlan-inject/README.md](wlan-inject/README.md).

---

## Helper commands

All are in `/system/bin` after a reboot (run by full path before the first reboot).

| Command | What it does |
|---|---|
| `nh-kmod load \| unload \| status \| autoload on\|off` | load/unload the driver set, show state |
| `nh-wlan monitor [chan] \| managed \| channel N \| status` | built-in Wi-Fi monitor mode (defaults to channel 6 — **required**, monitor is dead without a channel) |
| `nh-wlan-driver swap \| restore \| status \| autoswap on\|off` | swap the built-in Wi-Fi driver for the injection build, or back to stock (swaps automatically on boot) |
| `nh-bt start \| stop \| status \| install-bluebinder` | built-in Bluetooth as `hci0` via the AIDL bridge |
| `nh-fix-nethunter boot \| cache \| commands \| su \| check` | the NetHunter fixes below |

While Wi-Fi/BT monitor is active, Android Wi-Fi/Bluetooth is off (the HAL serves one client); the helpers save and restore your settings. For LE use `btmgmt find -l` / `bluetoothctl scan on`, not `hcitool lescan`. In Kali run `tcpdump -Z root`.

## NetHunter fixes (automatic)

The module repairs three NetHunter issues specific to this 64-bit, AIDL-only, Android-15+ device. Originals are backed up under `/data/adb/nethunter-kmods-fix/`; only stock NetHunter artifacts (or our own previous ones) are touched — anything you edited by hand is left alone.

- **32-bit busybox** — NetHunter's Magisk module ships a 32-bit `busybox_nh`; this phone is pure arm64 so it won't run, and after a reboot NetHunter shows Kali as "Not yet installed". `nh-fix-nethunter` swaps in a 64-bit busybox on every boot.
- **`su: unknown user root`** — NetHunter's `post-fs-data.sh` links `su → busybox` before Magisk mounts its own `su`, and NetHunter Terminal drops `/product/bin` from `PATH`. The module repoints `su` to Magisk's `su` and stops the busybox link from returning. (The `PATH` bug is in the app and must be reported upstream.)
- **Built-in Bluetooth** — NetHunter's `bluebinder` only speaks the legacy HIDL `@1.0` HAL; this device only has the AIDL `IBluetoothHci`. `nh-btbridge` is a from-scratch AIDL-HAL ↔ `/dev/vhci` bridge; the Kali `bluebinder` is replaced by a wrapper that launches it.
- **wlan0 monitor custom commands** — the stock "Start/Stop wlan0 monitor mode" commands don't set a channel or wait for Wi-Fi to stop (dead monitor on this chip); rewritten to call `nh-wlan`.

---

## Building from source

Requires Docker (x86_64 image runs under emulation on Apple Silicon) and `adb`. The build fetches Google's exact kernel source/artifacts and verifies the KMI itself.

```bash
# 1. stock inputs (not redistributed here — produced from your device + Google CI)
adb shell 'zcat /proc/config.gz' > stock/device.config
#    extract vendor_dlkm.img from your firmware into fw/logical/vendor_dlkm (fsck.erofs --extract)

# 2. third-party drivers and device link-libraries (not stored in this repo)
tools/fetch-oot.sh          # clones morrownr/8812au, 8814au, aircrack-ng/rtl8188eus (pinned)
tools/fetch-devlibs.sh      # adb pull of libbinder_ndk.so etc. for linking nh-btbridge

# 3. full reproducible build + all compatibility checks + packaged zip
tools/build-all.sh 15756704 f0987337fa351d7e303b071df533fd4c1c194687
#                  ^ab build  ^kernel/common commit (from `adb shell uname -r`)
```

After a Nothing OS update, rerun step 1 with the new `vendor_dlkm`/config and `tools/build-all.sh <new ab> <new sha>`.

The built-in Wi-Fi driver is built separately (it needs Nothing's kernel source, not Google's): [wlan-inject/README.md](wlan-inject/README.md).

### Layout

```
module/nethunter-kmods/   Magisk/KernelSU module: helper scripts (the .ko/firmware are built, not committed)
wlan-inject/              how the built-in Wi-Fi driver is built: upstream delta, stock-parity edits, injection patches, checks
btbridge/nh-btbridge.c    AIDL Bluetooth HAL ↔ /dev/vhci bridge  (+ build.sh)
patches/                  5 minimal driver patches, one file each, each explained
config/                   kernel config fragment: what is added, and what is impossible and why
oot/                      minstrel_ht module + our glue for the out-of-tree Realtek drivers
tools/                    build-all.sh, fetch-*.sh, check_gki_access.py (GKI load simulator), kocrc.py, add-wlan-inject.sh
docker/                   clang-18 arm64 build image
```

---

## Uninstall

Magisk → *Modules* → remove `nethunter-kmods` (and NetHunter) → Reboot, then reflash the stock `init_boot.img`. To relock (wipes data, stock firmware only): `fastboot flashing lock`.

## Licensing

- Scripts, patches, `nh-btbridge.c` and the minstrel wrapper are **GPL-2.0** (kernel-derived) — see [LICENSE](LICENSE).
- This repo does **not** contain: Nothing's proprietary partition images, Google's kernel binaries, the device's system libraries, or any firmware blobs. The build fetches these from their sources; `fetch-devlibs.sh` pulls link-time libraries from your own device.
- Release zips bundle firmware from [linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware) under its respective vendor licenses (see that project's `WHENCE`).
- `wlan-inject/patches/` modifies Qualcomm's qcacld-3.0 / qca-wifi-host-cmn / fw-api sources and keeps their ISC license; the monitor/injection work is by [Loukious](https://github.com/Loukious/vendor_qcom_opensource_wlan), the version delta comes from CodeLinaro. Origins per file: [wlan-inject/README.md](wlan-inject/README.md#patches).
- The out-of-tree Wi-Fi drivers are separate projects: [morrownr/8812au-20210820](https://github.com/morrownr/8812au-20210820), [morrownr/8814au](https://github.com/morrownr/8814au), [aircrack-ng/rtl8188eus](https://github.com/aircrack-ng/rtl8188eus).

## Disclaimer

Provided as-is, for research and for authorized testing of systems and networks you own or have permission to test. Unlocking the bootloader and modifying the kernel environment can brick a device, void warranty and break security guarantees; you do this at your own risk. The authors are not responsible for any damage or misuse.
