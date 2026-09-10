#!/bin/sh
# DNSCrypt Manager
# Primary DNS manager based on dnscrypt-proxy2.
# Canonical filename: dnscrypt-manager.sh
VERSION="1.2"

BASE_DIR="/etc/dnscrypt-manager"
STATE_DIR="$BASE_DIR/state"
BACKUP_DIR="$BASE_DIR/backups"
CATALOG="$BASE_DIR/dns-catalog.conf"
MAIN_CFG="/etc/dnscrypt-proxy2/dnscrypt-proxy.toml"
BASE_CFG="$STATE_DIR/package-base.toml"
RU_CFG="$BASE_DIR/dnscrypt-proxy-ru.toml"
RU_LOG="$BASE_DIR/dnscrypt-proxy-ru.log"
RU_PID="$STATE_DIR/ru.pid"
LOG="$BASE_DIR/manager.log"
BIN="/usr/sbin/dnscrypt-proxy"
PKG="dnscrypt-proxy2"
PKG_INIT="/etc/init.d/dnscrypt-proxy"
MANAGER_INIT="/etc/init.d/dnscrypt-manager"
MAIN_PORT=5053
RU_PORT=5054
TEST_PORT_FIRST=5353
TEST_PORT_LAST=5399

C_GREEN='\033[1;32m'; C_RED='\033[1;31m'; C_CYAN='\033[1;36m'; C_YELLOW='\033[1;33m'; C_MAGENTA='\033[1;35m'; C_NC='\033[0m'; C_BOLD='\033[1m'; C_WHITE='\033[1;37m'

mkdir -p "$BASE_DIR" "$STATE_DIR" "$BACKUP_DIR" 2>/dev/null || exit 1
TMP="$(mktemp -d /tmp/dnscrypt-manager.XXXXXX 2>/dev/null || { d="/tmp/dnscrypt-manager.$$"; mkdir -p "$d"; printf '%s' "$d"; })"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT INT TERM

log(){ printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null; }
ok(){ printf "${C_GREEN}[✓] %s${C_NC}\n" "$*"; log "OK $*"; }
err(){ printf "${C_RED}[✗] %s${C_NC}\n" "$*"; log "ERR $*"; }
warn(){ printf "${C_YELLOW}[!] %s${C_NC}\n" "$*"; log "WARN $*"; }
info(){ printf "${C_CYAN}[ℹ] %s${C_NC}\n" "$*"; log "INFO $*"; }
pause(){ printf '\n%b' "${C_WHITE}Нажмите Enter...${C_NC}"; read -r _x; }
menu_prompt(){ printf '\nВыберите пункт: '; }

pkg_mgr(){ command -v apk >/dev/null 2>&1 && { printf apk; return; }; command -v opkg >/dev/null 2>&1 && { printf opkg; return; }; printf none; }
pkg_installed(){ case "$(pkg_mgr)" in apk) apk info -e "$PKG" >/dev/null 2>&1;; opkg) opkg status "$PKG" 2>/dev/null | grep -q '^Status: install ok installed$';; *) return 1;; esac; }
proxy_version(){ [ -x "$BIN" ] && "$BIN" -version 2>&1 | head -n1; }

check_env(){ [ "$(id -u 2>/dev/null)" = 0 ] || { err "Нужны права root."; return 1; }; [ -f /etc/openwrt_release ] || { err "Это не OpenWrt."; return 1; }; . /etc/openwrt_release 2>/dev/null || true; ok "OpenWrt: ${DISTRIB_RELEASE:-?} | ${DISTRIB_TARGET:-?} | ${DISTRIB_ARCH:-?}"; }
ensure_package(){
    if pkg_installed && [ -x "$BIN" ]; then return 0; fi
    pm="$(pkg_mgr)"; [ "$pm" != none ] || { err "Не найден apk/opkg."; return 1; }
    printf "dnscrypt-proxy2 не установлен. Установить сейчас? [Y/n]: "; read -r a
    case "$a" in n|N|no|NO|нет|Нет|НЕТ|т|Т) return 1;; esac
    case "$pm" in apk) apk update && apk add "$PKG" || return 1;; opkg) opkg update && opkg install "$PKG" || return 1;; esac
    pkg_installed && [ -x "$BIN" ] || { err "dnscrypt-proxy2 установлен неполностью."; return 1; }
    ok "dnscrypt-proxy2 установлен: $(proxy_version)"
}

