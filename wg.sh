#!/bin/bash

set -e

# Step 1: Ask user to choose password option
echo "Пароль для входа в админку сгенерировать или ввёдете свой?:"
echo "1. Сгенерировать пароль автоматически"
echo "2. Ввести свой пароль"
read -p "Введите номер (1 или 2): " CHOICE

if [[ "$CHOICE" == "1" ]]; then
    WG_PASSWORD=$(< /dev/urandom tr -dc 'A-Za-z0-9!@#$%^&*()_+=' | head -c15)
    echo -e "\nАвтоматически сгенерированный пароль: $WG_PASSWORD"
elif [[ "$CHOICE" == "2" ]]; then
    read -s -p "Введите пароль для WG-Easy (ввод скрыт): " WG_PASSWORD
    echo ""
else
    echo "Неверный выбор. Завершение."
    exit 1
fi

# Step 2: Get public IP and ask for confirmation
DEFAULT_IP=$(curl -s ifconfig.me)
echo "Обнаружен внешний IP: $DEFAULT_IP"
read -p "Введите домен или IP (по умолчанию: $DEFAULT_IP): " WG_HOST
WG_HOST=${WG_HOST:-$DEFAULT_IP}

# Step 3: Check Docker
if ! command -v docker &> /dev/null; then
    echo "Docker не найден. Устанавливаем..."
    curl -fsSL https://get.docker.com | bash
fi

# Step 4-5: Create and move to folder
WG_DIR="/root/.wg-easy"
mkdir -p "$WG_DIR"
cd "$WG_DIR"

# Step 6: Download docker-compose.yml
wget -q https://raw.githubusercontent.com/WeeJeWel/wg-easy/master/docker-compose.yml

# Step 7: Generate bcrypt hash
if ! command -v htpasswd &> /dev/null; then
    echo "Устанавливаем apache2-utils для генерации bcrypt..."
    apt-get update && apt-get install -y apache2-utils
fi
HASH=$(htpasswd -nbB user "$WG_PASSWORD" | cut -d ":" -f2)
HASH_ESCAPED=${HASH//\$/\$\$}  # Escape '$' for YAML

# Step 8: Update docker-compose.yml:
sed -i \
    -e 's/^\s*#\s*-\s*PASSWORD=/      - PASSWORD_HASH=/g' \
    -e "s|PASSWORD_HASH=.*|PASSWORD_HASH=$HASH_ESCAPED|g" \
    -e "s|WG_HOST=.*|WG_HOST=$WG_HOST|g" docker-compose.yml

# Step 9: Launch docker compose
docker compose up -d

# Step 10: Final output
echo -e "\nWG-Easy успешно установлен и запущен."
echo "Доступ: http://$WG_HOST:51821"
echo "Пароль: $WG_PASSWORD"
