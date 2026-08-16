#!/usr/bin/env bash
set -Eeuo pipefail

default_kiosk_url='http://homeassistant.local:8123/dashboard-1/0?kiosk'

usage() {
  cat <<'EOF'
Verwendung:
  ./deploy.sh BENUTZER@HOST [KIOSK-URL]

Beispiel:
  ./deploy.sh christianraudzis@192.168.178.199
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

ssh_target=$1
kiosk_url=${2:-$default_kiosk_url}

if [[ ! $ssh_target =~ ^[A-Za-z0-9._:@%+-]+$ ]]; then
  printf 'Ungültiges SSH-Ziel: %s\n' "$ssh_target" >&2
  exit 2
fi

if [[ $kiosk_url != http://* && $kiosk_url != https://* ]]; then
  printf 'Die Kiosk-URL muss mit http:// oder https:// beginnen.\n' >&2
  exit 2
fi

if [[ $kiosk_url == *"'"* || $kiosk_url == *' '* || $kiosk_url == *$'\n'* ]]; then
  printf 'Die Kiosk-URL darf keine Leerzeichen, Zeilenumbrüche oder Hochkommas enthalten.\n' >&2
  exit 2
fi

bundle_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
remote_dir="/tmp/raspi-kiosk-setup-$$"

cleanup() {
  ssh "$ssh_target" "rm -rf '$remote_dir'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Übertrage Kiosk-Paket nach %s …\n' "$ssh_target"
ssh "$ssh_target" "mkdir -p '$remote_dir'"
scp -r \
  "$bundle_dir/install.sh" \
  "$bundle_dir/files" \
  "$bundle_dir/assets" \
  "$ssh_target:$remote_dir/"

printf 'Installiere Kiosk-Konfiguration …\n'
ssh -t "$ssh_target" \
  "chmod 0755 '$remote_dir/install.sh' '$remote_dir/files/start-homeassistant-kiosk'; '$remote_dir/install.sh' '$kiosk_url'"

printf 'Fertig. Der Pi startet die grafische Kiosk-Sitzung jetzt neu.\n'