write_catalog(){
cat > "$CATALOG" <<EOF_CATALOG
mafioznik|bypass|Mafioznik DNS|https://dns.mafioznik.com/dns-query|ru/global|sdns://AgAAAAAAAAAAAAARZG5zLm1hZmlvem5pay5jb20KL2Rucy1xdWVyeQ
mafioznik_xyz|bypass|Mafioznik DNS XYZ|https://dns.mafioznik.xyz/dns-query|ru/global|sdns://AgAAAAAAAAAAAAARZG5zLm1hZmlvem5pay54eXoKL2Rucy1xdWVyeQ
astracat|bypass|Astrakat DNS|https://dns.astrakat.ru/dns-query|ru/global|sdns://AgAAAAAAAAAAAAAPZG5zLmFzdHJha2F0LnJ1Ci9kbnMtcXVlcnk
astracat_1498|bypass|AstraCat DNS :1498|https://dns.astrakat.ru:1498/dns-query|ru/global|sdns://AgAAAAAAAAAAAAAUZG5zLmFzdHJha2F0LnJ1OjE0OTgKL2Rucy1xdWVyeQ
astracat_8443|bypass|AstraCat DNS :8443|https://dns.astrakat.ru:8443/dns-query|ru/global|sdns://AgAAAAAAAAAAAAAUZG5zLmFzdHJha2F0LnJ1Ojg0NDMKL2Rucy1xdWVyeQ
malw_link|bypass|Malw.link|https://dns.malw.link/dns-query|ru/global|sdns://AgAAAAAAAAAAAAANZG5zLm1hbHcubGluawovZG5zLXF1ZXJ5
xbox_dns|bypass|Xbox DNS|https://xbox-dns.ru/dns-query|ru/global|sdns://AgAAAAAAAAAAAAALeGJveC1kbnMucnUKL2Rucy1xdWVyeQ
geohide|bypass|GeoHide DNS|https://dns.geohide.ru:444/dns-query|ru/global|sdns://AgAAAAAAAAAAAAASZG5zLmdlb2hpZGUucnU6NDQ0Ci9kbnMtcXVlcnk
geohide_8443|bypass|GeoHide DNS :8443|https://dns.geohide.ru:8443/dns-query|ru/global|sdns://AgAAAAAAAAAAAAATZG5zLmdlb2hpZGUucnU6ODQ0MwovZG5zLXF1ZXJ5
comss_ru|bypass|Comss DNS RU|https://dns.comss.ru/dns-query|ru/global|sdns://AgAAAAAAAAAAAAAMZG5zLmNvbXNzLnJ1Ci9kbnMtcXVlcnk
comss_bypass|bypass|Comss.one|https://dns.comss.one/dns-query|ru/global|sdns://AgAAAAAAAAAAAAANZG5zLmNvbXNzLm9uZQovZG5zLXF1ZXJ5
comss_adblock_bypass|bypass|Comss.one Ad Filter|https://router.comss.one/dns-query|ru/global|sdns://AgAAAAAAAAAAAAAQcm91dGVyLmNvbXNzLm9uZQovZG5zLXF1ZXJ5
dns_ai_ru|bypass|DNS-AI.RU|https://dns.dns-ai.ru/dns-query|ru/global|sdns://AgAAAAAAAAAAAAANZG5zLmRucy1haS5ydQovZG5zLXF1ZXJ5
yo1nk|bypass|YO1NK DNS|https://dns.yo1nk.app/dns-query|global|sdns://AgAAAAAAAAAAAAANZG5zLnlvMW5rLmFwcAovZG5zLXF1ZXJ5
vppay|bypass|VPPay DNS|https://dns.vppay.ru/dns-query|ru/global|sdns://AgAAAAAAAAAAAAAMZG5zLnZwcGF5LnJ1Ci9kbnMtcXVlcnk
dynx|bypass|DynX DNS|https://dns.dynx.pro/dns-query|global|sdns://AgAAAAAAAAAAAAAMZG5zLmR5bngucHJvCi9kbnMtcXVlcnk
paesa|bypass|Paesa DNS|https://dns.paesa.es/dns-query|global|sdns://AgAAAAAAAAAAAAAMZG5zLnBhZXNhLmVzCi9kbnMtcXVlcnk
anon_no|bypass|Anon.no DNS|https://dns.anon.no/dns-query|norway|sdns://AgAAAAAAAAAAAAALZG5zLmFub24ubm8KL2Rucy1xdWVyeQ
bebas_unfiltered|bypass|BebasDNS Unfiltered|https://dns.bebasid.com/unfiltered|id/global|sdns://AgAAAAAAAAAAAAAPZG5zLmJlYmFzaWQuY29tCy91bmZpbHRlcmVk
dns4all|bypass|DNS4all|https://doh.dns4all.eu/dns-query|eu/global|sdns://AgAAAAAAAAAAAAAOZG9oLmRuczRhbGwuZXUKL2Rucy1xdWVyeQ
dns4eu_unfiltered|clean|DNS4EU Unfiltered|https://unfiltered.joindns4.eu/dns-query|eu|sdns://AgAAAAAAAAAAAAAWdW5maWx0ZXJlZC5qb2luZG5zNC5ldQovZG5zLXF1ZXJ5
shecan|bypass|Shecan DNS|https://free.shecan.ir/dns-query|ir/global|sdns://AgAAAAAAAAAAAAAOZnJlZS5zaGVjYW4uaXIKL2Rucy1xdWVyeQ
yandex_ru|regional|Yandex RU|https://common.dot.dns.yandex.net/dns-query|ru|sdns://AgAAAAAAAAAAAAAZY29tbW9uLmRvdC5kbnMueWFuZGV4Lm5ldAovZG5zLXF1ZXJ5
yandex_safe|regional|Yandex Safe|https://safe.dot.dns.yandex.net/dns-query|ru|sdns://AgAAAAAAAAAAAAAXc2FmZS5kb3QuZG5zLnlhbmRleC5uZXQKL2Rucy1xdWVyeQ
yandex_family|regional|Yandex Family|https://family.dot.dns.yandex.net/dns-query|ru|sdns://AgAAAAAAAAAAAAAZZmFtaWx5LmRvdC5kbnMueWFuZGV4Lm5ldAovZG5zLXF1ZXJ5
cloudflare_clean|clean|Cloudflare|https://cloudflare-dns.com/dns-query|global|sdns://AgAAAAAAAAAAAAASY2xvdWRmbGFyZS1kbnMuY29tCi9kbnMtcXVlcnk
google_clean|clean|Google Public DNS|https://dns.google/dns-query|global|sdns://AgAAAAAAAAAAAAAKZG5zLmdvb2dsZQovZG5zLXF1ZXJ5
quad9_unfiltered|clean|Quad9 Unsecured|https://dns10.quad9.net/dns-query|global|sdns://AgAAAAAAAAAAAAAPZG5zMTAucXVhZDkubmV0Ci9kbnMtcXVlcnk
adguard_unfiltered|clean|AdGuard Unfiltered|https://unfiltered.adguard-dns.com/dns-query|global|sdns://AgAAAAAAAAAAAAAadW5maWx0ZXJlZC5hZGd1YXJkLWRucy5jb20KL2Rucy1xdWVyeQ
controld_p0|clean|Control D Unfiltered|https://freedns.controld.com/p0|global|sdns://AgAAAAAAAAAAAAAUZnJlZWRucy5jb250cm9sZC5jb20DL3Aw
controld_uncensored|clean|Control D Uncensored|https://freedns.controld.com/uncensored|global|sdns://AgAAAAAAAAAAAAAUZnJlZWRucy5jb250cm9sZC5jb20LL3VuY2Vuc29yZWQ
he_public|clean|Hurricane Electric Public Recursor|https://ordns.he.net/dns-query|global|sdns://AgAAAAAAAAAAAAAMb3JkbnMuaGUubmV0Ci9kbnMtcXVlcnk
18bit_cn|clean|18bit.cn|https://doh.18bit.cn/dns-query|asia|sdns://AgAAAAAAAAAAAAAMZG9oLjE4Yml0LmNuCi9kbnMtcXVlcnk
aa_dns|clean|Andrews & Arnold|https://dns.aa.net.uk/dns-query|uk/eu|sdns://AgAAAAAAAAAAAAANZG5zLmFhLm5ldC51awovZG5zLXF1ZXJ5
aquilenet|clean|Aquilenet DNS|https://dns.aquilenet.fr/dns-query|fr/eu|sdns://AgAAAAAAAAAAAAAQZG5zLmFxdWlsZW5ldC5mcgovZG5zLXF1ZXJ5
belnet|clean|Belnet DNS|https://dns.belnet.be/dns-query|be/eu|sdns://AgAAAAAAAAAAAAANZG5zLmJlbG5ldC5iZQovZG5zLXF1ZXJ5
cynthia|clean|CynthiaLabs DNS|https://dns.cynthialabs.net/dns-query|global|sdns://AgAAAAAAAAAAAAATZG5zLmN5bnRoaWFsYWJzLm5ldAovZG5zLXF1ZXJ5
digitalsize|clean|DigitalSize DNS|https://dns.digitalsize.net/dns-query|de/eu|sdns://AgAAAAAAAAAAAAATZG5zLmRpZ2l0YWxzaXplLm5ldAovZG5zLXF1ZXJ5
doh_disconnect|clean|Disconnect DNS|https://doh.disconnect.app/dns-query|global|sdns://AgAAAAAAAAAAAAASZG9oLmRpc2Nvbm5lY3QuYXBwCi9kbnMtcXVlcnk
dnshome|clean|DNSHome|https://dns.dnshome.de/dns-query|de/eu|sdns://AgAAAAAAAAAAAAAOZG5zLmRuc2hvbWUuZGUKL2Rucy1xdWVyeQ
one_dns_pure|clean|OneDNS Pure|https://doh-pure.onedns.net/dns-query|asia|sdns://AgAAAAAAAAAAAAATZG9oLXB1cmUub25lZG5zLm5ldAovZG5zLXF1ZXJ5
dns_pub|clean|DNSPod Public DNS|https://dns.pub/dns-query|cn/global|sdns://AgAAAAAAAAAAAAAHZG5zLnB1YgovZG5zLXF1ZXJ5
dns_fdn0|clean|FDN DNS 0|https://ns0.fdn.fr/dns-query|fr/eu|sdns://AgAAAAAAAAAAAAAKbnMwLmZkbi5mcgovZG5zLXF1ZXJ5
dns_fdn1|clean|FDN DNS 1|https://ns1.fdn.fr/dns-query|fr/eu|sdns://AgAAAAAAAAAAAAAKbnMxLmZkbi5mcgovZG5zLXF1ZXJ5
doh_lacontrevoie|clean|LaContreVoie DNS|https://doh.lacontrevoie.fr/dns-query|fr/eu|sdns://AgAAAAAAAAAAAAATZG9oLmxhY29udHJldm9pZS5mcgovZG5zLXF1ZXJ5
cznic_odvr_doh|clean|CZ.NIC ODVR DNS-сервер|https://odvr.nic.cz/doh|cz/eu|sdns://AgAAAAAAAAAAAAALb2R2ci5uaWMuY3oEL2RvaA
cznic_odvr_query|clean|CZ.NIC ODVR Query|https://odvr.nic.cz/dns-query|cz/eu|sdns://AgAAAAAAAAAAAAALb2R2ci5uaWMuY3oKL2Rucy1xdWVyeQ
doh_seby|clean|Seby DNS|https://doh.seby.io/dns-query|global|sdns://AgAAAAAAAAAAAAALZG9oLnNlYnkuaW8KL2Rucy1xdWVyeQ
dns_surfshark|clean|Surfshark DNS|https://dns.surfsharkdns.com/dns-query|global|sdns://AgAAAAAAAAAAAAAUZG5zLnN1cmZzaGFya2Rucy5jb20KL2Rucy1xdWVyeQ
hostux|clean|Hostux DNS|https://dns.hostux.net/dns-query|global|sdns://AgAAAAAAAAAAAAAOZG5zLmhvc3R1eC5uZXQKL2Rucy1xdWVyeQ
cloudflare_security|security|Cloudflare Security|https://security.cloudflare-dns.com/dns-query|global|sdns://AgAAAAAAAAAAAAAbc2VjdXJpdHkuY2xvdWRmbGFyZS1kbnMuY29tCi9kbnMtcXVlcnk
quad9_secure|security|Quad9 Secure|https://dns.quad9.net/dns-query|global|sdns://AgAAAAAAAAAAAAANZG5zLnF1YWQ5Lm5ldAovZG5zLXF1ZXJ5
quad9_ecs|security|Quad9 Secure ECS|https://dns11.quad9.net/dns-query|global|sdns://AgAAAAAAAAAAAAAPZG5zMTEucXVhZDkubmV0Ci9kbnMtcXVlcnk
controld_p1|security|Control D Malware|https://freedns.controld.com/p1|global|sdns://AgAAAAAAAAAAAAAUZnJlZWRucy5jb250cm9sZC5jb20DL3Ax
opendns_standard|security|OpenDNS Standard|https://doh.opendns.com/dns-query|global|sdns://AgAAAAAAAAAAAAAPZG9oLm9wZW5kbnMuY29tCi9kbnMtcXVlcnk
cleanbrowsing_security|security|CleanBrowsing Security|https://doh.cleanbrowsing.org/doh/security-filter/|global|sdns://AgAAAAAAAAAAAAAVZG9oLmNsZWFuYnJvd3Npbmcub3JnFS9kb2gvc2VjdXJpdHktZmlsdGVyLw
dns4eu_protective|security|DNS4EU Protective|https://protective.joindns4.eu/dns-query|eu|sdns://AgAAAAAAAAAAAAAWcHJvdGVjdGl2ZS5qb2luZG5zNC5ldQovZG5zLXF1ZXJ5
cert_ee|security|CERT-EE|https://dns.cert.ee/dns-query|estonia|sdns://AgAAAAAAAAAAAAALZG5zLmNlcnQuZWUKL2Rucy1xdWVyeQ
cira_protected|security|CIRA Protected|https://protected.canadianshield.cira.ca/dns-query|canada|sdns://AgAAAAAAAAAAAAAgcHJvdGVjdGVkLmNhbmFkaWFuc2hpZWxkLmNpcmEuY2EKL2Rucy1xdWVyeQ
one_dns_block|security|OneDNS Block|https://doh.onedns.net/dns-query|asia|sdns://AgAAAAAAAAAAAAAOZG9oLm9uZWRucy5uZXQKL2Rucy1xdWVyeQ
hagezi_root|security|HaGeZi Root|https://root.hagezi.org/dns-query|germany|sdns://AgAAAAAAAAAAAAAPcm9vdC5oYWdlemkub3JnCi9kbnMtcXVlcnk
hagezi_wurzn|security|HaGeZi Wurzn|https://wurzn.hagezi.org/dns-query|germany|sdns://AgAAAAAAAAAAAAAQd3Vyem4uaGFnZXppLm9yZwovZG5zLXF1ZXJ5
hagezi_juuri|security|HaGeZi Juuri|https://juuri.hagezi.org/dns-query|finland|sdns://AgAAAAAAAAAAAAAQanV1cmkuaGFnZXppLm9yZwovZG5zLXF1ZXJ5
hagezi_ctif|security|HaGeZi CTIF|https://ctif.hagezi.org/dns-query|germany|sdns://AgAAAAAAAAAAAAAPY3RpZi5oYWdlemkub3JnCi9kbnMtcXVlcnk
openbld_ada|security|OpenBLD ADA|https://ada.openbld.net/dns-query|global|sdns://AgAAAAAAAAAAAAAPYWRhLm9wZW5ibGQubmV0Ci9kbnMtcXVlcnk
openbld_ric|security|OpenBLD RIC|https://ric.openbld.net/dns-query|global|sdns://AgAAAAAAAAAAAAAPcmljLm9wZW5ibGQubmV0Ci9kbnMtcXVlcnk
dnsforge_strict|security|dnsforge Strict|https://hard.dnsforge.de/dns-query|germany|sdns://AgAAAAAAAAAAAAAQaGFyZC5kbnNmb3JnZS5kZQovZG5zLXF1ZXJ5
dnsbunker|security|DNSBUNKER Pro+TIF|https://dnsbunker.org/dns-query|germany|sdns://AgAAAAAAAAAAAAANZG5zYnVua2VyLm9yZwovZG5zLXF1ZXJ5
nsec_arnor|security|arnor.org|https://nsec.arnor.org/dns-query|global|sdns://AgAAAAAAAAAAAAAObnNlYy5hcm5vci5vcmcKL2Rucy1xdWVyeQ
mullvad_clean|privacy|Mullvad Clean|https://dns.mullvad.net/dns-query|global|sdns://AgAAAAAAAAAAAAAPZG5zLm11bGx2YWQubmV0Ci9kbnMtcXVlcnk
mullvad_adblock|adblock|Mullvad Adblock|https://adblock.dns.mullvad.net/dns-query|global|sdns://AgAAAAAAAAAAAAAXYWRibG9jay5kbnMubXVsbHZhZC5uZXQKL2Rucy1xdWVyeQ
mullvad_base|security|Mullvad Base|https://base.dns.mullvad.net/dns-query|global|sdns://AgAAAAAAAAAAAAAUYmFzZS5kbnMubXVsbHZhZC5uZXQKL2Rucy1xdWVyeQ
mullvad_extended|security|Mullvad Extended|https://extended.dns.mullvad.net/dns-query|global|sdns://AgAAAAAAAAAAAAAYZXh0ZW5kZWQuZG5zLm11bGx2YWQubmV0Ci9kbnMtcXVlcnk
nextdns_fast|privacy|NextDNS|https://dns.nextdns.io|global|sdns://AgAAAAAAAAAAAAAOZG5zLm5leHRkbnMuaW8KL2Rucy1xdWVyeQ
nextdns_anycast|privacy|NextDNS Anycast|https://anycast.dns.nextdns.io|global|sdns://AgAAAAAAAAAAAAAWYW55Y2FzdC5kbnMubmV4dGRucy5pbwovZG5zLXF1ZXJ5
dns_sb|privacy|DNS.SB|https://doh.dns.sb/dns-query|global|sdns://AgAAAAAAAAAAAAAKZG9oLmRucy5zYgovZG5zLXF1ZXJ5
applied_privacy|privacy|Applied Privacy|https://doh.applied-privacy.net/query|europe|sdns://AgAAAAAAAAAAAAAXZG9oLmFwcGxpZWQtcHJpdmFjeS5uZXQGL3F1ZXJ5
cznic_odvr|security|CZ.NIC ODVR|https://odvr.nic.cz/doh|czechia|sdns://AgAAAAAAAAAAAAALb2R2ci5uaWMuY3oEL2RvaA
digitale_gesellschaft|privacy|Digitale Gesellschaft|https://dns.digitale-gesellschaft.ch/dns-query|switzerland|sdns://AgAAAAAAAAAAAAAcZG5zLmRpZ2l0YWxlLWdlc2VsbHNjaGFmdC5jaAovZG5zLXF1ZXJ5
cira_private|privacy|CIRA Private|https://private.canadianshield.cira.ca/dns-query|canada|sdns://AgAAAAAAAAAAAAAecHJpdmF0ZS5jYW5hZGlhbnNoaWVsZC5jaXJhLmNhCi9kbnMtcXVlcnk
libredns_clean|privacy|LibreDNS|https://doh.libredns.gr/dns-query|greece/eu|sdns://AgAAAAAAAAAAAAAPZG9oLmxpYnJlZG5zLmdyCi9kbnMtcXVlcnk
switch_ch|privacy|SWITCH DNS|https://dns.switch.ch/dns-query|switzerland|sdns://AgAAAAAAAAAAAAANZG5zLnN3aXRjaC5jaAovZG5zLXF1ZXJ5
wikimedia|privacy|Wikimedia DNS|https://wikimedia-dns.org/dns-query|global|sdns://AgAAAAAAAAAAAAARd2lraW1lZGlhLWRucy5vcmcKL2Rucy1xdWVyeQ
pumplex|privacy|PumpleX|https://dns.pumplex.com/dns-query|france|sdns://AgAAAAAAAAAAAAAPZG5zLnB1bXBsZXguY29tCi9kbnMtcXVlcnk
dnsforge|privacy|dnsforge|https://dnsforge.de/dns-query|germany|sdns://AgAAAAAAAAAAAAALZG5zZm9yZ2UuZGUKL2Rucy1xdWVyeQ
ffmuc|privacy|FFMUC|https://doh.ffmuc.net/dns-query|germany|sdns://AgAAAAAAAAAAAAANZG9oLmZmbXVjLm5ldAovZG5zLXF1ZXJ5
adguard_default|adblock|AdGuard DNS|https://dns.adguard-dns.com/dns-query|global|sdns://AgAAAAAAAAAAAAATZG5zLmFkZ3VhcmQtZG5zLmNvbQovZG5zLXF1ZXJ5
controld_p2|adblock|Control D Ads+Tracking|https://freedns.controld.com/p2|global|sdns://AgAAAAAAAAAAAAAUZnJlZWRucy5jb250cm9sZC5jb20DL3Ay
dns4eu_noads|adblock|DNS4EU No Ads|https://noads.joindns4.eu/dns-query|eu|sdns://AgAAAAAAAAAAAAARbm9hZHMuam9pbmRuczQuZXUKL2Rucy1xdWVyeQ
libredns_ads|adblock|LibreDNS Ads|https://doh.libredns.gr/ads|greece/eu|sdns://AgAAAAAAAAAAAAAPZG9oLmxpYnJlZG5zLmdyBC9hZHM
dnsguard|adblock|DNSGuard|https://dns.dnsguard.pub/dns-query|global|sdns://AgAAAAAAAAAAAAAQZG5zLmRuc2d1YXJkLnB1YgovZG5zLXF1ZXJ5
nwps_standard|adblock|NWPS.fi Standard|https://public.ns.nwps.fi/dns-query|finland|sdns://AgAAAAAAAAAAAAARcHVibGljLm5zLm53cHMuZmkKL2Rucy1xdWVyeQ
oszx|adblock|OSZX DNS|https://dns.oszx.co/dns-query|france|sdns://AgAAAAAAAAAAAAALZG5zLm9zenguY28KL2Rucy1xdWVyeQ
angry_im|adblock|Angry.im|https://doh.angry.im/dns-query|global|sdns://AgAAAAAAAAAAAAAMZG9oLmFuZ3J5LmltCi9kbnMtcXVlcnk
dns_bebas_default|adblock|BebasDNS|https://dns.bebasid.com/dns-query|id/global|sdns://AgAAAAAAAAAAAAAPZG5zLmJlYmFzaWQuY29tCi9kbnMtcXVlcnk
blokada|adblock|Blokada DNS|https://dns.blokada.org/dns-query|global|sdns://AgAAAAAAAAAAAAAPZG5zLmJsb2thZGEub3JnCi9kbnMtcXVlcnk
cloudflare_family|family|Cloudflare Family|https://family.cloudflare-dns.com/dns-query|global|sdns://AgAAAAAAAAAAAAAZZmFtaWx5LmNsb3VkZmxhcmUtZG5zLmNvbQovZG5zLXF1ZXJ5
adguard_family|family|AdGuard Family|https://family.adguard-dns.com/dns-query|global|sdns://AgAAAAAAAAAAAAAWZmFtaWx5LmFkZ3VhcmQtZG5zLmNvbQovZG5zLXF1ZXJ5
mullvad_family|family|Mullvad Family|https://family.dns.mullvad.net/dns-query|global|sdns://AgAAAAAAAAAAAAAWZmFtaWx5LmRucy5tdWxsdmFkLm5ldAovZG5zLXF1ZXJ5
mullvad_all|family|Mullvad All|https://all.dns.mullvad.net/dns-query|global|sdns://AgAAAAAAAAAAAAATYWxsLmRucy5tdWxsdmFkLm5ldAovZG5zLXF1ZXJ5
controld_family|family|Control D Family|https://freedns.controld.com/family|global|sdns://AgAAAAAAAAAAAAAUZnJlZWRucy5jb250cm9sZC5jb20HL2ZhbWlseQ
opendns_family|family|OpenDNS FamilyShield|https://doh.familyshield.opendns.com/dns-query|global|sdns://AgAAAAAAAAAAAAAcZG9oLmZhbWlseXNoaWVsZC5vcGVuZG5zLmNvbQovZG5zLXF1ZXJ5
cleanbrowsing_adult|family|CleanBrowsing Adult|https://doh.cleanbrowsing.org/doh/adult-filter/|global|sdns://AgAAAAAAAAAAAAAVZG9oLmNsZWFuYnJvd3Npbmcub3JnEi9kb2gvYWR1bHQtZmlsdGVyLw
cleanbrowsing_family|family|CleanBrowsing Family|https://doh.cleanbrowsing.org/doh/family-filter/|global|sdns://AgAAAAAAAAAAAAAVZG9oLmNsZWFuYnJvd3Npbmcub3JnEy9kb2gvZmFtaWx5LWZpbHRlci8
dns4eu_child|family|DNS4EU Child|https://child.joindns4.eu/dns-query|eu|sdns://AgAAAAAAAAAAAAARY2hpbGQuam9pbmRuczQuZXUKL2Rucy1xdWVyeQ
dns4eu_child_noads|family|DNS4EU Child No Ads|https://child-noads.joindns4.eu/dns-query|eu|sdns://AgAAAAAAAAAAAAAXY2hpbGQtbm9hZHMuam9pbmRuczQuZXUKL2Rucy1xdWVyeQ
dns_for_family|family|DNS for Family|https://dns-doh.dnsforfamily.com/dns-query|global|sdns://AgAAAAAAAAAAAAAYZG5zLWRvaC5kbnNmb3JmYW1pbHkuY29tCi9kbnMtcXVlcnk
cira_family|family|CIRA Family|https://family.canadianshield.cira.ca/dns-query|canada|sdns://AgAAAAAAAAAAAAAdZmFtaWx5LmNhbmFkaWFuc2hpZWxkLmNpcmEuY2EKL2Rucy1xdWVyeQ
nwps_kids|family|NWPS.fi Kids|https://kids.ns.nwps.fi/dns-query|finland|sdns://AgAAAAAAAAAAAAAPa2lkcy5ucy5ud3BzLmZpCi9kbnMtcXVlcnk
iijjp|family|IIJ.JP DNS|https://public.dns.iij.jp/dns-query|japan|sdns://AgAAAAAAAAAAAAARcHVibGljLmRucy5paWouanAKL2Rucy1xdWVyeQ
dnsforge_youth|family|dnsforge Youth Protection|https://clean.dnsforge.de/dns-query|germany|sdns://AgAAAAAAAAAAAAARY2xlYW4uZG5zZm9yZ2UuZGUKL2Rucy1xdWVyeQ
EOF_CATALOG
}
name_of(){ awk -F'|' -v i="$1" '$1==i{print $3;exit}' "$CATALOG"; }
cat_of(){ awk -F'|' -v i="$1" '$1==i{print $2;exit}' "$CATALOG"; }
url_of(){ awk -F'|' -v i="$1" '$1==i{print $4;exit}' "$CATALOG"; }
stamp_of(){ awk -F'|' -v i="$1" '$1==i{print $6;exit}' "$CATALOG"; }
region_of(){ awk -F'|' -v i="$1" '$1==i{print $5;exit}' "$CATALOG"; }

