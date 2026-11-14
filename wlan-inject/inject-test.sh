#!/system/bin/sh
# Тест монітора та інжекції для збірки WCN7750 з патчем інжекції (запускати від root на телефоні).
#   inject-test.sh <канал> <bssid> <essid>
# Передавання лише в бік вказаної (власної) точки доступу: aireplay-ng --test -a <bssid> -e <essid>.
# Лог: /data/local/tmp/inject-test.log, захоплення: /data/local/tmp/inject-rx.pcap
CH=/data/local/nhsystem/kali-arm64; L=/data/local/tmp/inject-test.log
P=/sys/module/qca_cld3_wcn7750/parameters
CHAN=${1:?channel}; BSSID=${2:?bssid}; ESSID=${3:?essid}
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a $L; sync; }
inchroot(){ chroot $CH /usr/bin/env PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin "$@"; }
: > $L
log "driver: $(dmesg | grep -a 'Loading driver' | tail -1 | sed 's/.*qca_cld3/qca_cld3/')"
if [ -e $P/injection_dp_inflight_limit ]; then log "injection param present"; else log "WARN: no injection param (base module?)"; fi
echo "INJECT-TEST-START" > /dev/kmsg

log "-> monitor (con_mode=4)"
svc wifi disable; sleep 5; ip link set wlan0 down
echo 4 > $P/con_mode; log "con_mode write rc=$? now=$(cat $P/con_mode)"
sleep 2; ip link set wlan0 up; log "link up rc=$?"; sleep 3
log "wlan0 type=$(cat /sys/class/net/wlan0/type) (803=radiotap) operstate=$(cat /sys/class/net/wlan0/operstate)"
inchroot iw dev wlan0 set channel "$CHAN" 2>&1 | tee -a $L; log "set channel $CHAN done"
inchroot iw dev wlan0 info 2>&1 | grep -E "type|channel" | tee -a $L

log "RX 8s on channel $CHAN:"
timeout 8 tcpdump -i wlan0 -n -c 3000 -w /data/local/tmp/inject-rx.pcap 2>&1 | tail -3 | tee -a $L
log "frames from own AP in capture: $(tcpdump -n -r /data/local/tmp/inject-rx.pcap 2>/dev/null | grep -ci "$BSSID")"

log "aireplay-ng --test (own AP only)"
inchroot timeout 45 aireplay-ng --test -a "$BSSID" -e "$ESSID" wlan0 2>&1 | tail -15 | tee -a $L

log "dmesg injection lines:"
dmesg | sed -n '/INJECT-TEST-START/,$p' | grep -aiE "inject|monitor tx|helper" | tail -15 | cut -c1-200 | tee -a $L

log "-> managed"
ip link set wlan0 down; echo 0 > $P/con_mode; sleep 2; ip link set wlan0 up 2>/dev/null; svc wifi enable
i=0; IPA=""; while [ $i -lt 45 ]; do sleep 1; i=$((i+1)); IPA=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | head -1); [ -n "$IPA" ] && break; done
log "managed: type=$(cat /sys/class/net/wlan0/type) con_mode=$(cat $P/con_mode) ip=${IPA:-none} after ${i}s"
log "fatal lines since start: $(dmesg | sed -n '/INJECT-TEST-START/,$p' | grep -aciE 'qdf_trigger_self_recovery|ASSERT|FW_DOWN|Unhandled context fault|Call trace')"
log "DONE"
