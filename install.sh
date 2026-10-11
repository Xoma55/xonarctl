#!/usr/bin/env bash
set -Eeuo pipefail

die() {
	printf 'Ошибка: %s\n' "$*" >&2
	exit 1
}

note() {
	printf '\n==> %s\n' "$*"
}

if (( EUID != 0 )); then
	die "Запустите установщик от root: sudo $0 [имя_пользователя_GNOME]"
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
KVER=$(uname -r)
KDIR="/lib/modules/$KVER/build"
MODULE="$SCRIPT_DIR/snd-xonar-ae.ko"
CLI="$SCRIPT_DIR/xonarctl"
DESKTOP="$SCRIPT_DIR/xonar-ae-toggle.desktop"

TARGET_USER=${1:-${SUDO_USER:-}}
if [[ -z "$TARGET_USER" ]]; then
	TARGET_USER=$(stat -c '%U' "$SCRIPT_DIR")
fi
[[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || \
	die "Не определён пользователь GNOME. Запустите: sudo $0 xoma55"
PASSWD_ENTRY=$(getent passwd "$TARGET_USER") || \
	die "Пользователь '$TARGET_USER' не найден"
TARGET_HOME=$(cut -d: -f6 <<<"$PASSWD_ENTRY")
TARGET_GROUP=$(id -gn "$TARGET_USER")
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || \
	die "Не найдена домашняя папка пользователя '$TARGET_USER'"

[[ -e "$KDIR" ]] || die "Нет заголовков для ядра $KVER. Установите kernel-devel-$KVER и повторите запуск."
[[ -x "$CLI" ]] || die "Не найден исполняемый файл $CLI"
[[ -f "$DESKTOP" ]] || die "Не найден ярлык $DESKTOP"

note "Сборка модуля для ядра $KVER"
make -C "$SCRIPT_DIR" KDIR="$KDIR" clean
make -C "$SCRIPT_DIR" KDIR="$KDIR"
[[ -f "$MODULE" ]] || die "Сборка не создала $MODULE"

SB_STATE=$(mokutil --sb-state 2>&1) || die "Не удалось проверить Secure Boot: $SB_STATE"
if grep -q 'SecureBoot enabled' <<<"$SB_STATE"; then
	note "Secure Boot включён: подписываю модуль ключом akmods"
	KEY=/etc/pki/akmods/private/private_key.priv
	CERT=/etc/pki/akmods/certs/public_key.der
	SIGN_FILE="$KDIR/scripts/sign-file"
	[[ -r "$KEY" && -r "$CERT" ]] || die "Не найден ключ akmods. Создайте/настройте MOK ключ и повторите установку."
	[[ -x "$SIGN_FILE" ]] || die "Не найден инструмент подписи $SIGN_FILE"

	TEST_OUTPUT=$(mokutil --test-key "$CERT" 2>&1 || true)
	if grep -qi 'already enrolled' <<<"$TEST_OUTPUT"; then
		printf 'Ключ MOK уже зарегистрирован.\n'
	elif grep -qiE 'already.*(request|pending)|pending.*(MOK|key)' <<<"$TEST_OUTPUT"; then
		cat <<EOF

Запрос регистрации ключа уже ожидает подтверждения. Перезагрузите компьютер,
в MOK Manager
выберите Enroll MOK → Continue → Yes, введите заданный пароль и подтвердите
перезагрузку. Затем повторно запустите установщик:

  sudo "$SCRIPT_DIR/install.sh" "$TARGET_USER"

Установка остановлена до регистрации ключа; модуль не загружался.
EOF
		exit 0
	else
		note "Ключ MOK не зарегистрирован; запускаю его импорт"
		mokutil --import "$CERT" || die "Не удалось добавить ключ в очередь MOK"
		cat <<EOF

Запрос регистрации ключа поставлен в очередь. Если mokutil запросил пароль,
это временный пароль, который вы вводите вслепую, без отображения символов.
Перезагрузите компьютер, в MOK Manager выберите Enroll MOK → Continue → Yes,
введите этот пароль и подтвердите перезагрузку. Затем повторно запустите:

  sudo "$SCRIPT_DIR/install.sh" "$TARGET_USER"

Установка остановлена до регистрации ключа; модуль не загружался.
EOF
		exit 0
	fi

	"$SIGN_FILE" sha256 "$KEY" "$CERT" "$MODULE"
	SIGNER=$(modinfo -F signer "$MODULE")
	[[ -n "$SIGNER" ]] || die "Подпись модуля не обнаружена после sign-file"
	printf 'Подписано ключом: %s\n' "$SIGNER"
else
	note "Secure Boot выключён; подпись модуля не требуется"
fi

note "Установка системных файлов"
install -D -m 0644 "$MODULE" "/lib/modules/$KVER/extra/snd-xonar-ae.ko"
install -D -m 0755 "$CLI" /usr/local/bin/xonarctl
printf '%s\n' snd-xonar-ae > /etc/modules-load.d/snd-xonar-ae.conf
chmod 0644 /etc/modules-load.d/snd-xonar-ae.conf
depmod -a "$KVER"

note "Установка ярлыка GNOME для пользователя $TARGET_USER"
DESKTOP_DIR="$TARGET_HOME/.local/share/applications"
install -D -o "$TARGET_USER" -g "$TARGET_GROUP" -m 0644 \
	"$DESKTOP" "$DESKTOP_DIR/xonar-ae-toggle.desktop"
if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

note "Перезагрузка установленной версии модуля"
if grep -q '^snd_xonar_ae ' /proc/modules; then
	modprobe -r snd_xonar_ae || die "Не удалось выгрузить старый модуль; закройте программы, использующие его, и повторите запуск"
fi
modprobe snd-xonar-ae || die "Модуль не загрузился. Проверьте: journalctl -k -n 50"

cat <<EOF

Установка завершена.

Проверка и ручное переключение:
  /usr/local/bin/xonarctl status
  /usr/local/bin/xonarctl speakers
  /usr/local/bin/xonarctl headphones
  /usr/local/bin/xonarctl toggle

Ярлык установлен для пользователя $TARGET_USER. Нажмите Super, найдите
«Переключить выход Xonar AE», запустите и подтвердите запрос авторизации.
Затем добавьте приложение в избранное, чтобы закрепить его в доке GNOME.

После обновления ядра запустите этот установщик повторно из этой папки.
EOF
