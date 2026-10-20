#!/bin/sh
# Клонує сторонні out-of-tree Wi-Fi драйвери (їх ми не зберігаємо в репозиторії —
# це окремі GPL-проєкти). Запускати перед tools/build-all.sh.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)/oot"
clone() { # url dir commit
  d="$HERE/$2"
  if [ -d "$d/.git" ]; then echo "exists: $2"; return; fi
  git clone --depth 50 "$1" "$d"
  git -C "$d" checkout -q "$3"
  echo "fetched: $2 @ $3"
}
clone https://github.com/morrownr/8812au-20210820.git 8812au-20210820 4722250
clone https://github.com/morrownr/8814au.git           8814au          1840d7b
clone https://github.com/aircrack-ng/rtl8188eus.git    rtl8188eus      af3bf00
