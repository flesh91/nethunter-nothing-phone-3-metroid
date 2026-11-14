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
set_perm "$MODPATH/system/bin/nh-wlan-driver" 0 2000 0755
set_perm "$MODPATH/system/bin/nh-gki" 0 2000 0755

# Додаткові функції власного ядра NetHunter (варіант B): активні лише на ньому, на стоковому — сплять
if [ -f "$MODPATH/gki/kernel.version" ]; then
  if [ "$(cat /proc/version)" = "$(cat "$MODPATH/gki/kernel.version")" ]; then
    ui_print "- NetHunter kernel detected: its extra modules (CAN, BT PAN, USB-net, NFC, NFS, old USB Wi-Fi...) load after boot"
    ui_print "  (disable: su -c nh-gki autoload off)"
  else
    ui_print "- Stock kernel: NetHunter-kernel features stay idle (they need nethunter-boot.img)"
  fi
fi

# Драйвер вбудованого Wi-Fi з інжекцією: підміняється автоматично після старту, але лише на тій самій
# збірці прошивки (ядро, vendor, стоковий драйвер), на якій його перевірено. Інакше пропускається,
# а решта модуля працює як завжди.
if [ -f "$MODPATH/wlan/qca_cld3_wcn7750.ko" ]; then
  if [ "$(getprop ro.vendor.build.fingerprint)" = "$(cat "$MODPATH/wlan/vendor.fingerprint")" ] && \
     [ "$(sha256sum /vendor_dlkm/lib/modules/qca_cld3_wcn7750.ko | cut -d' ' -f1)" = "$(cat "$MODPATH/wlan/stock.sha256")" ]; then
    ui_print "- Built-in Wi-Fi injection: on, the driver is swapped ~15 s after boot"
    ui_print "  (disable: su -c nh-wlan-driver autoswap off)"
  else
    ui_print "- Built-in Wi-Fi injection: skipped, this firmware differs from the tested one"
  fi
fi

# Колишній окремий модуль інжекції тепер входить сюди — прибираємо його, щоб не було двох підмін
for d in /data/adb/modules/nethunter-wlan-inject /data/adb/modules_update/nethunter-wlan-inject; do
  [ -d "$d" ] || continue
  touch "$d/remove"
  ui_print "- Old nethunter-wlan-inject module will be removed on reboot (now part of this module)"
done

# Custom Commands NetHunter: «Start/Stop wlan0 monitor mode» → nh-wlan (якщо NetHunter уже встановлено)
ui_print "- Checking NetHunter custom commands (wlan0 monitor mode)"
sh "$MODPATH/system/bin/nh-fix-nethunter" commands --force-stop 2>&1 | while read -r l; do ui_print "  ${l#nh-fix-nethunter: }"; done
