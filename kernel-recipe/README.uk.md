# Кастомне ядро NetHunter для Nothing Phone (3) — рецепт

Мета: **другий варіант** поставки на стокову прошивку поряд із модулем `nethunter-kmods` —
власне boot-ядро, що додає функції, недосяжні модулю на стоковому ядрі
(через `CONFIG_MODULE_SIG_PROTECT`). Кінцева ціль — подати пристрій в офіційний NetHunter.

## Два варіанти поставки

- **A. Модуль на стоковому ядрі** — `nethunter-kmods` v1.3. Вже містить усе, що можливо без заміни ядра.
- **B. Власне ядро + той самий модуль** — ядро додає фічі нижче; модуль лишається (USB-драйвери, прошивки, вбудований Wi-Fi monitor+injection, `nh-*`).

## Що таке стокове ядро насправді

Ядро в `boot.img` прошивки **C5.0-260924-2115** — це **чистий Google GKI**, а не збірка Nothing:

```
Linux version 6.6.127-android15-8-gf0987337fa35-ab15756704-4k (kleaf@build-host)
  (Android clang 18.0.0, based on r510928) #1 SMP PREEMPT Tue Jun 30 2026
```

Google публікує артефакти цієї збірки на ci.android.com (build `15756704`, target `kernel_aarch64`):
маніфест із точним комітом, `vmlinux.symvers` (CRC усіх 9175 експортів), `abi_symbollist.raw`.
Тому збираємо **з того самого коміту ACK** і перевіряємо результат проти **еталонних CRC Google**.

| Що | Значення |
|---|---|
| ACK `kernel/common` | `f0987337fa351d7e303b071df533fd4c1c194687` (гілка `android15-6.6-2026-04`, 29.06.2026) |
| Конфіг | ikconfig зі стокового `fw/boot/boot.img` (7753 рядки) |
| Рядок версії | `6.6.127-android15-8-gf0987337fa35-ab15756704-4k` — мусить збігатися **точно** |

> Джерела Nothing (`NothingOSS/android_kernel_msm-6.6_nothing_sm8735`): гілка `sm8735/b/mr` — 6.6.127
> (ACK `2026-04-r3`, NOS 4.1), `sm8735/v/mr` — 6.6.57 (стартовий NOS 3.5). Для boot-ядра вони
> не потрібні: це GKI, а вендорні модулі лишаються стоковими. `b/mr` використовується для WLAN-драйвера.

## Які фічі додає ядро

Усе з офіційних сторінок «Configuring the Kernel» Kali NetHunter, чого бракує стоку і що можна додати,
не змінюючи KMI — модулями (`=m`), а System V IPC — вбудовано з невеликим патчем (див. нижче), тож
KMI лишається ідентичним збірці Google: усі 9175 стокових експортів з тими самими CRC (плюс нові з `extra-exports.txt`).

| Фіча | Конфіг | Перевірено |
|---|---|---|
| CAN ISO-TP / J1939 | `CAN_ISOTP`, `CAN_J1939` | ✅ передача на `vcan0` |
| USB CAN-адаптери Kvaser / EMS / ESD / UCAN | `CAN_KVASER_USB`, `CAN_EMS_USB`, `CAN_ESD_USB`, `CAN_UCAN` | 🟡 вантажаться |
| tc-фільтр за CAN-id | `NET_EMATCH_CANID` | ✅ `basic match canid(...)` |
| Bluetooth PAN (BNEP), BPA10x | `BT_BNEP` (+ фільтри), `BT_HCIBPA10X` | 🟡 вантажаться |
| USB-net RNDIS / QMI / MBIM / DM9601 / MCS7830 | `USB_NET_RNDIS_HOST/QMI_WWAN/CDC_MBIM/DM9601/MCS7830` (+ `USB_WDM`) | 🟡 вантажаться |
| RNDIS-гаджет (BadUSB-мережа) | `USB_CONFIGFS_RNDIS=y` (+ `USB_F_RNDIS=y`) | 🟡 вбудовано |
| NFC-зчитувачі PN533/PN532 (USB) | `NFC_PN533_USB` | 🟡 вантажаться |
| NFS клієнт і сервер | `NFS_FS` (`V2/V3/V4`), `NFSD` (`V4`) → sunrpc, lockd, grace, rpcsec_gss_krb5, dns_resolver | ✅ `nfs`/`nfs4`/`nfsd` у `/proc/filesystems` (монтування — ще ні) |
| Діагностика netlink-сокетів | `NETLINK_DIAG` | ✅ `ss -a -A netlink` |
| Примусове вивантаження модулів | `MODULE_FORCE_UNLOAD=y` | ✅ у конфігу запущеного ядра |
| System V IPC (PostgreSQL → база Metasploit) | `SYSVIPC=y` (+ `SYSVIPC_SYSCTL`, `SYSVIPC_COMPAT`, `IPC_NS`) і патч [`patches/0001-…`](patches/) | ✅ `ipcmk`, PostgreSQL 18, `msfconsole` + `db_connect`; ~97 тис. процесів із `SEM_UNDO` і shm |
| Старі USB Wi-Fi AR9170 / ZD1211 / Broadcom 4320 | драйвери — модулем з конвеєра (`config/nh-kernel-only.list`), ядро лишає їм експорти з [`extra-exports.txt`](extra-exports.txt) | 🟡 вантажаться |

