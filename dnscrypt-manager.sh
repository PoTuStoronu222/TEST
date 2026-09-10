#!/bin/sh
# DNSCrypt Manager 0.3
# Experimental primary DNS manager based on dnscrypt-proxy2.
# Phase 1: install, inspect, validate and run an isolated instance.
VERSION="0.3"
BASE_DIR="/etc/dnscrypt-manager"
CFG_DIR="/etc/dnscrypt-proxy2"
CFG="$CFG_DIR/dnscrypt-proxy.toml"
BIN="/usr/sbin/dnscrypt-proxy"
INIT="/etc/init.d/dnscrypt-proxy"
TEST_DIR="$BASE_DIR/test"
TEST_CFG="$TEST_DIR/dnscrypt-proxy.toml"
TEST_LOG="$TEST_DIR/proxy.log"
TEST_PID="$TEST_DIR/proxy.pid"
STATE="$BASE_DIR/state"
LOG="$BASE_DIR/manager.log"
BACKUP_DIR="$BASE_DIR/backups"
TMP="/tmp/dnscrypt-manager.$$"
PKG="dnscrypt-proxy2"
TEST_IP="127.0.0.1"
TEST_PORT=""

C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_CYAN='\033[1;36m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

mkdir -p "$BASE_DIR" "$TEST_DIR" "$STATE" "$BACKUP_DIR" 2>/dev/null || exit 1
mkdir -p "$TMP" 2>/dev/null || exit 1
trap 'rm -rf "$TMP" 2>/dev/null' EXIT INT TERM

log(){ printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null; }
ok(){ printf "${C_GREEN}[✓] %s${C_NC}\n" "$*"; log "OK $*"; }
err(){ printf "${C_RED}[✗] %s${C_NC}\n" "$*"; log "ERR $*"; }
info(){ printf "${C_CYAN}[ℹ] %s${C_NC}\n" "$*"; log "INFO $*"; }
warn(){ printf "${C_YELLOW}[!] %s${C_NC}\n" "$*"; log "WARN $*"; }
pause(){ printf '\nНажмите Enter...'; read -r _x; }

pkg_mgr(){
    if command -v apk >/dev/null 2>&1; then printf 'apk'; return 0; fi
    if command -v opkg >/dev/null 2>&1; then printf 'opkg'; return 0; fi
    printf 'none'
}

pkg_installed(){
    case "$(pkg_mgr)" in
        apk) apk info -e "$PKG" >/dev/null 2>&1 ;;
        opkg) opkg status "$PKG" 2>/dev/null | grep -q '^Status: install ok installed$' ;;
        *) return 1 ;;
    esac
}

pkg_version(){
    case "$(pkg_mgr)" in
        apk) apk info "$PKG" 2>/dev/null | sed -n '1p' ;;
        opkg) opkg status "$PKG" 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p' | head -n1 ;;
        *) : ;;
    esac
}

binary_version(){
    [ -x "$BIN" ] || return 1
    "$BIN" -version 2>&1 | head -n1
}

check_env(){
    [ "$(id -u 2>/dev/null)" = 0 ] || { err "Нужны права root."; return 1; }
    [ -f /etc/openwrt_release ] || { err "Это не OpenWrt."; return 1; }
    . /etc/openwrt_release 2>/dev/null || true
    ok "OpenWrt: ${DISTRIB_RELEASE:-unknown} | ${DISTRIB_TARGET:-unknown} | ${DISTRIB_ARCH:-unknown}"
}

check_tools(){
    _miss=""
    command -v ip >/dev/null 2>&1 || _miss="$_miss ip"
    command -v awk >/dev/null 2>&1 || _miss="$_miss awk"
    command -v sed >/dev/null 2>&1 || _miss="$_miss sed"
    command -v grep >/dev/null 2>&1 || _miss="$_miss grep"
    if command -v ss >/dev/null 2>&1; then :; elif command -v netstat >/dev/null 2>&1; then :; else _miss="$_miss ss/netstat"; fi
    if command -v dig >/dev/null 2>&1; then :; elif command -v nslookup >/dev/null 2>&1; then :; else _miss="$_miss dig/nslookup"; fi
    [ -z "$_miss" ] && ok "Диагностические утилиты найдены." || warn "Не хватает:$ _miss"
}

