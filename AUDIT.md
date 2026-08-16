# Vollständige Änderungsinventur des Ausgangssystems

Erfasst am 16. August 2026 auf einem Raspberry Pi 3 Model B Rev 1.2 mit Debian 13/Trixie und `labwc`.

## Prüfmethoden

Für die Inventur wurden verwendet:

- Prüfsummenvergleich aller Dateien aus `/var/lib/dpkg/info/*.md5sums`
- Vergleich aller Debian-Conffiles mit den in `dpkg` hinterlegten MD5-Werten
- Prüfung von Bootdateien, Plymouth-Theme und allen vorhandenen Initramfs-Dateien
- Inventur von systemd-Diensten, Benutzer-Diensten, Autostarts und Cronjobs
- Inventur von `/usr/local`, `/opt`, `/srv` und relevanten Dateien im Benutzerverzeichnis
- APT-Historie und Liste manuell markierter Pakete
- ausschließlich visuell relevante Zeilen aus der Shell-Historie
- Zeitstempelvergleich zur Trennung von Image-/First-Boot-Änderungen und späteren manuellen Eingriffen

## Vor Beginn der Codex-Arbeiten manuell geändert

### Eigener Boot-Splash

- Quelldatei: `~/splash.png`
- Auflösung: 1024 × 768, RGB-PNG
- SHA-256: `1d30c3b5a804db74ad840b4446f8f4b9a66038fb7f8127a8eed5b770067f24fd`
- Ziel: `/usr/share/plymouth/themes/pix/splash.png`
- Paketstandard wurde zuvor als `splash.png.original` gesichert.
- `/etc/plymouth/plymouthd.conf` wurde auf `Theme=pix` gesetzt.
- `plymouth-set-default-theme --rebuild-initrd pix` wurde ausgeführt.
- Die benutzerdefinierte Grafik und `Theme=pix` sind in beiden vorhandenen Initramfs-Dateien enthalten.
- `/boot/firmware/cmdline.txt` enthält `quiet splash plymouth.ignore-serial-consoles`.

### Eigenes Desktop-Wallpaper

- Quelldatei: `~/wall.png`
- Auflösung: 1540 × 720, RGB-PNG
- SHA-256: `e3049636ba4cfa2c2a27c22e1dac81262579ff783430f807321f1093b5d5ddd8`
- Mit `pcmanfm --set-wallpaper=... --wallpaper-mode=fit` gesetzt.
- PCManFM-Konfiguration: `~/.config/pcmanfm/default/desktop-items-HDMI-A-1.conf`.

### Desktop-Autostart und Panel

- `/etc/xdg/labwc/autostart` wurde nach `~/.config/labwc/autostart` kopiert.
- Der Start von `wf-panel-pi` wurde dort auskommentiert.
- Die übrigen labwc-Standardprogramme waren PCManFM, Kanshi und `lxsession-xdg-autostart`.

### Erster Versuch eines unsichtbaren Cursors

- `x11-apps` wurde für `xcursorgen` installiert.
- Unter `~/.icons/Invisible` wurde ein eigenes Cursor-Theme angelegt.
- Verschiedene Cursor-Aliase wurden auf einen transparenten Cursor verlinkt.
- Es wurden mehrere Varianten über `~/.config/environment.d/` und `~/.config/labwc/environment.d/90-cursor.env` getestet.
- Der letzte Vorzustand enthielt nur `XCURSOR_SIZE=0` und war nicht zuverlässig wirksam.
- `wtype` wurde während dieser Versuche installiert, wird von der finalen Konfiguration aber nicht aktiv verwendet.

## Danach gemeinsam mit Codex eingerichtet

