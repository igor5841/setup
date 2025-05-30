#!/bin/bash

set -e

# Получение основного сетевого интерфейса
get_default_iface() {
    ip route get 1.1.1.1 2>/dev/null | awk '{print $5}' | head -n1
}

IFACE=$(get_default_iface)
if [[ -z "$IFACE" ]]; then
    echo "[!] Не удалось определить сетевой интерфейс."
    exit 1
fi

# Очистка qdisc
clear_qdisc() {
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
    sudo tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
    echo "[+] Ограничения сняты с интерфейса $IFACE"
}

# Применение лимита через tc (в мбитах)
apply_limit() {
    local LIMIT_MBIT=$1
    local LIMIT_KBIT=$((LIMIT_MBIT * 1000))

    clear_qdisc

    # Upload: HTB
    sudo tc qdisc add dev "$IFACE" root handle 1: htb default 30
    sudo tc class add dev "$IFACE" parent 1: classid 1:1 htb rate ${LIMIT_KBIT}kbit ceil ${LIMIT_KBIT}kbit
    sudo tc filter add dev "$IFACE" protocol ip parent 1: prio 1 u32 match ip dst 0.0.0.0/0 flowid 1:1

    # Download: ingress + police
    sudo tc qdisc add dev "$IFACE" handle ffff: ingress
    sudo tc filter add dev "$IFACE" parent ffff: protocol ip u32 match ip src 0.0.0.0/0 police rate ${LIMIT_KBIT}kbit burst 10k drop flowid :1

    echo "[+] Лимит $LIMIT_MBIT мбит/с применён на интерфейс $IFACE (upload и download)"
}

# Меню выбора
show_menu() {
    echo "\nВыберите лимит скорости:"
    echo "1) 5 мбит/с"
    echo "2) 10 мбит/с"
    echo "3) 50 мбит/с"
    echo "4) 100 мбит/с"
    echo "5) 150 мбит/с"
    echo "6) Убрать ограничение"
    echo -n "Введите номер (1-6): "
    read -r choice

    case "$choice" in
        1) apply_limit 5 ;;
        2) apply_limit 10 ;;
        3) apply_limit 50 ;;
        4) apply_limit 100 ;;
        5) apply_limit 150 ;;
        6) clear_qdisc ;;
        *) echo "[!] Неверный выбор." ; exit 1 ;;
    esac
}

show_menu