ensure_package(){
    if pkg_installed && [ -x "$BIN" ]; then
        ok "dnscrypt-proxy2 установлен: $(binary_version)"
        return 0
    fi
    _pm="$(pkg_mgr)"
    [ "$_pm" != none ] || { err "Не найден apk/opkg."; return 1; }
    printf "dnscrypt-proxy2 не установлен. Установить сейчас? [Y/n]: "
    read -r _a
    case "$_a" in n|N|no|NO|нет|НЕТ|т|Т) info "Установка отменена."; return 1;; esac
    case "$_pm" in
        apk)
            apk update || { err "apk update завершился ошибкой."; return 1; }
            apk add "$PKG" || { err "Не удалось установить $PKG."; return 1; }
            ;;
        opkg)
            opkg update || { err "opkg update завершился ошибкой."; return 1; }
            opkg install "$PKG" || { err "Не удалось установить $PKG."; return 1; }
            ;;
    esac
    pkg_installed && [ -x "$BIN" ] || { err "Пакет установлен не полностью: бинарник не найден."; return 1; }
    ok "Установлено: $(binary_version)"
}

find_free_port(){
    TEST_PORT=""
    _p=5353
    while [ "$_p" -le 5399 ]; do
        _busy=0
        if command -v ss >/dev/null 2>&1; then
            ss -lnu 2>/dev/null | grep -Eq "(^|[[:space:]])${TEST_IP}:$_p([[:space:]]|$)" && _busy=1
            ss -lnt 2>/dev/null | grep -Eq "(^|[[:space:]])${TEST_IP}:$_p([[:space:]]|$)" && _busy=1
        elif command -v netstat >/dev/null 2>&1; then
            netstat -lnu 2>/dev/null | grep -Eq "${TEST_IP}:$_p([[:space:]]|$)" && _busy=1
            netstat -lnt 2>/dev/null | grep -Eq "${TEST_IP}:$_p([[:space:]]|$)" && _busy=1
        fi
        if [ "$_busy" = 0 ]; then TEST_PORT="$_p"; return 0; fi
        _p=$((_p+1))
    done
    return 1
}

backup_config(){
    [ -f "$CFG" ] || { info "Штатный TOML пока отсутствует."; return 0; }
    _ts="$(date +%Y%m%d-%H%M%S)"
    _dst="$BACKUP_DIR/dnscrypt-proxy.toml.$_ts"
    cp -p "$CFG" "$_dst" || return 1
    printf '%s\n' "$_dst" > "$STATE/last-backup"
    ok "Backup: $_dst"
}

check_config(){
    ensure_package || return 1
    [ -f "$CFG" ] || { err "Не найден штатный конфиг: $CFG"; return 1; }
    _o="$TMP/check"
    "$BIN" -config "$CFG" -check >"$_o" 2>&1
    _rc=$?
    cat "$_o"
    [ "$_rc" -eq 0 ] || { err "Проверка штатного TOML завершилась ошибкой."; return 1; }
    ok "Штатный TOML: -check OK"
}

make_test_config(){
    ensure_package || return 1
    [ -f "$CFG" ] || { err "Сначала нужен штатный TOML от пакета."; return 1; }
    find_free_port || { err "Не найден свободный тестовый UDP/TCP порт 5353-5399."; return 1; }
    cp -p "$CFG" "$TEST_CFG" || return 1
    # Replace any existing listen_addresses line. If absent, append one.
    if grep -Eq '^[[:space:]]*listen_addresses[[:space:]]*=' "$TEST_CFG"; then
        sed -i "s#^[[:space:]]*listen_addresses[[:space:]]*=.*#listen_addresses = ['$TEST_IP:$TEST_PORT']#" "$TEST_CFG" || return 1
    else
        printf '\nlisten_addresses = [\"%s:%s\"]\n' "$TEST_IP" "$TEST_PORT" >> "$TEST_CFG" || return 1
    fi
    printf '%s\n' "$TEST_PORT" > "$STATE/test-port"
    ok "Изолированный тестовый конфиг: $TEST_CFG"
    info "Тестовый listener: $TEST_IP:$TEST_PORT"
}

