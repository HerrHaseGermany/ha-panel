# Raspberry-Pi-Home-Assistant-Kiosk

Dieses Paket reproduziert die Kiosk-Konfiguration des eingerichteten Raspberry Pi auf einem weiteren Gerät.

Die vollständige Bestandsaufnahme mit Herkunft jeder Änderung steht in [AUDIT.md](AUDIT.md).

## Enthaltene Anpassungen

- automatische Anmeldung des gewählten Desktop-Benutzers in `rpd-labwc`
- dauerhaft deaktivierte Taskleiste (`wf-panel-pi`)
- keine doppelten Standard-Autostarts aus System- und Benutzerkonfiguration
- eigener Plymouth-Boot-Splash aus `assets/splash.png` mit Theme `pix`
- erforderliche Bootparameter und neu aufgebautes Initramfs für den Splash
- ausgeblendete Desktop-Symbole für Home, Dokumente, Papierkorb und Laufwerke
- aktuelles Hintergrundbild aus `assets/wall.png`
- vollständig transparentes Cursor-Theme
- System-Locale `de_DE.UTF-8`
- Zeitzone `Europe/Berlin` und WLAN-Regulierungsland `DE`
- deutsche QWERTZ-Tastatur (`de`, `pc105`)
- Chromium-Autostart, der auf Home Assistant wartet und erst bei erfolgreicher HTTP-Antwort startet
- Chromium im Kioskmodus, auf Deutsch und mit erzwungenem Dark Mode
- keine Keyring-Abfrage durch `--password-store=basic`
- automatischer Neustart des Kiosks über `lwrespawn`, falls Chromium beendet wird

Standardmäßig wird diese URL geöffnet:

```text
http://homeassistant.local:8123/dashboard-1/0?kiosk
```

## Nicht enthalten

Das Paket kopiert bewusst keine Chromium-Sitzung, Cookies, Home-Assistant-Tokens, gespeicherten Anmeldedaten, privaten SSH-Schlüssel oder WLAN-Passwörter. Auf dem neuen Pi ist deshalb eine einmalige Home-Assistant-Anmeldung nötig.

Der Hostname `ha-panel-eg` ist eine Geräteidentität und wird ebenfalls nicht kopiert. Beim Schreiben der SD-Karte einen eigenen eindeutigen Hostnamen für jeden Pi vergeben.

`--password-store=basic` verhindert die Keyring-Abfrage, speichert Browser-Anmeldedaten aber ohne Schutz durch den System-Keyring. Der Pi sollte deshalb wie ein Kioskgerät physisch und im Netzwerk geschützt werden.

## Voraussetzungen

- Raspberry Pi OS mit Desktop und `labwc` (getesteter Ausgangspunkt: Debian 13/Trixie)
- ein normaler Desktop-Benutzer mit `sudo`-Rechten
- aktivierter SSH-Zugang
- Netzwerkzugriff auf Home Assistant
- auf dem steuernden Rechner: `ssh`, `scp` und Bash

Das Skript installiert bei Bedarf automatisch `chromium`, `curl`, `ffmpeg`, `x11-apps`, `wtype`, `locales`, `plymouth`, `initramfs-tools` und `rpd-plym-splash` über APT. `wtype` war auf dem Ausgangssystem manuell installiert, wird von der finalen Kiosk-Konfiguration aber derzeit nicht aktiv verwendet.

## Schnellinstallation über SSH

Repository zunächst von GitHub laden:

```bash
git clone https://github.com/HerrHaseGermany/ha-panel.git
cd ha-panel
```

Anschließend das Paket auf den neuen Pi übertragen und installieren:

```bash
chmod +x deploy.sh install.sh files/start-homeassistant-kiosk
./deploy.sh BENUTZER@IP-ADRESSE
```

Beispiel:

```bash
./deploy.sh christianraudzis@192.168.178.199
```

Eine abweichende Dashboard-URL kann als zweites Argument angegeben werden:

```bash
./deploy.sh christianraudzis@192.168.178.199 'http://homeassistant.local:8123/dashboard-2/0?kiosk'
```

SSH oder `sudo` fragen gegebenenfalls interaktiv nach dem Passwort. Passwörter gehören nicht in dieses Paket.

## Direkte Installation auf dem Pi

Das gesamte Verzeichnis auf den Pi kopieren und als normaler Desktop-Benutzer ausführen:

```bash
chmod +x install.sh files/start-homeassistant-kiosk
./install.sh
```