load_state(){
    SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""; SLOT_RU=""
    BALANCE=1; CACHE=1; TLD=1; FORCE_DNS=0; QUIC=0; MSS=0; TCP=0; NTP_CLIENTS=0; WATCHDOG=1; WEB=0
    NTP_PRESET="cf_ip"; PROFILE="hybrid"
    [ -f "$STATE_DIR/config" ] && . "$STATE_DIR/config" 2>/dev/null || true
}
save_state(){
cat > "$STATE_DIR/config" <<EOF_STATE
SLOT_1="${SLOT_1:-}"; SLOT_2="${SLOT_2:-}"; SLOT_3="${SLOT_3:-}"; SLOT_4="${SLOT_4:-}"; SLOT_5="${SLOT_5:-}"; SLOT_6="${SLOT_6:-}"; SLOT_RU="${SLOT_RU:-}"
BALANCE="$BALANCE"; CACHE="$CACHE"; TLD="$TLD"; FORCE_DNS="$FORCE_DNS"; QUIC="$QUIC"; MSS="$MSS"; TCP="$TCP"; NTP_CLIENTS="$NTP_CLIENTS"; WATCHDOG="$WATCHDOG"; WEB="$WEB"; NTP_PRESET="$NTP_PRESET"; PROFILE="$PROFILE"
EOF_STATE
}
set_defaults(){ SLOT_1=mafioznik; SLOT_2=comss_bypass; SLOT_3=astracat; SLOT_4=malw_link; SLOT_5=comss_ru; SLOT_6=vppay; SLOT_RU=yandex_ru; PROFILE=hybrid; BALANCE=1; CACHE=1; TLD=1; }
count_selected(){ n=0; for s in 1 2 3 4 5 6 RU; do eval "v=\$SLOT_$s"; [ -n "$v" ] && n=$((n+1)); done; printf '%s' "$n"; }

