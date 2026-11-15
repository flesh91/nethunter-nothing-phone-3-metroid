#!/system/bin/sh
# Додаткові функції власного ядра NetHunter (варіант B: CAN ISO-TP/J1939, BNEP, USB RNDIS/QMI/MBIM) —
# після старту системи і лише тоді, коли працює саме це ядро (звірка з gki/kernel.version).
# На стоковому ядрі нічого не робить. Викликається з service.sh; вимкнути: nh-gki autoload off
MODDIR=${0%/*}
G="$MODDIR/gki"
LOG="$G/boot.log"

[ -f "$G/kernel.version" ] || exit 0

if [ "$(cat /proc/version)" != "$(cat "$G/kernel.version")" ]; then
  if grep -q '(nethunter@metroid)' /proc/version; then
    echo "Another NetHunter kernel build: features stay idle (flash the nethunter-boot.img of this module's release)" > "$LOG"
  else
    echo "Stock kernel: NetHunter-kernel features stay idle (they need nethunter-boot.img)" > "$LOG"
  fi
  exit 0
fi

# Запобіжник: попереднє завантаження обірвалось перезавантаженням — більше не вантажимо автоматично
if [ -f "$G/loading" ]; then
  touch "$G/autoload-off"
  mv "$G/loading" "$G/crashed-on"; sync
  echo "Previous load was interrupted by a reboot at: $(cat "$G/crashed-on")" > "$LOG"
  echo "Load on boot disabled. Re-enable: su -c nh-gki autoload on" >> "$LOG"
  exit 0
fi

if [ -f "$G/autoload-off" ]; then
  echo "Load on boot is off. Load now: su -c nh-gki load; enable: su -c nh-gki autoload on" > "$LOG"
  exit 0
fi

NH_GKI_MODDIR="$MODDIR" sh "$MODDIR/system/bin/nh-gki" load > "$LOG" 2>&1
