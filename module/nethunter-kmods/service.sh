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

# Запобіжник 1: якщо попереднє завантаження модулів не дійшло до кінця
# (телефон перезавантажився посеред insmod) — більше не вантажимо автоматично.
if [ -f "$MODDIR/loading" ]; then
  rm -f "$MODDIR/autoload"
  echo "Previous load was interrupted at module: $(cat "$MODDIR/loading")" > "$LOG"
  echo "Autoload disabled. Details: /sys/fs/pstore or logs; re-enable: su -c nh-kmod autoload on" >> "$LOG"
  mv "$MODDIR/loading" "$MODDIR/crashed-on"
  exit 0
fi

# Запобіжник 2: автозавантаження вмикається лише після першого успішного ручного `nh-kmod load`.
if [ ! -f "$MODDIR/autoload" ]; then
  echo "Autoload not enabled yet. Run the first load manually: su -c nh-kmod load" > "$LOG"
  exit 0
fi

"$MODDIR/system/bin/nh-kmod" load > "$LOG" 2>&1
