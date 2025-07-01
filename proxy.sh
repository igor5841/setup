#!/bin/bash

set -e

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
RESET='\033[0m'

function line() {
  echo -e "${BLUE}────────────────────────────────────────────────────────────${RESET}"
}

function header() {
  echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗"
  echo -e "║${RESET}         ${YELLOW}Установка Socks5 by igor5841${RESET}           ${BLUE}║"
  echo -e "╚════════════════════════════════════════════════════════════╝${RESET}"
}

function main_menu() {
  header
  echo -e "${YELLOW}Главное меню:${RESET}"
  echo -e "1. Установить или перезапустить прокси"
  echo -e "2. Проверить статус прокси"
  echo -e "3. Остановить прокси"
  echo -e "4. Удалить контейнер прокси"
  echo -e "5. Выход"
  echo -n "Выберите действие: "
  read -r menu_choice
  case "$menu_choice" in
    1) install_menu ;;  # Новое подменю
    2) print_proxy_status ;;
    3) docker stop socks5 && echo -e "${RED}Прокси остановлен.${RESET}" ;;
    4) docker rm -f socks5 && echo -e "${RED}Контейнер удалён.${RESET}" ;;
    5) exit 0 ;;
    *) echo "Неверный выбор." ;;
  esac
  echo
  read -p "Нажмите Enter для возврата в меню..."
  clear
  main_menu
}

function install_menu() {
  echo -e "${YELLOW}Выберите тип установки:${RESET}"
  echo "1. Ручная установка (с выбором логина/пароля и порта)"
  echo "2. Полностью автоматическая установка"
  read -rp "Ваш выбор (1 или 2): " sub_choice
  case "$sub_choice" in
    1) install_proxy ;;
    2) auto_install_proxy ;;
    *) echo "Неверный выбор." ;;
  esac
}

function print_proxy_status() {
  echo -e "${YELLOW}Состояние прокси:${RESET}"
  if docker ps -a --format '{{.Names}}' | grep -q '^socks5$'; then
    STATUS=$(docker inspect -f '{{.State.Running}}' socks5)
    if [[ "$STATUS" == "true" ]]; then
      echo -e "  ${GREEN}Установлен (запущен) ✅${RESET}"
    else
      echo -e "  ${RED}Установлен (остановлен) ❌${RESET}"
      echo -n "  Запустить контейнер? [y/N]: "
      read -r answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        docker start socks5
        echo -e "  ${GREEN}Контейнер запущен ✅${RESET}"
      fi
    fi
  else
    echo -e "  ${RED}Не установлен ❌${RESET}"
  fi
  line
}

function prompt_choice() {
  echo -e "${YELLOW}Выберите способ авторизации:${RESET}"
  echo "1. Указать логин и пароль вручную"
  echo "2. Сгенерировать логин и пароль автоматически"
  read -rp "Ваш выбор (1 или 2): " choice
  if [[ "$choice" == "1" ]]; then
    read -rp "Введите логин: " LOGIN
    read -rp "Введите пароль: " PASSWORD
  elif [[ "$choice" == "2" ]]; then
    LOGIN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c8)
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c12)
  else
    echo "Неверный выбор."
    exit 1
  fi
  read -rp "Введите порт для прокси (по умолчанию 1080): " PORT
  PORT=${PORT:-1080}
}

function check_docker() {
  if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}Docker не найден. Устанавливаем...${RESET}"
    curl -fsSL https://get.docker.com | bash
  fi
}

function get_external_ip() {
  EXTERNAL_IP=$(curl -s ifconfig.me)
  if [[ -z "$EXTERNAL_IP" ]]; then
    echo "Ошибка получения внешнего IP."
    exit 1
  fi
}

function start_socks5() {
  docker pull dijedodol/simple-socks5-server
  docker rm -f socks5 2>/dev/null || true
  docker run -d -p "$PORT":1080 --name=socks5 --restart=always \
    -e "SSS_USERNAME=$LOGIN" \
    -e "SSS_PASSWORD=$PASSWORD" \
    dijedodol/simple-socks5-server
}

function print_result() {
  echo ""
  echo -e "${YELLOW}Ваш прокси запущен.${RESET}"
  echo -e "${YELLOW}Адрес прокси:${RESET} ${GREEN}$EXTERNAL_IP${RESET}"
  echo -e "${YELLOW}Порт:${RESET} ${GREEN}$PORT${RESET}"
  echo -e "${YELLOW}Логин:${RESET} ${GREEN}$LOGIN${RESET}"
  echo -e "${YELLOW}Пароль:${RESET} ${GREEN}$PASSWORD${RESET}"
  echo -e "${YELLOW}Ссылка для Telegram:${RESET} ${GREEN}https://t.me/socks?server=$EXTERNAL_IP&port=$PORT&user=$LOGIN&pass=$PASSWORD${RESET}"
  line
}

function install_proxy() {
  check_docker
  prompt_choice
  get_external_ip
  start_socks5
  print_result
}

function auto_install_proxy() {
  LOGIN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c8)
  PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c12)
  PORT=$(shuf -i 10000-20000 -n 1)
  check_docker
  get_external_ip
  start_socks5
  print_result
}

clear
main_menu