Фрагмент — [`nethunter.config`](nethunter.config). Вбудована Wi-Fi-інжекція лишається в модулі.
Додаткові експорти — [`extra-exports.txt`](extra-exports.txt): функції vmlinux і модулів, які Google вирізає
(`TRIM_UNUSED_KSYMS`), а USB Wi-Fi-драйверам з модуля вони потрібні. Лише нові експорти: CRC стокових не змінюються.

### Звірка з офіційним списком NetHunter (106 опцій)

Зібрано зі сторінок kali.org/docs/nethunter/nethunter-kernel-*-config-* (General, Network/BT, Wi-Fi, SDR, USB, NFS, CAN):
- **вже є у стоку**: CAN core/raw/bcm/gw/dev/slcan/vcan, cdc-acm, rtl8150/8152, ftdi_sio, hci_uart, binder, devlink, vsock;
- **дає модуль `nethunter-kmods`**: USB Wi-Fi (Ralink rt2800/rt73/rt2500, ath9k_htc, mt7601u/mt76, rtl8187, rtl8xxxu, 88xxau), USB-BT (btusb, bfusb, bcm203x, ath3k, hci_vhci), CAN gs_usb/peak_usb/usb_8dev, ch341;
- **додано в ядро** — таблиця вище;
- **USB Wi-Fi, що лишились** — модулем, не в ядрі, бо `cfg80211`/`mac80211` на цьому телефоні вендорські (Qualcomm):
  zd1201, rtl8192cu, ath6kl працюють і на стоковому ядрі; carl9170, zd1211rw, rndis_wlan — лише з цим ядром
  (їм потрібні `usb_poison_anchored_urbs`, `usb_wait_anchor_empty_timeout`, `usbnet_pause_rx` та ін., див. [`extra-exports.txt`](extra-exports.txt));
- **з патчем**: `SYSVIPC` — просте `=y` змінює `task_struct` і ламає KMI, тому поля кладуться в запасні слоти (див. нижче);
- **свідомо ні**: DVB/SDR-драйвери ядра (userspace librtlsdr/hackrf/airspy уже працює, а драйвер ядра забирав би донгли), CAN-контролери SoC/SPI/PCI (такого заліза в телефоні немає), HLCAN (поза деревом ядра), `USB_SERIAL_CONSOLE`/`GENERIC` (потребують перезбірки гуглівського usbserial), формати образу й `LOCALVERSION` (до GKI не застосовні).

### System V IPC без зміни KMI

`CONFIG_SYSVIPC` додає в `struct task_struct` поля `sysvsem` (вказівник) і `sysvshm` (`list_head`) одразу після
`nameidata`. Усе, що далі, зсувається на 24 байти, і genksyms дає інший CRC для 5909 з 9175 експортів vmlinux:
не завантажився б жоден із 748 модулів `vendor_dlkm`/`system_dlkm`/`vendor_boot` (виміряно).

Патч [`patches/0001-sched-keep-SysV-IPC-state-in-KABI-reserved-slots.patch`](patches/) кладе ці поля в запасні слоти
`ANDROID_KABI_RESERVE(6)` і `(7, 8)`, які Google лишає в `task_struct` саме для таких доповнень (у цьому коміті
зайнятий лише слот 1, `dmabuf_info`). Для genksyms (`__GENKSYMS__`) структура лишається тією самою, тож CRC не змінюються; у
зібраному ядрі розмір і всі зміщення `task_struct` збігаються з vmlinux Google (pahole по всіх 10698 типах). Той
самий прийом використовує Halium для GKI-ядер. Звернень модулів Qualcomm і Google до
слотів 6-8 через `current` немає (сканування 748 модулів); звернення через інші вказівники на `task_struct` статично
до кінця не відсіяні. Модуль, який писав би туди, зіпсував би стан SysV і ламав би ядро при завершенні процесів; у
тесті ~100 тис. процесів пройшли без помилок.