backup_file(){ [ -f "$1" ] || return 0; cp -p "$1" "$BACKUP_DIR/$(basename "$1").$(date +%Y%m%d-%H%M%S)"; }
snapshot_router(){
    [ -s "$STATE_DIR/router-snapshot" ] && return 0
    for f in /etc/config/dhcp /etc/config/firewall /etc/config/system /etc/config/ttyd; do
        [ -f "$f" ] && { cp -p "$f" "$BACKUP_DIR/$(basename "$f").initial"; printf '%s\n' "$f" >> "$STATE_DIR/router-snapshot"; }
    done
    [ -f "$MAIN_CFG" ] && cp -p "$MAIN_CFG" "$BASE_CFG"
}

config_replace_line(){ f="$1"; k="$2"; v="$3"; if grep -Eq "^[[:space:]]*$k[[:space:]]*=" "$f"; then sed -i "s#^[[:space:]]*$k[[:space:]]*=.*#$k = $v#" "$f" || return 1; else printf '\n%s = %s\n' "$k" "$v" >> "$f" || return 1; fi; }
config_delete_key(){ sed -i "/^[[:space:]]*$1[[:space:]]*=/d" "$2" 2>/dev/null || true; }

build_static(){ ids="$1"; out="$2"; : > "$out" || return 1; for id in $ids; do st="$(stamp_of "$id")"; [ -n "$st" ] || return 1; printf "[static.'%s']\nstamp = '%s'\n\n" "$id" "$st" >> "$out"; done; }

build_proxy_config(){ cfg="$1" port="$2" ids="$3" is_ru="$4"; [ -f "$BASE_CFG" ] || cp -p "$MAIN_CFG" "$BASE_CFG" || return 1; cp -p "$BASE_CFG" "$cfg" || return 1
    # Remove previously generated static sections safely by rebuilding from the clean package baseline.
    sed -i '/^[[:space:]]*server_names[[:space:]]*=/d; /^[[:space:]]*listen_addresses[[:space:]]*=/d; /^[[:space:]]*forwarding_rules[[:space:]]*=/d' "$cfg" 2>/dev/null || true
    arr=""; for id in $ids; do [ -n "$arr" ] && arr="$arr, "; arr="$arr'$id'"; done
    config_replace_line "$cfg" listen_addresses "[\"127.0.0.1:$port\"]" || return 1
    config_replace_line "$cfg" server_names "[$arr]" || return 1
    config_replace_line "$cfg" ignore_system_dns true || return 1
    config_replace_line "$cfg" ipv4_servers true || true
    config_replace_line "$cfg" ipv6_servers false || true
    config_replace_line "$cfg" lb_strategy "'wp2'" || return 1
    config_replace_line "$cfg" lb_estimator true || true
    if [ "$CACHE" = 1 ]; then
        config_replace_line "$cfg" cache true || return 1
        config_replace_line "$cfg" cache_size 4096 || true
        config_replace_line "$cfg" cache_min_ttl 2400 || true
        config_replace_line "$cfg" cache_max_ttl 86400 || true
        config_replace_line "$cfg" cache_neg_min_ttl 60 || true
        config_replace_line "$cfg" cache_neg_max_ttl 600 || true
    else
        config_replace_line "$cfg" cache false || return 1
    fi
    build_static "$ids" "$TMP/static.$$" || return 1
    cat "$TMP/static.$$" >> "$cfg" || return 1
    "$BIN" -config "$cfg" -check >"$TMP/check.$port" 2>&1 || { cat "$TMP/check.$port"; return 1; }
    return 0
}

stop_ru(){ [ -s "$RU_PID" ] || return 0; p="$(cat "$RU_PID" 2>/dev/null)"; case "$p" in ''|*[!0-9]*) ;; *) kill "$p" 2>/dev/null || true; sleep 1; kill -9 "$p" 2>/dev/null || true;; esac; rm -f "$RU_PID"; }
start_ru(){ [ -n "$SLOT_RU" ] || { stop_ru; return 0; }; build_proxy_config "$RU_CFG" "$RU_PORT" "$SLOT_RU" 1 || return 1; stop_ru; "$BIN" -config "$RU_CFG" >"$RU_LOG" 2>&1 & printf '%s\n' "$!" > "$RU_PID"; i=0; while [ "$i" -lt 8 ]; do if kill -0 "$(cat "$RU_PID")" 2>/dev/null && dns_query_local "$RU_PORT" yandex.ru; then ok "RU proxy работает: 127.0.0.1:$RU_PORT ← $(name_of "$SLOT_RU")"; return 0; fi; sleep 1; i=$((i+1)); done; err "RU proxy не запустился."; cat "$RU_LOG" 2>/dev/null; stop_ru; return 1; }

