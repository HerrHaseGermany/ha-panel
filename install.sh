#!/usr/bin/env bash
set -Eeuo pipefail

default_kiosk_url='http://homeassistant.local:8123/dashboard-1/0?kiosk'
kiosk_url=${1:-$default_kiosk_url}

die() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

if (( EUID == 0 )); then
  die 'Dieses Skript als normaler Desktop-Benutzer ausführen, nicht mit sudo.'
fi

if [[ $kiosk_url != http://* && $kiosk_url != https://* ]]; then
  die 'Die Kiosk-URL muss mit http:// oder https:// beginnen.'
fi

if [[ $kiosk_url == *"'"* || $kiosk_url == *' '* || $kiosk_url == *$'\n'* ]]; then
  die 'Die Kiosk-URL darf keine Leerzeichen, Zeilenumbrüche oder Hochkommas enthalten.'
fi

target_user=$(id -un)
target_uid=$(id -u)
target_home=$(getent passwd "$target_user" | cut -d: -f6)
bundle_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
timestamp=$(date +%Y%m%d-%H%M%S)
task_tmp=$(mktemp -d /tmp/raspi-kiosk-install.XXXXXX)
user_backup="$target_home/.local/state/raspi-kiosk/backups/$timestamp"
system_backup="/var/backups/raspi-kiosk/$timestamp"

cleanup() {
  rm -rf -- "$task_tmp"
}
trap cleanup EXIT

[[ -f /etc/xdg/labwc/autostart ]] || die 'Kein Raspberry-Pi-labwc-Desktop erkannt.'
[[ -f "$bundle_dir/files/start-homeassistant-kiosk" ]] || die 'Paket ist unvollständig: Kiosk-Starter fehlt.'
[[ -f "$bundle_dir/assets/wall.png" ]] || die 'Paket ist unvollständig: Hintergrundbild fehlt.'
[[ -f "$bundle_dir/assets/splash.png" ]] || die 'Paket ist unvollständig: Boot-Splash fehlt.'

sudo -v

required_packages=(chromium curl ffmpeg x11-apps wtype locales plymouth initramfs-tools rpd-plym-splash)
missing_packages=()
for package_name in "${required_packages[@]}"; do
  if ! dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q '^install ok installed$'; then
    missing_packages+=("$package_name")
  fi
done

if (( ${#missing_packages[@]} > 0 )); then
  printf 'Installiere fehlende Pakete: %s\n' "${missing_packages[*]}"
  sudo apt-get update
  sudo apt-get install -y "${missing_packages[@]}"
fi

mkdir -p "$user_backup"
chmod 0700 "$user_backup"
sudo install -d -m 0700 "$system_backup"

backup_user() {
  local source_path=$1
  local backup_name=$2
  if [[ -e $source_path ]]; then
    cp -a -- "$source_path" "$user_backup/$backup_name"
  fi
}

backup_system() {
  local source_path=$1
  local backup_name=$2
  if sudo test -e "$source_path"; then
    sudo cp -a -- "$source_path" "$system_backup/$backup_name"
  fi
}

backup_user "$target_home/.config/labwc/environment" labwc-environment
backup_user "$target_home/.config/labwc/environment.d" labwc-environment.d
backup_user "$target_home/.config/labwc/autostart" labwc-autostart
backup_user "$target_home/.config/pcmanfm/default" pcmanfm-default
backup_user "$target_home/.icons/Invisible" invisible-cursor-theme
backup_user "$target_home/.local/bin/start-homeassistant-kiosk" kiosk-launcher
backup_user "$target_home/.config/raspi-kiosk" kiosk-config
backup_user "$target_home/wall.png" wallpaper.png
backup_user "$target_home/splash.png" splash-source.png

backup_system /etc/xdg/labwc/autostart labwc-autostart
backup_system /etc/default/locale default-locale
backup_system /etc/locale.gen locale.gen
backup_system /etc/default/keyboard default-keyboard
backup_system /etc/lightdm/lightdm.conf lightdm.conf
backup_system /etc/lightdm/lightdm.conf.d/90-raspi-kiosk.conf lightdm-kiosk.conf
backup_system /etc/systemd/system/getty@tty1.service.d/autologin.conf tty1-autologin.conf
backup_system /etc/plymouth/plymouthd.conf plymouthd.conf
backup_system /usr/share/plymouth/themes/pix/splash.png plymouth-splash.png
backup_system /usr/share/plymouth/themes/pix/splash.png.original plymouth-splash.png.original
backup_system /boot/firmware/cmdline.txt boot-firmware-cmdline.txt

printf 'Konfiguriere deutsche Locale …\n'
if command -v raspi-config >/dev/null 2>&1; then
  sudo raspi-config nonint do_change_locale de_DE.UTF-8
else
  sudo sed -i -E 's/^#[[:space:]]*(de_DE.UTF-8[[:space:]]+UTF-8)/\1/' /etc/locale.gen
  if ! grep -q '^de_DE.UTF-8[[:space:]]\+UTF-8' /etc/locale.gen; then
    printf '%s\n' 'de_DE.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen >/dev/null
  fi
  sudo locale-gen
  sudo update-locale LANG=de_DE.UTF-8
fi
sudo timedatectl set-timezone Europe/Berlin

cat > "$task_tmp/keyboard" <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="de"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
sudo install -m 0644 "$task_tmp/keyboard" /etc/default/keyboard

printf 'Konfiguriere eigenen Plymouth-Splash …\n'
splash_theme_dir=/usr/share/plymouth/themes/pix
sudo install -d -m 0755 "$splash_theme_dir"
if sudo test -f "$splash_theme_dir/splash.png" && ! sudo test -e "$splash_theme_dir/splash.png.original"; then
  sudo cp -p "$splash_theme_dir/splash.png" "$splash_theme_dir/splash.png.original"
fi
install -m 0644 "$bundle_dir/assets/splash.png" "$target_home/splash.png"
sudo install -m 0644 "$bundle_dir/assets/splash.png" "$splash_theme_dir/splash.png"

cat > "$task_tmp/plymouthd.conf" <<'EOF'
# Administrator customizations go in this file
#[Daemon]
#Theme=ceratopsian
#ShowDelay=0
[Daemon]
Theme=pix
EOF
sudo install -m 0644 "$task_tmp/plymouthd.conf" /etc/plymouth/plymouthd.conf

boot_cmdline_file=/boot/firmware/cmdline.txt
[[ -f $boot_cmdline_file ]] || die "Boot-Kommandozeile fehlt: $boot_cmdline_file"
boot_cmdline=$(<"$boot_cmdline_file")
for boot_parameter in quiet splash plymouth.ignore-serial-consoles; do
  if [[ " $boot_cmdline " != *" $boot_parameter "* ]]; then
    boot_cmdline+=" $boot_parameter"
  fi
done
if [[ $boot_cmdline == *cfg80211.ieee80211_regdom=* ]]; then
  boot_cmdline=$(sed -E 's/cfg80211\.ieee80211_regdom=[^ ]+/cfg80211.ieee80211_regdom=DE/' <<<"$boot_cmdline")
else
  boot_cmdline+=' cfg80211.ieee80211_regdom=DE'
fi
printf '%s\n' "$boot_cmdline" | sudo tee "$boot_cmdline_file" >/dev/null

if [[ -x /usr/sbin/plymouth-set-default-theme ]]; then
  sudo /usr/sbin/plymouth-set-default-theme --rebuild-initrd pix
else
  sudo /usr/sbin/update-initramfs -u -k all
fi

mkdir -p \
  "$target_home/.config/labwc/environment.d" \
  "$target_home/.config/pcmanfm/default" \
  "$target_home/.config/raspi-kiosk" \
  "$target_home/.local/bin" \
  "$target_home/.icons/Invisible/cursors"

cat > "$task_tmp/labwc-environment" <<EOF
LANG=de_DE.UTF-8
LANGUAGE=de_DE:de
XKB_DEFAULT_MODEL=pc105
XKB_DEFAULT_LAYOUT=de
XCURSOR_THEME=Invisible
XCURSOR_SIZE=24
XCURSOR_PATH=$target_home/.icons:/usr/share/icons
EOF
install -m 0644 "$task_tmp/labwc-environment" "$target_home/.config/labwc/environment"
install -m 0644 "$task_tmp/labwc-environment" "$target_home/.config/labwc/environment.d/99-raspi-kiosk.env"

install -m 0644 "$bundle_dir/files/invisible-index.theme" "$target_home/.icons/Invisible/index.theme"
install -m 0644 "$bundle_dir/files/invisible-cursor.cfg" "$target_home/.icons/Invisible/cursor.cfg"
/usr/bin/ffmpeg \
  -v error \
  -f lavfi \
  -i 'color=c=black@0.0:s=24x24,format=rgba' \
  -frames:v 1 \
  -y \
  "$target_home/.icons/Invisible/transparent.png"
(
  cd "$target_home/.icons/Invisible"
  /usr/bin/xcursorgen cursor.cfg cursors/default
)

cursor_sources=(/usr/share/icons/PiXtrix/cursors /usr/share/icons/Adwaita/cursors)
for cursor_source in "${cursor_sources[@]}"; do
  [[ -d $cursor_source ]] || continue
  while IFS= read -r cursor_name; do
    [[ $cursor_name == default ]] && continue
    ln -sfn default "$target_home/.icons/Invisible/cursors/$cursor_name"
  done < <(find "$cursor_source" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -u)
done

install -m 0644 "$bundle_dir/assets/wall.png" "$target_home/wall.png"

set_desktop_value() {
  local desktop_file=$1
  local setting_name=$2
  local setting_value=$3
  if grep -q "^${setting_name}=" "$desktop_file"; then
    sed -i -E "s|^${setting_name}=.*|${setting_name}=${setting_value}|" "$desktop_file"
  else
    printf '%s=%s\n' "$setting_name" "$setting_value" >> "$desktop_file"
  fi
}

mapfile -d '' desktop_files < <(
  find "$target_home/.config/pcmanfm/default" \
    -maxdepth 1 \
    -type f \
    -name 'desktop-items-*.conf' \
    -print0
)

if (( ${#desktop_files[@]} == 0 )); then
  output_name=HDMI-A-1
  while IFS= read -r status_file; do
    if [[ $(<"$status_file") == connected ]]; then
      output_name=$(basename "$(dirname "$status_file")" | sed -E 's/^card[0-9]+-//')
      break
    fi
  done < <(find /sys/class/drm -mindepth 2 -maxdepth 2 -name status -type f 2>/dev/null | sort)

  desktop_file="$target_home/.config/pcmanfm/default/desktop-items-${output_name}.conf"
  if [[ -f /etc/xdg/pcmanfm/default/desktop-items-0.conf ]]; then
    cp /etc/xdg/pcmanfm/default/desktop-items-0.conf "$desktop_file"
  else
    printf '[*]\n' > "$desktop_file"
  fi
  desktop_files=("$desktop_file")
fi

for desktop_file in "${desktop_files[@]}"; do
  set_desktop_value "$desktop_file" wallpaper_mode fit
  set_desktop_value "$desktop_file" wallpaper_common 1
  set_desktop_value "$desktop_file" wallpaper "$target_home/wall.png"
  set_desktop_value "$desktop_file" show_wm_menu 0
  set_desktop_value "$desktop_file" show_documents 0
  set_desktop_value "$desktop_file" show_home 0
  set_desktop_value "$desktop_file" show_trash 0
  set_desktop_value "$desktop_file" show_mounts 0
done

printf '%s\n' "$kiosk_url" > "$target_home/.config/raspi-kiosk/url"
chmod 0600 "$target_home/.config/raspi-kiosk/url"
install -m 0755 "$bundle_dir/files/start-homeassistant-kiosk" "$target_home/.local/bin/start-homeassistant-kiosk"

autostart_file="$target_home/.config/labwc/autostart"
autostart_tmp="$task_tmp/labwc-autostart"
if [[ -f $autostart_file ]]; then
  awk '
    !/start-homeassistant-kiosk/ &&
    !/^# Managed by raspi-kiosk-setup$/ &&
    !/^[[:space:]]*\/usr\/bin\/lwrespawn[[:space:]]+\/usr\/bin\/pcmanfm-pi[[:space:]]*&[[:space:]]*$/ &&
    !/^[[:space:]]*#?[[:space:]]*\/usr\/bin\/lwrespawn[[:space:]]+\/usr\/bin\/wf-panel-pi[[:space:]]*&[[:space:]]*$/ &&
    !/^[[:space:]]*\/usr\/bin\/kanshi[[:space:]]*&[[:space:]]*$/ &&
    !/^[[:space:]]*\/usr\/bin\/lxsession-xdg-autostart[[:space:]]*$/
  ' "$autostart_file" > "$autostart_tmp"
else
  : > "$autostart_tmp"
fi
sed -i -E \
  's|^([[:space:]]*)/usr/bin/lwrespawn[[:space:]]+/usr/bin/wf-panel-pi[[:space:]]*&[[:space:]]*$|\1# /usr/bin/lwrespawn /usr/bin/wf-panel-pi \&|' \
  "$autostart_tmp"
printf '\n%s\n' '# Managed by raspi-kiosk-setup' >> "$autostart_tmp"
printf '/usr/bin/lwrespawn "%s/.local/bin/start-homeassistant-kiosk" &\n' "$target_home" >> "$autostart_tmp"
install -m 0644 "$autostart_tmp" "$autostart_file"

sudo sed -i -E \
  's|^([[:space:]]*)/usr/bin/lwrespawn[[:space:]]+/usr/bin/wf-panel-pi[[:space:]]*&[[:space:]]*$|\1# /usr/bin/lwrespawn /usr/bin/wf-panel-pi \&|' \
  /etc/xdg/labwc/autostart

cat > "$task_tmp/lightdm-kiosk.conf" <<EOF
[Seat:*]
user-session=rpd-labwc
autologin-user=$target_user
autologin-user-timeout=0
autologin-session=rpd-labwc
EOF
sudo install -d -m 0755 /etc/lightdm/lightdm.conf.d
sudo install -m 0644 "$task_tmp/lightdm-kiosk.conf" /etc/lightdm/lightdm.conf.d/90-raspi-kiosk.conf

if command -v raspi-config >/dev/null 2>&1; then
  sudo env USER="$target_user" raspi-config nonint do_boot_behaviour B4
else
  sudo sed -i -E "s|^#?autologin-user=.*|autologin-user=$target_user|" /etc/lightdm/lightdm.conf
  sudo systemctl set-default graphical.target
fi

printf 'Starte die grafische Sitzung neu …\n'
sudo systemctl restart lightdm
sleep 12

printf '\nInstallation abgeschlossen.\n'
printf 'Benutzer-Sicherung: %s\n' "$user_backup"
printf 'System-Sicherung:   %s\n' "$system_backup"
printf 'Kiosk-URL:          %s\n' "$kiosk_url"

if pgrep -u "$target_uid" -af '^/bin/sh /usr/bin/lwrespawn .*/start-homeassistant-kiosk$' >/dev/null; then
  printf 'Kiosk-Starter:      aktiv\n'
else
  printf 'Kiosk-Starter:      nicht erkannt – bitte Sitzung prüfen\n'
fi

if pgrep -u "$target_uid" -x wf-panel-pi >/dev/null; then
  printf 'Taskleiste:         läuft unerwartet\n'
else
  printf 'Taskleiste:         deaktiviert\n'
fi
