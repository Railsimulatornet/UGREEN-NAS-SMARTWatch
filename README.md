# UGREEN-NAS-SMARTWatch

![SMARTWatch](Screens/SMARTWatch.png)

[Deutsch](#deutsch) | [English](#english)

---

<a id="deutsch"></a>

# Deutsch

UGREEN-NAS-SMARTWatch ist ein leichtgewichtiges Bash-Skript für UGREEN NAS mit UGOS.  
Das Skript liest SMART-Werte von HDD-, NVMe-, USB- und eMMC-Laufwerken aus, kann SMART-Selbsttests starten und versendet einen Outlook-freundlichen HTML-Report per E-Mail.

## Features

- SMART-Überwachung für HDD, NVMe, USB und eMMC
- Wöchentlicher Kurztest und monatlicher Langtest
- Outlook-freundlicher HTML-Report
- Deutsche und englische Ausgabe per `LANGUAGE`
- USB- und Wechsellaufwerke optional einbeziehbar
- NVMe-Stillstandserkennung bei festhängenden Selbsttests
- Cron-tauglich, auch ohne interaktives Shell-Environment
- Für UGREEN NAS mit UGOS optimiert

## Neuerungen in V5.00

- Unterstützung für DXP2800 GT, DXP4800 GT, DXP6800 Ultra und DXP8800 Ultra
- U.2-NVMe-Unterstützung für die GT-Serie
- Physische Unterscheidung von U.2-Schacht 1 und 2 beim DXP4800 GT
- Verbesserte Modellnormalisierung
- Vollständig getrennte deutsche und englische Konsolen-, Protokoll- und E-Mail-Ausgaben
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
- Root-Zugriff für die Ausführung des Skripts
- Python 3 unter `/usr/bin/python3`
- `smartctl` beziehungsweise Smartmontools

## Installation (Quickstart)

1. Paket auf das NAS kopieren, zum Beispiel nach:

   ```text
   /volume2/NASAdmin/Skripte/SmartWatch/
   ```

2. In den Ordner wechseln:

   ```bash
   cd /volume2/NASAdmin/Skripte/SmartWatch
   ```

3. Beispielkonfiguration kopieren:

   ```bash
   cp smart-report.env.example smart-report.env
   ```

4. Konfiguration anpassen:

   ```bash
   nano smart-report.env
   ```

5. Skript ausführbar machen:

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

Auf dem NAS wird daraus die aktive Konfiguration erstellt:

```bash
cp smart-report.env.example smart-report.env
```

Wichtige Optionen:

- `LANGUAGE`
- `NAS_CUSTOM_NAME`
- `NAS_MODEL_OVERRIDE`
- `LOG_DIR`
- `LOG_RETENTION_DAYS`
- `MAIL_FROM`
- `MAIL_TO`
- `SMTP_SERVER`
- `SMTP_PORT`
- `SMTP_USER`
- `SMTP_PASS`
- `SMTP_USE_TLS`
- `SMTP_USE_SSL`
- `INCLUDE_USB_DRIVES`
- `EMMC_ENABLE_CHECK`
- `EMMC_ENABLE_READTEST`
- `NVME_MAX_WAIT_SHORT_MIN`
- `NVME_MAX_WAIT_LONG_MIN`
- `NVME_STALL_DETECTION`
- `ABORT_RUNNING_TESTS_BEFORE_START`

Empfohlene Standardpfade:

- Skriptpfad: `/volume2/NASAdmin/Skripte/SmartWatch`
- Logpfad: `/volume2/NASAdmin/Logs/SmartWatch`

## Dokumentation

- Handbuch (DE/EN): `UGREEN_SMARTWatch_Manual_DE-EN_v5.00.pdf`
- Versionshinweise: `RELEASE_NOTES_v5.00.md`

## Lizenz

MIT License

## Version

- v5.00

---

<a id="english"></a>

# English

UGREEN-NAS-SMARTWatch is a lightweight Bash script for UGREEN NAS systems running UGOS.  
The script reads SMART data from HDD, NVMe, USB and eMMC drives, can start SMART self-tests and sends an Outlook-friendly HTML report by email.

## Features

- SMART monitoring for HDD, NVMe, USB and eMMC drives
- Weekly short test and monthly long test
- Outlook-friendly HTML report
- German and English output via `LANGUAGE`
- Optional inclusion of USB and removable drives
- NVMe stall detection for stuck self-tests
- Cron-ready, even without an interactive shell environment
- Optimized for UGREEN NAS systems running UGOS

## What's new in V5.00

- Added support for DXP2800 GT, DXP4800 GT, DXP6800 Ultra and DXP8800 Ultra
- Added U.2 NVMe support for the GT series
- Added physical distinction between U.2 Bay 1 and Bay 2 on the DXP4800 GT
- Improved model normalization
- Fully separated German and English console, log and email output
- More precise display of supported NVMe drives
- Corrected display of skipped eMMC read tests
- Added progress messages before and after full eMMC read tests

## Screenshots

### German (DE)

| Outlook | Mobile view |
|---|---|
| ![SMARTWatch DE - Outlook](Screens/Outlook.jpg) | ![SMARTWatch DE - Mobile](Screens/Mobil.jpg) |

### English (EN)

| Outlook | Mobile view |
|---|---|
| ![SMARTWatch EN - Outlook](Screens/OutlookEN.jpg) | ![SMARTWatch EN - Mobile](Screens/MobileEN.jpg) |

## Supported UGREEN NAS models

UGREEN-NAS-SMARTWatch is optimized for UGREEN NAS systems running UGOS. The following models are currently explicitly recognized and supported:

### DH series

- DH2300
- DH4300 Plus

### DX and iDX series

- DX4700
- iDX6011
- iDX6011 Pro

### DXP series

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

The GT series additionally supports U.2 NVMe drives. On the DXP4800 GT, U.2 Bay 1 and U.2 Bay 2 can be physically distinguished.

Other UGREEN NAS models running UGOS may also work through the generic drive detection, but they have not yet been explicitly verified. Feedback for additional models is welcome.

## Requirements

- Supported UGREEN NAS running UGOS
- Root access to run the script
- Python 3 at `/usr/bin/python3`
- `smartctl` or Smartmontools

## Installation (Quickstart)

1. Copy the package to the NAS, for example to:

   ```text
   /volume2/NASAdmin/Skripte/SmartWatch/
   ```

2. Change to the directory:

   ```bash
   cd /volume2/NASAdmin/Skripte/SmartWatch
   ```

3. Copy the example configuration:

   ```bash
   cp smart-report.env.example smart-report.env
   ```

4. Edit the configuration:

   ```bash
   nano smart-report.env
   ```

5. Make the script executable:

   ```bash
   chmod +x ugreen-smart-report.sh
   ```

## Testing and usage

### Send a test email

```bash
bash ./ugreen-smart-report.sh --test-mail
```

### Create a report only

```bash
bash ./ugreen-smart-report.sh --report-only
```

### Start the weekly short test

```bash
bash ./ugreen-smart-report.sh --weekly-short
```

### Start the monthly long test

```bash
bash ./ugreen-smart-report.sh --monthly-long
```

### Show help

```bash
bash ./ugreen-smart-report.sh --help
```

## Cron example

When using `crontab -e`, it is recommended to define `SHELL` and `PATH` explicitly:

```bash
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

0 3 * * 1 /usr/bin/flock -n /tmp/smarthealth.lock /bin/bash /volume2/NASAdmin/Skripte/SmartWatch/ugreen-smart-report.sh --weekly-short >/dev/null 2>&1
15 4 1 * * /usr/bin/flock -n /tmp/smarthealth.lock /bin/bash /volume2/NASAdmin/Skripte/SmartWatch/ugreen-smart-report.sh --monthly-long >/dev/null 2>&1
```

## Configuration

All settings are based on the following file:

```text
SmartWatch/smart-report.env.example
```

On the NAS, this file is copied to create the active configuration:

```bash
cp smart-report.env.example smart-report.env
```

Important options:

- `LANGUAGE`
- `NAS_CUSTOM_NAME`
- `NAS_MODEL_OVERRIDE`
- `LOG_DIR`
- `LOG_RETENTION_DAYS`
- `MAIL_FROM`
- `MAIL_TO`
- `SMTP_SERVER`
- `SMTP_PORT`
- `SMTP_USER`
- `SMTP_PASS`
- `SMTP_USE_TLS`
- `SMTP_USE_SSL`
- `INCLUDE_USB_DRIVES`
- `EMMC_ENABLE_CHECK`
- `EMMC_ENABLE_READTEST`
- `NVME_MAX_WAIT_SHORT_MIN`
- `NVME_MAX_WAIT_LONG_MIN`
- `NVME_STALL_DETECTION`
- `ABORT_RUNNING_TESTS_BEFORE_START`

Recommended default paths:

- Script path: `/volume2/NASAdmin/Skripte/SmartWatch`
- Log path: `/volume2/NASAdmin/Logs/SmartWatch`

## Documentation

- Manual (DE/EN): `UGREEN_SMARTWatch_Manual_DE-EN_v5.00.pdf`
- Release notes: `RELEASE_NOTES_v5.00.md`

## License

MIT License

## Version

- v5.00

<!-- refresh contributors graph -->
