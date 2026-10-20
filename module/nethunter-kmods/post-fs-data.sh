#!/system/bin/sh
MODDIR=${0%/*}
# 64-бітний busybox для модуля NetHunter (див. system/bin/nh-fix-nethunter) — до монтування модулів
sh "$MODDIR/system/bin/nh-fix-nethunter" boot > "$MODDIR/nethunter-fix.log" 2>&1
