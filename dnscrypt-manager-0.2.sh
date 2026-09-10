#!/bin/sh
# dnscrypt-manager — diagnostic/install manager for OpenWrt dnscrypt-proxy2
VERSION="0.2"
BASE_DIR="/etc/dnscrypt-manager"
LOG="$BASE_DIR/manager.log"
STATE="$BASE_DIR/state"
PKG="dnscrypt-proxy2"
BIN="/usr/sbin/dnscrypt-proxy"
INIT="/etc/init.d/dnscrypt-proxy"
CFG_DIR="/etc/dnscrypt-proxy2"
CFG="$CFG_DIR/dnscrypt-proxy.toml"
TEST_IP="127.0.0.53"
TEST_PORT="5353"
TEST_CFG="$BASE_DIR/dnscrypt-proxy-test.toml"
BACKUP_DIR="$BASE_DIR/backups"
TMP="/tmp/dnscrypt-manager.$$"

C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_CYAN='\033[1;36m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

mkdir -p "$BASE_DIR" "$STATE" "$BACKUP_DIR" 2>/dev/null || exit 1
trap 'rm -rf "$TMP" 2>/dev/null' EXIT INT TERM
mkdir -p "$TMP" 2>/dev/null

log(){ printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null; }
ok(){ printf "${C_GREEN}[✓] %s${C_NC}\n" "$*"; log "OK $*"; }
err(){ printf "${C_RED}[✗] %s${C_NC}\n" "$*"; log "ERR $*"; }
info(){ printf "${C_CYAN}[ℹ] %s${C_NC}\n" "$*"; log "INFO $*"; }
warn(){ printf "${C_YELLOW}[!] %s${C_NC}\n" "$*"; log "WARN $*"; }
pause(){ printf '\nНажмите Enter...'; read -r _x; }

pkg_mgr(){
    if command -v opkg >/dev/null 2>&1; then printf 'opkg'; return 0; fi
    if command -v apk >/dev/null 2>&1; then printf 'apk'; return 0; fi
    printf 'none'
}

find_bin(){
    [ -x "$BIN" ] && { printf '%s' "$BIN"; return 0; }
    command -v dnscrypt-proxy 2>/dev/null && return 0
    return 1
}

pkg_installed(){
    p="$(pkg_mgr)"
    case "$p" in
        opkg) opkg status "$PKG" 2>/dev/null | grep -q '^Status: install ok installed$' ;;
        apk) apk info -e "$PKG" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

package_version(){
    p="$(pkg_mgr)"
    case "$p" in
        opkg) opkg status "$PKG" 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p' | head -n1 ;;
        apk) apk info -e "$PKG" >/dev/null 2>&1 && apk info "$PKG" 2>/dev/null | sed -n '1p' ;;
        *) printf '' ;;
    esac
}

binary_version(){
    b="$(find_bin 2>/dev/null)" || return 1
    "$b" -version 2>&1 | head -n1
}

ensure_installed(){
    if pkg_installed && find_bin >/dev/null 2>&1; then
        ok "dnscrypt-proxy2 уже установлен. $(binary_version)"
        return 0
    fi
    p="$(pkg_mgr)"
    [ "$p" != none ] || { err "Не найден менеджер пакетов OpenWrt (opkg/apk)."; return 1; }
    printf "dnscrypt-proxy2 не установлен. Установить сейчас? [Y/n]: "
    read -r a
    case "$a" in n|N|т|Т|no|NO|нет|НЕТ) info "Установка отменена."; return 1;; esac
    log "INSTALL requested package=$PKG manager=$p"
    case "$p" in
        opkg)
            opkg update || { err "opkg update завершился ошибкой."; return 1; }
            opkg install "$PKG" || { err "Не удалось установить $PKG."; return 1; }
            ;;
        apk)
            apk update || { err "apk update завершился ошибкой."; return 1; }
            apk add "$PKG" || { err "Не удалось установить $PKG."; return 1; }
            ;;
    esac
    pkg_installed && find_bin >/dev/null 2>&1 || { err "Пакет заявлен установленным, но бинарник не найден."; return 1; }
    ok "Установка завершена: $(binary_version)"
}

check_openwrt(){
    [ "$(id -u 2>/dev/null)" = 0 ] || { err "Нужны права root."; return 1; }
    [ -f /etc/openwrt_release ] || { err "Это не похоже на OpenWrt."; return 1; }
}