main_proxy_up(){ "$PKG_INIT" status >/dev/null 2>&1; }
dns_query_local(){ p="$1" d="$2"; if command -v dig >/dev/null 2>&1; then dig @127.0.0.1 -p "$p" "$d" A +time=3 +tries=1 +short 2>/dev/null | grep -Eq '^[0-9]+(\.[0-9]+){3}$'; elif command -v nslookup >/dev/null 2>&1; then nslookup -port="$p" "$d" 127.0.0.1 2>/dev/null | grep -Eq 'Address.*[0-9]+(\.[0-9]+){3}'; else return 1; fi; }
port_in_use(){ p="$1"; if command -v ss >/dev/null 2>&1; then ss -lntu 2>/dev/null | grep -Eq "(^|[[:space:]])([^[:space:]]*:)${p}([[:space:]]|$)" && return 0; fi; if command -v netstat >/dev/null 2>&1; then netstat -lntu 2>/dev/null | grep -Eq ":${p}([[:space:]]|$)" && return 0; fi; return 1; }
next_free_port(){ start="${1:-$TEST_PORT_FIRST}"; end="${2:-$TEST_PORT_LAST}"; p="$start"; while [ "$p" -le "$end" ]; do if ! port_in_use "$p"; then printf '%s' "$p"; return 0; fi; p=$((p+1)); done; return 1; }

snapshot_dnsmasq(){ sec="$(get_dnsmasq_sec)"; : > "$STATE_DIR/dnsmasq-before"; for k in server noresolv allservers strictorder cachesize dnsforwardmax max_cache_ttl boguspriv domainneeded quietdhcp filter_aaaa dhcp_option; do printf '%s|%s\n' "$k" "$(uci -q get dhcp.$sec.$k 2>/dev/null)" >> "$STATE_DIR/dnsmasq-before"; done; }
get_dnsmasq_sec(){ secs="$(uci show dhcp 2>/dev/null | sed -n 's/^dhcp\.\([^.=]*\)=dnsmasq$/\1/p')"; for s in $secs; do [ "$(uci -q get dhcp.$s.interface 2>/dev/null)" = lan ] && { printf '%s' "$s"; return; }; done; s="$(printf '%s\n' $secs | head -n1)"; [ -n "$s" ] && printf '%s' "$s" || printf '%s' '@dnsmasq[0]'; }

configure_dnsmasq(){ sec="$(get_dnsmasq_sec)"; snapshot_dnsmasq; uci -q delete "dhcp.$sec.server"; uci add_list "dhcp.$sec.server=127.0.0.1#$MAIN_PORT" || return 1; if [ -n "$SLOT_RU" ] && [ "$TLD" = 1 ]; then for t in /ru /su /xn--p1ai; do uci add_list "dhcp.$sec.server=$t/127.0.0.1#$RU_PORT" || return 1; done; fi; uci set "dhcp.$sec.noresolv=1" || return 1; uci set "dhcp.$sec.strictorder=0" || true; if [ "$BALANCE" = 1 ]; then uci set "dhcp.$sec.allservers=1" || return 1; else uci -q delete "dhcp.$sec.allservers"; fi; if [ "$CACHE" = 1 ]; then uci set "dhcp.$sec.cachesize=0" || true; fi; uci commit dhcp || return 1; /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1; }

restore_dnsmasq(){ [ -s "$STATE_DIR/dnsmasq-before" ] || return 0; sec="$(get_dnsmasq_sec)"; uci -q delete "dhcp.$sec.server"; while IFS='|' read -r k v; do case "$k" in server) for x in $v; do [ -n "$x" ] && uci add_list "dhcp.$sec.server=$x"; done;; noresolv|allservers|strictorder|cachesize|dnsforwardmax|max_cache_ttl|boguspriv|domainneeded|quietdhcp|filter_aaaa|dhcp_option) if [ -n "$v" ]; then uci set "dhcp.$sec.$k=$v"; else uci -q delete "dhcp.$sec.$k"; fi;; esac; done < "$STATE_DIR/dnsmasq-before"; uci commit dhcp >/dev/null 2>&1 || true; /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true; }

apply_dns(){
    ensure_package || return 1; [ -f "$MAIN_CFG" ] || return 1; [ -f "$BASE_CFG" ] || cp -p "$MAIN_CFG" "$BASE_CFG" || return 1
    ids=""; for s in 1 2 3 4 5 6; do eval "v=\$SLOT_$s"; [ -n "$v" ] && ids="$ids $v"; done; ids="$(printf '%s' "$ids" | sed 's/^ *//')"; [ -n "$ids" ] || return 1
    backup_file "$MAIN_CFG" || return 1
    build_proxy_config "$TMP/main.toml" "$MAIN_PORT" "$ids" 0 || return 1
    if [ "$TLD" = 1 ] && [ -n "$SLOT_RU" ]; then build_proxy_config "$RU_CFG" "$RU_PORT" "$SLOT_RU" 1 || return 1; else stop_ru; fi
    cp -p "$TMP/main.toml" "$MAIN_CFG" || return 1
    "$MAIN_CFG" >/dev/null 2>&1 || true
    "$PKG_INIT" enable >/dev/null 2>&1 || true
    "$PKG_INIT" restart >/dev/null 2>&1 || return 1
    sleep 3
    dns_query_local "$MAIN_PORT" example.com || { err "Основной dnscrypt-proxy не отвечает."; return 1; }
    if [ "$TLD" = 1 ] && [ -n "$SLOT_RU" ]; then start_ru || return 1; fi
    configure_dnsmasq || return 1
    verify_dns || return 1
    return 0
}
verify_dns(){ dns_query_local "$MAIN_PORT" example.com || return 1; if [ "$TLD" = 1 ] && [ -n "$SLOT_RU" ]; then dns_query_local "$RU_PORT" yandex.ru || return 1; fi; sec="$(get_dnsmasq_sec)"; [ "$(uci -q get dhcp.$sec.noresolv 2>/dev/null)" = 1 ] || return 1; printf '%s\n' "$(uci -q get dhcp.$sec.server 2>/dev/null)" | grep -qxF "127.0.0.1#$MAIN_PORT" || true; return 0; }

