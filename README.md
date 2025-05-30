**Скрипт создан для первоначальной настройки Ubuntu server и установки нужных пакетов.**
Работа проверялась на Ubuntu server 22.04.

## ИНСТРУКЦИЯ ##
1. Если вы хотите, чтобы скрипт настроил ваш ключ, то положите его (файл **.pub**) рядом со скриптом. На новых VDS просто закиньте его в папку **/root**.
2. Скопируйте команду и вставьте её на сервере:
<pre> wget -qO setup.sh "https://raw.githubusercontent.com/igor5841/setup/refs/heads/main/setup.sh" && chmod +x setup.sh && ./setup.sh </pre>
3. Дождитесь установки. Если вы загрузили **.pub ключ**, то скрипт его увидит и сам настроит. Если не загрузили - сможете пропустить настройку **SSH** или доверить скрипту автоматическую генерацию.

## ВАРИАНТЫ УСТАНОВКИ: ##
1. Автоматический - софт устанавливается автоматически.
2. Ручная установка - вы можете выбрать, какие пакеты устанавливать.

## КАКОЙ СОФТ УСТАНАВЛИВАЕТСЯ?
В автоматическом режиме на данный момент устанавливается:
Базовый пакет: **nano, curl, wget, htop**;
Дополнительный софт:
- **vnstat** (запись и просмотр статистики по 5 минутам, часам, дням, неделям, месяцам и годам);
- **Docker** (запуск докер контейнеров);
- **Speedtest** (Тестирование скорости интернета. Версия с офицального сайта ookla);
- **btop** (системный мониторинг);
- **JDK21** (Java Development KIT 21 для запуска майнкрафт серверов версии 21 и выше);
**Список будет пополняться.**

## SSH ##
Если вы не хотите трогать SSH и настраивать ключи, то в процессе настройки, когда скрипт не увидит файл ключа и попросит выбрать действие - выберите вариант пропуска.
Скрипт удаляет файл **50-cloud-init.conf**, так как он иногда мешает и конфликтует с основным файлом настройки SSH.
Он есть на некоторых серверах по пути: **/etc/ssh/sshd_config.d/50-cloud-init.conf**

   ## ❗ ОЧЕНЬ ВАЖНО
**Не забудьте скачать SSH-ключи (`id_rsa`, `id_rsa.pub`) после установки. Это ваш единственный способ доступа! Если файлы не сохраните - по SSH больше не зайдёте и придется лезть в VNC!**
