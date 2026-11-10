#!/usr/bin/env bash
# ==============================================================
#  server.sh — первичная настройка сервера (Ubuntu / Debian)
# ==============================================================
set -o pipefail

LOG="/var/log/server-setup.log"

# --- Полностью неинтерактивный apt: никаких диалогов needrestart/debconf,
#     никаких «съезжающих» прогресс-баров dpkg ---
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
APT_OPTS=(-y -q
  -o Dpkg::Progress-Fancy=0
  -o APT::Color=0
  -o DPkg::Lock::Timeout=120
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold)

OOKLA_KEY="/etc/apt/keyrings/ookla_speedtest-cli-archive-keyring.gpg"
OOKLA_LIST="/etc/apt/sources.list.d/ookla_speedtest-cli.list"
OOKLA_TGZ_VER="1.2.0"

# --- Цвета (только если вывод в терминал) ---
if [[ -t 1 ]]; then
  IS_TTY=1
  BOLD=$'\e[1m'; DIM=$'\e[2m'; NC=$'\e[0m'
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; CYAN=$'\e[36m'
else
  IS_TTY=0
  BOLD=""; DIM=""; NC=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""
fi

# --- Восстановление терминала при любом выходе ---
CURRENT_PID=""
restore_terminal() {
  if [[ $IS_TTY -eq 1 ]]; then
    printf '\e[r'                          # сброс области прокрутки
    printf '\e[?25h'                       # показать курсор
    stty sane </dev/tty 2>/dev/null || true  # вернуть эхо ввода
  fi
}
on_interrupt() {
  [[ -n $CURRENT_PID ]] && kill "$CURRENT_PID" 2>/dev/null
  printf '\n\n  %s✗ Прервано пользователем%s\n' "$RED" "$NC"
  exit 130
}
trap restore_terminal EXIT
trap on_interrupt INT TERM

# --- Учёт результатов ---
TOTAL_STEPS=4
CUR_STEP=0
RESULTS=()
FAILS=0

step() {
  CUR_STEP=$((CUR_STEP + 1))
  printf '\n%s%s[%d/%d]%s %s%s%s\n' "$BOLD" "$BLUE" "$CUR_STEP" "$TOTAL_STEPS" "$NC" "$BOLD" "$1" "$NC"
}

skip() {
  printf '  %s○ %s%s\n' "$DIM" "$1" "$NC"
  RESULTS+=("skip|$1")
}

warn() {
  printf '  %s! %s%s\n' "$YELLOW" "$1" "$NC"
  RESULTS+=("warn|$1")
}

# run_task "Описание" команда [аргументы...]
# Вывод команды уходит в лог, на экране — спиннер и итог.
run_task() {
  local msg="$1"; shift
  local start=$SECONDS
  printf '\n===== %s =====\n$ %s\n' "$msg" "$*" >>"$LOG"

  "$@" >>"$LOG" 2>&1 </dev/null &
  CURRENT_PID=$!

  if [[ $IS_TTY -eq 1 ]]; then
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0
    printf '\e[?25l'
    while kill -0 "$CURRENT_PID" 2>/dev/null; do
      printf '\r  %s%s%s %s %s%ds%s\e[K' \
        "$CYAN" "${frames[i++ % ${#frames[@]}]}" "$NC" "$msg" "$DIM" $((SECONDS - start)) "$NC"
      sleep 0.1
    done
    printf '\e[?25h'
  fi

  wait "$CURRENT_PID"; local rc=$?
  CURRENT_PID=""
  local t=$((SECONDS - start))

  if (( rc == 0 )); then
    printf '\r  %s✓%s %s %s%ds%s\e[K\n' "$GREEN" "$NC" "$msg" "$DIM" "$t" "$NC"
    RESULTS+=("ok|$msg")
  else
    printf '\r  %s✗%s %s %s(код %d)%s\e[K\n' "$RED" "$NC" "$msg" "$DIM" "$rc" "$NC"
    tail -n 5 "$LOG" | sed "s/^/      ${DIM}│${NC} /"
    RESULTS+=("fail|$msg")
    FAILS=$((FAILS + 1))
  fi
  return $rc
}

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

pkg_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

install_pkg() {
  local pkg="$1"
  if pkg_installed "$pkg"; then
    skip "$pkg — уже установлен"
    return 0
  fi
  run_task "Установка $pkg" apt-get install "${APT_OPTS[@]}" "$pkg"
}

# --- Speedtest ---
setup_speedtest_repo() {
  install -d -m 0755 /etc/apt/keyrings || return 1
  curl -fsSL --max-time 30 --retry 3 https://packagecloud.io/ookla/speedtest-cli/gpgkey \
    | gpg --dearmor --yes -o "$OOKLA_KEY" || return 1
  chmod 0644 "$OOKLA_KEY"
  # У Ookla нет сборок под noble и новее — используем jammy (пакет статический, работает везде)
  echo "deb [signed-by=$OOKLA_KEY] https://packagecloud.io/ookla/speedtest-cli/ubuntu/ jammy main" >"$OOKLA_LIST"
  apt-get update -q -o DPkg::Lock::Timeout=120
}

install_speedtest_tarball() {
  local arch tmp rc
  case "$(uname -m)" in
    x86_64)        arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    armv7l)        arch=armhf ;;
    armv6l)        arch=armel ;;
    i?86)          arch=i386 ;;
    *) echo "Неподдерживаемая архитектура: $(uname -m)"; return 1 ;;
  esac
  tmp=$(mktemp -d)
  curl -fsSL --max-time 60 --retry 3 -o "$tmp/st.tgz" \
       "https://install.speedtest.net/app/cli/ookla-speedtest-${OOKLA_TGZ_VER}-linux-${arch}.tgz" \
    && tar -xzf "$tmp/st.tgz" -C "$tmp" \
    && install -m 0755 "$tmp/speedtest" /usr/local/bin/speedtest
  rc=$?
  rm -rf "$tmp"
  return $rc
}