# ----- extra router settings -----
ntp_servers(){ case "$1" in cf_ip) echo '162.159.200.1 162.159.200.123';; nist_ip) echo '129.6.15.28 129.6.15.29 129.6.15.30 129.6.15.27 129.6.15.26';; google_ip) echo '216.239.35.0 216.239.35.4 216.239.35.8 216.239.35.12';; vniiftri_moscow) echo '89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25';; esac; }
apply_tcp(){
    f="/etc/sysctl.d/90-dnscrypt-manager.conf"
    sf="$STATE_DIR/tcp-before"
    if [ "$TCP" = 1 ]; then
        if [ ! -s "$sf" ]; then
            : > "$sf" || return 1
            for k in net.ipv4.tcp_fastopen net.ipv4.tcp_fin_timeout net.core.somaxconn net.netfilter.nf_conntrack_max net.ipv4.tcp_keepalive_time net.ipv4.tcp_keepalive_intvl net.ipv4.tcp_keepalive_probes net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default; do
                printf "%s|%s\n" "$k" "$(sysctl -n "$k" 2>/dev/null)" >> "$sf" || return 1
            done
        fi
        cat > "$f.tmp" <<EOF_SYSCTL
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=15
net.core.somaxconn=1024
net.netfilter.nf_conntrack_max=65536
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=60
net.ipv4.tcp_keepalive_probes=5
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.core.rmem_default=262144
net.core.wmem_default=262144
EOF_SYSCTL
        mv "$f.tmp" "$f" || return 1
        sysctl -p "$f" >/dev/null 2>&1 || return 1
        return 0
    fi
    if [ -s "$sf" ]; then
        while IFS="|" read -r k v; do
            [ -n "$k" ] || continue
            [ -n "$v" ] || continue
            sysctl -w "$k=$v" >/dev/null 2>&1 || true
        done < "$sf"
    fi
    rm -f "$f" "$sf"
    return 0
}
apply_quic(){ if [ "$QUIC" = 1 ]; then for p in 80 443; do r="dnscrypt_manager_quic_$p"; uci -q delete "firewall.$r"; uci set "firewall.$r=rule" || return 1; uci set "firewall.$r.name=DNSCrypt Manager: UDP $p" || return 1; uci set "firewall.$r.src=lan" || return 1; uci set "firewall.$r.dest=wan" || return 1; uci set "firewall.$r.proto=udp" || return 1; uci set "firewall.$r.dest_port=$p" || return 1; uci set "firewall.$r.target=REJECT" || return 1; done; else uci -q delete firewall.dnscrypt_manager_quic_80; uci -q delete firewall.dnscrypt_manager_quic_443; fi; uci commit firewall || return 1; /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || return 1; }
apply_mss(){ sf="$STATE_DIR/mss-before"; if [ "$MSS" = 1 ]; then [ -f "$sf" ] || printf '%s\n' "$(uci -q get firewall.@defaults[0].mtu_fix 2>/dev/null)" > "$sf"; uci set firewall.@defaults[0].mtu_fix=1 || return 1; else if [ -f "$sf" ]; then _v="$(cat "$sf" 2>/dev/null)"; if [ -n "$_v" ]; then uci set firewall.@defaults[0].mtu_fix="$_v"; else uci -q delete firewall.@defaults[0].mtu_fix; fi; rm -f "$sf"; else uci -q delete firewall.@defaults[0].mtu_fix; fi; fi; uci commit firewall || return 1; /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || return 1; }
apply_force(){ lan="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)"; if [ "$FORCE_DNS" = 1 ]; then uci -q delete firewall.dnscrypt_manager_dns_redirect; uci set firewall.dnscrypt_manager_dns_redirect=redirect || return 1; uci set firewall.dnscrypt_manager_dns_redirect.src=lan || return 1; uci set firewall.dnscrypt_manager_dns_redirect.proto='tcp udp' || return 1; uci set firewall.dnscrypt_manager_dns_redirect.src_dport=53 || return 1; uci set firewall.dnscrypt_manager_dns_redirect.dest_ip="$lan" || return 1; uci set firewall.dnscrypt_manager_dns_redirect.dest_port=53 || return 1; uci set firewall.dnscrypt_manager_dns_redirect.target=DNAT || return 1; else uci -q delete firewall.dnscrypt_manager_dns_redirect; fi; uci commit firewall || return 1; /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || return 1; }
apply_ntp_clients(){
    sec="$(get_dnsmasq_sec)"
    lan="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)"
    sf="$STATE_DIR/ntp-client-before"
    if [ "$NTP_CLIENTS" = 1 ]; then
        if [ ! -s "$sf" ]; then
            printf 'OPTION|%s\n' "$(uci -q get "dhcp.$sec.dhcp_option" 2>/dev/null)" > "$sf"
            if uci -q get firewall.dnscrypt_manager_ntp >/dev/null 2>&1; then uci -q show firewall.dnscrypt_manager_ntp > "$STATE_DIR/ntp-fw-before"; else printf 'ABSENT\n' > "$STATE_DIR/ntp-fw-before"; fi
        fi
        uci -q del_list "dhcp.$sec.dhcp_option=42,$lan"
        uci add_list "dhcp.$sec.dhcp_option=42,$lan" || return 1
        uci -q delete firewall.dnscrypt_manager_ntp
        uci set firewall.dnscrypt_manager_ntp=redirect || return 1
        uci set firewall.dnscrypt_manager_ntp.name='DNSCrypt Manager: NTP клиентов' || return 1
        uci set firewall.dnscrypt_manager_ntp.src=lan || return 1
        uci set firewall.dnscrypt_manager_ntp.proto=udp || return 1
        uci set firewall.dnscrypt_manager_ntp.src_dport=123 || return 1
        uci set firewall.dnscrypt_manager_ntp.dest_ip="$lan" || return 1
        uci set firewall.dnscrypt_manager_ntp.dest_port=123 || return 1
        uci set firewall.dnscrypt_manager_ntp.target=DNAT || return 1
    else
        if [ -s "$sf" ]; then
            _old_opt="$(sed -n 's/^OPTION|//p' "$sf" 2>/dev/null)"
            if [ -n "$_old_opt" ]; then uci set "dhcp.$sec.dhcp_option=$_old_opt"; else uci -q delete "dhcp.$sec.dhcp_option"; fi
        else
            uci -q del_list "dhcp.$sec.dhcp_option=42,$lan"
        fi
        uci -q delete firewall.dnscrypt_manager_ntp
        rm -f "$sf" "$STATE_DIR/ntp-fw-before"
    fi
    uci commit dhcp || return 1
    uci commit firewall || return 1
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
    /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || return 1
}
apply_ntp(){
    servers="$(ntp_servers "$NTP_PRESET")"
    [ -n "$servers" ] || return 1
    sf="$STATE_DIR/ntp-before"
    if [ ! -s "$sf" ]; then
        { printf 'EXISTS|%s\n' "$(uci -q get system.ntp >/dev/null 2>&1 && printf 1 || printf 0)"; printf 'ENABLED|%s\n' "$(uci -q get system.ntp.enabled 2>/dev/null)"; printf 'USE_DHCP|%s\n' "$(uci -q get system.ntp.use_dhcp 2>/dev/null)"; printf 'SERVER|%s\n' "$(uci -q get system.ntp.server 2>/dev/null)"; } > "$sf"
    fi
    uci -q get system.ntp >/dev/null 2>&1 || uci -q set system.ntp=timeserver || return 1
    uci -q delete system.ntp.server
    for ip in $servers; do uci add_list system.ntp.server="$ip" || return 1; done
    uci set system.ntp.enabled=1 || return 1
    uci set system.ntp.use_dhcp=0 || return 1
    uci commit system || return 1
    /etc/init.d/sysntpd restart >/dev/null 2>&1 || return 1
    return 0
}
apply_dnsmasq_perf(){
    sec="$(get_dnsmasq_sec)"
    sf="$STATE_DIR/dnsmasq-perf-before"
    if [ "$CACHE" = 1 ]; then
        if [ ! -s "$sf" ]; then
            : > "$sf"
            for k in cachesize dnsforwardmax max_cache_ttl boguspriv domainneeded quietdhcp filter_aaaa; do printf '%s|%s\n' "$k" "$(uci -q get "dhcp.$sec.$k" 2>/dev/null)" >> "$sf"; done
        fi
        uci set "dhcp.$sec.cachesize=0" || return 1
        uci set "dhcp.$sec.dnsforwardmax=300" || return 1
        uci set "dhcp.$sec.max_cache_ttl=86400" || return 1
        uci set "dhcp.$sec.boguspriv=1" || return 1
        uci set "dhcp.$sec.domainneeded=1" || return 1
        uci set "dhcp.$sec.quietdhcp=1" || return 1
        if [ "${IPV6_ROUTE:-yes}" = no ]; then uci set "dhcp.$sec.filter_aaaa=1" || return 1; fi
    elif [ -s "$sf" ]; then
        while IFS='|' read -r k v; do if [ -n "$v" ]; then uci set "dhcp.$sec.$k=$v"; else uci -q delete "dhcp.$sec.$k"; fi; done < "$sf"
        rm -f "$sf"
    fi
    uci commit dhcp || return 1
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
}
apply_client_fixes(){
    f="/etc/dnsmasq.d/dnscrypt-manager-client-fixes.conf"
    sf="$STATE_DIR/client-before"
    if [ -f "$f" ] && [ ! -f "$sf" ]; then cp -p "$f" "$sf" || return 1; elif [ ! -f "$f" ] && [ ! -f "$sf" ]; then printf 'ABSENT\n' > "$sf"; fi
    cat > "$f.tmp" <<EOF_CLIENT
local=/telemetry.mozilla.org/
local=/telemetry.microsoft.com/
local=/vortex.data.microsoft.com/
local=/settings-win.data.microsoft.com/
local=/metrics.android.com/
local=/metrics.samsung.com/
server=/clients3.google.com/77.88.8.8
server=/clients3.google.com/77.88.8.1
server=/connectivitycheck.gstatic.com/77.88.8.8
server=/connectivitycheck.gstatic.com/77.88.8.1
server=/connectivitycheck.android.com/77.88.8.8
server=/connectivitycheck.android.com/77.88.8.1
server=/connectivitycheck.samsung.com/77.88.8.8
server=/connectivitycheck.samsung.com/77.88.8.1
server=/connectivitycheck.platform.hicloud.com/77.88.8.8
server=/connectivitycheck.platform.hicloud.com/77.88.8.1
EOF_CLIENT
    mv "$f.tmp" "$f" || return 1
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
}
remove_client_fixes(){ f="/etc/dnsmasq.d/dnscrypt-manager-client-fixes.conf"; sf="$STATE_DIR/client-before"; if [ -s "$sf" ] && [ "$(cat "$sf" 2>/dev/null)" = ABSENT ]; then rm -f "$f"; elif [ -s "$sf" ]; then cp -p "$sf" "$f" 2>/dev/null || true; else rm -f "$f"; fi; rm -f "$sf"; /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true; }
apply_all_extras(){ apply_tcp || return 1; apply_quic || return 1; apply_mss || return 1; apply_force || return 1; apply_ntp_clients || return 1; apply_ntp || return 1; apply_dnsmasq_perf || return 1; if [ "$WEB" = 1 ]; then apply_web || return 1; else remove_web; fi; if [ "$WATCHDOG" = 1 ]; then apply_watchdog || return 1; else remove_watchdog; fi; return 0; }

