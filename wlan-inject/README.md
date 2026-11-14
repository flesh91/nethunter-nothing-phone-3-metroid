# wlan-inject — monitor mode + packet injection on the built-in Wi-Fi

*[Українською →](README.uk.md)*

The Nothing Phone (3) has a Qualcomm **WCN7750** (FullMAC, `qca_cld3_wcn7750.ko`, qcacld-3.0). On the stock driver, monitor mode (`con_mode=4`) receives in bursts and cannot transmit. This directory rebuilds **only that one driver module** with working monitor mode and frame injection, and the `nethunter-wlan-inject` Magisk module swaps it in after boot.

**No custom kernel.** The stock Google GKI `Image`, `boot`/`init_boot` (apart from root) and every other vendor module stay untouched. The stock driver file in `vendor_dlkm` is not modified either: the swap happens in memory and is gone after a reboot.

> **Built for one firmware build only:** Nothing OS C5.0 (`C5.0-260924-2115`, EEA), kernel `6.6.127-android15-8-gf0987337fa35-ab15756704-4k`, stock driver qcacld-3.0 **5.2.1.123K**. The Magisk module refuses to install or to swap on anything else (it checks the kernel release, the vendor build fingerprint and the SHA-256 of the stock driver). A driver that does not match the Wi-Fi firmware hard-resets the phone when Wi-Fi is turned on — see [What went wrong before](#what-went-wrong-before).

## Result (verified on the device)

All tests were run against my own access point, one band at a time.

| Check | Stock driver | This build |
|---|---|---|
| Normal Wi-Fi (connect on 2.4 and 5 GHz, out of range and back) | ✅ | ✅ |
| Monitor RX, 2.4 GHz | bursts, 30–45 s gaps | steady, every beacon of the AP |
| Monitor RX, 5 GHz | not measured | 700–1500 frames / 8 s |
| `aireplay-ng --test`, 2.4 GHz (ch 9) | fails (0 APs answer) | **30/30** |
| `aireplay-ng --test`, 5 GHz (ch 36) | not measured | **30/30** |
| Injection completions (`injection_stats`) | — | 369 submitted, 369 completed, 0 failed, 0 timed out |
| Deauth against a client, 5 GHz (`aireplay-ng --deauth 8 -a <AP> -c <client>`) | — | **works**: frames ACKed by both the client and the AP, client dropped and reconnected |
| WPA2 handshake capture, 5 GHz (airodump-ng + that deauth) | — | **captured**: `aircrack-ng` reports "1 handshake", 4 EAPOL frames |
| Monitor on DFS channels (e.g. ch 52, "no IR") | — | tunes and receives |
| Monitor on 6 GHz (5955–6415 MHz) | — | tunes without errors |
| Survives reboot (swap on boot) | — | ✅ |

**Not tested yet:** deauth and handshake capture on 2.4 GHz (no client was on that AP), WPS (disabled on my router — its beacons carry no WPS element), transmitting on 6 GHz and on DFS channels (no AP of mine on those frequencies; the 6 GHz test above only shows that the radio tunes, there was nothing to receive), bandwidths above 20 MHz.

**Still not there:** monitor mode and a normal connection at the same time. Android Wi-Fi is turned off while monitoring (`nh-wlan` saves and restores it). The upstream work this is based on has follow-up commits for STA/AP + monitor coexistence; they do not apply cleanly to the Nothing tree and are not ported.

## Using it

```bash
su -c nh-wlan-driver status      # which driver is loaded, swap-on-boot state, compatibility
su -c nh-wlan monitor 9          # monitor mode on channel 9 (nh-wlan comes from nethunter-kmods)
#   ... tcpdump / aireplay-ng / hcxdumptool on wlan0 from the Kali chroot ...
su -c nh-wlan managed            # back to normal Wi-Fi
su -c nh-wlan-driver restore     # stock driver until the next boot
su -c nh-wlan-driver autoswap off   # stop swapping on boot
cat /sys/module/qca_cld3_wcn7750/parameters/injection_stats
```

### Safety nets in the Magisk module

- **Interrupted swap.** A marker is written to disk before the swap and removed ~20 s after Wi-Fi is back. If the phone reboots in between, the next boot finds the marker, disables swap-on-boot and leaves the stock driver in place. Worst case is one extra reboot.
- **First swap is manual.** Swap-on-boot is armed only by one successful `nh-wlan-driver swap`, for every new version of the module.
- **Compatibility guard.** Kernel release, `ro.vendor.build.fingerprint` and the SHA-256 of the stock driver must equal the values recorded when the package was built. After a Nothing OS update they will not, and the module does nothing until the driver is rebuilt.
- If the kernel refuses the module, the stock driver is loaded back immediately.
- Last resort: Magisk safe mode (hold volume-down while booting) disables all modules.

## What went wrong before

A driver built straight from Nothing's kernel source loads fine and then **hard-resets the SoC the moment the Wi-Fi firmware is brought up** — no panic, nothing in pstore. That looked like a firmware wall. It is not:

1. **Kbuild ≠ the build Nothing ships.** Production uses Qualcomm's Bazel/DDK flow. The public tree only builds the driver through the legacy `Kbuild` file, and the two produce different macro sets. `parity-apply.py` closes the gap (26 changed lines in `Kbuild` and one defconfig):
   - `ENABLE_CE4_COMP_DISABLE_HTT_HTC_MISC_LIST` is tested without its `CONFIG_` prefix in `Kbuild`, so it is never defined — this changes the copy-engine configuration handed to the firmware;
   - `FEATURE_MGMT_RX_OVER_SRNG` is enabled in the defconfig, but `Kbuild` neither lists its objects nor defines the macro;
   - `DBR_MULTI_SRNG_ENABLE` and `WLAN_DP_PROFILE_SUPPORT` are on in the Kbuild build and absent from stock;
   - two flags are assigned to `cppflags-`/a variable without `CONFIG_` and silently dropped; `FEATURE_SMEM_MAILBOX`, `WLAN_FEATURE_SSR_DRIVER_DUMP` and five DDK-only defines are missing.

   Which of these is the fatal one was not isolated; with all of them fixed the driver brings the firmware up.
2. **Version skew.** The source drop (`sm8735/b/mr`, "Nothing OS 4.1 … B4.1-260814") contains qcacld **5.2.1.123**; the binary on the device is **5.2.1.123K**. The missing 24 qcacld and 8 qca-wifi-host-cmn commits and 8 fw-api headers are public on CodeLinaro and are applied from `patches/k-delta/`.

With both applied, the rebuilt *base* driver (no injection) is statically equivalent to the stock binary: identical import set, 527/527 symbol CRCs, all 1874 common data symbols the same size, `.data` the same length to the byte. The remaining differences are inlining decisions of a different compiler build.

## Building it

Requirements: Docker, `adb`, the build image from this repo (`docker build -t nh-kbuild docker`), and the kernel source on a **case-sensitive** filesystem (the tree contains both `xt_DSCP.c` and `xt_dscp.c`; on macOS use a case-sensitive APFS volume).

```bash
# 0. sources: NothingOSS kernel, the commit matching the firmware
git clone -b sm8735/b/mr https://github.com/NothingOSS/android_kernel_msm-6.6_nothing_sm8735 msm-sm8735
#    used here: 5f6161492828 "Merge codes for Nothing Phone(3) Nothing OS 4.1.A024(Metroid-B4.1-260814-1733)"

# 1. once per kernel: full vendor-kernel build for a consistent Module.symvers (hours)
docker run --rm -v "$PWD/msm-sm8735":/src -v nh-work:/work -v "$PWD/wlan-inject":/h nh-kbuild bash /h/kernel-prep.sh

# 2. driver source tree: 123K delta + stock parity + injection patches
wlan-inject/prepare-tree.sh msm-sm8735 wlan-tree            # add --base for a stock-equivalent driver

# 3. build the module (~35 min; under a minute after a one-file change)
docker run --rm -e TAG=inject -v "$PWD/msm-sm8735":/src -v "$PWD/wlan-tree":/parity \
  -v nh-work:/work -v "$PWD/wlan-inject":/h nh-kbuild bash /h/build-driver.sh

# 4. compare with the stock driver before it goes anywhere near the phone
adb pull /vendor_dlkm/lib/modules/qca_cld3_wcn7750.ko stock.ko
LLVM_BIN=<dir with llvm-nm> wlan-inject/ko-compare.sh stock.ko wlan-inject/qca_cld3_wcn7750.inject.ko wlan-inject/inject-hdd_main.cmd
#    expect: same version string, imports only-in-stock = 0, CRC MISMATCH=0, every "want" macro OK

# 5. try it without installing anything (in-memory swap; a reboot restores stock)
adb push wlan-inject/qca_cld3_wcn7750.inject.ko wlan-inject/swap-test.sh wlan-inject/inject-test.sh /data/local/tmp/
adb shell su -c 'sh /data/local/tmp/swap-test.sh test /data/local/tmp/qca_cld3_wcn7750.inject.ko'
adb shell su -c 'sh /data/local/tmp/inject-test.sh <channel> <your AP bssid> <your AP essid>'

# 6. package the Magisk module, bound to the firmware of the connected phone
tools/pack-wlan-inject.sh wlan-inject/qca_cld3_wcn7750.inject.ko v2     # -> out/nethunter-wlan-inject-metroid-ab<build>-v2.zip
```

What was actually run: steps 3–6 as written; `prepare-tree.sh` was checked to reproduce, file for file, the source tree the released driver was built from. `kernel-prep.sh` is the kernel-preparation part of the longer script that produced the build output used here — it has not been re-run in this trimmed form.

`parity-extra.symvers` carries one CRC (`cnss_utils_smem_mailbox_write`) taken from the stock driver's `__versions` table: the symbol is exported by the stock `cnss_utils` on the device, but not by the platform modules built in step 1.

### For another firmware build

Everything here is pinned to one build. For a different one you need the matching NothingOSS source commit, the qcacld version string of *your* stock driver (`strings qca_cld3_wcn7750.ko | grep '^5\.'`) and, if it differs from the source drop, the corresponding CodeLinaro delta. Then run `ko-compare.sh` until the base build matches the stock binary **before** trying it on the phone. Expect `parity-apply.py` anchors and patch hunks to need adjusting.

## Patches

| File | Origin |
|---|---|
| `k-delta/qcacld-3.0-123-to-123K.patch` | CodeLinaro `qcacld-3.0` `502f40c76b8d..6282f85f4cd8` (Release 5.2.1.123 → 5.2.1.123K), minus one defconfig hunk re-applied by `prepare-tree.sh` |
| `k-delta/qca-wifi-host-cmn-to-123K.patch` | CodeLinaro `qca-wifi-host-cmn` `6c63b35f9e62..1d00121` |
| `k-delta/fw-api-to-123K.patch` | CodeLinaro `fw-api` at `bd1756641a23` vs the Nothing drop (8 headers) |
| `0001-wcn7750-monitor-mode-and-direct-packet-injection.patch` | [Loukious](https://github.com/Loukious/vendor_qcom_opensource_wlan) `25875eb1a6`, ported to the Nothing tree |
| `0002`–`0004` | Loukious `fa5f0aa`, `50fec79`, `f339653` (scan fix; EAPOL/raw data/control injection and reply addressing; monitor teardown order) |
| `0005-wlan-send-CCK-radiotap-rates-outside-2.4-GHz-…` | this repo, see below |

**About 0005.** Patch 0003 starts honouring the radiotap rate and rejects CCK rates outside 2.4 GHz. `aireplay-ng` puts 1 Mb/s into radiotap on every band, so on 5 GHz every frame was refused. Dropping the rate request instead is worse: a frame sent through the direct data path with band/bandwidth metadata but **no rate** makes the WCN7750 firmware assert (`cmnos_assert.c:528`; the Wi-Fi subsystem restarts by itself). The patch sends such frames at 6 Mb/s OFDM, the lowest legal rate of the band — what mac80211 effectively does.

The injection design — a hidden helper vdev with a self-peer, because the firmware drops management TX from a monitor vdev — is entirely Loukious's work, originally for the Poco F7 (same chip). His prebuilt module cannot be used on this phone: it is built for his own kernel, whose `module_layout` and 257 of the 458 symbols the driver imports have different CRCs.

All patches keep the license of the files they modify (qcacld-3.0, qca-wifi-host-cmn and fw-api are ISC-licensed Qualcomm sources).

## Authorized use only

Transmit and capture only on networks you own or are explicitly authorized to test.
