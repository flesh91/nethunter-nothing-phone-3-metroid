# nethunter-kmods — функції ядра Kali NetHunter для Nothing Phone (3)

*[In English →](README.md)*

Модуль Magisk / KernelSU, що додає до **Nothing Phone (3)** функції рівня ядра, потрібні Kali NetHunter, — **без заміни ядра**. Зовнішній USB Wi-Fi (monitor mode + injection), USB Bluetooth, **вбудований** Bluetooth і monitor mode Wi-Fi телефона (а також injection на вбудованому Wi-Fi через необов'язковий другий модуль), USB-serial, USB-net і CAN реалізовані як завантажувані модулі ядра плюс кілька userspace-утиліт, усе зібране під стокове ядро Google GKI.

> **Пристрій:** Nothing Phone (3) (кодова назва *Metroid*, платформа `sun`)
> **Збірка, під яку зроблено:** Nothing OS C5.0 (`ab15756704`), ядро `6.6.127-android15-8-gf0987337fa35-ab15756704-4k`
> Після оновлення Nothing OS, що змінює збірку ядра, модулі треба перезібрати — див. [Збірка з джерел](#збірка-з-джерел).

---

## Чому модулі, а не кастомне ядро

Це ядро Android 15+ GKI з `CONFIG_MODULE_SIG_PROTECT=y`. Власні модулі Google в `system_dlkm` (bluetooth, can, usbnet, zram…) підписані ключем саме цієї збірки Google. Ядро з іншим ключем вважатиме їх непідписаними, а непідписаним модулям заборонено користуватися «захищеними» символами (`kernel/module/main.c`), тож Bluetooth, CAN, USB-мережа і zram перестали б вантажитись. Постачання драйверів NetHunter **як модулів, що вантажаться у незмінене ядро Google**, повністю це оминає.

Сумісність доведена на реальних артефактах, а не «на око»:

| Перевірка | Результат |
|---|---|
| Ядро в стоковому `boot.img` vs збірка Google CI `ab15756704` | побайтово ідентичне |
| Конфіг ядра (`/proc/config.gz`) відтворено з вихідників ACK `@f0987337fa35` | ідентичний (крім рядка версії компілятора) |
| KMI: CRC усіх 9535 експортованих символів vmlinux + GKI-модулів після додавання драйверів | **0 розбіжностей** з `Module.symvers` Google |
| Wi-Fi стек Qualcomm (`cfg80211.ko`, `mac80211.ko` з `vendor_dlkm` пристрою) | CRC збігаються: 111/111 і 74/74 |
| Симуляція правил завантаження GKI (`resolve_symbol()`, protected exports, дублікати) для кожного модуля | **62/62 проходять** |

Ключова знахідка: `cfg80211`/`mac80211` на пристрої — Qualcomm, а не Google. Заголовки збігаються з ACK, але конфіг інший: `CONFIG_NL80211_TESTMODE=y` (інакше CRC `wiphy_new_nm`/`ieee80211_alloc_hw_nm` не збігаються і драйвери не вантажаться) і `CONFIG_MAC80211_RC_MINSTREL` **вимкнено** (у mac80211 Qualcomm немає rate control, тож USB-адаптери не стартують). Тому `minstrel_ht` зібрано окремим модулем і зроблено типовим при завантаженні. Джерело для звірки: [NothingOSS/android_kernel_msm-6.6_nothing_sm8735](https://github.com/NothingOSS/android_kernel_msm-6.6_nothing_sm8735), гілка `sm8735/b/mr`, `arch/arm64/configs/vendor/sun_perf.config`.

---

## Стан функцій

Позначки: ✅ перевірено наживо на пристрої · 🟡 зібрано й вантажиться, із залізом не перевіряли · ❌ неможливо на стоковому ядрі.

### Працює

| Функція | Стан | Примітка |
|---|---|---|
| 62 драйвери вантажаться у стокове ядро | ✅ | `loaded=62 failed=0`, без помилок ядра, автозавантаження при старті |
| Вбудований Bluetooth як Linux `hci0` (`nh-bt` + `nh-btbridge`) | ✅ | класичне сканування + LE; працює під SELinux Enforcing |
| **Monitor mode** вбудованого Wi-Fi (`nh-wlan`) | ✅ | захоплення на 2.4/5 ГГц, перемикання каналів; зі стоковим драйвером лише приймання |
| **Packet injection** на вбудованому Wi-Fi (необов'язковий модуль `nethunter-wlan-inject`) | ✅ | перезібраний драйвер Wi-Fi, **ядро так само стокове**: `aireplay-ng --test` 30/30 на 2.4 і 5 ГГц, deauth і захоплення WPA2 handshake на 5 ГГц, рівне приймання в моніторі — див. [wlan-inject](wlan-inject/README.uk.md) |
| Зовнішній USB Wi-Fi: Atheros AR9271 (перевірено на TP-Link TL-WN722N **v1**) | ✅ | `ath9k_htc` вантажиться при підключенні, прошивка `htc_9271` підхоплюється, з'являється `wlan1`; monitor mode, `aireplay-ng --test` 30/30 на моїй точці; deauth і повний WPA2 4-way handshake захоплено на власній мережі |
| USB Arsenal: HID клавіатура+миша, mass storage, ACM, ECM | ✅ | USB-функції визначаються хостом (гаджет зі стокового ядра) |
| Фікс 32-бітного busybox NetHunter (`nh-fix-nethunter`) | ✅ | 64-бітному пристрою потрібен 64-бітний busybox; застосовується щозавантаження |
| Фікс `su: unknown user root` у NetHunter | ✅ | команди з `su` тепер працюють з NetHunter Terminal |
| Custom Commands монітора wlan0 | ✅ | переписані на виклик `nh-wlan` |

### Зібрано, із залізом ще не перевірено (🟡)

Інші зовнішні USB Wi-Fi адаптери (усі чипсети нижче, крім AR9271), USB Bluetooth-донгли, USB-serial/UART адаптери, CAN-адаптери, USB-Ethernet. Драйвери і 77 файлів прошивок у модулі є, їх просто ще не випробувано на реальному залізі.

**Підтримувані USB Wi-Fi адаптери:**

| Чипсет | Драйвер | Популярні адаптери |
|---|---|---|
| Atheros AR9271 / AR7010 | `ath9k_htc` | Alfa AWUS036NHA, TP-Link TL-WN722N **v1** — ✅ *перевірено* |
| Ralink RT3070/3572/5370/5572 | `rt2800usb` | Alfa AWUS036NH/NEH, Panda PAU05/09 |
| Ralink RT2501/2573 | `rt73usb`, `rt2500usb` | старі Alfa/Edimax |
| Realtek RTL8187L | `rtl8187` | Alfa AWUS036H |
| MediaTek MT7610U / MT7612U | `mt76x0u` / `mt76x2u` | Alfa AWUS036ACHM / AWUS036ACM |
| MediaTek MT7921AU | `mt7921u` | Alfa AWUS036AXML (Wi-Fi 6E) |
| MediaTek MT7601U / MT7663U | `mt7601u` / `mt7663u` | дешеві MT7601 донгли |
| Realtek RTL8812AU/8814AU/8188EUS | `8812au` / `8814au` / `8188eu` (out-of-tree) | Alfa AWUS036ACH / AWUS1900, TL-WN722N v2/v3 |
| Realtek RTL8822BU/8821CU/8723DU, 8xxx | `rtw88_*u`, `rtl8xxxu` | TP-Link Archer T3U/T2U |

**Який адаптер узяти:** Alfa **AWUS036ACM** (MT7612U) або **AWUS036ACHM** (MT7610U) — драйвери в ядрі, стабільний monitor + injection, 2.4/5 ГГц. Для 2.4 ГГц і максимальної сумісності з інструментами — **AWUS036NHA** (AR9271).

**Із зовнішнім адаптером:** працюйте на `wlan1` і не чіпайте `wlan0` — не запускайте `airmon-ng check kill`, він може вимкнути власний Wi-Fi телефона. Поки `airodump-ng` тримає канал, запускайте `aireplay-ng` з `--ignore-negative-one`, інакше він чекає бікона на «channel -1» і нічого не надсилає.

### Неможливо на стоковому ядрі (❌)

| Функція | Причина | Обхід |
|---|---|---|
| PostgreSQL для БД Metasploit (`CONFIG_SYSVIPC`) | вмикання змінює `task_struct` → ламає KMI і всі вендорські модулі | msfconsole без БД, або БД на іншій машині |
| CAN ISO-TP / J1939 у ядрі | `can_proto_register` та ін. захищені в GKI `can.ko` | userspace `python-can-isotp` / `j1939` поверх `can_raw` |
| BNEP (Bluetooth PAN) | `bt_sock_register` поза KMI | — |
| USB-net `rndis_host`, `qmi_wwan`, `cdc_mbim`, `dm9601`, `mcs7830` | потрібні захищені символи GKI | працюють `r8152`/`asix`/`ax88179`/`cdc_ether`/`smsc95xx` |
| `carl9170`, `zd1211rw`, `bpa10x` | рідкісне старе залізо, символи поза KMI | — |

---

## Встановлення

> ⚠️ Розблокування завантажувача **стирає всі дані**. Зробіть резервну копію. Після розблокування Play Integrity (strong) не проходитиме — частина банківських застосунків і Google Wallet можуть не працювати.

**Потрібно:**

1. **Флешабельний модуль** `nethunter-kmods-metroid-ab15756704.zip` з [Releases](../../releases).
2. **Стоковий `init_boot.img`** саме *вашої* збірки — для root через Magisk і для відкату. Заводські образи Nothing дзеркалить спільнота: [nothing_archive](https://github.com/spike0en/nothing_archive) (беріть збірку, що збігається з `adb shell getprop ro.build.fingerprint`). Цей репозиторій **не** поширює пропрієтарні образи Nothing.
3. [Magisk](https://github.com/topjohnwu/Magisk/releases) (KernelSU у режимі LKM теж підходить).

**1 — Розблокувати завантажувач.** Увімкніть *OEM unlocking* і *USB debugging* у параметрах розробника, потім:

```bash
adb reboot bootloader && fastboot flashing unlock
```

Підтвердіть на пристрої (це стирає дані), пройдіть налаштування, знову увімкніть USB debugging.

**2 — Root через Magisk.** Пропатчте стоковий `init_boot.img` у застосунку Magisk (*Install → Select and Patch a File*), заберіть пропатчений образ і прошийте:

```bash
adb reboot bootloader
fastboot flash init_boot magisk_patched-XXXXX.img
fastboot reboot
```

Відкат, якщо телефон не вантажиться: `fastboot flash init_boot <стоковий init_boot.img>`.

**3 — Прошити модуль.** Залийте zip, далі Magisk → *Modules → Install from storage* → zip → *Reboot*.

Перше завантаження **ручне** (автозавантаження вмикається лише після одного успішного, тож поганий модуль не спричинить цикл):

```bash
adb shell su -c "nh-kmod load"     # очікувано: loaded=62 failed=0, rate control: minstrel_ht
adb shell su -c "nh-kmod status"
```

Перед кожним `insmod` пишеться маркер; якщо телефон перезавантажився посеред завантаження, на наступному старті модулі не вантажаться, автозавантаження вимикається, а `load.log` називає винуватця. Аварійний вихід, якщо все ж не стартує: прошити стоковий `init_boot.img`.

**4 — Kali NetHunter.** Встановіть **NetHunter Generic ARM64 (Full)** для Magisk з [kali.org](https://www.kali.org/get-kali/#kali-mobile) (окремого образу під Phone (3) немає, generic правильний), перезавантажте, налаштуйте Kali chroot у застосунку. Фікси NetHunter нижче застосовуються автоматично при встановленні/завантаженні модуля.


**5 — Injection на вбудованому Wi-Fi (необов'язково).** Так само прошийте другий модуль, `nethunter-wlan-inject-metroid-ab15756704-v2.zip` з [Releases](../../releases), і перезавантажте. Він підміняє стоковий драйвер Wi-Fi **у пам'яті** на перезібраний — тієї самої версії, з виправленнями монітора та інжекцією кадрів; стоковий файл у `vendor_dlkm` не змінюється і повертається після будь-якого перезавантаження без модуля. Перша підміна ручна, як і `nh-kmod load`:

```bash
adb shell su -c "nh-wlan-driver swap"     # очікуйте: Swap OK ... Swap on boot enabled
adb shell su -c "nh-wlan monitor 9"       # monitor mode: wlan0 (receive + injection)
```

Модуль прив'язаний саме до цієї збірки прошивки (перевіряються ядро, збірка vendor і стоковий драйвер) і після оновлення Nothing OS нічого не робить, доки драйвер не перезберуть. Результати тестів, обмеження і запобіжники: [wlan-inject/README.uk.md](wlan-inject/README.uk.md).

---

## Команди-утиліти

Усі в `/system/bin` після перезавантаження (до першого — повним шляхом).

| Команда | Що робить |
|---|---|
| `nh-kmod load \| unload \| status \| autoload on\|off` | завантажити/вивантажити драйвери, показати стан |
| `nh-wlan monitor [канал] \| managed \| channel N \| status` | monitor mode вбудованого Wi-Fi (типово канал 6 — **обов'язковий**, без каналу монітор мертвий) |
| `nh-wlan-driver swap \| restore \| status \| autoswap on\|off` | (модуль `nethunter-wlan-inject`) підмінити драйвер вбудованого Wi-Fi на збірку з injection або повернути стоковий |
| `nh-bt start \| stop \| status \| install-bluebinder` | вбудований Bluetooth як `hci0` через AIDL-міст |
| `nh-fix-nethunter boot \| cache \| commands \| su \| check` | фікси NetHunter нижче |

Поки активний монітор Wi-Fi/BT, Android Wi-Fi/Bluetooth вимкнений (HAL обслуговує одного клієнта); утиліти зберігають і відновлюють ваші налаштування. Для LE використовуйте `btmgmt find -l` / `bluetoothctl scan on`, а не `hcitool lescan`. У Kali запускайте `tcpdump -Z root`.

## Фікси NetHunter (автоматичні)

Модуль виправляє три проблеми NetHunter, характерні для цього 64-бітного пристрою з лише AIDL HAL на Android 15+. Оригінали збережено в `/data/adb/nethunter-kmods-fix/`; чіпаються лише стандартні артефакти NetHunter (або наші попередні) — змінене вручну не чіпається.

- **32-бітний busybox** — модуль NetHunter для Magisk постачає 32-бітний `busybox_nh`; цей телефон суто arm64, тож він не запускається, і після перезавантаження NetHunter показує Kali як «Not yet installed». `nh-fix-nethunter` підставляє 64-бітний busybox щозавантаження.
- **`su: unknown user root`** — `post-fs-data.sh` NetHunter створює `su → busybox` до того, як Magisk змонтує свій `su`, а NetHunter Terminal губить `/product/bin` з `PATH`. Модуль перенаправляє `su` на Magisk `su` і не дає посиланню на busybox повернутися. (Баг з `PATH` — у застосунку, його треба повідомити апстріму.)
- **Вбудований Bluetooth** — `bluebinder` з NetHunter вміє лише старий HIDL `@1.0` HAL; у пристрою є лише AIDL `IBluetoothHci`. `nh-btbridge` — власний міст AIDL HAL ↔ `/dev/vhci`; Kali-шний `bluebinder` замінено обгорткою, яка його запускає.
- **Custom Commands монітора wlan0** — стандартні «Start/Stop wlan0 monitor mode» не ставлять канал і не чекають вимкнення Wi-Fi (мертвий монітор на цьому чипі); переписані на `nh-wlan`.

---

## Збірка з джерел

Потрібні Docker (образ x86_64 працює через емуляцію на Apple Silicon) і `adb`. Збірка підтягує точні вихідники/артефакти ядра Google і сама звіряє KMI.

```bash
# 1. стокові вхідні дані (тут не поширюються — беруться з вашого пристрою + Google CI)
adb shell 'zcat /proc/config.gz' > stock/device.config
#    розпакуйте vendor_dlkm.img вашої прошивки у fw/logical/vendor_dlkm (fsck.erofs --extract)

# 2. сторонні драйвери і бібліотеки пристрою для лінкування (у репозиторії не зберігаються)
tools/fetch-oot.sh          # клонує morrownr/8812au, 8814au, aircrack-ng/rtl8188eus (піновані)
tools/fetch-devlibs.sh      # adb pull libbinder_ndk.so тощо для лінкування nh-btbridge

# 3. повна відтворювана збірка + усі перевірки сумісності + готовий zip
tools/build-all.sh 15756704 f0987337fa351d7e303b071df533fd4c1c194687
#                  ^ab-збірка ^коміт kernel/common (з `adb shell uname -r`)
```

Після оновлення Nothing OS повторіть крок 1 з новим `vendor_dlkm`/конфігом і `tools/build-all.sh <новий ab> <новий sha>`.

Драйвер вбудованого Wi-Fi збирається окремо (йому потрібні джерела ядра Nothing, а не Google): [wlan-inject/README.uk.md](wlan-inject/README.uk.md).

### Структура

```
module/nethunter-kmods/   Модуль Magisk/KernelSU: скрипти-утиліти (.ko/прошивки збираються, не комітяться)
module/nethunter-wlan-inject/  другий модуль: підміняє драйвер вбудованого Wi-Fi після старту (.ko збирається, не комітиться)
wlan-inject/              як зібрати цей драйвер: дельта апстріму, паритет зі стоковою збіркою, патчі injection, перевірки
btbridge/nh-btbridge.c    Міст AIDL Bluetooth HAL ↔ /dev/vhci  (+ build.sh)
patches/                  5 мінімальних патчів драйверів, по одному файлу, кожен пояснено
config/                   фрагмент конфігу ядра: що додано і що неможливо та чому
oot/                      модуль minstrel_ht + наш клей для out-of-tree Realtek-драйверів
tools/                    build-all.sh, fetch-*.sh, check_gki_access.py (симулятор завантаження GKI), kocrc.py, pack-wlan-inject.sh
docker/                   образ збірки clang-18 arm64
```

---

## Видалення

Magisk → *Modules* → видалити `nethunter-kmods`, `nethunter-wlan-inject` (і NetHunter) → Reboot, потім прошити стоковий `init_boot.img`. Заблокувати завантажувач (стирає дані, лише стокова прошивка): `fastboot flashing lock`.

## Ліцензія

- Скрипти, патчі, `nh-btbridge.c` і обгортка minstrel — **GPL-2.0** (похідні від ядра), див. [LICENSE](LICENSE).
- Репозиторій **не** містить: пропрієтарних образів Nothing, бінарників ядра Google, системних бібліотек пристрою, жодних прошивкових блобів. Збірка підтягує їх з першоджерел; `fetch-devlibs.sh` бере бібліотеки для лінкування з вашого ж пристрою.
- Release-zip містить прошивки з [linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware) під їхніми вендорськими ліцензіями (див. `WHENCE` того проєкту).
- `wlan-inject/patches/` змінює джерела Qualcomm qcacld-3.0 / qca-wifi-host-cmn / fw-api і зберігає їхню ліцензію ISC; монітор та injection — робота [Loukious](https://github.com/Loukious/vendor_qcom_opensource_wlan), дельта версій — з CodeLinaro. Походження кожного файла: [wlan-inject/README.uk.md](wlan-inject/README.uk.md).
- Out-of-tree Wi-Fi драйвери — окремі проєкти: [morrownr/8812au-20210820](https://github.com/morrownr/8812au-20210820), [morrownr/8814au](https://github.com/morrownr/8814au), [aircrack-ng/rtl8188eus](https://github.com/aircrack-ng/rtl8188eus).

## Дисклеймер

Надається як є, для дослідження і авторизованого тестування систем і мереж, якими ви володієте або маєте дозвіл тестувати. Розблокування завантажувача і зміна оточення ядра можуть вивести пристрій з ладу, позбавити гарантії і зламати гарантії безпеки; ви робите це на власний ризик. Автори не відповідають за шкоду чи зловживання.
