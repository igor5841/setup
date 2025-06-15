#!/bin/bash

set -euo pipefail

RULES_FILE="/etc/ufw/before.rules"
BACKUP_FILE="/etc/ufw/before.rules.bak"

if ! command -v ufw >/dev/null; then
  echo "❌ ufw не установлен"
  exit 1
fi

# Убедимся, что порт SSH открыт
if ! ufw status | grep -qE "(22/tcp|OpenSSH)\s+ALLOW"; then
  echo "⚠️ SSH порт (22) не открыт. Открываем..."
  ufw allow ssh
fi

cp "$RULES_FILE" "$BACKUP_FILE"
echo "✅ Бэкап: $BACKUP_FILE"

awk '
BEGIN { in_input=0; in_forward=0 }

/^# ok icmp codes for INPUT/ {
  in_input=1; in_forward=0; print; next
}

/^# ok icmp code for FORWARD/ {
  in_input=0; in_forward=1; print; next
}

in_input && /--icmp-type (destination-unreachable|time-exceeded|parameter-problem|echo-request)/ {
  print gensub(/ACCEPT/, "DROP", 1, $0);
  if (/echo-request/) print "-A ufw-before-input -p icmp --icmp-type source-quench -j DROP";
  next
}

in_forward && /--icmp-type (destination-unreachable|time-exceeded|parameter-problem|echo-request)/ {
  print gensub(/ACCEPT/, "DROP", 1, $0);
  next
}

{ print }
' "$BACKUP_FILE" > "$RULES_FILE"

ufw disable && ufw enable

echo "✅ ICMP правила обновлены и UFW перезапущен"
