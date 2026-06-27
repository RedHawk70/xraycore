#!/bin/bash

# =========================================
# Quick Setup | Script Setup Manager
# XRAY-CORE CHANGER (Fixed UI + Fixed Ctrl+C + Fixed Backup + 0=Exit)
# Edition : Stable Edition V1.0 (UI Revamp)
# Author  : NiLphreakz
# (C) Copyright 2022
# =========================================
set -u

# -------------------------
# Basic helpers
# -------------------------
is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

# -------------------------
# Color auto-detect (256/16)
# -------------------------
supports_256() {
  if need_cmd tput; then
    local c
    c="$(tput colors 2>/dev/null || echo 0)"
    [[ "$c" -ge 256 ]]
  else
    [[ "${COLORTERM:-}" =~ (truecolor|24bit) ]] || [[ "${TERM:-}" == *"256color"* ]]
  fi
}

RESET='\e[0m'; BOLD='\e[1m'; DIM='\e[2m'
if supports_256; then
  C_RED='\e[38;5;196m'
  C_GREEN='\e[38;5;82m'
  C_YELLOW='\e[38;5;226m'
  C_ORANGE='\e[38;5;208m'
  C_BLUE='\e[38;5;39m'
  C_CYAN='\e[38;5;51m'
  C_PURPLE='\e[38;5;135m'
  C_PINK='\e[38;5;213m'
  C_WHITE='\e[38;5;255m'
  C_GRAY='\e[38;5;245m'
else
  C_RED='\e[1;31m'
  C_GREEN='\e[0;32m'
  C_YELLOW='\e[1;33m'
  C_ORANGE='\e[0;33m'
  C_BLUE='\e[1;34m'
  C_CYAN='\e[0;36m'
  C_PURPLE='\e[0;35m'
  C_PINK='\e[1;35m'
  C_WHITE='\e[1;37m'
  C_GRAY='\e[0;37m'
fi

ok()   { printf "%b\n" "${C_GREEN}${BOLD}✔${RESET} $*"; }
info() { printf "%b\n" "${C_CYAN}${BOLD}ℹ${RESET} $*"; }
warn() { printf "%b\n" "${C_YELLOW}${BOLD}⚠${RESET} $*"; }
err()  { printf "%b\n" "${C_RED}${BOLD}✘${RESET} $*"; }

line() { printf "%b\n" "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

badge() {
  local text="$1" color="$2"
  case "$color" in
    green) printf "%b" "${C_GREEN}${BOLD}[ ${text} ]${RESET}" ;;
    red)   printf "%b" "${C_RED}${BOLD}[ ${text} ]${RESET}" ;;
    yellow)printf "%b" "${C_YELLOW}${BOLD}[ ${text} ]${RESET}" ;;
    *)     printf "%b" "${C_WHITE}${BOLD}[ ${text} ]${RESET}" ;;
  esac
}

menu_item() {
  local n="$1" text="$2" tag="${3:-}"
  local bullet="${C_CYAN}•${RESET}"
  local left="${C_YELLOW}${BOLD}${n}${RESET}"
  local t="${C_WHITE}${text}${RESET}"
  if [[ -n "$tag" ]]; then
    printf "%b\n" " [${bullet} ${left}]  ${t}  ${tag}"
  else
    printf "%b\n" " [${bullet} ${left}]  ${t}"
  fi
}

# -------------------------
# Friendly Box (portable ASCII)
# -------------------------
BOX_W=44

repeat_char() { local n="$1" ch="$2"; printf '%*s' "$n" '' | tr ' ' "$ch"; }

term_cols() {
  local c=80
  if need_cmd tput; then
    c="$(tput cols 2>/dev/null || echo 80)"
  fi
  [[ "$c" =~ ^[0-9]+$ ]] || c=80
  echo "$c"
}