- dedizierter öffentlicher SSH-Schlüssel für die Administration des ersten Pi
- systemweit deaktivierter `wf-panel-pi`-Autostart, da `labwc -m` zusätzlich die Systemdatei einliest
- ausgeblendete PCManFM-Symbole für Home, Dokumente, Papierkorb und Laufwerke
- verifiziertes transparentes Xcursor-Theme mit 106 Aliasnamen
- Kiosk-Starter unter `~/.local/bin/start-homeassistant-kiosk`
- Warten auf eine erfolgreiche HTTP-Antwort von Home Assistant vor dem Chromium-Start
- Chromium-Kiosk mit deutscher Sprache, erzwungenem Dark Mode und automatischem Neustart
- Vermeidung des Keyring-Dialogs durch `--password-store=basic`
- System-Locale `de_DE.UTF-8`
- QWERTZ über `XKB_DEFAULT_LAYOUT=de` und `/etc/default/keyboard`
- Zeitzone `Europe/Berlin`
- einmaliger Chromium-Profilwechsel für eine neue deutsche Home-Assistant-Anmeldung

Das Replikationspaket kopiert den privaten SSH-Schlüssel und das Chromium-Profil ausdrücklich nicht.

## Bestätigte Basis-/First-Boot-Einstellungen

- Desktop-Sitzung: `rpd-labwc`
- automatisches LightDM-Login
- Tastaturmodell `pc105`, Layout `de`
- WLAN-Regulierungsland `DE`
- Zeitzone `Europe/Berlin`
- Bootziel `graphical.target`
- leere Kanshi-Konfiguration; die Auflösung wird vom angeschlossenen Display erkannt

Der Hostname des ersten Geräts lautet `ha-panel-eg`. Er wird nicht repliziert, weil jeder weitere Pi einen eindeutigen Hostnamen benötigt.

## Vollscan: keine weiteren eigenen Anpassungen gefunden

- keine eigenen Cronjobs
- keine eigenen systemd-Service-Dateien
- keine Benutzer-systemd-Dienste
- keine zusätzlichen `.desktop`-Autostarts
- keine benutzerdefinierte Kanshi-/Displaykonfiguration
- keine lokale Software unter `/usr/local` oder `/srv`
- keine weiteren Kiosk-Skripte außerhalb der dokumentierten Dateien

## Paketabweichungen, die nicht vom Benutzer stammen

Der Paketvollscan meldete neben dem eigenen Plymouth-Splash drei weitere abweichende Payload-Dateien:

- `/usr/lib/python3.13/EXTERNALLY-MANAGED` – Paket-Diversion durch `raspberrypi-sys-mods`
- `/usr/share/firefox/distribution/distribution.ini` – Raspberry-Pi-Vorgaben aus `rpi-firefox-mods`
- `/usr/lib/modprobe.d/g_ether.conf` – Raspberry-Pi-USB-Gadget-Vorgabe aus `rpi-usb-gadget`

Ihre Zeitstempel und Paketzuordnung zeigen, dass sie aus dem Image beziehungsweise den Raspberry-Pi-Paketen stammen. Dasselbe gilt für die Conffile-Abweichungen vom 18. Juni 2026, unter anderem Avahi-, LightDM-, Login-, Chromium- und Greeter-Vorgaben.

## Umsetzung im Replikationspaket

`install.sh` bildet alle für das zweite Kioskgerät relevanten Änderungen ab:

- kopiert beide eigenen PNG-Dateien
- installiert und aktiviert den Plymouth-Splash einschließlich Initramfs-Neubau
- erhält den Paket-Splash als `.original`
- setzt Wallpaper und blendet Desktop-Symbole aus
- deaktiviert das Panel ohne doppelte labwc-Standardprozesse
- erzeugt das transparente Cursor-Theme
- setzt Locale, QWERTZ, Zeitzone und WLAN-Land
- richtet LightDM-Autologin und den vollständigen Chromium-Kiosk ein
- installiert auch die vorher manuell hinzugefügten Pakete `x11-apps` und `wtype`
- erstellt vor jeder Änderung Benutzer- und Systemsicherungen