# ----- watchdog + web -----
watchdog_run(){
    ensure_package >/dev/null 2>&1 || exit 1
    [ -f "$MAIN_CFG" ] || exit 1
    okmain=0; dns_query_local "$MAIN_PORT" example.com && okmain=1
    okru=1; [ "$TLD" = 1 ] && [ -n "$SLOT_RU" ] && { dns_query_local "$RU_PORT" yandex.ru || okru=0; }
    if [ "$okmain" = 0 ]; then "$PKG_INIT" restart >/dev/null 2>&1 || true; sleep 3; fi
    if [ "$TLD" = 1 ] && [ -n "$SLOT_RU" ] && [ "$okru" = 0 ]; then start_ru >/dev/null 2>&1 || true; fi
    if [ "$WATCHDOG" = 1 ]; then log "WATCHDOG main=$okmain ru=$okru"; fi
}
apply_watchdog(){ mkdir -p /etc/crontabs; grep -v 'dnscrypt-manager --watchdog' /etc/crontabs/root 2>/dev/null > "$TMP/root" || true; printf '*/5 * * * * /usr/bin/dnscrypt-manager --watchdog >> /etc/dnscrypt-manager/watchdog.log 2>&1\n' >> "$TMP/root"; cat "$TMP/root" > /etc/crontabs/root; chmod 600 /etc/crontabs/root; }
remove_watchdog(){ [ -f /etc/crontabs/root ] || return 0; grep -v 'dnscrypt-manager --watchdog' /etc/crontabs/root > "$TMP/root" 2>/dev/null || true; cat "$TMP/root" > /etc/crontabs/root; chmod 600 /etc/crontabs/root; }
apply_web(){ command -v ttyd >/dev/null 2>&1 || { pm="$(pkg_mgr)"; case "$pm" in apk) apk add ttyd >/dev/null 2>&1 || return 1;; opkg) opkg update >/dev/null 2>&1 && opkg install ttyd >/dev/null 2>&1 || return 1;; *) return 1;; esac; }; mkdir -p /usr/lib/lua/luci/controller; uci -q delete ttyd.dnscrypt_manager; uci set ttyd.dnscrypt_manager=ttyd || return 1; uci set ttyd.dnscrypt_manager.enable=1 || return 1; uci set ttyd.dnscrypt_manager.port=7682 || return 1; uci set ttyd.dnscrypt_manager.interface=@lan || return 1; uci set ttyd.dnscrypt_manager.command=/usr/bin/dnscrypt-manager || return 1; uci commit ttyd || return 1; uci -q delete firewall.dnscrypt_manager_web; uci set firewall.dnscrypt_manager_web=rule || return 1; uci set firewall.dnscrypt_manager_web.name='DNSCrypt Manager Web' || return 1; uci set firewall.dnscrypt_manager_web.src=lan || return 1; uci set firewall.dnscrypt_manager_web.proto=tcp || return 1; uci set firewall.dnscrypt_manager_web.dest_port=7682 || return 1; uci set firewall.dnscrypt_manager_web.target=ACCEPT || return 1; uci commit firewall || return 1; /etc/init.d/firewall reload >/dev/null 2>&1 || true; /etc/init.d/ttyd enable >/dev/null 2>&1 || true; /etc/init.d/ttyd restart >/dev/null 2>&1 || true; cat > /usr/lib/lua/luci/controller/dnscrypt_manager.lua <<EOF_LUA
module("luci.controller.dnscrypt_manager", package.seeall)
function index()
 local uci=require "luci.model.uci".cursor()
 if uci:get("ttyd","dnscrypt_manager","enable") ~= "1" then return end
 local e=entry({"admin","services","dnscrypt_manager"},call("redirect"),_("DNSCrypt Manager"),70); e.leaf=true
end
function redirect()
 local uci=require "luci.model.uci".cursor(); local http=require "luci.http"; local ip=uci:get("network","lan","ipaddr") or "192.168.1.1"; ip=ip:match("^[^/]+") or ip; http.redirect("http://"..ip..":7682/")
end
EOF_LUA
/etc/init.d/rpcd reload >/dev/null 2>&1 || true; }
remove_web(){ uci -q delete ttyd.dnscrypt_manager; uci commit ttyd >/dev/null 2>&1 || true; uci -q delete firewall.dnscrypt_manager_web; uci commit firewall >/dev/null 2>&1 || true; rm -f /usr/lib/lua/luci/controller/dnscrypt_manager.lua; /etc/init.d/ttyd restart >/dev/null 2>&1 || true; /etc/init.d/firewall reload >/dev/null 2>&1 || true; }

# ----- status / menus -----
state_word(){ [ "$2" = 1 ] && { [ "$1" = 1 ] && printf "${C_GREEN}✓ ВКЛ • применено${C_NC}" || printf "${C_YELLOW}⚠ ВКЛ • ожидает применения${C_NC}"; } || { [ "$1" = 1 ] && printf "${C_MAGENTA}↻ ЕСТЬ • физически включено${C_NC}" || printf "${C_RED}✗ ВЫКЛ${C_NC}"; }; }
module_state(){ m="$1"; case "$m" in dns) [ "$(_dns_state)" = 1 ] && printf 1 || printf 0;; quic) [ "$(uci -q get firewall.dnscrypt_manager_quic_80.dest_port 2>/dev/null)" = 80 ] && [ "$(uci -q get firewall.dnscrypt_manager_quic_443.dest_port 2>/dev/null)" = 443 ] && [ "$(uci -q get firewall.dnscrypt_manager_quic_80.target 2>/dev/null)" = REJECT ] && [ "$(uci -q get firewall.dnscrypt_manager_quic_443.target 2>/dev/null)" = REJECT ] && printf 1 || printf 0;; mtu) [ "$(uci -q get firewall.@defaults[0].mtu_fix 2>/dev/null)" = 1 ] && printf 1 || printf 0;; force) [ "$(uci -q get firewall.dnscrypt_manager_dns_redirect.target 2>/dev/null)" = DNAT ] && [ "$(uci -q get firewall.dnscrypt_manager_dns_redirect.src_dport 2>/dev/null)" = 53 ] && printf 1 || printf 0;; tcp) _ok=1; for kv in 'net.ipv4.tcp_fastopen=3' 'net.ipv4.tcp_fin_timeout=15' 'net.core.somaxconn=1024' 'net.netfilter.nf_conntrack_max=65536' 'net.ipv4.tcp_keepalive_time=600' 'net.ipv4.tcp_keepalive_intvl=60' 'net.ipv4.tcp_keepalive_probes=5' 'net.core.rmem_max=4194304' 'net.core.wmem_max=4194304' 'net.core.rmem_default=262144' 'net.core.wmem_default=262144'; do _k="${kv%%=*}"; _v="${kv#*=}"; [ "$(sysctl -n "$_k" 2>/dev/null)" = "$_v" ] || _ok=0; done; [ "$_ok" = 1 ] && [ -s /etc/sysctl.d/90-dnscrypt-manager.conf ] && printf 1 || printf 0;; ntp_clients) [ "$(uci -q get firewall.dnscrypt_manager_ntp.dest_port 2>/dev/null)" = 123 ] && [ "$(uci -q get firewall.dnscrypt_manager_ntp.target 2>/dev/null)" = DNAT ] && printf 1 || printf 0;; web) [ "$(uci -q get ttyd.dnscrypt_manager.enable 2>/dev/null)" = 1 ] && pgrep -f '[t]tyd.*dnscrypt-manager' >/dev/null 2>&1 && printf 1 || printf 0;; watchdog) grep -q '/usr/bin/dnscrypt-manager --watchdog' /etc/crontabs/root 2>/dev/null && printf 1 || printf 0;; client) [ -f /etc/dnsmasq.d/dnscrypt-manager-client-fixes.conf ] && grep -q '^local=/telemetry.mozilla.org/$' /etc/dnsmasq.d/dnscrypt-manager-client-fixes.conf 2>/dev/null && grep -q '^server=/clients3.google.com/77.88.8.8$' /etc/dnsmasq.d/dnscrypt-manager-client-fixes.conf 2>/dev/null && printf 1 || printf 0;; *) printf 0;; esac; }
_dns_state(){ dns_query_local "$MAIN_PORT" example.com || return 1; sec="$(get_dnsmasq_sec)"; [ "$(uci -q get dhcp.$sec.noresolv 2>/dev/null)" = 1 ] || return 1; printf '%s\n' "$(uci -q get dhcp.$sec.server 2>/dev/null)" | grep -qxF "127.0.0.1#$MAIN_PORT" || return 1; if [ "$TLD" = 1 ] && [ -n "$SLOT_RU" ]; then dns_query_local "$RU_PORT" yandex.ru || return 1; fi; return 0; }

