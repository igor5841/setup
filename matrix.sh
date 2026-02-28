#!/bin/bash

#=============================================================================
# Автоматическая установка Matrix Synapse + Element + Coturn + Nginx
# Поддержка: звонки, федерация, .well-known
#=============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "=============================================="
echo "  Matrix Synapse + Element - Установщик"
echo "=============================================="
echo -e "${NC}"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ошибка: скрипт должен быть запущен с правами root${NC}"
   exit 1
fi

# Запрос доменов
echo -e "${YELLOW}Введите три поддомена для установки:${NC}"
echo ""
read -p "1. Основной домен (для Matrix сервера, например: matrix.example.com): " MATRIX_DOMAIN
read -p "2. Домен для Element веб-клиента (например: element.example.com): " ELEMENT_DOMAIN
read -p "3. Базовый домен для федерации (например: example.com): " BASE_DOMAIN

# Валидация
if [[ -z "$MATRIX_DOMAIN" ]] || [[ -z "$ELEMENT_DOMAIN" ]] || [[ -z "$BASE_DOMAIN" ]]; then
    echo -e "${RED}Ошибка: все три домена должны быть указаны${NC}"
    exit 1
fi

# Запрос email для Let's Encrypt
read -p "Введите email для сертификатов Let's Encrypt: " LE_EMAIL

if [[ -z "$LE_EMAIL" ]]; then
    echo -e "${RED}Ошибка: email обязателен${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Конфигурация:${NC}"
echo "  Matrix сервер: $MATRIX_DOMAIN"
echo "  Element клиент: $ELEMENT_DOMAIN"
echo "  Базовый домен: $BASE_DOMAIN"
echo "  Email: $LE_EMAIL"
echo ""
read -p "Продолжить установку? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" ]] && [[ "$CONFIRM" != "Y" ]]; then
    echo "Установка отменена"
    exit 0
fi

echo -e "${GREEN}[1/10] Обновление системы...${NC}"
apt update && apt upgrade -y

echo -e "${GREEN}[2/10] Установка зависимостей...${NC}"
apt install -y nginx certbot python3-certbot-nginx lsb-release wget apt-transport-https gnupg2 ufw

echo -e "${GREEN}[3/10] Добавление репозитория Matrix...${NC}"
wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/matrix-org.list

echo -e "${GREEN}[4/10] Установка Matrix Synapse и Coturn...${NC}"
apt update
DEBIAN_FRONTEND=noninteractive apt install -y matrix-synapse-py3 coturn

# Генерация ключей
echo -e "${GREEN}[5/10] Генерация ключей безопасности...${NC}"
MACAROON_KEY=$(openssl rand -hex 32)
TURN_SECRET=$(openssl rand -hex 32)
REGISTRATION_SECRET=$(openssl rand -hex 32)

echo -e "${GREEN}[6/10] Настройка Matrix Synapse...${NC}"

# Настройка server_name
cat > /etc/matrix-synapse/conf.d/server_name.yaml <<EOF
server_name: "$BASE_DOMAIN"
EOF

# Основная конфигурация
cat > /etc/matrix-synapse/conf.d/90-custom.yaml <<EOF
# Регистрация (будет отключена после создания админа)
enable_registration: true
enable_registration_without_verification: true
registration_shared_secret: "$REGISTRATION_SECRET"

# Безопасность
macaroon_secret_key: "$MACAROON_KEY"

# TURN сервер для звонков
turn_uris:
  - "turn:$MATRIX_DOMAIN:3478?transport=udp"
  - "turn:$MATRIX_DOMAIN:3478?transport=tcp"
  - "turns:$MATRIX_DOMAIN:5349?transport=udp"
  - "turns:$MATRIX_DOMAIN:5349?transport=tcp"

turn_shared_secret: "$TURN_SECRET"
turn_user_lifetime: 86400000
turn_allow_guests: true

# Загрузка файлов
max_upload_size: 50M

# Прокси через Nginx
public_baseurl: "https://$MATRIX_DOMAIN"

# Настройки listeners
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['127.0.0.1']
    resources:
      - names: [client, federation]
        compress: false
EOF

echo -e "${GREEN}[7/10] Настройка Coturn...${NC}"

# Активация Coturn
sed -i 's/#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn

# Конфигурация Coturn
cat > /etc/turnserver.conf <<EOF
listening-port=3478
tls-listening-port=5349
fingerprint
use-auth-secret
static-auth-secret=$TURN_SECRET
realm=$MATRIX_DOMAIN
lt-cred-mech
no-multicast-peers
no-cli
no-tlsv1
no-tlsv1_1
# Сертификаты будут добавлены после получения от Let's Encrypt
EOF

echo -e "${GREEN}[8/10] Получение SSL сертификатов...${NC}"

