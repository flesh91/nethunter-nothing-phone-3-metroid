#!/system/bin/sh
# Ставимо лише на те ядро, під яке зібрано (інакше модулі не завантажаться або, гірше, завантажаться з іншим ABI).
WANT="$(cat "$MODPATH/kernel.release")"
HAVE="$(uname -r)"
if [ "$HAVE" != "$WANT" ]; then
  ui_print "! Running kernel $HAVE, but modules were built for $WANT"
  ui_print "! Rebuild the modules after a Nothing OS update."
  abort "! Installation aborted"
fi
ui_print "- Kernel matches: $HAVE"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/system/bin/nh-kmod" 0 2000 0755
set_perm "$MODPATH/system/bin/nh-bt" 0 2000 0755
set_perm "$MODPATH/system/bin/nh-btbridge" 0 2000 0755
set_perm "$MODPATH/system/bin/nh-wlan" 0 2000 0755
set_perm "$MODPATH/system/bin/nh-fix-nethunter" 0 2000 0755

# Custom Commands NetHunter: «Start/Stop wlan0 monitor mode» → nh-wlan (якщо NetHunter уже встановлено)
ui_print "- Checking NetHunter custom commands (wlan0 monitor mode)"
sh "$MODPATH/system/bin/nh-fix-nethunter" commands --force-stop 2>&1 | while read -r l; do ui_print "  ${l#nh-fix-nethunter: }"; done