check_dependencies(){
    miss=""
    command -v ip >/dev/null 2>&1 || miss="$miss ip"
    command -v ss >/dev/null 2>&1 || command -v netstat >/dev/null 2>&1 || miss="$miss ss/netstat"
    command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || miss="$miss wget/curl"
    [ -f /etc/ssl/certs/ca-certificates.crt ] || [ -d /etc/ssl/certs ] || miss="$miss ca-bundle"
    [ -n "$miss" ] && warn "Отсутствуют/не подтверждены зависимости:$miss" || ok "Базовые зависимости найдены."
}

backup_config(){
    [ -f "$CFG" ] || return 0
    ts="$(date +%Y%m%d-%H%M%S)"
    cp -p "$CFG" "$BACKUP_DIR/dnscrypt-proxy.toml.$ts" 2>/dev/null || return 1
    printf '%s\n' "$BACKUP_DIR/dnscrypt-proxy.toml.$ts" > "$STATE/last-backup"
    ok "Резервная копия: $BACKUP_DIR/dnscrypt-proxy.toml.$ts"
}

check_config(){
    ensure_installed || return 1
    b="$(find_bin)" || return 1
    [ -f "$CFG" ] || { err "Конфиг $CFG не найден. Пакет установлен некорректно."; return 1; }
    out="$TMP/check"
    "$b" -config "$CFG" -check >"$out" 2>&1
    rc=$?
    cat "$out"
    if [ "$rc" -eq 0 ]; then
        ok "dnscrypt-proxy configuration check: OK"
        return 0
    fi
    err "dnscrypt-proxy configuration check: FAILED"
    return 1
}

make_test_config(){
    ensure_installed || return 1
    mkdir -p "$BASE_DIR" || return 1
    if [ -f "$CFG" ]; then
        cp -p "$CFG" "$TEST_CFG" || return 1
        sed -i "s#^[[:space:]]*listen_addresses[[:space:]]*=.*#listen_addresses = ['$TEST_IP:$TEST_PORT']#" "$TEST_CFG" || return 1
    else
        err "Пакет не установил $CFG — не создаю самодельный конфиг. Сначала проверьте установку пакета."
        return 1
    fi
    ok "Создан изолированный тестовый конфиг: $TEST_CFG"
}

check_test_config(){
    ensure_installed || return 1
    [ -f "$TEST_CFG" ] || make_test_config || return 1
    b="$(find_bin)" || return 1
    out="$TMP/test-check"
    "$b" -config "$TEST_CFG" -check >"$out" 2>&1
    rc=$?
    cat "$out"
    [ "$rc" -eq 0 ] || { err "Изолированный тестовый конфиг не прошёл -check."; return 1; }
    ok "Изолированный тестовый конфиг прошёл -check."
}

listener_check(){
    if command -v ss >/dev/null 2>&1; then
        ss -lnptu 2>/dev/null | grep -Eq "(^|[[:space:]])(${TEST_IP}):${TEST_PORT}([[:space:]]|$)" && return 0
        ss -lnptu 2>/dev/null | grep -Eq "127\.0\.0\.1:${TEST_PORT}([[:space:]]|$)" && return 0
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lnptu 2>/dev/null | grep -Eq "${TEST_IP}:${TEST_PORT}([[:space:]]|$)" && return 0
    fi
    return 1
}

stop_test(){
    if [ -f "$STATE/test.pid" ]; then
        p="$(cat "$STATE/test.pid" 2>/dev/null)"
        if [ -n "$p" ]; then
            kill "$p" 2>/dev/null || true
            sleep 1
            kill -9 "$p" 2>/dev/null || true
        fi
        rm -f "$STATE/test.pid"
    fi
}

start_test(){
    check_test_config || return 1
    stop_test
    b="$(find_bin)" || return 1
    logf="$BASE_DIR/test-proxy.log"
    "$b" -config "$TEST_CFG" >"$logf" 2>&1 &
    p=$!
    printf '%s\n' "$p" > "$STATE/test.pid"
    sleep 2
    if kill -0 "$p" 2>/dev/null && listener_check; then
        ok "Изолированный dnscrypt-proxy запущен на $TEST_IP:$TEST_PORT (PID $p)."
        return 0
    fi
    err "Изолированный dnscrypt-proxy не запустился."
    cat "$logf" 2>/dev/null
    stop_test
    return 1
}