# Временная конфигурация Nginx для получения сертификатов
cat > /etc/nginx/sites-available/temp-certbot <<EOF
server {
    listen 80;
    server_name $MATRIX_DOMAIN $ELEMENT_DOMAIN $BASE_DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/temp-certbot /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# Получение сертификатов
certbot certonly --nginx --non-interactive --agree-tos --email "$LE_EMAIL" -d "$MATRIX_DOMAIN"
certbot certonly --nginx --non-interactive --agree-tos --email "$LE_EMAIL" -d "$ELEMENT_DOMAIN"
certbot certonly --nginx --non-interactive --agree-tos --email "$LE_EMAIL" -d "$BASE_DOMAIN"

# Добавление сертификатов в Coturn
cat >> /etc/turnserver.conf <<EOF
cert=/etc/letsencrypt/live/$MATRIX_DOMAIN/fullchain.pem
pkey=/etc/letsencrypt/live/$MATRIX_DOMAIN/privkey.pem
EOF

echo -e "${GREEN}[9/10] Установка и настройка Element...${NC}"

# Скачивание последней версии Element
cd /tmp
ELEMENT_VERSION=$(curl -s https://api.github.com/repos/element-hq/element-web/releases/latest | grep "tag_name" | cut -d '"' -f 4)
wget "https://github.com/element-hq/element-web/releases/download/$ELEMENT_VERSION/element-$ELEMENT_VERSION.tar.gz"

mkdir -p /var/www/element
tar -xzf element-*.tar.gz -C /var/www/element --strip-components=1

# Конфигурация Element
cat > /var/www/element/config.json <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://$MATRIX_DOMAIN",
            "server_name": "$BASE_DOMAIN"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "disable_custom_urls": false,
    "disable_guests": false,
    "disable_login_language_selector": false,
    "disable_3pid_login": false,
    "brand": "Element",
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api",
        "https://scalar-staging.vector.im/_matrix/integrations/v1",
        "https://scalar-staging.vector.im/api",
        "https://scalar-staging.riot.im/scalar/api"
    ],
    "bug_report_endpoint_url": "https://element.io/bugreports/submit",
    "defaultCountryCode": "RU",
    "showLabsSettings": true,
    "features": {},
    "default_federate": true,
    "default_theme": "light",
    "roomDirectory": {
        "servers": [
            "$BASE_DOMAIN"
        ]
    },
    "enable_presence_by_hs_url": {
        "https://$MATRIX_DOMAIN": false
    },
    "settingDefaults": {
        "breadcrumbs": true
    }
}
EOF

chown -R www-data:www-data /var/www/element

echo -e "${GREEN}[10/10] Настройка Nginx...${NC}"

# Nginx конфигурация для Matrix
cat > /etc/nginx/sites-available/matrix <<EOF
server {
    listen 80;
    server_name $MATRIX_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $MATRIX_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MATRIX_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MATRIX_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Matrix Client API
    location ~* ^(\/_matrix|\/_synapse\/client) {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        
        client_max_body_size 50M;
    }

    # Matrix Federation API
    location ~* ^(\/_matrix\/federation) {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
    }
}

# Federation на порту 8448
server {
    listen 8448 ssl http2 default_server;
    listen [::]:8448 ssl http2 default_server;
    server_name $MATRIX_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MATRIX_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MATRIX_DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
    }
}
EOF

# Nginx конфигурация для Element
cat > /etc/nginx/sites-available/element <<EOF
server {
    listen 80;
    server_name $ELEMENT_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $ELEMENT_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$ELEMENT_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$ELEMENT_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/element;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Безопасность
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "frame-ancestors 'self'";
}
EOF

# Nginx конфигурация для .well-known (федерация)
mkdir -p /var/www/wellknown/.well-known/matrix

cat > /var/www/wellknown/.well-known/matrix/server <<EOF
{
    "m.server": "$MATRIX_DOMAIN:443"
}
EOF

cat > /var/www/wellknown/.well-known/matrix/client <<EOF
{
    "m.homeserver": {
        "base_url": "https://$MATRIX_DOMAIN"
    },
    "m.identity_server": {
        "base_url": "https://vector.im"
    }
}
EOF

cat > /etc/nginx/sites-available/wellknown <<EOF
server {
    listen 80;
    server_name $BASE_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $BASE_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$BASE_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$BASE_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/wellknown;

    location /.well-known/matrix/ {
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
    }
}
EOF

chown -R www-data:www-data /var/www/wellknown

# Активация конфигураций
rm -f /etc/nginx/sites-enabled/temp-certbot
ln -sf /etc/nginx/sites-available/matrix /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/element /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/wellknown /etc/nginx/sites-enabled/

nginx -t

echo -e "${GREEN}Настройка firewall...${NC}"
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8448/tcp
ufw allow 3478/tcp
ufw allow 3478/udp
ufw allow 5349/tcp
ufw allow 5349/udp

echo -e "${GREEN}Запуск сервисов...${NC}"
systemctl enable --now coturn
systemctl restart coturn
systemctl restart matrix-synapse
systemctl restart nginx

echo ""
echo -e "${GREEN}=============================================="
echo "  Установка завершена!"
echo "==============================================${NC}"
echo ""
echo -e "${YELLOW}Теперь создайте администратора:${NC}"
echo ""
echo "  sudo register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml http://127.0.0.1:8008"
echo ""
echo -e "${YELLOW}После создания пользователя ОТКЛЮЧИТЕ регистрацию:${NC}"
echo ""
echo "  1. sudo nano /etc/matrix-synapse/conf.d/90-custom.yaml"
echo "  2. Измените enable_registration: true на false"
echo "  3. sudo systemctl restart matrix-synapse"
echo ""
echo -e "${GREEN}Ваши URL:${NC}"
echo "  Element (веб-клиент): https://$ELEMENT_DOMAIN"
echo "  Matrix сервер: https://$MATRIX_DOMAIN"
echo "  Федерация: https://$BASE_DOMAIN/.well-known/matrix/server"
echo ""
echo -e "${YELLOW}Проверьте федерацию:${NC}"
echo "  https://federationtester.matrix.org/"
echo ""
echo -e "${GREEN}Ключ регистрации для создания пользователей:${NC}"
echo "  $REGISTRATION_SECRET"
echo ""
echo -e "${YELLOW}Сохраните этот ключ в безопасном месте!${NC}"
echo ""