show_status(){ clear 2>/dev/null || true; printf '\n%b\n\n' "${C_BOLD}${C_YELLOW}DNSCrypt Manager $VERSION${C_NC}"; printf '  dnscrypt-proxy2:  %s\n' "$(pkg_installed && proxy_version || printf 'не установлен')"; printf '  Основной proxy:   127.0.0.1:%s  %s\n' "$MAIN_PORT" "$( [ "$(module_state dns)" = 1 ] && printf 'работает' || printf 'не активен')"; if [ "$TLD" = 1 ] && [ -n "$SLOT_RU" ]; then printf '  RU proxy:         127.0.0.1:%s  %s\n' "$RU_PORT" "$( dns_query_local "$RU_PORT" yandex.ru && printf 'работает' || printf 'не активен')"; fi; sec="$(get_dnsmasq_sec)"; printf '  dnsmasq:           %s\n' "$(/etc/init.d/dnsmasq status >/dev/null 2>&1 && printf 'работает' || printf 'не работает')"; printf '  DNS-серверов:      %s\n' "$(count_selected)"; printf '  Hybrid:            %s\n' "$PROFILE"; printf '  Балансировка:      %s\n' "$(state_word "$(grep -Eq '^[[:space:]]*lb_strategy[[:space:]]*=' "$MAIN_CFG" 2>/dev/null && printf 1 || printf 0)" "$BALANCE")"; printf '  DNS cache:         %s\n' "$(state_word "$(grep -Eq '^[[:space:]]*cache[[:space:]]*=[[:space:]]*true' "$MAIN_CFG" 2>/dev/null && printf 1 || printf 0)" "$CACHE")"; printf '  RU routing:        %s\n' "$(state_word "$( [ "$TLD" = 1 ] && [ -n "$SLOT_RU" ] && printf 1 || printf 0)" "$TLD")"; printf '\n%b\n' "${C_YELLOW}${C_BOLD}ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ${C_NC}"; printf '  QUIC:              %s\n' "$(state_word "$(module_state quic)" "$QUIC")"; printf '  MSS/MTU:           %s\n' "$(state_word "$(module_state mtu)" "$MSS")"; printf '  Принудительный DNS:%s\n' "$(state_word "$(module_state force)" "$FORCE_DNS")"; printf '  TCP/Conntrack:     %s\n' "$(state_word "$(module_state tcp)" "$TCP")"; printf '  NTP клиентов:      %s\n' "$(state_word "$(module_state ntp_clients)" "$NTP_CLIENTS")"; printf '  Client fixes:      %s\n' "$(state_word "$(module_state client)" "$CLIENT_FIXES")"; printf '  Watchdog:          %s\n' "$(state_word "$(module_state watchdog)" "$WATCHDOG")"; printf '  Web:               %s\n' "$(state_word "$(module_state web)" "$WEB")"; }
select_slot(){ slot="$1"; clear 2>/dev/null || true; printf "\n${C_BOLD}Слот %s — выберите DNS${C_NC}\n\n" "$slot"; n=1; while IFS='|' read -r id cat name url region stamp; do [ -n "$id" ] || continue; if [ "$slot" = RU ] && [ "$cat" != regional ]; then continue; fi; printf "[%3s] %-32s [%s/%s]\n" "$n" "$name" "$cat" "$region"; eval "SEL_$n=\"$id\""; n=$((n+1)); done < "$CATALOG"; printf "\n[99] Очистить  [Enter] Назад\n"; printf 'Выбор: '; read -r c; [ -n "$c" ] || return; if [ "$c" = 99 ]; then eval "SLOT_$slot=\"\""; save_state; return; fi; eval "id=\${SEL_$c:-}" 2>/dev/null; [ -n "$id" ] || { warn "Неверный выбор."; pause; return; }; [ "$slot" != RU ] || [ "$(cat_of "$id")" = regional ] || { err "В RU-слот разрешены только региональные DNS."; pause; return; }; eval "SLOT_$slot=\"$id\""; save_state; }
menu_dns(){ while :; do clear 2>/dev/null || true; printf "\\n${C_BOLD}DNS / HYBRID${C_NC}\\n\\n"; for s in 1 2 3 4 5 6 RU; do eval "v=\$SLOT_$s"; [ -n "$v" ] && printf "  %-3s %-32s %s\\n" "$s" "$(name_of "$v")" "$(region_of "$v")" || printf "  %-3s —\\n" "$s"; done; printf "\\n[1-6] Изменить основной DNS\\n[r]  Изменить RU DNS\\n[a]  Сбросить Hybrid по умолчанию\\n[t]  Проверить выбранные DNS\\n[x]  Применить DNSCrypt\\n[b]  Назад\\n"; menu_prompt; read -r c; case "$c" in 1|2|3|4|5|6) select_slot "$c";; r|R) select_slot RU;; a|A) set_defaults; save_state; ok "Hybrid-набор восстановлен."; pause;; t|T) test_selected; pause;; x|X) printf 'Применить DNSCrypt как основной DNS? [Y/n]: '; read -r a; case "$a" in n|N|нет|Нет) ;; *) apply_all || err "Применение не завершено.";; esac; pause;; b|B|"") return;; esac; done; }
test_one(){ id="$1"; port="$2"; port_in_use "$port" && return 1; cfg="$TMP/test-$id.toml"; cp -p "$BASE_CFG" "$cfg" || return 1; sed -i '/^[[:space:]]*server_names[[:space:]]*=/d; /^[[:space:]]*listen_addresses[[:space:]]*=/d' "$cfg"; config_replace_line "$cfg" listen_addresses "[\"127.0.0.1:$port\"]" || return 1; config_replace_line "$cfg" server_names "['$id']" || return 1; printf '\n[static.'"'"'%s'"'"']\nstamp = '\''%s'\''\n' "$id" "$(stamp_of "$id")" >> "$cfg"; "$BIN" -config "$cfg" -check >/dev/null 2>&1 || return 1; "$BIN" -config "$cfg" >"$TMP/$id.log" 2>&1 & p=$!; i=0; okx=0; while [ "$i" -lt 8 ]; do if kill -0 "$p" 2>/dev/null && dns_query_local "$port" example.com; then okx=1; break; fi; sleep 1; i=$((i+1)); done; kill "$p" 2>/dev/null || true; kill -9 "$p" 2>/dev/null || true; [ "$okx" = 1 ]; }
test_selected(){ [ -f "$BASE_CFG" ] || cp -p "$MAIN_CFG" "$BASE_CFG"; for s in 1 2 3 4 5 6 RU; do eval "id=\$SLOT_$s"; [ -n "$id" ] || continue; p="$(next_free_port)" || { warn "Нет свободного тестового порта $TEST_PORT_FIRST-$TEST_PORT_LAST."; return 1; }; printf '  Проверка %s → 127.0.0.1:%s ... ' "$(name_of "$id")" "$p"; if test_one "$id" "$p"; then printf '%b\n' "${C_GREEN}OK${C_NC}"; else printf '%b\n' "${C_RED}FAIL${C_NC}"; fi; done; }
menu_settings(){ while :; do clear 2>/dev/null || true; printf "\\n${C_BOLD}ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ${C_NC}\\n\\n"; printf "  [1] QUIC                 %s\\n  [2] MSS/MTU              %s\\n  [3] Принудительный DNS    %s\\n  [4] TCP/Conntrack         %s\\n  [5] DNS cache              %s\\n  [6] NTP для клиентов       %s\\n  [7] Client fixes           %s\\n  [8] Watchdog               %s\\n  [9] Web access             %s\\n  [a] Применить доп. настройки\\n  [b] Назад\\n" "$QUIC" "$MSS" "$FORCE_DNS" "$TCP" "$CACHE" "$NTP_CLIENTS" "$CLIENT_FIXES" "$WATCHDOG" "$WEB"; menu_prompt; read -r c; case "$c" in 1) [ "$QUIC" = 1 ] && QUIC=0 || QUIC=1;; 2) [ "$MSS" = 1 ] && MSS=0 || MSS=1;; 3) [ "$FORCE_DNS" = 1 ] && FORCE_DNS=0 || FORCE_DNS=1;; 4) [ "$TCP" = 1 ] && TCP=0 || TCP=1;; 5) [ "$CACHE" = 1 ] && CACHE=0 || CACHE=1;; 6) [ "$NTP_CLIENTS" = 1 ] && NTP_CLIENTS=0 || NTP_CLIENTS=1;; 7) [ "$CLIENT_FIXES" = 1 ] && CLIENT_FIXES=0 || CLIENT_FIXES=1;; 8) [ "$WATCHDOG" = 1 ] && WATCHDOG=0 || WATCHDOG=1;; 9) [ "$WEB" = 1 ] && WEB=0 || WEB=1;; a|A) save_state; if [ "$CLIENT_FIXES" = 1 ]; then apply_client_fixes; else remove_client_fixes; fi; apply_all_extras && ok "Дополнительные настройки применены." || err "Не удалось применить все дополнительные настройки."; pause;; b|B|"") save_state; return;; esac; save_state; done; }
menu_ntp(){ clear 2>/dev/null || true; printf "\\n${C_BOLD}NTP${C_NC}\\n  [1] Cloudflare\\n  [2] NIST\\n  [3] ВНИИФТРИ\\n  [4] Google\\n  Выбор: "; read -r c; case "$c" in 1) NTP_PRESET=cf_ip;; 2) NTP_PRESET=nist_ip;; 3) NTP_PRESET=vniiftri_moscow;; 4) NTP_PRESET=google_ip;; *) return;; esac; save_state; apply_ntp; pause; }

apply_all(){ snapshot_router; save_state; apply_dns || return 1; if [ "$CLIENT_FIXES" = 1 ]; then apply_client_fixes || return 1; else remove_client_fixes; fi; apply_all_extras || return 1; save_state; ok "DNSCrypt Manager полностью применён и проверен."; }

main_menu(){ check_env || exit 1; ensure_package >/dev/null 2>&1 || true; write_catalog; load_state; [ -n "$SLOT_1$SLOT_2$SLOT_3$SLOT_4$SLOT_5$SLOT_6" ] || set_defaults; save_state; while :; do show_status; printf "\\n${C_BOLD}МЕНЮ${C_NC}\\n  [1] DNS / Hybrid\\n  [2] Проверка DNS\\n  [3] Дополнительные настройки\\n  [4] Серверы времени\\n  [5] Применить всё\\n  [6] Восстановить предыдущий DNS\\n  [7] Backup\\n  [0] Журнал\\n  [Enter] Выход\\n"; menu_prompt; read -r c; case "$c" in 1) menu_dns;; 2) test_selected; pause;; 3) menu_settings;; 4) menu_ntp;; 5) printf 'Применить всю конфигурацию как основной DNS? [Y/n]: '; read -r a; case "$a" in n|N|нет|Нет) ;; *) apply_all || err "Полное применение завершилось ошибкой.";; esac; pause;; 6) restore_dnsmasq; [ -f "$BASE_CFG" ] && cp -p "$BASE_CFG" "$MAIN_CFG"; "$PKG_INIT" restart >/dev/null 2>&1 || true; stop_ru; remove_watchdog; pause;; 7) backup_file "$MAIN_CFG"; ok "Backup выполнен."; pause;; 0) tail -n 100 "$LOG" 2>/dev/null; pause;; '') stop_ru; exit 0;; esac; done; }

if [ "${1:-}" = --watchdog ]; then check_env >/dev/null 2>&1; write_catalog; load_state; watchdog_run; exit $?; fi
main_menu