query_test(){
    command -v dig >/dev/null 2>&1 || { err "Для DNS-теста нужен dig."; return 1; }
    if ! [ -f "$STATE/test.pid" ] || ! kill -0 "$(cat "$STATE/test.pid" 2>/dev/null)" 2>/dev/null; then
        start_test || return 1
    fi
    printf "\nПроверка example.com через %s:%s\n\n" "$TEST_IP" "$TEST_PORT"
    dig +time=4 +tries=1 @"$TEST_IP" -p "$TEST_PORT" example.com A
    rc1=$?
    printf "\nПроверка yandex.ru через %s:%s\n\n" "$TEST_IP" "$TEST_PORT"
    dig +time=4 +tries=1 @"$TEST_IP" -p "$TEST_PORT" yandex.ru A
    rc2=$?
    [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] || return 1
}

show_resolvers(){
    ensure_installed || return 1
    [ -f "$CFG" ] || { err "Нет $CFG"; return 1; }
    b="$(find_bin)" || return 1
    "$b" -config "$CFG" -list 2>&1 | head -n 160
}

show_status(){
    printf "\n${C_YELLOW}DNSCrypt Manager $VERSION${C_NC}\n"
    if pkg_installed; then printf "  Пакет:          ${C_GREEN}установлен${C_NC} • %s\n" "$(package_version)"; else printf "  Пакет:          ${C_RED}не установлен${C_NC}\n"; fi
    if find_bin >/dev/null 2>&1; then printf "  Бинарник:       %s\n" "$(find_bin)"; printf "  Версия:         %s\n" "$(binary_version)"; else printf "  Бинарник:       ${C_RED}не найден${C_NC}\n"; fi
    [ -x "$INIT" ] && printf "  Init:            ${C_GREEN}есть${C_NC} • %s\n" "$INIT" || printf "  Init:            ${C_RED}нет${C_NC}\n"
    [ -f "$CFG" ] && printf "  TOML:            ${C_GREEN}есть${C_NC} • %s\n" "$CFG" || printf "  TOML:            ${C_RED}нет${C_NC}\n"
    if listener_check; then printf "  Тестовый listener: ${C_GREEN}активен${C_NC} • %s:%s\n" "$TEST_IP" "$TEST_PORT"; else printf "  Тестовый listener: ${C_YELLOW}не активен${C_NC} • %s:%s\n" "$TEST_IP" "$TEST_PORT"; fi
    if [ -f "$INIT" ]; then "$INIT" enabled >/dev/null 2>&1 && printf "  Автозапуск:     ${C_GREEN}включён${C_NC}\n" || printf "  Автозапуск:     ${C_YELLOW}не включён${C_NC}\n"; fi
    command -v uci >/dev/null 2>&1 && printf "  dnsmasq:         %s\n" "$(uci -q get dhcp.@dnsmasq[0].noresolv 2>/dev/null || printf 'не проверен')"
}

install_and_check(){
    ensure_installed || return 1
    check_dependencies
    [ -x "$INIT" ] || { err "После установки не найден init-скрипт $INIT."; return 1; }
    [ -f "$CFG" ] || { err "После установки не найден $CFG."; return 1; }
    check_config || return 1
    make_test_config || return 1
    check_test_config || return 1
    ok "Установка и базовая проверка dnscrypt-proxy2 завершены."
    info "Роутерный DNS и старый dns-manager не изменялись."
}

main(){
    check_openwrt || exit 1
    while :; do
        show_status
        printf "\n${C_YELLOW}ДЕЙСТВИЯ${C_NC}\n"
        printf "  [1] Установить/проверить dnscrypt-proxy2\n"
        printf "  [2] Проверить штатный TOML (-check)\n"
        printf "  [3] Подготовить изолированный тест\n"
        printf "  [4] Запустить/проверить изолированный proxy\n"
        printf "  [5] Проверить DNS-запросы через тестовый proxy\n"
        printf "  [6] Остановить тестовый proxy\n"
        printf "  [7] Показать доступные resolvers\n"
        printf "  [8] Сделать backup штатного TOML\n"
        printf "  [9] Показать журнал\n"
        printf "  [Enter] Выход\n\nВыберите пункт: "
        read -r c
        case "$c" in
            1) install_and_check; pause ;;
            2) check_config; pause ;;
            3) make_test_config && check_test_config; pause ;;
            4) start_test; pause ;;
            5) query_test; pause ;;
            6) stop_test && ok "Тестовый proxy остановлен."; pause ;;
            7) show_resolvers; pause ;;
            8) backup_config; pause ;;
            9) cat "$LOG" 2>/dev/null || info "Журнал пуст."; pause ;;
            '') stop_test; exit 0 ;;
            *) warn "Неверный выбор."; pause ;;
        esac
    done
}
main "$@"