При переході на новіший коміт ACK треба перевірити, чи Google не зайняв слоти 6-8 (`ANDROID_KABI_USE` у
`include/linux/sched.h`): тоді патч не накладеться, і поля треба перенести в інші вільні слоти.
`android-base.config` формально вимагає `SYSVIPC` вимкненим (тест VTS), але на завантаження Android це не впливає.

### Чому вимкнено `CONFIG_MODULE_SIG_PROTECT`

Наше ядро має власний ключ підпису. Модулі Google у `system_dlkm` для нього — «ключ недоступний»
(`-ENOKEY`), тобто непідписані. З увімкненим `SIG_PROTECT` вони втратили б доступ до GKI-захищених
символів, і Bluetooth / CAN / usbnet / zram не завантажились би. Без нього вони вантажаться
(ядро позначається taint `E`). Перевірено в коді ACK: `kernel/module/signing.c`; lockdown-LSM у цьому
конфігу не зібраний, тож інших перешкод для непідписаних модулів немає; `gki_module.c` нічого
не експортує, тож KMI це не змінює. Ціна — ядро не застосовує GKI-захист символів (для NetHunter прийнятно).

## Збірка

```bash
# 1. еталонні артефакти й стоковий конфіг (у kernel/ — gitignored)
mkdir -p kernel/ref-ab15756704 && cd kernel/ref-ab15756704
for f in manifest_15756704.xml vmlinux.symvers abi_symbollist.raw System.map; do
  curl -sLO "https://ci.android.com/builds/submitted/15756704/kernel_aarch64/latest/raw/$f"; done
#    stock.config — scripts/extract-ikconfig із ядра в fw/boot/boot.img (blob з offset 4096)
cd ../..

# 2. точний коміт ACK у регістрозалежний Docker-том (на APFS ламаються xt_DSCP.c/xt_dscp.c)
docker volume create nh-gki-src
docker run --rm -v nh-gki-src:/src nh-kbuild bash -c 'cd /src && git init -q . &&
  git fetch --depth 1 https://android.googlesource.com/kernel/common f0987337fa351d7e303b071df533fd4c1c194687 &&
  git checkout -q FETCH_HEAD'

# 3. конфіг → збірка → перевірка KMI
docker run --rm -v nh-gki-src:/src -v nh-gki-out:/out \
  -v "$PWD/kernel-recipe":/r:ro -v "$PWD/kernel/ref-ab15756704":/ref:ro \
  nh-kbuild bash /r/build-gki.sh all
```

[`build-gki.sh`](build-gki.sh) стадіями:
- **config** — накладає [`patches/*.patch`](patches/) на чисте дерево (`/src` має бути або точним комітом ACK, або рівно
  цим комітом + цими патчами — інакше збірка зупиняється); стоковий конфіг + фрагмент + `SIG_PROTECT` off;
  `extra-exports.txt` дописується до `abi_symbollist.raw`; друкує **кожну** відмінність від стоку
  (зараз 46: опції фрагмента, їхні підопції й автозалежності — sunrpc/lockd/grace/`NET_HANDSHAKE`…, `SYSVIPC_*`/`IPC_NS`, `SIG_PROTECT`)
  і звіряє рядок версії. Рядок відтворено як у Kleaf: файл `localversion` в O= + `GIT_DIR` вимкнено
  для `make` (тоді `scripts/setlocalversion` не додає `-g<sha>`/`-dirty`).
- **build** — `Image` + модулі (нативний arm64, clang 18.1.3; стоковий r510928 — те саме покоління LLVM 18).
- **check** — [`kmi-check.py`](kmi-check.py): кожен із 9175 стокових експортів мусить мати **той самий CRC**.

Середовище: образ `nh-kbuild` (Ubuntu 24.04 arm64, clang/lld 18, `pahole` 1.25 = стоковий `PAHOLE_VERSION=125`).

## Статус

