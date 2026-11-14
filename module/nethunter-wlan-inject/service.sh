#!/system/bin/sh
# Підміна драйвера вбудованого Wi-Fi на збірку з монітором та інжекцією — після завантаження системи.
MODDIR=${0%/*}
LOG="$MODDIR/boot.log"
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 8

# Запобіжник 1: якщо попередня підміна не дійшла до кінця (телефон перезавантажився посеред неї) —
# більше не підміняємо автоматично. Лишається стоковий драйвер, Wi-Fi працює як завжди.
if [ -f "$MODDIR/swapping" ]; then
  rm -f "$MODDIR/autoswap"
  mv "$MODDIR/swapping" "$MODDIR/crashed"; sync
  echo "Previous driver swap was interrupted by a reboot (started $(cat "$MODDIR/crashed"))." > "$LOG"
  echo "Swap on boot disabled, stock driver in use. Try again manually: su -c nh-wlan-driver swap" >> "$LOG"
  exit 0
fi

# Запобіжник 2: автопідміна вмикається лише після першої успішної ручної `nh-wlan-driver swap`.
if [ ! -f "$MODDIR/autoswap" ]; then
  echo "Swap on boot not enabled yet. Run the first swap manually: su -c nh-wlan-driver swap" > "$LOG"
  exit 0
fi

# Запобіжник 3 (сумісність ядра, прошивки і стокового драйвера) — усередині самої команди.
NH_WLAN_MODDIR="$MODDIR" sh "$MODDIR/system/bin/nh-wlan-driver" swap > "$LOG" 2>&1
