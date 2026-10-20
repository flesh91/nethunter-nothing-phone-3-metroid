#!/bin/sh
# Готує вихідники minstrel_ht з дерева ядра ($1 = шлях до дерева)
set -e
K="$1"; D="$(dirname "$0")"
cp "$K/net/mac80211/rc80211_minstrel_ht.c" "$D/minstrel_ht_core.c"
cp "$K/net/mac80211/rc80211_minstrel_ht.h" "$D/"
{
  echo '// SPDX-License-Identifier: GPL-2.0-only'
  echo '/* Автоматично витягнуто з net/mac80211/util.c */'
  echo '#include "ieee80211_i.h"'
  awk '/^int ieee80211_frame_duration\(enum nl80211_band band/{p=1} p{print} p&&/^}/{exit}' "$K/net/mac80211/util.c"
} > "$D/frame_duration.c"