- [x] Стокове ядро ідентифіковано (Google GKI ab15756704), еталонні артефакти Google отримано.
- [x] Точний коміт ACK склоновано; конфіг = сток + 12 очікуваних змін; рядок версії збігається.
- [x] Збірка (10 хв, нативний arm64) + **KMI IDENTICAL**: усі 9175 стокових експортів, ті самі CRC, 0 розбіжностей
      (+3 зайві експорти для нових USB-net/BNEP модулів — стоку не заважають).
- [x] 62 модулі `nethunter-kmods`: 2712 імпортів звірено з нашою збіркою, 0 розбіжностей CRC.
- [x] `boot.img` ([`make-bootimg.sh`](make-bootimg.sh)): стоковий заголовок v4 + наш `Image`, AVB-футер зі стоковими
      параметрами (rollback index, props), тестовий ключ AOSP. Результат: `kernel/out-gki/nethunter-boot.img`.
- [x] **Тест наживо без запису** (`fastboot boot`, 14.11.2026) — бутлоадер Nothing це підтримує (потрібен свіжий
      `fastboot` із SDK platform-tools; старий 31.x на macOS пристрою не бачить). Результат на нашому ядрі:
      завантажено ті самі модулі, що й на стоку (575 vs 576 — різниця лише тимчасова, на момент підміни WLAN-драйвера);
      Wi-Fi (наш injection-драйвер через `nethunter-kmods`) і LTE на обох SIM працюють; Google-модулі з `system_dlkm`
      вантажаться з taint `E` як очікувалось; **ISO-TP і J1939 функціонально перевірено на `vcan0`** (Python `AF_CAN`).
- [x] Пакування варіанта B (модуль v5): `tools/add-gki-extras.sh` кладе в `module/nethunter-kmods/gki/` 7 нових `.ko`,
      наші `can.ko`/`can-raw.ko`/`cdc_ncm.ko` і `kernel.version` (точний `/proc/version` збірки — за ним модуль упізнає
      це ядро, бо `uname -r` стоковий). `gki-boot.sh` + `nh-gki` вантажать їх після старту лише на цьому ядрі, з відкатом
      на гуглівський батьківський модуль і маркером від циклу. Перевірено наживо: unload/load, гард стокового ядра
      (нічого не чіпає), запобіжник обірваного завантаження.
- [x] **Цикл перезавантажень із встановленим модулем v5** (14.11.2026):
      стокове ядро — `nh-kmod` 62/0, Wi-Fi injection «Swap OK», `gki`: «Stock kernel … stay idle», гуглівський `cdc_ncm`
      не зачеплено, LTE; ядро NetHunter (`fastboot boot`) — `gki-boot.sh` **сам** завантажив усі 7 функцій із нашими
      `can`/`cdc_ncm`, 584 модулі (= 576 стокових + 8), **0 відсутніх**, Wi-Fi injection, LTE на обох SIM.
      Рядки dmesg `sram -16`, `cpuss-sleep-stats -22`, `regulatory.db` є й на свіжому старті стоку — не від ядра.
