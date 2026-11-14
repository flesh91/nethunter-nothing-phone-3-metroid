#!/system/bin/sh
# Ставимо лише на ту прошивку, під яку драйвер зібрано й перевірено: те саме ядро, та сама збірка
# vendor і той самий стоковий драйвер. Драйвер, що не відповідає прошивці Wi-Fi, перезавантажує телефон.
WANT_K="$(cat "$MODPATH/kernel.release")"
WANT_F="$(cat "$MODPATH/vendor.fingerprint")"
WANT_S="$(cat "$MODPATH/stock.sha256")"
STOCK=/vendor_dlkm/lib/modules/qca_cld3_wcn7750.ko

[ -f "$MODPATH/qca_cld3_wcn7750.ko" ] || abort "! Driver file is missing from the package"
if [ "$(uname -r)" != "$WANT_K" ]; then
  ui_print "! Running kernel $(uname -r), but the driver was built for $WANT_K"
  abort "! Rebuild the driver after a Nothing OS update. Installation aborted"
fi
if [ "$(getprop ro.vendor.build.fingerprint)" != "$WANT_F" ]; then
  ui_print "! Vendor build: $(getprop ro.vendor.build.fingerprint)"
  ui_print "! Driver was matched to: $WANT_F"
  abort "! Installation aborted"
fi
if [ "$(sha256sum "$STOCK" | cut -d' ' -f1)" != "$WANT_S" ]; then
  abort "! Stock Wi-Fi driver differs from the one this build was matched to. Installation aborted"
fi
ui_print "- Kernel, vendor build and stock driver match"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/system/bin/nh-wlan-driver" 0 2000 0755

# Запобіжник 2 діє для кожної нової версії: автопідміну на старті вмикає лише перша успішна ручна підміна.
ui_print "- After reboot run once: su -c nh-wlan-driver swap"
ui_print "  (a successful first swap enables swap on boot)"
