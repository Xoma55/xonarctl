# ASUS Xonar AE: установка и кнопка в доке GNOME

Инструкция для Linux с ядром, собранным с поддержкой USB-аудио. Проверено на
ASUS Xonar AE с USB ID `0b05:180f` и Fedora. Внутри PCIe-карты аудиоустройство
подключено как USB, поэтому его обслуживает стандартный драйвер `snd-usb-audio`.

## Что лежит в этой папке

- `install.sh` — установщик: сборка, Secure Boot подпись, системная установка,
  автозагрузка и ярлык GNOME.
- `snd-xonar-ae.c` — модуль ядра, который посылает карте команды переключения.
- `xonarctl` — команды для проверки и переключения выхода.
- `xonar-ae-toggle.desktop` — ярлык GNOME для переключения одним нажатием.
- `Makefile` — сборка модуля для запущенного ядра.

Модуль не отключает `snd-usb-audio` и не перехватывает интерфейсы аудиокарты.
Переключение передаётся карте через USB control request.

## Быстрая установка

На Fedora установите инструменты сборки и заголовки текущего ядра, затем
запустите установщик от root. Передайте ему имя пользователя GNOME, чтобы
ярлык попал в правильный профиль:

```bash
sudo dnf install gcc make kernel-devel-$(uname -r) mokutil
cd /home/xoma55/www/sound
sudo ./install.sh xoma55
```

Установщик собирает модуль, проверяет Secure Boot, подписывает модуль
зарегистрированным ключом akmods, устанавливает модуль и CLI, настраивает
автозагрузку и копирует GNOME ярлык. Если ключ MOK ещё не зарегистрирован,
установщик добавит его в очередь и остановится. После регистрации ключа в
MOK Manager во время перезагрузки запустите установщик повторно.

После успешной установки нажмите **Super**, найдите **Переключить выход
Xonar AE**, запустите ярлык и подтвердите запрос авторизации. Затем добавьте
его в избранное, чтобы он появился в доке.

После установки ядра новой версии загрузитесь в него, установите
`kernel-devel-$(uname -r)` и снова запустите `sudo ./install.sh xoma55`.
Модуль собирается отдельно для каждой версии ядра.

## 1. Установить пакеты для сборки

В Fedora установите компилятор, make и заголовки именно для запущенного ядра:

```bash
sudo dnf install gcc make kernel-devel-$(uname -r) mokutil
```

Если `kernel-devel-$(uname -r)` не найден, сначала обновите систему и
перезагрузитесь в установленное ядро, затем повторите установку:

```bash
sudo dnf upgrade --refresh
sudo reboot
```

Убедитесь, что каталог сборки существует:

```bash
test -e /lib/modules/$(uname -r)/build && echo "kernel-devel найден"
```

В Debian/Ubuntu вместо Fedora-пакета заголовков установите
`linux-headers-$(uname -r)`, `build-essential` и `mokutil`.

## 2. Собрать модуль

Из этой папки выполните:

```bash
make
```

В результате появится `snd-xonar-ae.ko`. При каждой новой сборке подпись
старого файла теряется: новый `.ko` нужно подписать заново до загрузки.

## 3. Подписать модуль для Secure Boot

Проверьте состояние Secure Boot:

```bash
sudo mokutil --sb-state
```

Если вывод содержит `SecureBoot disabled`, переходите к разделу 4.

Если Secure Boot включён, ядро Fedora отклоняет неподписанные сторонние
модули. На системах с akmods обычно уже есть ключ:

```text
/etc/pki/akmods/private/private_key.priv
/etc/pki/akmods/certs/public_key.der
```

Проверьте наличие ключа и его регистрацию:

```bash
sudo ls -l /etc/pki/akmods/private/private_key.priv \
  /etc/pki/akmods/certs/public_key.der
sudo mokutil --test-key /etc/pki/akmods/certs/public_key.der
```

Если вывод говорит `is already enrolled`, подпишите собранный модуль:

```bash
sudo /usr/src/kernels/$(uname -r)/scripts/sign-file sha256 \
  /etc/pki/akmods/private/private_key.priv \
  /etc/pki/akmods/certs/public_key.der \
  ./snd-xonar-ae.ko
```

Если ключ есть, но ещё не зарегистрирован, добавьте его в MOK:

