#!/system/bin/sh
# Підміна драйвера вбудованого Wi-Fi на збірку з монітором та інжекцією — після завантаження системи.
# Викликається з service.sh. Увімкнено за замовчуванням; вимкнути: nh-wlan-driver autoswap off
MODDIR=${0%/*}
W="$MODDIR/wlan"
LOG="$W/boot.log"

# модуль зібрано без драйвера інжекції — нічого не робимо
[ -f "$W/qca_cld3_wcn7750.ko" ] || exit 0

# Запобіжник 1: якщо попередня підміна не дійшла до кінця (телефон перезавантажився посеред неї) —
# більше не підміняємо автоматично. Лишається стоковий драйвер, Wi-Fi працює як завжди.
if [ -f "$W/swapping" ]; then
  touch "$W/autoswap-off"
  mv "$W/swapping" "$W/crashed"; sync
  echo "Previous driver swap was interrupted by a reboot (started $(cat "$W/crashed"))." > "$LOG"
  echo "Swap on boot disabled, stock driver in use. Re-enable: su -c nh-wlan-driver autoswap on" >> "$LOG"
  exit 0
fi

# Вимкнено користувачем (або запобіжником 1)
if [ -f "$W/autoswap-off" ]; then
  echo "Swap on boot is off. Enable: su -c nh-wlan-driver autoswap on" > "$LOG"
  exit 0
fi

# Запобіжник 2 (сумісність ядра, прошивки і стокового драйвера) — усередині самої команди.
NH_WLAN_MODDIR="$MODDIR" sh "$MODDIR/system/bin/nh-wlan-driver" swap > "$LOG" 2>&1
