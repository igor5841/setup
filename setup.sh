#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALLED=()
SKIPPED=()
ACTIONS=()

ALL_SOFTWARE_OPTIONS=(
  "base:Базовые пакеты"
  "speedtest:Speedtest"
  "docker:Docker"
  "vnstat:VnStat (мониторинг трафика)"
  "btop:btop (системный монитор)"
)

# --- Меню выбора режима ---
echo -e "${YELLOW}Выберите режим установки:${NC}"
echo "1) Автоматическая установка всех пакетов"
echo "2) Выборочная установка"
read -p "Введите 1 или 2: " INSTALL_MODE

if [[ "$INSTALL_MODE" == "2" ]]; then
  if ! command -v dialog &>/dev/null; then
    echo -e "${YELLOW}Устанавливаем 'dialog' для отображения интерфейса выбора...${NC}"
    sudo apt update && sudo apt install -y dialog
  fi

  TEMPFILE=$(mktemp)

  dialog --checklist "Выберите пакеты для установки (пробел — выбрать):" 15 50 8 \
    base "Базовые пакеты (curl, nano, htop, wget)" on \
    speedtest "Speedtest CLI" off \
    docker "Docker" off \
    vnstat "VnStat (мониторинг трафика)" off \
    btop "btop (системный монитор)" off \
    2>"$TEMPFILE"

  SELECTED_PACKAGES=$(<"$TEMPFILE")
  rm -f "$TEMPFILE"
else
  SELECTED_PACKAGES="base speedtest docker vnstat btop"
fi

sudo apt update && sudo apt upgrade -y
ACTIONS+=("Обновление системы")

# --- Установка snapd (обязательный пакет) ---
echo -e "${YELLOW}Проверка и установка snapd...${NC}"
if ! command -v snap &>/dev/null; then
  sudo apt install -y snapd
  INSTALLED+=("snapd")
  ACTIONS+=("Установка snapd")
else
  echo -e "${GREEN}snap уже установлен${NC}"
  SKIPPED+=("snapd")
fi

# --- Установка базовых пакетов ---
if [[ "$SELECTED_PACKAGES" == *base* ]]; then
  PACKAGES=(curl nano htop wget)
  echo -e "${YELLOW}Проверка и установка базовых пакетов...${NC}"
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
  ACTIONS+=("Установка базовых пакетов: curl, nano, htop, wget")
fi

# --- Установка btop (необязательный) ---
if [[ "$SELECTED_PACKAGES" == *btop* ]]; then
  if ! command -v btop &>/dev/null; then
    echo -e "${YELLOW}Устанавливаем btop через snap...${NC}"
    sudo snap install btop
    INSTALLED+=("btop")
    ACTIONS+=("Установка btop через snap")
  else
    echo -e "${GREEN}btop уже установлен${NC}"
    SKIPPED+=("btop")
  fi
fi

# --- Установка vnStat ---
if [[ "$SELECTED_PACKAGES" == *vnstat* ]]; then
  if dpkg -s vnstat &>/dev/null; then
    echo -e "${GREEN}vnstat уже установлен${NC}"
    SKIPPED+=("vnstat")
  else
    echo -e "${YELLOW}Устанавливаем vnstat...${NC}"
    sudo apt install -y vnstat
    INSTALLED+=("vnstat")
    ACTIONS+=("Установка vnstat")
  fi
fi

# --- Установка Speedtest ---
if [[ "$SELECTED_PACKAGES" == *speedtest* ]]; then
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
fi

# --- Установка Docker ---
if [[ "$SELECTED_PACKAGES" == *docker* ]]; then
  if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}Устанавливаем Docker...${NC}"
    curl -fsSL https://get.docker.com | bash
    INSTALLED+=("docker")
    ACTIONS+=("Установка Docker")
  else
    echo -e "${GREEN}Docker уже установлен${NC}"
    SKIPPED+=("docker")
  fi
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
else
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

if [[ "$SETUP_SSH" == true ]]; then
  echo -e "${YELLOW}Настройка SSH: отключаем пароль и разрешаем root-доступ...${NC}"
  sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config || echo 'PasswordAuthentication no' | sudo tee -a /etc/ssh/sshd_config
  sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' | sudo tee -a /etc/ssh/sshd_config

  if [[ -f "/etc/ssh/sshd_config.d/50-cloud-init.conf" ]]; then
    echo -e "${YELLOW}Удаляем конфликтующий файл 50-cloud-init.conf...${NC}"
    sudo rm /etc/ssh/sshd_config.d/50-cloud-init.conf
    ACTIONS+=("Удалён /etc/ssh/sshd_config.d/50-cloud-init.conf для избежания конфликта пароля")
  fi

  sudo systemctl restart ssh || sudo systemctl restart sshd || sudo service ssh restart
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

# --- Подтверждение наличия snap ---
echo -e "\n${GREEN}snap установлен и готов к использованию.${NC}"

exit 0