# ==============================================================
#  Проверки
# ==============================================================
if [[ $EUID -ne 0 ]]; then
  printf '%s[ERROR]%s Запустите скрипт с правами root: %ssudo %s%s\n' "$RED" "$NC" "$BOLD" "$0" "$NC"
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  printf '%s[ERROR]%s Скрипт рассчитан на Ubuntu/Debian (apt-get не найден)\n' "$RED" "$NC"
  exit 1
fi

: >"$LOG" 2>/dev/null || LOG="/tmp/server-setup.log"
. /etc/os-release 2>/dev/null

printf '\n%s%s╭──────────────────────────────────────────╮%s\n' "$BOLD" "$CYAN" "$NC"
printf   '%s%s│        Настройка сервера                 │%s\n' "$BOLD" "$CYAN" "$NC"
printf   '%s%s╰──────────────────────────────────────────╯%s\n' "$BOLD" "$CYAN" "$NC"
printf '  %sСистема:%s %s\n' "$DIM" "$NC" "${PRETTY_NAME:-unknown}"
printf '  %sХост:%s    %s\n' "$DIM" "$NC" "$(hostname)"
printf '  %sЛог:%s     %s\n' "$DIM" "$NC" "$LOG"

# ==============================================================
#  1. Обновление системы
# ==============================================================
step "Обновление системы"
run_task "Обновление списка пакетов" apt-get update -q -o DPkg::Lock::Timeout=120 \
  && run_task "Обновление установленных пакетов" apt-get upgrade "${APT_OPTS[@]}"

# ==============================================================
#  2. Базовые утилиты
# ==============================================================
step "Базовые утилиты"
for pkg in ca-certificates gnupg wget curl nano htop vnstat; do
  install_pkg "$pkg"
done

if pkg_installed vnstat && command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet vnstat; then
    skip "служба vnstat — уже запущена"
  else
    run_task "Запуск службы vnstat" systemctl enable --now vnstat
  fi
fi

# ==============================================================
#  3. neofetch (или fastfetch на новых системах)
# ==============================================================
step "Информация о системе"
if pkg_installed neofetch || pkg_installed fastfetch; then
  skip "neofetch/fastfetch — уже установлен"
elif pkg_available neofetch; then
  install_pkg neofetch
elif pkg_available fastfetch; then
  warn "neofetch нет в репозитории — ставим fastfetch"
  install_pkg fastfetch
else
  warn "neofetch и fastfetch недоступны в репозиториях — пропущено"
fi

# ==============================================================
#  4. Speedtest (Ookla)
# ==============================================================
step "Speedtest (Ookla)"
if pkg_installed speedtest || [[ -x /usr/local/bin/speedtest ]]; then
  skip "speedtest — уже установлен"
else
  # Пакет speedtest-cli из штатного репозитория конфликтует с пакетом Ookla
  if pkg_installed speedtest-cli; then
    run_task "Удаление конфликтующего speedtest-cli" apt-get remove "${APT_OPTS[@]}" speedtest-cli
  fi

  if run_task "Подключение репозитория Ookla" setup_speedtest_repo \
     && run_task "Установка speedtest" apt-get install "${APT_OPTS[@]}" speedtest; then
    :
  else
    warn "Через apt не вышло — пробуем бинарник с сайта Ookla"
    rm -f "$OOKLA_LIST"
    apt-get update -q >>"$LOG" 2>&1
    run_task "Установка speedtest из архива" install_speedtest_tarball
  fi
fi

# ==============================================================
#  Итог
# ==============================================================
printf '\n%s%s╭──────────────────────────────────────────╮%s\n' "$BOLD" "$CYAN" "$NC"
if (( FAILS == 0 )); then
  printf '%s%s│%s  %s✓ Готово, ошибок нет%s                    %s%s│%s\n' "$BOLD" "$CYAN" "$NC" "$GREEN$BOLD" "$NC" "$BOLD" "$CYAN" "$NC"
else
  printf '%s%s│%s  %s✗ Завершено с ошибками: %-3d%s             %s%s│%s\n' "$BOLD" "$CYAN" "$NC" "$RED$BOLD" "$FAILS" "$NC" "$BOLD" "$CYAN" "$NC"
fi
printf '%s%s╰──────────────────────────────────────────╯%s\n' "$BOLD" "$CYAN" "$NC"

for r in "${RESULTS[@]}"; do
  status="${r%%|*}"; text="${r#*|}"
  case "$status" in
    ok)   printf '  %s✓%s %s\n' "$GREEN" "$NC" "$text" ;;
    fail) printf '  %s✗%s %s\n' "$RED" "$NC" "$text" ;;
    warn) printf '  %s!%s %s\n' "$YELLOW" "$NC" "$text" ;;
    skip) printf '  %s○ %s%s\n' "$DIM" "$text" "$NC" ;;
  esac
done

printf '\n  %sПолный лог:%s %s\n' "$DIM" "$NC" "$LOG"
if command -v speedtest >/dev/null 2>&1; then
  printf '  %sПервый запуск speedtest:%s speedtest --accept-license --accept-gdpr\n' "$DIM" "$NC"
fi
if [[ -f /var/run/reboot-required ]]; then
  printf '  %s! Требуется перезагрузка:%s sudo reboot\n' "$YELLOW" "$NC"
fi
echo

(( FAILS == 0 ))
