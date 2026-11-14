#!/system/bin/sh
MODDIR=${0%/*}
LOG="$MODDIR/load.log"
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 5

# Кеш 64-бітного busybox із застосунку NetHunter: дані застосунку доступні лише після першого розблокування
(
  until [ "$(getprop sys.user.0.ce_available)" = "true" ]; do sleep 5; done
  sh "$MODDIR/system/bin/nh-fix-nethunter" cache >> "$MODDIR/nethunter-fix.log" 2>&1
) &

# Обгортка bluebinder → nh-btbridge (apt upgrade у Kali може її перезаписати)
KALI_BB=/data/local/nhsystem/kali-arm64/usr/sbin/bluebinder
if [ -f "$KALI_BB" ] && ! grep -q nh-btbridge "$KALI_BB"; then
  sh "$MODDIR/system/bin/nh-bt" install-bluebinder > "$MODDIR/bluebinder.log" 2>&1
fi

# Драйвери вантажаться автоматично (вимкнути: nh-kmod autoload off).
kmods_boot() {
  # Запобіжник: якщо попереднє завантаження модулів не дійшло до кінця
  # (телефон перезавантажився посеред insmod) — більше не вантажимо автоматично.
  if [ -f "$MODDIR/loading" ]; then
    touch "$MODDIR/autoload-off"
    echo "Previous load was interrupted at module: $(cat "$MODDIR/loading")" > "$LOG"
    echo "Autoload disabled. Details: /sys/fs/pstore or logs; re-enable: su -c nh-kmod autoload on" >> "$LOG"
    mv "$MODDIR/loading" "$MODDIR/crashed-on"; sync
    return
  fi
  if [ -f "$MODDIR/autoload-off" ]; then
    echo "Autoload is off. Load now: su -c nh-kmod load; enable on boot: su -c nh-kmod autoload on" > "$LOG"
    return
  fi
  "$MODDIR/system/bin/nh-kmod" load > "$LOG" 2>&1
}
kmods_boot

# Додаткові функції власного ядра NetHunter (варіант B) — лише коли працює саме воно;
# на стоковому ядрі нічого не робить (вимкнути: nh-gki autoload off)
sh "$MODDIR/gki-boot.sh"

# Драйвер вбудованого Wi-Fi з інжекцією (вимкнути: nh-wlan-driver autoswap off)
sh "$MODDIR/wlan-boot.sh"
