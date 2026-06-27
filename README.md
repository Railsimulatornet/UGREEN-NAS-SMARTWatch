# UGREEN-NAS-SMARTWatch

![SMARTWatch](Screens/SMARTWatch.png)

UGREEN-NAS-SMARTWatch ist ein leichtgewichtiges Bash-Skript für UGREEN NAS mit UGOS.  
Das Skript liest SMART-Werte von HDD-, NVMe-, USB- und eMMC-Laufwerken aus, kann SMART-Selbsttests starten und versendet einen Outlook-freundlichen HTML-Report per E-Mail.

## Features

- SMART-Überwachung für HDD, NVMe, USB und eMMC
- Wöchentlicher Kurztest und monatlicher Langtest
- Outlook-freundlicher HTML-Report
- DE/EN-Ausgabe per `LANGUAGE`
- USB-/Wechsellaufwerke optional einbeziehbar
- NVMe-Stillstandserkennung bei festhängenden Selbsttests
- Cron-tauglich, auch ohne interaktives Shell-Environment
- Für UGREEN NAS / UGOS optimiert

## Neuerungen in V5.00

- Unterstützung für DXP2800 GT, DXP4800 GT, DXP6800 Ultra und DXP8800 Ultra
- U.2-NVMe-Unterstützung für die GT-Serie
- Physische Unterscheidung von U.2-Schacht 1 und 2 beim DXP4800 GT
- Verbesserte Modellnormalisierung
- Vollständig getrennte deutsche und englische Konsolen- und E-Mail-Ausgaben
- Präzisere Anzeige der unterstützten NVMe-Laufwerke
- Korrigierte Darstellung übersprungener eMMC-Lesetests
- Fortschrittsmeldungen vor und nach vollständigen eMMC-Lesetests

## Screenshots

### Deutsch (DE)

| Outlook | Mobile Ansicht |
|---|---|
| ![SMARTWatch DE - Outlook](Screens/Outlook.jpg) | ![SMARTWatch DE - Mobile](Screens/Mobil.jpg) |

### Englisch (EN)

| Outlook | Mobile Ansicht |
|---|---|
| ![SMARTWatch EN - Outlook](Screens/OutlookEN.jpg) | ![SMARTWatch EN - Mobile](Screens/MobileEN.jpg) |

## Unterstützte UGREEN-NAS-Modelle

UGREEN-NAS-SMARTWatch ist für UGREEN NAS mit UGOS optimiert. Folgende Modelle werden derzeit ausdrücklich erkannt und unterstützt:

### DH-Serie

- DH2300
- DH4300 Plus

### DX- und iDX-Serie

- DX4700
- iDX6011
- iDX6011 Pro

### DXP-Serie

- DXP2800
- DXP2800 GT
- DXP4800
- DXP4800 Plus
- DXP4800 Pro
- DXP4800 GT
- DXP480T Plus
- DXP6800 Plus
- DXP6800 Pro
- DXP6800 Ultra
- DXP8800 Plus
- DXP8800 Pro
- DXP8800 Ultra

Die GT-Serie unterstützt zusätzlich U.2-NVMe-Laufwerke. Beim DXP4800 GT können U.2-Schacht 1 und U.2-Schacht 2 physisch unterschieden werden.

Andere UGREEN-NAS-Modelle mit UGOS können durch die allgemeine Laufwerkserkennung ebenfalls funktionieren, wurden jedoch noch nicht ausdrücklich verifiziert. Rückmeldungen zu weiteren Modellen sind willkommen.

## Voraussetzungen

- Unterstütztes UGREEN NAS mit UGOS

## Installation (Quickstart)

1) Paket auf das NAS kopieren, zum Beispiel nach:  
`/volume2/NASAdmin/Skripte/SmartWatch/`

2) In den Ordner wechseln:

```bash
cd /volume2/NASAdmin/Skripte/SmartWatch
```

3) Beispielkonfiguration kopieren:

```bash
cp smart-report.env.example smart-report.env
```

4) Konfiguration anpassen:

```bash
nano smart-report.env
```

5) Skript ausführbar machen:

```bash
chmod +x ugreen-smart-report.sh
```

## Test und Nutzung

### Testmail senden

```bash
bash ./ugreen-smart-report.sh --test-mail
```

### Nur Report erzeugen

```bash
bash ./ugreen-smart-report.sh --report-only
```

### Wöchentlichen Kurztest starten

```bash
bash ./ugreen-smart-report.sh --weekly-short
```

### Monatlichen Langtest starten

```bash
bash ./ugreen-smart-report.sh --monthly-long
```

### Hilfe anzeigen

```bash
bash ./ugreen-smart-report.sh --help
```

## Cron-Beispiel

Für die Nutzung per `crontab -e` wird empfohlen, `SHELL` und `PATH` explizit zu setzen:

```bash
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

0 3 * * 1 /usr/bin/flock -n /tmp/smarthealth.lock /bin/bash /volume2/NASAdmin/Skripte/SmartWatch/ugreen-smart-report.sh --weekly-short >/dev/null 2>&1
15 4 1 * * /usr/bin/flock -n /tmp/smarthealth.lock /bin/bash /volume2/NASAdmin/Skripte/SmartWatch/ugreen-smart-report.sh --monthly-long >/dev/null 2>&1
```

## Konfiguration

Alle Einstellungen basieren auf der Datei:

```text
SmartWatch/smart-report.env.example
```

Auf dem NAS wird daraus deine aktive Konfiguration erstellt:

```bash
cp smart-report.env.example smart-report.env
```

Wichtige Optionen:

- `LANGUAGE`
- `LOG_DIR`
- `LOG_RETENTION_DAYS`
- `MAIL_FROM`
- `MAIL_TO`
- `SMTP_SERVER`
- `SMTP_PORT`
- `SMTP_USER`
- `SMTP_PASS`
- `INCLUDE_USB_DRIVES`
- `EMMC_ENABLE_CHECK`
- `EMMC_ENABLE_READTEST`
- `NVME_MAX_WAIT_SHORT_MIN`
- `NVME_MAX_WAIT_LONG_MIN`
- `NVME_STALL_DETECTION`

Empfohlene Standardpfade für Nutzer:

- Skriptpfad: `/volume2/NASAdmin/Skripte/SmartWatch`
- Logpfad: `/volume2/NASAdmin/Logs/SmartWatch`

## Dokumentation

- Handbuch (PDF): `UGREEN_SMARTWatch_Manual_DE-EN_v5.00.pdf`

## Lizenz

MIT License

## Version

- v5.00

<!-- refresh contributors graph -->
