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
| Simulated GKI load rules (`resolve_symbol()`, protected exports, duplicates) per module | **69/69 pass** |
| The same for the NetHunter kernel (variant B), with CRCs: `gki/`, the stock part, and Google modules on top of our parent copies | **114/114 pass** |

Key finding: `cfg80211`/`mac80211` on the device are Qualcomm's, not Google's. Their headers match ACK but the config differs — `CONFIG_NL80211_TESTMODE=y` (otherwise `wiphy_new_nm`/`ieee80211_alloc_hw_nm` CRCs mismatch and drivers refuse to load) and `CONFIG_MAC80211_RC_MINSTREL` is **off** (Qualcomm's mac80211 has no rate-control algorithm, so USB adapters won't start). `minstrel_ht` is therefore built as a standalone module and made the default at load time. Reference: [NothingOSS/android_kernel_msm-6.6_nothing_sm8735](https://github.com/NothingOSS/android_kernel_msm-6.6_nothing_sm8735), branch `sm8735/b/mr`, `arch/arm64/configs/vendor/sun_perf.config`.

**Optional variant B — the NetHunter kernel.** What a module on the stock kernel cannot add (System V IPC for PostgreSQL and the Metasploit database, CAN ISO-TP/J1939, BNEP, USB RNDIS/QMI/MBIM, RNDIS gadget, old USB Wi-Fi AR9170/ZD1211/Broadcom 4320) comes from an own boot kernel: the same Google kernel, built from the same ACK commit and the stock config, with a KMI identical to Google's build. The module stays the same and turns these features on by itself when that kernel runs — see [Variant B](#variant-b-the-nethunter-kernel-optional).

**At a glance — module only vs. module + the NetHunter kernel:**

| Capability | Module only (stock GKI kernel) | + NetHunter kernel (variant B) |
|---|---|---|
| Built-in Wi-Fi **monitor + packet injection**, and a **monitor alongside a live Wi-Fi link or SoftAP** (STA/AP + monitor coexistence) | ✅ | ✅ |
| 69 driver modules: Bluetooth (`hci0`), USB HID / Arsenal (BadUSB), USB-serial, USB-net, most USB Wi-Fi chipsets, SocketCAN basics (`can327`, `f81604`, `mcba_usb`) | ✅ | ✅ |
| PostgreSQL + Metasploit database (System V IPC) | ❌ | ✅ |
| CAN **ISO-TP / J1939** in-kernel, `tc` filters on CAN ids | ❌ | ✅ |
| NFS client + server | ❌ | ✅ |
| BNEP (Bluetooth PAN), PN533 NFC, BPA10x, USB CAN (Kvaser/EMS/ESD/UCAN), host RNDIS/QMI/MBIM/DM9601/MCS7830, RNDIS gadget, legacy USB Wi-Fi (AR9170 / ZD1211 / Broadcom 4320) | ❌ | 🟡 load |

The module is the **same file** either way — it simply enables the kernel-only rows by itself when the NetHunter kernel is running. Per-feature detail is in [Feature status](#feature-status); the kernel, what it adds and how to flash it are in [Variant B](#variant-b-the-nethunter-kernel-optional). Both the module and the pre-built kernel `boot.img` ship together in each [release](../../releases).

---

## Feature status

Legend: ✅ verified live on the device · 🟡 built & loads, not exercised with hardware · ❌ not possible on the stock kernel.

### Works

| Feature | Status | Notes |
|---|---|---|
| 69 driver modules load into the stock kernel | ✅ | `loaded=69 failed=0` on boot (including the new `zd1201`, `rtl8192cu`, `ath6kl`), no kernel errors |
| Built-in Bluetooth as Linux `hci0` (`nh-bt` + `nh-btbridge`) | ✅ | classic inquiry + LE scan; works under SELinux Enforcing |
| Built-in Wi-Fi **monitor mode** (`nh-wlan`) | ✅ | capture on 2.4/5 GHz, channel switching; receive-only with the stock driver |
| Built-in Wi-Fi **packet injection** (`nh-wlan-driver`) | ✅ | the Wi-Fi driver rebuilt and swapped in automatically after boot, **still no custom kernel**: `aireplay-ng --test` 30/30 on 2.4 and 5 GHz, deauth + WPA2 handshake capture on 5 GHz, steady monitor RX — see [wlan-inject](wlan-inject/README.md) |
| Built-in Wi-Fi **STA/AP + monitor coexistence** (`nh-wlan coex`) | ✅ | a dedicated `mon0` captures (and injects) **alongside a connected Wi-Fi link or a SoftAP**, on that link's channel, while the link stays up — no need to drop the connection. Verified live on WCN7750: stable capture (rx climbing past 300k frames), STA ping 0% loss throughout, real 802.11 radiotap frames, and the same beside a hostapd SoftAP. Channel-locked to the link (no hopping); for a full-band sweep use plain monitor mode |
| External USB Wi-Fi: Atheros AR9271 (tested with TP-Link TL-WN722N **v1**) | ✅ | `ath9k_htc` loads on plug-in, `htc_9271` firmware loads, `wlan1` appears; monitor mode, `aireplay-ng --test` 30/30 on my AP; deauth + full WPA2 4-way handshake captured on my own network |
| USB keyboard and mouse `nh-hid` (`/dev/hidg0`, `/dev/hidg1`, android-keyboard-gadget descriptors) | ✅ | the laptop sees both, key presses and mouse movement arrive; they stay through USB mode changes; `--app <package>` gives access to that app only (other uids are refused) |
| USB Arsenal: HID keyboard+mouse, mass storage, ACM, ECM | ✅ | gadget functions enumerate on a host PC (stock-kernel gadget) |
| NetHunter 32-bit busybox fix (`nh-fix-nethunter`) | ✅ | 64-bit device needs a 64-bit busybox; applied every boot |
| NetHunter `su: unknown user root` fix | ✅ | custom commands with `su` now run from NetHunter Terminal |
| NetHunter wlan0 monitor custom commands | ✅ | rewritten to call `nh-wlan` |

### Built, not yet hardware-tested (🟡)

Other external USB Wi-Fi adapters (every chipset below except AR9271), USB Bluetooth dongles, USB-serial/UART adapters, CAN adapters, USB-Ethernet. Drivers and 92 firmware files are in the module; they just haven't been exercised with the physical hardware yet.

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
| Realtek RTL8188CUS/8192CU | `rtl8xxxu` (default) or `rtl8192cu` | RTL8188CUS nano dongles (Edimax EW-7811Un) |
| Atheros AR6004 (USB) | `ath6kl_usb` | FullMAC: client only, no monitor mode |
| ZyDAS ZD1201 | `zd1201` | old 802.11b dongles; bring your own firmware (below) |
| Atheros AR9170, ZyDAS ZD1211/ZD1211B, Broadcom 4320 (RNDIS) | `carl9170`, `zd1211rw`, `rndis_wlan` | **NetHunter kernel only** ([variant B](#variant-b-the-nethunter-kernel-optional)) |

**Recommended adapter if you don't have one:** Alfa **AWUS036ACM** (MT7612U) or **AWUS036ACHM** (MT7610U) — in-kernel drivers, stable monitor + injection, 2.4/5 GHz. For 2.4 GHz and maximum tool compatibility, **AWUS036NHA** (AR9271).

**RTL8188CUS/8192CU:** `rtl8xxxu` and `rtl8192cu` share 60 USB IDs, and an adapter goes to whichever driver loaded first: for those 60 that is `rtl8xxxu`, as before `rtl8192cu` was added. Another 12 IDs only `rtl8192cu` knows — such adapters go straight to it. To move an adapter to `rtl8192cu`, find its interface first (looks like `1-1:1.0`):

```bash
ls /sys/bus/usb/drivers/rtl8xxxu/ | grep :
```

```bash
echo 1-1:1.0 > /sys/bus/usb/drivers/rtl8xxxu/unbind; echo 1-1:1.0 > /sys/bus/usb/drivers/rtl8192cu/bind
```

**ZD1201:** its firmware is not in linux-firmware and the project archive states no license, so the module does not ship it. Get `zd1201-0.14-fw.tar.gz` from [linux-lc100020](https://sourceforge.net/projects/linux-lc100020/files/) and put `zd1201.fw` (and `zd1201-ap.fw` for access-point mode) into `/data/adb/modules/nethunter-kmods/firmware/`.

**With an external adapter:** work on `wlan1` and leave `wlan0` alone — skip `airmon-ng check kill`, it can take down the phone's own Wi-Fi. While `airodump-ng` holds the channel, run `aireplay-ng` with `--ignore-negative-one`; otherwise it waits for a beacon on "channel -1" and sends nothing.

### Not possible on the stock kernel (❌) — covered by the NetHunter kernel

| Feature | Reason on the stock kernel | Stock workaround | With the NetHunter kernel ([variant B](#variant-b-the-nethunter-kernel-optional)) |
|---|---|---|---|
| PostgreSQL for the Metasploit DB (`CONFIG_SYSVIPC`) | off in the stock kernel; simply enabling it changes `task_struct` → breaks the KMI and every vendor module | msfconsole without a DB, or DB on another host | ✅ built in, same KMI (the SysV fields sit in `task_struct` reserved slots); PostgreSQL 18 and Metasploit with a DB verified live |
| CAN ISO-TP / J1939 in-kernel | `can_proto_register` etc. are protected in GKI `can.ko` | userspace `python-can-isotp` / `j1939` over `can_raw` | ✅ verified live on `vcan0` |
| BNEP (Bluetooth PAN) | `bt_sock_register` outside the KMI | — | 🟡 loads, not exercised with hardware |
| USB-net `rndis_host`, `qmi_wwan`, `cdc_mbim`, `dm9601`, `mcs7830` | need protected GKI symbols | `r8152`/`asix`/`ax88179`/`cdc_ether`/`smsc95xx` work | 🟡 load, not exercised with hardware |
| RNDIS gadget (BadUSB networking) | not enabled in the stock config | ECM gadget | 🟡 built in, not exercised |
| BT adapter `bpa10x`, NFC PN533 (USB), USB CAN Kvaser/EMS/ESD/UCAN | not enabled in the stock config | — | 🟡 load, not exercised with hardware |
| NFS client and server | not enabled in the stock config | — | ✅ `nfs`/`nfs4`/`nfsd` in the kernel (Kali needs `nfs-common` / `nfs-kernel-server`) |
| USB Wi-Fi `carl9170` (AR9170), `zd1211rw` (ZD1211), `rndis_wlan` (Broadcom 4320) | need USB and `usbnet` functions Google trims from the kernel and `usbnet.ko` (outside the KMI) | other chipsets from the table above | 🟡 load by themselves when the NetHunter kernel boots, not exercised with hardware |

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

## Variant B: the NetHunter kernel (optional)

An own boot kernel — **the same Google GKI kernel**, built from the same ACK commit (`f0987337fa35`) with the stock config, plus everything from the official NetHunter kernel-option list that can be added without changing the KMI (as modules, and System V IPC built in with a patch that keeps the `task_struct` layout; the comparison is in [kernel-recipe](kernel-recipe/README.uk.md#звірка-з-офіційним-списком-nethunter-106-опцій)). `uname -r` is the stock one and the KMI is identical to Google's build (all 9175 exports, same CRCs), so Qualcomm vendor modules and Google's `system_dlkm` modules load as usual. Verified live (without flashing, via `fastboot boot`): Wi-Fi with injection, LTE on both SIMs, every stock module; ISO-TP and J1939 functionally. How it is built and checked: [kernel-recipe/README.uk.md](kernel-recipe/README.uk.md).

**Only for firmware C5.0-260924-2115** (kernel `ab15756704`).

| Adds | State |
|---|---|
| System V IPC: PostgreSQL → Metasploit database, `ipcmk`/`ipcs` | ✅ verified: PostgreSQL 18, `msfconsole` + `db_connect`, ~97k processes using semaphores without errors |
| CAN ISO-TP / J1939, tc filter on CAN ids | ✅ verified on `vcan0` |
| NFS client and server | ✅ in the kernel (mounting needs `nfs-common`/`nfs-kernel-server` in Kali) |
| Netlink socket diagnostics (`ss -A netlink`), `rmmod -f` | ✅ |
| USB CAN adapters Kvaser / EMS / ESD / UCAN | 🟡 load |
| Bluetooth PAN (BNEP), BPA10x adapter | 🟡 load |
| USB-net host RNDIS / QMI / MBIM / DM9601 / MCS7830 | 🟡 load |
| NFC readers PN533/PN532 (USB) | 🟡 load |
| RNDIS gadget (BadUSB networking) | 🟡 built in |
| USB Wi-Fi AR9170 (`carl9170`), ZD1211 (`zd1211rw`), Broadcom 4320 (`rndis_wlan`) | 🟡 load |

**First, without flashing.** The kernel boots from RAM once; any reboot brings the stock one back:

```bash
adb reboot bootloader
fastboot boot nethunter-boot.img
```

```bash
adb shell su -c "nh-gki status"
```

Needs a recent `fastboot` (Android SDK platform-tools); the old 31.x on macOS does not see the phone in fastboot mode.

**Permanently** (verified: the phone boots this kernel by itself, also across normal reboots; still, try the RAM boot first). Flash to the current slot; keep your firmware's stock `boot.img` at hand to go back:

```bash
fastboot getvar current-slot
```

```bash
fastboot flash boot_b nethunter-boot.img
```

Back to stock: `fastboot flash boot_b boot.img` (use your current slot). Magisk lives in `init_boot` and stays. Restore the stock `boot.img` before a Nothing OS update.

**Same module** (take the module and `nethunter-boot.img` from the same release — the module recognises the kernel by its exact `/proc/version`; the kernel with System V IPC needs module v8+): on the stock kernel these features stay idle; on the NetHunter kernel `nh-gki` loads them after boot, together with our own `can.ko`/`cdc_ncm.ko`/`nfc.ko`/`usbnet.ko` in place of Google's (those have the exports J1939, MBIM, PN533 and `rndis_wlan` need trimmed away; if ours fails to load, Google's is put back). For the old USB Wi-Fi drivers the NetHunter kernel also keeps a few exports Google trims ([extra-exports.txt](kernel-recipe/extra-exports.txt)): new exports only, the KMI does not change. Disable: `nh-gki autoload off`.

Trade-off: this kernel has `CONFIG_MODULE_SIG_PROTECT` off — otherwise Google's `system_dlkm` modules, signed with a key foreign to this kernel, would lose access to protected symbols. So Google's modules load as "unsigned" (the kernel gets taint `E`) and GKI symbol protection is not enforced.

System V IPC rests on a small patch ([kernel-recipe/patches](kernel-recipe/patches/)): the `sysvsem`/`sysvshm` fields live in the `ANDROID_KABI_RESERVE(6..8)` spare slots of `task_struct`, so its size, every field offset and the export CRCs stay the same as Google's (Halium uses the same technique). These slots are free at this ACK commit, and no Qualcomm or Google module touches them through `current` (accesses through other `task_struct` pointers are not fully ruled out statically); a module that did write there would crash the kernel on process exit — the test ran ~100k processes without errors. Android formally requires `SYSVIPC` off (`android-base.config`), but that does not affect booting.

---

## Helper commands

All are in `/system/bin` after a reboot (run by full path before the first reboot).

| Command | What it does |
|---|---|
| `nh-kmod load \| unload \| status \| autoload on\|off` | load/unload the driver set, show state |
| `nh-wlan monitor [chan] \| managed \| channel N \| status` | built-in Wi-Fi monitor mode (defaults to channel 6 — **required**, monitor is dead without a channel) |
| `nh-wlan-driver swap \| restore \| status \| autoswap on\|off` | swap the built-in Wi-Fi driver for the injection build, or back to stock (swaps automatically on boot) |
| `nh-gki load \| unload \| status \| autoload on\|off` | NetHunter-kernel features (variant B): CAN ISO-TP/J1939 and USB CAN adapters, BT PAN, USB-net, NFC PN533, NFS, USB Wi-Fi AR9170/ZD1211/Broadcom 4320; does nothing on the stock kernel |
| `nh-hid on [--app <package>] \| off \| status` | USB keyboard and mouse (`/dev/hidg0`, `/dev/hidg1`) for NetHunter HID attacks and apps such as USB Keyboard from [android-keyboard-gadget](https://github.com/pelya/android-keyboard-gadget) — the same HID descriptors; that project's kernel patch is not needed here (the stock kernel has configfs HID). `--app <package>` opens the two nodes to that one app (owned by its uid, a dedicated SELinux type; re-applied by itself after a cable replug); adb over USB drops for a few seconds while it switches |
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
kernel-recipe/            variant B: the NetHunter kernel — build from the ACK commit, KMI check against Google, boot.img, on-device test
btbridge/nh-btbridge.c    AIDL Bluetooth HAL ↔ /dev/vhci bridge  (+ build.sh)
patches/                  5 minimal driver patches, one file each, each explained
config/                   kernel config fragment: what is added, and what is impossible and why; nh-kernel-only.list — modules for the NetHunter kernel only
oot/                      minstrel_ht module + our glue for the out-of-tree Realtek drivers
tools/                    build-all.sh, fetch-*.sh, check_gki_access.py (GKI load simulator), check_nh_kernel_access.py (the same for the NetHunter kernel, with CRCs), add-gki-extras.sh, kocrc.py, add-wlan-inject.sh
docker/                   clang-18 arm64 build image
```

---

## Uninstall

Magisk → *Modules* → remove `nethunter-kmods` (and NetHunter) → Reboot, then reflash the stock `init_boot.img`. To relock (wipes data, stock firmware only): `fastboot flashing lock`.

## Licensing

- Scripts, patches, `nh-btbridge.c` and the minstrel wrapper are **GPL-2.0** (kernel-derived) — see [LICENSE](LICENSE).
- This repo does **not** contain: Nothing's proprietary partition images, Google's kernel binaries, the device's system libraries, or any firmware blobs. The build fetches these from their sources; `fetch-devlibs.sh` pulls link-time libraries from your own device.
- Release zips bundle firmware from [linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware) under its respective vendor licenses (see that project's `WHENCE`; the license texts are in the module's `firmware/LICENSES/`) and the ZD1211 firmware (GPL-2.0, from the Debian package [zd1211-firmware](https://deb.debian.org/debian/pool/non-free-firmware/z/zd1211-firmware/), `firmware/zd1211/`).
- `wlan-inject/patches/` modifies Qualcomm's qcacld-3.0 / qca-wifi-host-cmn / fw-api sources and keeps their ISC license; the monitor/injection work is by [Loukious](https://github.com/Loukious/vendor_qcom_opensource_wlan), the version delta comes from CodeLinaro. Origins per file: [wlan-inject/README.md](wlan-inject/README.md#patches).
- The out-of-tree Wi-Fi drivers are separate projects: [morrownr/8812au-20210820](https://github.com/morrownr/8812au-20210820), [morrownr/8814au](https://github.com/morrownr/8814au), [aircrack-ng/rtl8188eus](https://github.com/aircrack-ng/rtl8188eus).

## Disclaimer

Provided as-is, for research and for authorized testing of systems and networks you own or have permission to test. Unlocking the bootloader and modifying the kernel environment can brick a device, void warranty and break security guarantees; you do this at your own risk. The authors are not responsible for any damage or misuse.