box_fixed() {
  local title="$1"
  local cols w t len padL padR

  cols="$(term_cols)"
  w="$BOX_W"

  # auto-fit ikut terminal (tinggal margin kiri/kanan)
  if (( cols > 0 && cols - 4 < w )); then
    w=$((cols - 4))
  fi
  (( w < 20 )) && w=20

  t="$title"
  if (( ${#t} > w )); then
    t="${t:0:$((w-3))}..."
  fi

  len=${#t}
  padL=$(( (w - len) / 2 ))
  padR=$(( w - len - padL ))

  # ASCII border: paling compatible
  printf "%b\n" "${C_CYAN}+$(repeat_char "$w" "=")+${RESET}"
  printf "%b\n" "${C_CYAN}|${RESET}$(repeat_char "$padL" " ")${BOLD}${C_WHITE}${t}${RESET}$(repeat_char "$padR" " ")${C_CYAN}|${RESET}"
  printf "%b\n" "${C_CYAN}+$(repeat_char "$w" "=")+${RESET}"
}

# -------------------------
# Spinner
# -------------------------
_spinner_pid=""
spinner_start() {
  local msg="${1:-Working...}"
  printf "%b" "${C_GRAY}${DIM}${msg}${RESET} "
  (
    local frames='|/-\'
    local i=0
    while :; do
      printf "\b%b" "${C_CYAN}${BOLD}${frames:i++%4:1}${RESET}"
      sleep 0.1
    done
  ) &
  _spinner_pid=$!
}
spinner_stop() {
  if [[ -n "${_spinner_pid}" ]]; then
    kill "${_spinner_pid}" >/dev/null 2>&1 || true
    wait "${_spinner_pid}" 2>/dev/null || true
    _spinner_pid=""
    printf "\b \n"
  fi
}
cleanup() { spinner_stop; }

# Ctrl+C exit properly
trap 'cleanup; echo; printf "%b\n" "${C_YELLOW}${BOLD}Exit...${RESET}"; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup' EXIT

# -------------------------
# Download helper
# -------------------------
download_to() {
  local url="$1" out="$2"
  if need_cmd curl; then
    curl -fsSL -o "$out" "$url"
  elif need_cmd wget; then
    wget -q -O "$out" "$url"
  else
    return 1
  fi
}

# -------------------------
# Xray paths & version info
# -------------------------
xrays_path="$(command -v xray 2>/dev/null || true)"
[[ -z "$xrays_path" ]] && xrays_path="/usr/local/bin/xray"

current_version="-"
latest_version="(unknown)"

refresh_current_version() {
  current_version="-"
  if [[ -x "$xrays_path" ]]; then
    local v
    v="$("$xrays_path" --version 2>&1 || true)"
    current_version="$(echo "$v" | awk '/Xray/{print $2}' | head -n 1)"
    [[ -z "$current_version" ]] && current_version="-"
  fi
}

refresh_latest_version() {
  latest_version="(unknown)"
  if need_cmd curl; then
    latest_version="$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases \
      | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"
  elif need_cmd wget; then
    latest_version="$(wget -qO- https://api.github.com/repos/XTLS/Xray-core/releases \
      | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"
  fi
  [[ -z "$latest_version" ]] && latest_version="(unknown)"
}

# -------------------------
# Backup (FIX mv .bakk error)
# -------------------------
backup_current() {
  if [[ -n "$xrays_path" && -f "$xrays_path" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    mv -f "$xrays_path" "${xrays_path}.bakk-${ts}" 2>/dev/null \
      || mv -f "$xrays_path" "${xrays_path}.bakk" 2>/dev/null \
      || true
  fi
}

install_single_binary() {
  local url="$1"

  if ! is_root; then
    err "Sila run sebagai root (sudo -i / sudo bash)."
    return 1
  fi

  if ! need_cmd curl && ! need_cmd wget; then
    err "curl/wget tak ada. Install salah satu dulu."
    return 1
  fi

  [[ -z "$xrays_path" ]] && xrays_path="/usr/local/bin/xray"

  backup_current

  spinner_start "Downloading binary"
  if ! download_to "$url" "$xrays_path"; then
    spinner_stop
    err "Download failed."
    return 1
  fi
  spinner_stop

  chmod 755 "$xrays_path" || true
  ok "Installed: ${url}"
  "$xrays_path" version 2>/dev/null || "$xrays_path" --version 2>/dev/null || true
}

install_latest_zip() {
  local ver="$1"
  local url="https://github.com/XTLS/Xray-core/releases/download/v${ver}/Xray-linux-64.zip"

  if ! is_root; then err "Sila run sebagai root (sudo -i / sudo bash)."; return 1; fi
  if ! need_cmd unzip; then err "unzip tak ada. Install: apt/yum install unzip"; return 1; fi
  if ! need_cmd curl && ! need_cmd wget; then err "curl/wget tak ada. Install salah satu dulu."; return 1; fi

  [[ -z "$xrays_path" ]] && xrays_path="/usr/local/bin/xray"

  backup_current

  local tmp
  tmp="$(mktemp -d)"

  spinner_start "Downloading latest zip"
  if ! download_to "$url" "${tmp}/Xray-linux-64.zip"; then
    spinner_stop
    rm -rf "$tmp"
    err "Download failed."
    return 1
  fi
  spinner_stop

  spinner_start "Extracting & installing"
  (cd "$tmp" && unzip -o "Xray-linux-64.zip" >/dev/null 2>&1) || {
    spinner_stop
    rm -rf "$tmp"
    err "Unzip failed."
    return 1
  }

  if [[ -f "${tmp}/xray" ]]; then
    mv -f "${tmp}/xray" "$xrays_path"
    chmod 755 "$xrays_path" || true
    spinner_stop
    rm -rf "$tmp"
    ok "Installed latest Xray-core v${ver}"
    "$xrays_path" version 2>/dev/null || "$xrays_path" --version 2>/dev/null || true
  else
    spinner_stop
    rm -rf "$tmp"
    err "Binary 'xray' tak jumpa dalam zip."
    return 1
  fi
}

press_enter() {
  read -rp "$(printf "%b" "Press ${C_ORANGE}[${RESET}${C_GREEN} Enter ${RESET}${C_ORANGE}]${RESET} Back to menu . . . ")" _
}

# -------------------------
# Main function (menu)
# -------------------------
xcorechanger() {
  refresh_latest_version
  refresh_current_version

  while true; do
    clear
    box_fixed "XRAY-CORE CHANGER"
    printf "%b\n" "${C_GRAY}${DIM}Xray-core Changer By NiLphreakz${RESET}"
    printf "%b\n" "${C_GRAY}${DIM}Telegram : https://t.me/Nilphreakz${RESET}"
    line

    local_status="$( [[ -x "$xrays_path" ]] && badge "OK" green || badge "NO" red )"
    printf "%b\n" " ${C_WHITE}Xray binary${RESET}    : ${C_GRAY}${xrays_path}${RESET} ${local_status}"
    printf "%b\n" " ${C_WHITE}Current version${RESET} : ${C_ORANGE}${BOLD}v${current_version}${RESET}"
    printf "%b\n" " ${C_WHITE}Latest version ${RESET} : ${C_GREEN}${BOLD}v${latest_version}${RESET}"
    line

    printf "%b\n" "${C_PURPLE}${BOLD}XRAY-CORE (Official)${RESET}"
    menu_item "1"  "Xray-core v1.5.4"
    menu_item "2"  "Xray-core v1.6.1"
    menu_item "3"  "Xray-core v1.7.2"
    menu_item "4"  "Xray-core v1.7.5"
    menu_item "5"  "Xray-core v1.8.4"
    menu_item "6"  "Xray-core v${latest_version}" "${C_GREEN}${BOLD}<< Latest${RESET}"

    printf "\n%b\n" "${C_PINK}${BOLD}XRAY-CORE MOD${RESET}"
    menu_item "7"  "Xray-core MOD v1.6.5"
    menu_item "8"  "Xray-core MOD v1.7.2-1"
    menu_item "9"  "Xray-core MOD v24.11.30"
    menu_item "10" "Xray-core MOD v25.10.15"
    menu_item "11" "Xray-core MOD v26.2.6-1"

    printf "\n%b\n" "${C_BLUE}${BOLD}TOOLS${RESET}"
    menu_item "12" "Check Xray-core version"
    menu_item "13" "Restart Xray-core"
    printf "\n%b\n" "${C_GRAY}${BOLD}NAVIGATION${RESET}"
    menu_item "0"  "Exit"
    line

    printf "%b\n" "${C_YELLOW}${BOLD}Notes:${RESET}"
    printf "%b\n" " ${C_GREEN}❇️${RESET} Please restart / reboot server after change Xray-core."
    printf "%b\n" " ${C_GREEN}❇️${RESET} If you using old XTLS, downgrade Xray-core v1.7.5 or lower."
    printf "%b\n" " ${C_GREEN}❇️${RESET} Xray-core MOD support custom path / multipath. Only use it if your scripts support."
    line
    printf "%b\n\n" "${C_WHITE}${BOLD}Press [ Ctrl+C ]${RESET} ${C_GRAY}• To-Exit-Script${RESET}"

    read -rp "$(printf "%b" "${C_CYAN}${BOLD}Select From Options${RESET} ${C_GRAY}[1-99]${RESET} : ")" xcore
    echo

    case "${xcore}" in
      1)  clear; install_single_binary "https://github.com/NiL070/XrayCoreChanger/releases/download/Xray-Core_v1.5.4/Xray-linux-64-v1.5.4"; press_enter ;;
      2)  clear; install_single_binary "https://github.com/NiL070/XrayCoreChanger/releases/download/Xray-Core_v1.6.1/Xray-linux-64-v1.6.1"; press_enter ;;
      3)  clear; install_single_binary "https://github.com/NiL070/XrayCoreChanger/releases/download/Xray-Core_v1.7.2/Xray-linux-64-v1.7.2"; press_enter ;;
      4)  clear; install_single_binary "https://github.com/NiL070/XrayCoreChanger/releases/download/Xray-Core_v1.7.5/Xray-linux-64-v1.7.5"; press_enter ;;
      5)  clear; install_single_binary "https://github.com/NiL070/XrayCoreChanger/releases/download/Xray-Core_v1.8.4/Xray-linux-64-v1.8.4"; press_enter ;;
      6)  clear; install_latest_zip "${latest_version}"; press_enter ;;

      7)  clear; install_single_binary "https://github.com/NiL070/XrayCoreChanger/releases/download/Xray-CoreMod_v1.6.5.1/Xray-linux-64-v1.6.5.1"; press_enter ;;
      8)  clear; install_single_binary "https://github.com/NiL070/XrayCoreChanger/releases/download/Xray-CoreMod_v1.7.2-1/Xray-linux-64-v1.7.2-1"; press_enter ;;
      9)  clear; install_single_binary "https://github.com/howitzer07/xraycore/releases/download/v24.11.30/xray-v24.11.30"; press_enter ;;
      10) clear; install_single_binary "https://github.com/howitzer07/xraycore/releases/download/v25.10.15/xray-linux-amd64"; press_enter ;;
      11) clear; install_single_binary "https://github.com/RedHawk70/xraycore/releases/download/xrmodv26.2.6-1/Xray-linux-64-v26.2.6-1"; press_enter ;;	  

      12)
        clear
        if [[ -x "$xrays_path" ]]; then
          "$xrays_path" version 2>/dev/null || "$xrays_path" --version 2>/dev/null || true
        else
          err "xray binary not found at: $xrays_path"
        fi
        press_enter
        ;;

      13)
        clear
        if ! is_root; then
          err "Sila run sebagai root untuk restart service."
        else
          if need_cmd systemctl; then
            spinner_start "Restarting xray service"
            systemctl restart xray >/dev/null 2>&1 || true
            systemctl restart xray@config >/dev/null 2>&1 || true
            systemctl restart xray@none >/dev/null 2>&1 || true
            spinner_stop
            ok "Restart done."
          else
            warn "systemctl not found. Restart manually."
          fi
        fi
        press_enter
        ;;

      0)
        clear
        exit 0
        ;;

      *)
        clear
        err "Please enter an correct number . . ."
        sleep 2
        ;;
    esac

    refresh_current_version
    refresh_latest_version
  done
}

# Run
xcorechanger