check_test_config(){
    [ -f "$TEST_CFG" ] || make_test_config || return 1
    _o="$TMP/test-check"
    "$BIN" -config "$TEST_CFG" -check >"$_o" 2>&1
    _rc=$?
    cat "$_o"
    [ "$_rc" -eq 0 ] || { err "Тестовый TOML не прошёл -check."; return 1; }
    ok "Тестовый TOML: -check OK"
}

listener_up(){
    [ -n "$TEST_PORT" ] || TEST_PORT="$(cat "$STATE/test-port" 2>/dev/null)"
    [ -n "$TEST_PORT" ] || return 1
    if command -v ss >/dev/null 2>&1; then
        ss -lnu 2>/dev/null | grep -Eq "(^|[[:space:]])${TEST_IP}:$TEST_PORT([[:space:]]|$)" && return 0
        ss -lnt 2>/dev/null | grep -Eq "(^|[[:space:]])${TEST_IP}:$TEST_PORT([[:space:]]|$)" && return 0
    elif command -v netstat >/dev/null 2>&1; then
        netstat -lnu 2>/dev/null | grep -Eq "${TEST_IP}:$TEST_PORT([[:space:]]|$)" && return 0
        netstat -lnt 2>/dev/null | grep -Eq "${TEST_IP}:$TEST_PORT([[:space:]]|$)" && return 0
    fi
    return 1
}

stop_test(){
    if [ -s "$TEST_PID" ]; then
        _p="$(cat "$TEST_PID" 2>/dev/null)"
        case "$_p" in ''|*[!0-9]*) :;; *) kill "$_p" 2>/dev/null || true; sleep 1; kill -9 "$_p" 2>/dev/null || true;; esac
    fi
    rm -f "$TEST_PID"
}

start_test(){
    ensure_package || return 1
    make_test_config || return 1
    check_test_config || return 1
    stop_test
    "$BIN" -config "$TEST_CFG" >"$TEST_LOG" 2>&1 &
    _p=$!
    printf '%s\n' "$_p" > "$TEST_PID"
    _i=0
    while [ "$_i" -lt 8 ]; do
        if kill -0 "$_p" 2>/dev/null && listener_up; then
            ok "Изолированный proxy работает: $TEST_IP:$TEST_PORT (PID $_p)"
            return 0
        fi
        sleep 1
        _i=$((_i+1))
    done
    err "Изолированный dnscrypt-proxy не запустился."
    cat "$TEST_LOG" 2>/dev/null
    stop_test
    return 1
}

query_test(){
    [ -s "$TEST_PID" ] || start_test || return 1
    TEST_PORT="$(cat "$STATE/test-port" 2>/dev/null)"
    if command -v dig >/dev/null 2>&1; then
        dig +time=4 +tries=1 @"$TEST_IP" -p "$TEST_PORT" example.com A
        _r1=$?
        printf '\n'
        dig +time=4 +tries=1 @"$TEST_IP" -p "$TEST_PORT" yandex.ru A
        _r2=$?
        [ "$_r1" -eq 0 ] && [ "$_r2" -eq 0 ] || return 1
    else
        nslookup -port="$TEST_PORT" example.com "$TEST_IP" 2>&1
        _r1=$?
        nslookup -port="$TEST_PORT" yandex.ru "$TEST_IP" 2>&1
        _r2=$?
        [ "$_r1" -eq 0 ] && [ "$_r2" -eq 0 ] || return 1
    fi
    ok "Тестовые DNS-запросы прошли."
}

