#!/usr/bin/env bash

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] Запустите скрипт с правами root (sudo ./setup.sh)${NC}"
  exit 1
fi

log_step() {
    echo -e "\n${BLUE}===> [Шаг $1/7] $2...${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 1. Обновление системы
log_step "1" "Обновление списка пакетов и системы"
apt update && apt upgrade -y
log_success "Система успешно обновлена"

# 2. Установка wget
log_step "2" "Установка wget"
apt install wget -y
log_success "wget установлен"

# 3. Установка curl
log_step "3" "Установка curl"
apt install curl -y
log_success "curl установлен"

# 4. Установка nano
log_step "4" "Установка nano"
apt install nano -y
log_success "nano установлен"

# 5. Установка vnstat
log_step "5" "Установка vnstat"
apt install vnstat -y
log_success "vnstat установлен"

# 6. Установка neofetch
log_step "6" "Установка neofetch"
apt install neofetch -y
log_success "neofetch установлен"

# 7. Настройка и установка speedtest
log_step "7" "Подключение репозитория и установка Speedtest"

OOKLA_SCRIPT_URL="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
OOKLA_LIST_FILE="/etc/apt/sources.list.d/ookla_speedtest-cli.list"

# Попытка запустить скрипт с таймаутом 15 секунд (прерывает, если зависнет)
run_speedtest_repo_script() {
    timeout 15s bash -c "curl -s $OOKLA_SCRIPT_URL | bash"
}

echo "Добавление репозитория Ookla (с защитой от зависания)..."
if ! run_speedtest_repo_script; then
    echo -e "${RED}Первичная попытка зависла или завершилась с ошибкой. Перезапускаем...${NC}"
    run_speedtest_repo_script
fi

# Замена noble на jammy в файле источников
if [ -f "$OOKLA_LIST_FILE" ]; then
    echo "Замена 'noble' на 'jammy' в $OOKLA_LIST_FILE..."
    sed -i 's/noble/jammy/g' "$OOKLA_LIST_FILE"
else
    echo -e "${RED}Файл репозитория не найден! Создаем вручную...${NC}"
    echo "deb [signed-by=/etc/apt/keyrings/ookla_speedtest-cli-archive-keyring.gpg] https://packagecloud.io/ookla/speedtest-cli/ubuntu/ jammy main" > "$OOKLA_LIST_FILE"
fi

apt update
apt-get install speedtest -y
log_success "Speedtest успешно установлен"

# Финальный отчет
echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}   Установка и настройка завершена!       ${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "Выполненные шаги:"
echo -e " 1. [✓] Обновлена система (apt update && upgrade)"
echo -e " 2. [✓] Установлен wget"
echo -e " 3. [✓] Установлен curl"
echo -e " 4. [✓] Установлен nano"
echo -e " 5. [✓] Установлен vnstat"
echo -e " 6. [✓] Установлен neofetch"
echo -e " 7. [✓] Заменен дистрибутив 'noble' -> 'jammy' и установлен speedtest"
echo -e "${GREEN}===========================================${NC}\n"
