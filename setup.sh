#!/bin/bash

# ======================================
# 🎨 ЦВЕТОВАЯ СХЕМА
# ======================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

INSTALLED=()
SKIPPED=()
ACTIONS=()

# ======================================
# 📦 ОБНОВЛЕНИЕ СИСТЕМЫ
# ======================================
echo -e "${BLUE}${BOLD}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║    Обновление системы...              ║${NC}"
echo -e "${BLUE}${BOLD}╚═══════════════════════════════════════╝${NC}"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
sudo apt update && sudo apt upgrade -y
ACTIONS+=("Обновление системы")

# ======================================
# 🛠️  УСТАНОВКА БАЗОВЫХ ПАКЕТОВ
# ======================================
PACKAGES=(curl nano htop wget vnstat software-properties-common)
echo -e "\n${BLUE}${BOLD}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║    Проверка пакетов...                ║${NC}"
echo -e "${BLUE}${BOLD}╚═══════════════════════════════════════╝${NC}"

for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $pkg уже установлен"
        SKIPPED+=("$pkg")
    else
        echo -e "${YELLOW}⏳${NC} Устанавливаем $pkg..."
        sudo apt install -y "$pkg"
        INSTALLED+=("$pkg")
    fi
done
ACTIONS+=("Проверка и установка утилит: curl, nano, htop, wget, vnstat")

# ======================================
# 🐍 УСТАНОВКА PYTHON 3.11
# ======================================
echo -e "\n${BLUE}${BOLD}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║    🐍 Установка Python                ║${NC}"
echo -e "${BLUE}${BOLD}╚═══════════════════════════════════════╝${NC}"

if command -v python3.11 &>/dev/null; then
    echo -e "${GREEN}✓${NC} Python 3.11 уже установлен"
    SKIPPED+=("Python 3.11")
else
    echo -e "${CYAN}Выберите версию Python для установки:${NC}"
    echo -e "  ${YELLOW}1)${NC} Python 3.11"
    echo -e "  ${YELLOW}2)${NC} Пропустить установку Python"
    read -p "Ваш выбор [1/2]: " python_choice
    
    if [[ "$python_choice" == "1" ]]; then
        echo -e "${YELLOW}⏳${NC} Добавляем репозиторий deadsnakes..."
        sudo add-apt-repository ppa:deadsnakes/ppa -y
        sudo apt update
        echo -e "${YELLOW}⏳${NC} Устанавливаем Python 3.11..."
        sudo apt install -y python3.11 python3.11-venv python3.11-dev
        INSTALLED+=("Python 3.11")
        ACTIONS+=("Установка Python 3.11")
        echo -e "${GREEN}✓${NC} Python 3.11 успешно установлен"
    else
        echo -e "${YELLOW}⊘${NC} Пропускаем установку Python"
        SKIPPED+=("Python 3.11")
    fi
fi

# ======================================
# 🚀 УСТАНОВКА SPEEDTEST
# ======================================
if ! command -v speedtest &>/dev/null; then
    echo -e "\n${YELLOW}⏳${NC} Устанавливаем Speedtest..."
    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
    sudo apt-get install -y speedtest
    INSTALLED+=("speedtest")
    ACTIONS+=("Установка Speedtest")
else
    echo -e "${GREEN}✓${NC} Speedtest уже установлен"
    SKIPPED+=("speedtest")
fi

# ======================================
# 🔐 НАСТРОЙКА SSH
# ======================================
echo -e "\n${BLUE}${BOLD}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║    🔐 Настройка SSH                   ║${NC}"
echo -e "${BLUE}${BOLD}╚═══════════════════════════════════════╝${NC}"

mkdir -p ~/.ssh
chmod 700 ~/.ssh

PUBKEY_FILE=$(ls *.pub 2>/dev/null | head -n 1)

if [[ -n "$PUBKEY_FILE" ]]; then
    echo -e "${YELLOW}🔍${NC} Найден публичный ключ: $PUBKEY_FILE"
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    cat "$PUBKEY_FILE" >> ~/.ssh/authorized_keys
    echo -e "${GREEN}✓${NC} Публичный ключ добавлен в authorized_keys"
    SETUP_SSH=true
elif [[ -z "$PUBKEY_FILE" ]]; then
    echo -e "${CYAN}Публичный ключ не найден.${NC}"
    echo -e "  ${YELLOW}1)${NC} Сгенерировать автоматически"
    echo -e "  ${YELLOW}2)${NC} Продолжить без ключа"
    read -p "Выберите вариант [1/2]: " choice
    
    if [[ "$choice" == "1" ]]; then
        ssh-keygen -t rsa -b 2048 -f ./id_rsa -N ""
        cat ./id_rsa.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        echo -e "${GREEN}✓${NC} Ключи сгенерированы и добавлены в authorized_keys"
        echo -e "${YELLOW}⚠️${NC}  Скачайте файлы id_rsa и id_rsa.pub для последующего использования."
        SETUP_SSH=true
    else
        echo -e "${YELLOW}⊘${NC} Пропускаем настройку SSH."
        SKIPPED+=("SSH ключ")
        SETUP_SSH=false
    fi
fi

# --- Конфигурация SSH (если ключ добавлен) ---
if [[ "$SETUP_SSH" == true ]]; then
    echo -e "${YELLOW}⏳${NC} Настройка SSH: отключаем пароль и разрешаем root-доступ..."
    sudo sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sudo systemctl restart ssh || sudo systemctl restart sshd
    ACTIONS+=("Добавлен SSH ключ, отключен вход по паролю, разрешен root-доступ, перезапущен SSH")
fi

# ======================================
# ✅ ФИНАЛЬНЫЙ ОТЧЕТ
# ======================================
echo -e "\n${GREEN}${BOLD}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║    ✅ УСТАНОВКА ЗАВЕРШЕНА             ║${NC}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════╝${NC}"

echo -e "\n${CYAN}${BOLD}📦 Установлено:${NC} ${INSTALLED[*]:-нет новых пакетов}"
echo -e "${YELLOW}${BOLD}⊘ Пропущено:${NC} ${SKIPPED[*]:-ничего}"
echo -e "\n${BLUE}${BOLD}⚙️  Выполнено:${NC}"
for action in "${ACTIONS[@]}"; do
    echo -e "   ${GREEN}•${NC} $action"
done

if [[ -f "id_rsa" && -f "id_rsa.pub" ]]; then
    echo -e "\n${RED}${BOLD}⚠️  ВНИМАНИЕ: НЕ ЗАБУДЬТЕ СКАЧАТЬ ФАЙЛЫ id_rsa И id_rsa.pub. ЭТО ВАШИ SSH-КЛЮЧИ!${NC}"
fi

exit 0
