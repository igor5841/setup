#!/bin/bash

# 1. Ввод данных
read -p "Сколько попыток указать для ввода пароля? : " MAXRETRY
read -p "Какое время дать для использования попыток? ( например 10m, 1h): " FINDTIME
read -p "На какое время применяем бан? (например 1h, 1d): " BANTIME

# 2. Подтверждение
echo "\nВаше значение: При неверном вводе пароля ($MAXRETRY) в течение ($FINDTIME) бан применять на ($BANTIME)."
read -p "Подтверждаете? (Y/N): " CONFIRM

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "\nУстанавливаем fail2ban..."
  apt update && apt install fail2ban -y

  echo "\nСоздаём /etc/fail2ban/jail.local..."
  cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled   = true
backend   = systemd
maxretry  = $MAXRETRY
findtime  = $FINDTIME
bantime   = $BANTIME
ignoreip  = 127.0.0.1/8
EOF

  echo "\nПерезапускаем fail2ban..."
  systemctl restart fail2ban
  echo "\n✅ Настройка завершена успешно."
else
  echo "\n❌ Отменено пользователем."
  exit 1
fi