show_resolvers(){
    ensure_package || return 1
    [ -f "$CFG" ] || { err "Не найден $CFG"; return 1; }
    "$BIN" -config "$CFG" -list 2>&1 | head -n 220
}

install_check_all(){
    check_env || return 1
    ensure_package || return 1
    check_tools
    [ -x "$INIT" ] || { err "Нет init: $INIT"; return 1; }
    [ -f "$CFG" ] || { err "Нет штатного TOML: $CFG"; return 1; }
    check_config || return 1
    make_test_config || return 1
    check_test_config || return 1
    ok "Установка и проверки инфраструктуры завершены."
    info "Системный DNS, dnsmasq и старый dns-manager не изменялись."
}

status(){
    printf '\n%s\n' "${C_YELLOW}DNSCrypt Manager $VERSION${C_NC}"
    if pkg_installed; then printf '  Пакет:             %s • %s\n' "${C_GREEN}установлен${C_NC}" "$(pkg_version)"; else printf '  Пакет:             %s\n' "${C_RED}не установлен${C_NC}"; fi
    if [ -x "$BIN" ]; then printf '  Бинарник:          %s • %s\n' "$BIN" "$(binary_version)"; else printf '  Бинарник:          %s\n' "${C_RED}не найден${C_NC}"; fi
    [ -x "$INIT" ] && printf '  Init:               %s\n' "${C_GREEN}есть${C_NC}" || printf '  Init:               %s\n' "${C_RED}нет${C_NC}"
    [ -f "$CFG" ] && printf '  Штатный TOML:       %s\n' "${C_GREEN}$CFG${C_NC}" || printf '  Штатный TOML:       %s\n' "${C_RED}нет${C_NC}"
    TEST_PORT="$(cat "$STATE/test-port" 2>/dev/null)"
    if [ -n "$TEST_PORT" ] && listener_up; then printf '  Тестовый listener:  %s • %s:%s\n' "${C_GREEN}активен${C_NC}" "$TEST_IP" "$TEST_PORT"; else printf '  Тестовый listener:  %s\n' "${C_YELLOW}не активен${C_NC}"; fi
    if [ -x "$INIT" ] && "$INIT" enabled >/dev/null 2>&1; then printf '  Автозапуск пакета:  %s\n' "${C_GREEN}включён${C_NC}"; else printf '  Автозапуск пакета:  %s\n' "${C_YELLOW}выкл/не проверен${C_NC}"; fi
}

main(){
    check_env || exit 1
    while :; do
        status
        printf '\n${C_YELLOW}ДЕЙСТВИЯ${C_NC}\n'
        printf '  [1] Установить/проверить dnscrypt-proxy2\n'
        printf '  [2] Проверить штатный TOML\n'
        printf '  [3] Создать/проверить изолированный конфиг\n'
        printf '  [4] Запустить изолированный proxy\n'
        printf '  [5] Проверить реальные DNS-запросы\n'
        printf '  [6] Остановить тестовый proxy\n'
        printf '  [7] Показать доступные resolvers\n'
        printf '  [8] Сделать backup штатного TOML\n'
        printf '  [9] Полная проверка инфраструктуры\n'
        printf '  [0] Журнал\n'
        printf '  [Enter] Выход\n\nВыберите пункт: '
        read -r _c
        case "$_c" in
            1) ensure_package; pause;;
            2) check_config; pause;;
            3) make_test_config && check_test_config; pause;;
            4) start_test; pause;;
            5) query_test; pause;;
            6) stop_test; ok "Тестовый proxy остановлен."; pause;;
            7) show_resolvers; pause;;
            8) backup_config; pause;;
            9) install_check_all; pause;;
            0) cat "$LOG" 2>/dev/null || info "Журнал пуст."; pause;;
            '') stop_test; exit 0;;
            *) warn "Неверный выбор."; pause;;
        esac
    done
}

main "$@"
