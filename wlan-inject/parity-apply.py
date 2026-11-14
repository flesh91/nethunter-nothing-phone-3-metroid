#!/usr/bin/env python3
"""Apply stock (Bazel/DDK) feature parity to a Nothing B4.1 qcacld-3.0 tree built via legacy Kbuild.

usage: parity-apply.py <qcacld-3.0 dir>

Nothing ships the driver built with Qualcomm's Bazel/DDK flow; the public kernel source only builds it
through the legacy Kbuild file, which yields a different macro set (a typo'd CE4 flag that never gets
defined, a feature whose objects are not listed, a few DDK-only defines). A driver built that way loads
but hard-resets the SoC when the Wi-Fi firmware is brought up. These edits make the Kbuild build
macro-identical to the stock binary. Each edit asserts its anchor exactly (fails loudly otherwise)."""
import sys, re, pathlib
q = pathlib.Path(sys.argv[1])
kb = q / "Kbuild"; dc = q / "configs" / "sun_gki_wcn7750_defconfig"
k = kb.read_text(); d = dc.read_text()

def sub1(text, old, new, count=1, what=""):
    n = text.count(old)
    assert n == count, f"{what}: expected {count} occurrence(s) of anchor, found {n}"
    return text.replace(old, new)

# 1. CE4 completion flag: Kbuild tested a variable without the CONFIG_ prefix -> never set.
k = sub1(k, "ccflags-$(ENABLE_CE4_COMP_DISABLE_HTT_HTC_MISC_LIST) += -DENABLE_CE4_COMP_DISABLE_HTT_HTC_MISC_LIST",
            "ccflags-$(CONFIG_ENABLE_CE4_COMP_DISABLE_HTT_HTC_MISC_LIST) += -DENABLE_CE4_COMP_DISABLE_HTT_HTC_MISC_LIST", what="CE4")
# 2. mgmt RX over SRNG: defconfig enables it but legacy Kbuild neither builds the objects nor defines the macro.
anchor = "\t\t    -I$(WLAN_ROOT)/components/target_if/mgmt_rx_srng/inc\n"
block = anchor + """
ifeq ($(CONFIG_FEATURE_MGMT_RX_OVER_SRNG), y)
MGMT_RX_SRNG_OBJS := $(MGMT_RX_SRNG_DIR)/core/src/wlan_mgmt_rx_srng.o \\
		     $(MGMT_RX_SRNG_DIR)/dispatcher/src/wlan_mgmt_rx_srng_ucfg_api.o \\
		     components/target_if/mgmt_rx_srng/src/target_if_mgmt_rx_srng.o \\
		     $(MGMT_RX_SRNG_DIR)/dispatcher/src/wlan_mgmt_rx_srng_tgt_api.o
ccflags-y += -DFEATURE_MGMT_RX_OVER_SRNG
endif

$(call add-wlan-objs,mgmt_rx_srng,$(MGMT_RX_SRNG_OBJS))
"""
k = sub1(k, anchor, block, what="MGMT_RX_SRNG")
# 3. DBR multi-SRNG: legacy Kbuild sets it, production build does not.
k = sub1(k, "ccflags-$(CONFIG_DIRECT_BUF_RX_ENABLE) += -DDBR_MULTI_SRNG_ENABLE\n", "", count=2, what="DBR_MULTI_SRNG")
# 4. beacon ratecode: 'cppflags-' is not a compile-flag variable -> never applied.
k = sub1(k, "cppflags-$(CONFIG_BCN_RATECODE_ENABLE) += -DWLAN_BCN_RATECODE_ENABLE",
            "ccflags-$(CONFIG_BCN_RATECODE_ENABLE) += -DWLAN_BCN_RATECODE_ENABLE", what="BCN_RATECODE")
# 5. WLAN_OPEN_SOURCE: same missing-prefix bug.
k = sub1(k, "ccflags-$(WLAN_OPEN_SOURCE) += -DWLAN_OPEN_SOURCE",
            "ccflags-$(CONFIG_WLAN_OPEN_SOURCE) += -DWLAN_OPEN_SOURCE", what="OPEN_SOURCE")
# 6. remaining production-only macros that the legacy flow never derives.
anchor = 'ccflags-y += -DWLAN_CTRL_NAME=\\"$(WLAN_CTRL_NAME)\\"\nendif\n'
extra = anchor + """
# --- stock (Bazel/DDK) parity: macros present in the production build only ---
ccflags-y += -DWLAN_DISABLE_EXPORT_SYMBOL
ccflags-y += -DWLAN_TRACE_HIDE_MAC_ADDRESS
ccflags-y += -DQDF_NBUF_HISTORY_SIZE=4096
ccflags-y += -DWLAN_MCC_MIN_CHANNEL_QUOTA=20
ccflags-y += -DCONFIG_WLAN_SUPPORT_LAPB=1
"""
k = sub1(k, anchor, extra, what="CTRL_NAME anchor")
kb.write_text(k)

# defconfig: SSR driver dump + SMEM mailbox on, DP profile off.
d = sub1(d, "CONFIG_WLAN_DP_PROFILE_SUPPORT=y\n", "", what="DP_PROFILE")
assert "CONFIG_FEATURE_MGMT_RX_OVER_SRNG=y" in d and 'CONFIG_WLAN_CTRL_NAME="wlan"' in d
assert "CONFIG_CNSS2_SSR_DRIVER_DUMP" not in d and "CONFIG_FEATURE_SMEM_MAILBOX" not in d
d = d.rstrip("\n") + "\n\n# stock (Bazel/DDK) parity\nCONFIG_CNSS2_SSR_DRIVER_DUMP=y\nCONFIG_FEATURE_SMEM_MAILBOX=y\n"
dc.write_text(d)
print("parity edits applied OK")
