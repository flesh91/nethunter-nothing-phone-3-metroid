#!/system/bin/sh
# Non-persistent WLAN driver swap test (run as root on the phone).
#   swap-test.sh test <new.ko>   : wifi off -> rmmod stock -> insmod new -> wifi on -> report
#   swap-test.sh restore         : rmmod whatever is loaded -> insmod stock -> wifi on
# Logs survive a reset: /data/local/tmp/swap.log (+ swap-dmesg.log), synced continuously.
L=/data/local/tmp/swap.log; D=/data/local/tmp/swap-dmesg.log
STOCK=$(find /vendor_dlkm/lib/modules /vendor/lib/modules -name 'qca_cld3_wcn7750.ko' 2>/dev/null | head -1)
log(){ echo "[$(date +%H:%M:%S)] $*" >> $L; echo "[$(date +%H:%M:%S)] $*"; sync; }
bg_start(){ dmesg -w >> $D 2>&1 & echo $! > /data/local/tmp/swap-dmesg.pid
            ( while true; do sync; sleep 0.2; done ) & echo $! > /data/local/tmp/swap-sync.pid; }
bg_stop(){ for p in dmesg sync; do kill "$(cat /data/local/tmp/swap-$p.pid 2>/dev/null)" 2>/dev/null; done; }
wait_ip(){ i=0; IPA=""; while [ $i -lt "$1" ]; do sleep 1; i=$((i+1))
             IPA=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | head -1)
             [ $((i % 5)) -eq 0 ] && log "t=${i}s wlan0=$(ip -o link show wlan0 2>/dev/null | grep -o 'state [A-Z]*') ip=${IPA:-none}"
             [ -n "$IPA" ] && break; done; }
case "$1" in
test)
  KO="$2"; : > $L; : > $D
  log "stock=$STOCK new=$KO"
  { [ -f "$KO" ] && [ -f "$STOCK" ]; } || { log "ABORT: missing module file"; exit 1; }
  log "wifi off"; svc wifi disable; sleep 5; ip link set wlan0 down 2>/dev/null
  bg_start
  log "rmmod stock"; rmmod qca_cld3_wcn7750; RC=$?; log "rmmod rc=$RC"
  if [ $RC -ne 0 ]; then log "ABORT: rmmod failed; wifi back on"; svc wifi enable; bg_stop; exit 2; fi
  sleep 2
  log "insmod new"; insmod "$KO"; RC=$?; log "insmod rc=$RC"
  if [ $RC -ne 0 ]; then log "insmod failed -> restoring stock"; insmod "$STOCK"; svc wifi enable; bg_stop; exit 3; fi
  sleep 3
  log "loaded: version=$(cat /sys/module/qca_cld3_wcn7750/version 2>/dev/null) /dev/wlan=$(ls /dev/wlan 2>&1)"
  log "wifi on (firmware bring-up)"; svc wifi enable
  wait_ip 45
  log "RESULT ip=${IPA:-none} wlan0=$(ip -o link show wlan0 2>/dev/null | grep -o 'state [A-Z]*')"
  log "wpss: $(cat /sys/class/remoteproc/remoteproc3/state 2>/dev/null)"
  dmesg | grep -iE "Loading driver|wlan fw|fw_version|FW ready|mgmt_rx_srng|assert|crash|wpss.*(fatal|recover)|icnss.*(error|fail)" | tail -25 >> $L
  bg_stop; sync; log "DONE"
  ;;
restore)
  log "restore: wifi off"; svc wifi disable; sleep 5; ip link set wlan0 down 2>/dev/null
  rmmod qca_cld3_wcn7750; log "rmmod rc=$?"; sleep 2
  insmod "$STOCK"; log "insmod stock rc=$?"; sleep 3; svc wifi enable; wait_ip 45
  log "RESTORED ip=${IPA:-none} version=$(cat /sys/module/qca_cld3_wcn7750/version 2>/dev/null)"
  ;;
*) echo "usage: $0 test <new.ko> | restore"; exit 1;;
esac