- [x] **Розширений набір за офіційним списком NetHunter (модуль v6)**: 29 нових модулів + наші `can`/`cdc_ncm`/`nfc`.
      Пакування тепер виводиться зі збірки, без ручних списків: [`gki-deps-check.py`](gki-deps-check.py) статично
      розв'язує імпорти кожного нового модуля проти **справжніх** гуглівських `.ko` з телефона (`adb pull
      /system_dlkm/lib/modules/`) і знаходить урізані батьківські (так знайдено `nfc.ko` для PN533 — ще до тесту);
      [`gki-stage.py`](gki-stage.py) пише `gki/load.order` (порядок за `depends` з `.modinfo`); `nh-gki` виконує його,
      утримувачів батьківського модуля визначає з `/sys/module/<m>/holders`. Наживо (`fastboot boot`): **32 з 32**
      піднялись самі при старті, 605 модулів, 0 стокових відсутні, Wi-Fi injection, LTE; функціонально — ISO-TP, J1939,
      `em_canid`, `netlink_diag`, файлові системи NFS.
- [x] **Ядро без Magisk-модуля** (модуль вимкнено через `disable`, `fastboot boot`): старт нормальний, стоковий драйвер Wi-Fi
      і LTE працюють, помилок модулів немає; набір модулів = стокова базова лінія мінус рівно 62 драйвери самого модуля
      (0 непояснених відсутніх, 0 зайвих). Тобто без модуля ядро поводиться як стокове — бутлупу немає; лише нові
      функції недоступні, бо їхні `.ko` постачає модуль.
- [x] **Старі USB Wi-Fi (модуль v7, 14.11.2026).** zd1201, rtl8192cu, ath6kl — у стоковій частині модуля
      (`loaded=69 failed=0` на стоку при старті). carl9170, zd1211rw, rndis_wlan — лише з цим ядром: їх збирає конвеєр
      модулів (`config/nh-kernel-only.list`), `add-gki-extras.sh` кладе в `gki/`, а ядро лишає їм експорти з
      [`extra-exports.txt`](extra-exports.txt) (KMI так само IDENTICAL). rndis_wlan потребує нашого `usbnet.ko` (четвертий
      батьківський модуль). Перевірка на цьому ядрі — `tools/check_nh_kernel_access.py`: імена + CRC для `gki/`, стокової
      частини і гуглівських модулів поверх наших батьківських (114/114). Наживо (`fastboot boot`): 615 модулів = 583 стокових
      + 32, **36 з 36** функцій ядра піднялись самі, `usbnet` підмінено з повним ланцюгом утримувачів (cdc_ether ← cdc_ncm,
      r8153_ecm), гуглівські повернуто; `nh-gki unload`/`load` — туди й назад; Wi-Fi injection, LTE на обох SIM.
      Знайдено й виправлено на пристрої: Magisk запускає скрипти в BusyBox standalone, де `modprobe` — BusyBox без `-d`,
      тож гуглівські модулі повертаються через `/system/bin/toolbox modprobe`.
- [ ] Наживо з залізом: RNDIS/QMI/MBIM/DM9601/MCS7830 (USB-модем/Ethernet), BNEP (BT PAN), BPA10x, Kvaser/EMS/ESD/UCAN,
      PN533, RNDIS-гаджет, USB Wi-Fi carl9170/zd1211rw/rndis_wlan; NFS — монтування (потрібні `nfs-common`/`nfs-kernel-server` у Kali).
- [x] **Постійна прошивка** (14.11.2026): `fastboot flash boot_b` (поточний слот), вміст розділу = образ побайтово,
      `verifiedbootstate` orange. Старт із розділу і після звичайного `reboot`: 615 модулів, 0 стокових відсутні,
      модуль 69/69 + 36/36, Wi-Fi injection, LTE на обох SIM. Відкат — стоковий `boot.img` у той самий слот.
- [x] **System V IPC (модуль v8, 15.11.2026)** — `SYSVIPC=y` + патч [`patches/0001-…`](patches/) (поля SysV у запасних
      KABI-слотах `task_struct`). KMI IDENTICAL (9175/9175), `vmlinux.symvers` побайтово = збірка 14.11, розкладка всіх
      10678 структур = vmlinux Google; без патча — 5909 розбіжностей CRC. Наживо (`fastboot boot`): 615 модулів, 0 відсутніх,
      модуль v8 сам завантажив 36/36, Wi-Fi injection, LTE на обох SIM, камера; у chroot `Seccomp: 0`, `ipcmk`, `SEM_UNDO`,
      PostgreSQL 18.6, `msfconsole` + `db_connect`; навантаження ~97 тис. процесів без помилок.
      Прошито постійно (`fastboot flash boot_b`, sha256 `333f4e9e…`, вміст розділу = образ побайтово): старт із розділу і
      після звичайного `reboot` — 615 модулів, 0 відсутніх, 36/36, SysV, Wi-Fi injection, LTE. Попередній образ (14.11):
      `kernel/out-gki/nethunter-boot.v7-20261114.img`.
- [ ] Апстрім у NetHunter.

### Знахідка тесту: обрізані експорти в модулях Google

`can_j1939` і `cdc_mbim` спершу не вантажились: `Unknown symbol can_sock_destruct` / `cdc_ncm_bind_common`, …
Google збирає свої `can.ko` і `cdc_ncm.ko` з `TRIM_UNUSED_KSYMS`; у стоку j1939 і mbim немає, тож ці експорти вирізано.
KMI-перевірка vmlinux цього не бачить — це експорти **між модулями**. Рішення: возити наші `can.ko` (+`can-raw.ko`) і
`cdc_ncm.ko` з цієї ж збірки (у ній експорти збережені) і вантажити їх замість гуглівських. Гуглівський `cdc_ncm`
вантажиться при старті, але не використовується (refcount 0) — `rmmod` проходить; перевірено наживо.
