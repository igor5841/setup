#!/bin/bash

# Файл конфигурации
CONFIG_FILE="$HOME/.op_config"

# Функция установки
install_script() {
    echo "=== Установка скрипта управления портами ==="
    
    # Запрос порта
    read -p "Введите порт, который будем открывать: " PORT
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo "Ошибка: Неверный номер порта!"
        exit 1
    fi
    
    # Запрос комментария
    read -p "Какой комментарий добавить к правилу? " COMMENT
    
    # Сохранение конфигурации
    echo "PORT=$PORT" > "$CONFIG_FILE"
    echo "COMMENT=$COMMENT" >> "$CONFIG_FILE"
    
    # Копирование скрипта в систему
    SCRIPT_PATH="/usr/local/bin/op"
    sudo cp "$0" "$SCRIPT_PATH"
    sudo chmod +x "$SCRIPT_PATH"
    
    echo "✓ Скрипт установлен!"
    echo "✓ Порт: $PORT"
    echo "✓ Комментарий: $COMMENT"
    echo ""
    echo "Доступные команды:"
    echo "  op on         - открыть порт"
    echo "  op off        - закрыть порт"
    echo "  op on -5m     - открыть на 5 минут"
    echo "  op on -1h     - открыть на 1 час"
    echo "  op delete     - удалить скрипт"
    echo "  op help       - помощь"
    exit 0
}

# Функция помощи
show_help() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "=== Управление портами ==="
        echo "Настроенный порт: $PORT"
        echo "Комментарий: $COMMENT"
        echo ""
    else
        echo "=== Управление портами ==="
    fi
    
    echo "Использование:"
    echo "  op on              - открыть порт"
    echo "  op off             - закрыть порт"
    echo "  op on -<время>     - открыть на время, потом закрыть"
    echo "  op delete          - удалить скрипт"
    echo "  op help            - показать эту справку"
    echo ""
    echo "Примеры времени:"
    echo "  -5m   - 5 минут"
    echo "  -10m  - 10 минут"
    echo "  -1h   - 1 час"
    echo "  -2h   - 2 часа"
    exit 0
}

# Функция удаления существующих правил для порта
remove_existing_rules() {
    local port=$1
    
    # Поиск правил с портом (без протокола, /tcp и /udp)
    local rules=$(sudo ufw status numbered | grep -E "\s${port}(/tcp|/udp)?\s" | grep -oP '^\[\s*\K[0-9]+' | tac)
    
    if [ -n "$rules" ]; then
        echo "⚠ Найдены существующие правила для порта ${port}:"
        sudo ufw status numbered | grep -E "\s${port}(/tcp|/udp)?\s"
        echo ""
        echo "Удаляю дубликаты..."
        
        # Удаление правил (в обратном порядке, чтобы номера не сбивались)
        for rule_num in $rules; do
            echo "yes" | sudo ufw delete $rule_num > /dev/null 2>&1
        done
        
        echo "✓ Старые правила удалены"
    fi
}

# Функция открытия порта
open_port() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Ошибка: Скрипт не установлен. Запустите установку."
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    # Проверка UFW
    if ! command -v ufw &> /dev/null; then
        echo "Ошибка: UFW не установлен!"
        exit 1
    fi
    
    # Удаление существующих правил для этого порта (все варианты: порт, порт/tcp, порт/udp)
    remove_existing_rules "$PORT"
    
    # Открытие порта с комментарием
    sudo ufw allow ${PORT}/tcp comment "$COMMENT" > /dev/null 2>&1
    echo "✓ Порт $PORT открыт (TCP)"
    echo "  Комментарий: $COMMENT"
    
    # Если указано время
    if [ -n "$1" ]; then
        parse_time "$1"
        echo "⏱ Порт закроется через $DURATION"
        
        # Создание фонового процесса для закрытия порта
        (
            sleep "$SECONDS_TOTAL"
            
            # Удаление правила allow перед добавлением deny
            local rules=$(sudo ufw status numbered | grep -E "\s${PORT}(/tcp|/udp)?\s" | grep -oP '^\[\s*\K[0-9]+' | tac)
            for rule_num in $rules; do
                echo "yes" | sudo ufw delete $rule_num > /dev/null 2>&1
            done
            
            # Добавление правила deny
            sudo ufw deny ${PORT}/tcp comment "$COMMENT" > /dev/null 2>&1
            
            # Попытка отправить уведомление
            if command -v notify-send &> /dev/null; then
                notify-send "Порт $PORT закрыт" "$COMMENT" 2>/dev/null
            fi
            
            # Логирование в файл
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Порт $PORT автоматически закрыт: $COMMENT" >> "$HOME/.op_log"
        ) &
        
        echo "  PID процесса закрытия: $!"
    fi
}

# Функция закрытия порта
close_port() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Ошибка: Скрипт не установлен."
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    # Удаление существующих правил для этого порта (все варианты: порт, порт/tcp, порт/udp)
    remove_existing_rules "$PORT"
    
    # Закрытие порта с комментарием
    sudo ufw deny ${PORT}/tcp comment "$COMMENT" > /dev/null 2>&1
    echo "✓ Порт $PORT закрыт (TCP)"
    echo "  Комментарий: $COMMENT"
}

# Функция парсинга времени
parse_time() {
    TIME_ARG="$1"
    
    # Удаление начального тире
    TIME_ARG="${TIME_ARG#-}"
    
    # Извлечение числа и единицы
    if [[ "$TIME_ARG" =~ ^([0-9]+)([mh])$ ]]; then
        NUMBER="${BASH_REMATCH[1]}"
        UNIT="${BASH_REMATCH[2]}"
        
        if [ "$UNIT" = "m" ]; then
            SECONDS_TOTAL=$((NUMBER * 60))
            DURATION="$NUMBER минут(ы)"
        elif [ "$UNIT" = "h" ]; then
            SECONDS_TOTAL=$((NUMBER * 3600))
            DURATION="$NUMBER час(ов)"
        fi
    else
        echo "Ошибка: Неверный формат времени! Используйте -5m или -1h"
        exit 1
    fi
}

# Функция удаления
delete_script() {
    read -p "Вы уверены, что хотите удалить скрипт? (y/n): " CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        # Удаление конфигурации и логов
        rm -f "$CONFIG_FILE"
        rm -f "$HOME/.op_log"
        
        # Удаление скрипта из системы
        sudo rm -f /usr/local/bin/op
        
        echo "✓ Скрипт удален"
        echo "✓ Конфигурация и логи удалены"
    else
        echo "Отмена удаления"
    fi
    exit 0
}

# Основная логика
if [ ! -f "$CONFIG_FILE" ] && [ "$1" != "help" ]; then
    install_script
fi

case "$1" in
    on)
        if [ -n "$2" ]; then
            open_port "$2"
        else
            open_port
        fi
        ;;
    off)
        close_port
        ;;
    delete)
        delete_script
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo "Неизвестная команда: $1"
        echo "Используйте 'op help' для справки"
        exit 1
        ;;
esac