```bash
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

Задайте временный пароль, перезагрузитесь и в синем меню MOK Manager выберите
`Enroll MOK` → `Continue` → `Yes`. Введите временный пароль, подтвердите
перезагрузку. После запуска Fedora подпишите модуль командой выше. Если файлов
ключа akmods нет, сначала настройте подпись модулей по документации Fedora
(`akmods` / `kmodgenca`), затем повторите этот раздел с созданным ключом.

Подписывайте модуль после последней сборки. Любое изменение или повторный
`make` создаёт новый неподписанный `.ko`.

## 4. Загрузить и проверить модуль

Если старая версия уже загружена, выгрузите её:

```bash
sudo rmmod snd_xonar_ae
```

Загрузите подписанный модуль:

```bash
sudo insmod ./snd-xonar-ae.ko
```

Проверьте команды:

```bash
sudo ./xonarctl status
sudo ./xonarctl speakers
sudo ./xonarctl headphones
sudo ./xonarctl toggle
```

`speakers` направляет звук на колонки, `headphones` — в выход наушников,
`toggle` меняет выход на противоположный. На проверенной карте команда чтения
статуса не всегда возвращает состояние. После первой команды переключения
модуль запоминает выбранный режим, поэтому последующие `status` и `toggle`
работают. Если при первом `toggle` состояние неизвестно, утилита выбирает
колонки; последующие вызовы чередуют режимы по последней успешной команде.

Если `insmod` отвечает `Key was rejected by service`, модуль не подписан
доверенным ключом или ключ не зарегистрирован. Вернитесь к разделу 3.

## 5. Установить модуль для автозагрузки

Скопируйте уже подписанный модуль в каталог текущего ядра, обновите индекс
модулей, включите загрузку при старте и загрузите его сейчас:

```bash
sudo install -D -m 0644 ./snd-xonar-ae.ko \
  /lib/modules/$(uname -r)/extra/snd-xonar-ae.ko
sudo depmod -a
echo snd-xonar-ae | sudo tee /etc/modules-load.d/snd-xonar-ae.conf
sudo modprobe snd-xonar-ae
```

Проверьте, что модуль загрузился:

```bash
lsmod | grep snd_xonar_ae
cat /sys/module/snd_xonar_ae/parameters/output
```

После обновления ядра модуль нужно пересобрать под новое ядро, подписать и
скопировать в его каталог `/lib/modules/<версия>/extra/`, затем запустить
`sudo depmod -a`. Старый `.ko` для новой версии ядра не подходит.

## 6. Установить кнопку GNOME

Сначала установите CLI в постоянный путь, который использует ярлык:

```bash
sudo install -D -m 0755 ./xonarctl /usr/local/bin/xonarctl
```

Установите ярлык в меню приложений текущего пользователя:

```bash
mkdir -p ~/.local/share/applications
install -m 0644 ./xonar-ae-toggle.desktop \
  ~/.local/share/applications/xonar-ae-toggle.desktop
```

Выйдите из учётной записи и войдите снова, либо подождите обновления меню.
Нажмите клавишу Super, найдите **Переключить выход Xonar AE** и запустите.
GNOME покажет запрос авторизации: она нужна, потому что запись команды в
параметр модуля требует прав администратора. После проверки ярлыка щёлкните
по нему правой кнопкой и выберите **Добавить в избранное** — появится кнопка
в доке.

Ярлык вызывает `pkexec`, поэтому нужен работающий графический агент Polkit
(обычно он уже запущен в GNOME). Вызов из дока переключает выход, но не
показывает всплывающую надпись с новым режимом. Текущее состояние можно
посмотреть командой `sudo /usr/local/bin/xonarctl status`.

## Удаление

Удалите ярлык и CLI:

```bash
rm -f ~/.local/share/applications/xonar-ae-toggle.desktop
sudo rm -f /usr/local/bin/xonarctl
```

Отключите автозагрузку и удалите модуль:

```bash
sudo rm -f /etc/modules-load.d/snd-xonar-ae.conf
sudo rmmod snd_xonar_ae
sudo rm -f /lib/modules/$(uname -r)/extra/snd-xonar-ae.ko
sudo depmod -a
```

## Если что-то не работает

- `Key was rejected by service` — проверьте подпись модуля и MOK.
- `snd-xonar-ae is not loaded` — загрузите модуль: `sudo modprobe snd-xonar-ae`.
- Первый `toggle` при неизвестном состоянии выбирает колонки; дальнейшие
  переключения чередуют выходы по последней успешной команде.
- Кнопка просит пароль, но не переключает — проверьте, что CLI лежит по пути
  `/usr/local/bin/xonarctl`, модуль загружен и в GNOME работает Polkit agent.
- После сборки/подписи проверьте сообщения ядра командой `sudo dmesg | tail -40`.
