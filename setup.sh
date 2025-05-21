#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALLED=()
SKIPPED=()
ACTIONS=()

# --- Обновление системы ---
echo -e "${YELLOW}Обновляем систему...${NC}"
sudo apt update && sudo apt upgrade -y
ACTIONS+=("Обновление системы")

# --- Установка базовых пакетов ---
PACKAGES=(curl nano htop wget vnstat)
echo -e "${YELLOW}Проверка и установка необходимых пакетов...${NC}"
for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        echo -e "${GREEN}$pkg уже установлен${NC}"
        SKIPPED+=("$pkg")
    else
        echo -e "${YELLOW}Устанавливаем $pkg...${NC}"
        sudo apt install -y "$pkg"
        INSTALLED+=("$pkg")
    fi
done
ACTIONS+=("Проверка и установка утилит: curl, nano, htop, wget, vnstat")

# --- Установка Speedtest ---
if ! command -v speedtest &>/dev/null; then
    echo -e "${YELLOW}Устанавливаем Speedtest...${NC}"
    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
    sudo apt-get install -y speedtest
    INSTALLED+=("speedtest")
    ACTIONS+=("Установка Speedtest")
else
    echo -e "${GREEN}Speedtest уже установлен${NC}"
    SKIPPED+=("speedtest")
fi

# --- Установка Docker ---
if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}Устанавливаем Docker...${NC}"
    curl -fsSL https://get.docker.com | bash
    INSTALLED+=("docker")
    ACTIONS+=("Установка Docker")
else
    echo -e "${GREEN}Docker уже установлен${NC}"
    SKIPPED+=("docker")
fi

# --- Настройка SSH ---
mkdir -p ~/.ssh
chmod 700 ~/.ssh

PUBKEY_FILE=$(ls *.pub 2>/dev/null | head -n 1)
if [[ -n "$PUBKEY_FILE" ]]; then
    echo -e "${YELLOW}Найден публичный ключ: $PUBKEY_FILE${NC}"
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    cat "$PUBKEY_FILE" >> ~/.ssh/authorized_keys
    echo -e "${GREEN}Публичный ключ добавлен в authorized_keys${NC}"
    SETUP_SSH=true
elif [[ -z "$PUBKEY_FILE" ]]; then
    echo -e "${YELLOW}Публичный ключ не найден.\n1) Сгенерировать автоматически\n2) Продолжить без ключа${NC}"
    read -p "Выберите вариант [1/2]: " choice
    if [[ "$choice" == "1" ]]; then
        ssh-keygen -t rsa -b 2048 -f ./id_rsa -N ""
        cat ./id_rsa.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        echo -e "${GREEN}Ключи сгенерированы и добавлены в authorized_keys${NC}"
        echo -e "${YELLOW}Скачайте файлы id_rsa и id_rsa.pub для последующего использования.${NC}"
        SETUP_SSH=true
    else
        echo -e "${YELLOW}Пропускаем настройку SSH.${NC}"
        SKIPPED+=("SSH ключ")
        SETUP_SSH=false
    fi
fi

# --- Конфигурация SSH (если ключ добавлен) ---
if [[ "$SETUP_SSH" == true ]]; then
    echo -e "${YELLOW}Настройка SSH: отключаем пароль и разрешаем root-доступ...${NC}"
    sudo sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sudo systemctl restart ssh || sudo systemctl restart sshd
    ACTIONS+=("Добавлен SSH ключ, отключен вход по паролю, разрешен root-доступ, перезапущен SSH")
fi

# --- Финальный отчет ---
echo -e "\n${GREEN}--- УСТАНОВКА ЗАВЕРШЕНА ---${NC}"
echo -e "${YELLOW}Установлено:${NC} ${INSTALLED[*]}"
echo -e "${YELLOW}Пропущено:${NC} ${SKIPPED[*]}"
echo -e "${YELLOW}Выполнено:${NC}"
for action in "${ACTIONS[@]}"; do
    echo -e " - $action"
done

if [[ -f "id_rsa" && -f "id_rsa.pub" ]]; then
    echo -e "\n${YELLOW}ВНИМАНИЕ: НЕ ЗАБУДЬТЕ СКАЧАТЬ ФАЙЛЫ id_rsa И id_rsa.pub. ЭТО ВАШИ SSH-КЛЮЧИ!${NC}"
fi

exit 0