Die optionale Kiosk-URL ist das erste Argument:

```bash
./install.sh 'http://homeassistant.local:8123/dashboard-1/0?kiosk'
```

Das Installationsskript darf nicht direkt mit `sudo` gestartet werden. Es fordert `sudo` nur für Systemdateien, Paketinstallation, Locale und LightDM an.

## Was nach der Installation passiert

1. Vorhandene Konfigurationen werden mit einem Zeitstempel gesichert.
2. Die deutsche Locale wird erzeugt; QWERTZ und Autologin werden gesetzt.
3. Der eigene Plymouth-Splash wird installiert, `pix` gewählt und das Initramfs neu aufgebaut.
4. Desktop, Cursor, Hintergrund und Chromium-Kiosk werden konfiguriert.
5. Nur LightDM beziehungsweise die grafische Sitzung wird neu gestartet.
6. Der Kiosk wartet auf Home Assistant und öffnet die Seite automatisch.
7. Einmal auf Deutsch bei Home Assistant anmelden.

Wenn Home Assistant noch nicht erreichbar ist, bleibt der Desktop sichtbar. Der Starter prüft die URL fortlaufend und öffnet Chromium später automatisch.

## Sicherungen

Bei jedem Lauf entstehen neue Sicherungen:

```text
~/.local/state/raspi-kiosk/backups/ZEITSTEMPEL
/var/backups/raspi-kiosk/ZEITSTEMPEL
```

Das Skript löscht keine älteren Sicherungen. Es ist wiederholt ausführbar und ersetzt nur die von diesem Paket verwalteten Einstellungen.

## Ursprünglich manuell vorgenommene Änderungen

Zur Nachvollziehbarkeit wurden auf dem ersten Pi diese Bereiche angepasst:

```text
/etc/xdg/labwc/autostart
/etc/default/locale
/etc/default/keyboard
/etc/lightdm/lightdm.conf
/etc/plymouth/plymouthd.conf
/boot/firmware/cmdline.txt
/usr/share/plymouth/themes/pix/splash.png
~/.config/labwc/autostart
~/.config/labwc/environment
~/.config/labwc/environment.d/
~/.config/pcmanfm/default/desktop-items-*.conf
~/.icons/Invisible/
~/.local/bin/start-homeassistant-kiosk
~/.config/chromium/Default
~/wall.png
~/splash.png
```

Das Chromium-Profil wurde auf dem ersten Pi einmalig zurückgesetzt, damit die deutsche Home-Assistant-Anmeldung neu durchgeführt werden konnte. Das Replikationsskript löscht oder ersetzt ein vorhandenes Chromium-Profil nicht.

## Ergebnis der vollständigen Abweichungsprüfung

Das Ausgangssystem wurde gegen die Prüfsummen aller installierten Debian-/Raspberry-Pi-Pakete sowie gegen die Paket-Conffiles geprüft. Zusätzlich wurden Bootdateien, Initramfs, systemd-Dienste, Cronjobs, Benutzer-Autostarts, lokale Softwarepfade, APT-Historie und relevante Shell-Historie inventarisiert.

Als tatsächlich eigene, für den Kiosk relevante Vorarbeiten wurden bestätigt:

- `~/splash.png` wurde als `/usr/share/plymouth/themes/pix/splash.png` installiert.
- Der ursprüngliche Paket-Splash wurde als `splash.png.original` gesichert.
- Plymouth-Theme `pix` wurde gewählt und das Initramfs neu aufgebaut.
- `~/wall.png` wurde mit PCManFM im Modus `fit` als Hintergrund gesetzt.
- Die Benutzer-Autostartdatei wurde vom labwc-Systemstandard abgeleitet und `wf-panel-pi` deaktiviert.
- `x11-apps` und `wtype` wurden manuell installiert.
- Ein unsichtbares Cursor-Theme wurde zunächst manuell versucht; das Paket verwendet die später verifizierte robuste Variante.

Es wurden keine eigenen Cronjobs, keine eigenen systemd-Dienste, keine zusätzliche Kanshi-/Displaykonfiguration und keine weitere lokale Software unter `/usr/local` gefunden. Weitere Prüfsummenabweichungen mit Zeitstempeln vom 18. Juni stammen aus dem Raspberry-Pi-Image beziehungsweise dessen First-Boot-Konfiguration, nicht aus den heutigen manuellen Anpassungen.
