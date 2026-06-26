#!/usr/bin/env bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Copyright Roman Glos 2026
# ugreen-smart-report.sh
# Unified SMART report script for UGREEN NAS (DE/EN via env)
# Version 5.00

set -u

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="5.00"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/smart-report.env}"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

LANGUAGE="${LANGUAGE:-de}"
PYTHON_BIN="/usr/bin/python3"

NAS_CUSTOM_NAME="${NAS_CUSTOM_NAME:-}"
NAS_MODEL_OVERRIDE="${NAS_MODEL_OVERRIDE:-}"
LOG_DIR="${LOG_DIR:-/volume2/docker/smart-logs}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/ugreen-smart-report_$(date '+%Y-%m').log}"
SHUTDOWN_AFTER_LONG="${SHUTDOWN_AFTER_LONG:-false}"
EMMC_ENABLE_CHECK="${EMMC_ENABLE_CHECK:-true}"
EMMC_ENABLE_READTEST="${EMMC_ENABLE_READTEST:-true}"
NVME_MAX_WAIT_SHORT_MIN="${NVME_MAX_WAIT_SHORT_MIN:-${NVME_ONLY_WAIT_SHORT_MIN:-15}}"
NVME_MAX_WAIT_LONG_MIN="${NVME_MAX_WAIT_LONG_MIN:-${NVME_ONLY_WAIT_LONG_MIN:-240}}"
NVME_STALL_DETECTION="${NVME_STALL_DETECTION:-true}"
NVME_STALL_MIN_ELAPSED_SHORT_MIN="${NVME_STALL_MIN_ELAPSED_SHORT_MIN:-3}"
NVME_STALL_MIN_ELAPSED_LONG_MIN="${NVME_STALL_MIN_ELAPSED_LONG_MIN:-30}"
NVME_STALL_POLLS_SHORT="${NVME_STALL_POLLS_SHORT:-3}"
NVME_STALL_POLLS_LONG="${NVME_STALL_POLLS_LONG:-3}"
SMTP_SERVER="${SMTP_SERVER:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"
MAIL_FROM="${MAIL_FROM:-}"
MAIL_TO="${MAIL_TO:-}"
SMTP_USE_TLS="${SMTP_USE_TLS:-true}"
SMTP_USE_SSL="${SMTP_USE_SSL:-false}"
INCLUDE_USB_DRIVES="${INCLUDE_USB_DRIVES:-false}"
DEBUG_SMTP="${DEBUG_SMTP:-false}"
DEBUG_REPORT_MAIL="${DEBUG_REPORT_MAIL:-false}"
DEBUG_SAVE_REPORT_HTML="${DEBUG_SAVE_REPORT_HTML:-false}"
DEBUG_REPORT_DUMP_DIR="${DEBUG_REPORT_DUMP_DIR:-/tmp}"
ABORT_RUNNING_TESTS_BEFORE_START="${ABORT_RUNNING_TESTS_BEFORE_START:-${BORT_RUNNING_TESTS_BEFORE_START:-false}}"

lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }
is_true() { case "$(lower "${1:-}")" in true|1|yes|ja|on) return 0 ;; *) return 1 ;; esac; }
is_false() { case "$(lower "${1:-}")" in false|0|no|nein|off|"") return 0 ;; *) return 1 ;; esac; }
is_en() { [[ "$(lower "$LANGUAGE")" == en* ]]; }
tr_text() { local de="$1"; local en="$2"; if is_en; then printf '%s' "$en"; else printf '%s' "$de"; fi; }
normalize_bool() { if is_true "${1:-false}"; then printf '%s' 'true'; else printf '%s' 'false'; fi; }

DEBUG_SMTP="$(normalize_bool "$DEBUG_SMTP")"
DEBUG_REPORT_MAIL="$(normalize_bool "$DEBUG_REPORT_MAIL")"
DEBUG_SAVE_REPORT_HTML="$(normalize_bool "$DEBUG_SAVE_REPORT_HTML")"
SMTP_USE_TLS="$(normalize_bool "$SMTP_USE_TLS")"
SMTP_USE_SSL="$(normalize_bool "$SMTP_USE_SSL")"
INCLUDE_USB_DRIVES="$(normalize_bool "$INCLUDE_USB_DRIVES")"
SHUTDOWN_AFTER_LONG="$(normalize_bool "$SHUTDOWN_AFTER_LONG")"
EMMC_ENABLE_CHECK="$(normalize_bool "$EMMC_ENABLE_CHECK")"
EMMC_ENABLE_READTEST="$(normalize_bool "$EMMC_ENABLE_READTEST")"
ABORT_RUNNING_TESTS_BEFORE_START="$(normalize_bool "$ABORT_RUNNING_TESTS_BEFORE_START")"
NVME_STALL_DETECTION="$(normalize_bool "$NVME_STALL_DETECTION")"

log() {
  local ts fmt
  if is_en; then fmt='+%Y-%m-%d %H:%M:%S'; else fmt='+%d.%m.%Y %H:%M:%S'; fi
  ts="$(date "$fmt")"
  printf '[%s] %s\n' "$ts" "$*" | tee -a "$LOG_FILE"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "$(tr_text 'Dieses Skript muss als root ausgeführt werden.' 'This script must be run as root.')"
    exit 1
  fi
}

detect_python() {
  if [ ! -x "$PYTHON_BIN" ]; then
    echo "$(tr_text 'Python3 nicht gefunden: /usr/bin/python3' 'Python3 not found: /usr/bin/python3')"
    exit 1
  fi
}

setup_logging() {
  mkdir -p "$LOG_DIR"
  find "$LOG_DIR" -name 'ugreen-smart-report_*.log' -type f     -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
  touch "$LOG_FILE"
}

show_help() {
  if is_en; then
    cat <<EOF
UGREEN SMART Report v${SCRIPT_VERSION}

Usage:
  ${SCRIPT_NAME} --help
  ${SCRIPT_NAME} -h
  ${SCRIPT_NAME} --
  ${SCRIPT_NAME} --report-only
  ${SCRIPT_NAME} --weekly-short
  ${SCRIPT_NAME} --monthly-long
  ${SCRIPT_NAME} --test-mail

Description:
  Creates SMART reports for HDD and NVMe drives, can start SMART tests,
  and can send HTML reports by email.

Options:
  --help, -h, --   Show this help
  --report-only    Create report only, do not start new SMART tests
  --weekly-short   Start weekly SMART short test, then send report
  --monthly-long   Start monthly SMART long test, then send report
  --test-mail      Send test email only

Notes:
  - Without parameters, the script behaves like --monthly-long
  - Output language depends on LANGUAGE, e.g. de or en
  - DEBUG_SMTP controls only SMTP send/reply output
  - DEBUG_REPORT_MAIL controls only DEBUG_REPORT output
  - DEBUG_SAVE_REPORT_HTML saves the generated HTML report locally
  - Weekly and monthly test runs abort if another SMART test is already running
  - ABORT_RUNNING_TESTS_BEFORE_START=true aborts running SMART tests before a new test run
  - NVME_MAX_WAIT_SHORT_MIN and NVME_MAX_WAIT_LONG_MIN define the maximum wait for running NVMe self-tests
  - Legacy variables NVME_ONLY_WAIT_SHORT_MIN and NVME_ONLY_WAIT_LONG_MIN are still accepted as fallback
  - NVME_STALL_DETECTION can abort NVMe self-tests earlier if progress is stuck
EOF
  else
    cat <<EOF
UGREEN SMART Report v${SCRIPT_VERSION}

Verwendung:
  ${SCRIPT_NAME} --help
  ${SCRIPT_NAME} -h
  ${SCRIPT_NAME} --
  ${SCRIPT_NAME} --report-only
  ${SCRIPT_NAME} --weekly-short
  ${SCRIPT_NAME} --monthly-long
  ${SCRIPT_NAME} --test-mail

Beschreibung:
  Erstellt SMART-Berichte für HDD- und NVMe-Laufwerke, kann SMART-Tests
  starten und HTML-Berichte per E-Mail versenden.

Optionen:
  --help, -h, --   Diese Hilfe anzeigen
  --report-only    Nur Bericht erzeugen, keine neuen SMART-Tests starten
  --weekly-short   Wöchentlichen SMART-Kurztest starten, dann Bericht senden
  --monthly-long   Monatlichen SMART-Langtest starten, dann Bericht senden
  --test-mail      Nur Test-E-Mail senden

Hinweise:
  - Ohne Parameter verhält sich das Skript wie --monthly-long
  - Die Ausgabesprache richtet sich nach LANGUAGE, z. B. de oder en
  - DEBUG_SMTP steuert nur SMTP send/reply-Ausgaben
  - DEBUG_REPORT_MAIL steuert nur DEBUG_REPORT-Ausgaben
  - DEBUG_SAVE_REPORT_HTML speichert den erzeugten HTML-Bericht lokal
  - Wöchentliche und monatliche Testläufe brechen ab, wenn bereits ein anderer SMART-Test läuft
  - ABORT_RUNNING_TESTS_BEFORE_START=true bricht laufende SMART-Tests vor einem neuen Testlauf ab
  - NVME_MAX_WAIT_SHORT_MIN und NVME_MAX_WAIT_LONG_MIN definieren die maximale Wartezeit für laufende NVMe-Selbsttests
  - Die alten Variablen NVME_ONLY_WAIT_SHORT_MIN und NVME_ONLY_WAIT_LONG_MIN werden weiterhin als Fallback akzeptiert
  - NVME_STALL_DETECTION kann NVMe-Selbsttests früher abbrechen, wenn der Fortschritt hängen bleibt
EOF
  fi
}

get_raw_model_string() {
  # Try to find the most informative model string available.
  # Sources: DMI (x86), Device-Tree (ARM), Kernel log (dmesg).
  local cand="" pn="" pv="" bn="" dt="" dm=""

  # DMI (x86)
  if [ -r /sys/class/dmi/id/product_name ]; then
    pn="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    pv="$(cat /sys/class/dmi/id/product_version 2>/dev/null || true)"
    bn="$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)"
    cand="$pn $pv $bn"
  fi

  # Device-Tree (ARM)
  if [ -z "$cand" ] && [ -r /proc/device-tree/model ]; then
    dt="$(tr -d '\000' < /proc/device-tree/model 2>/dev/null || true)"
    cand="$dt"
  fi

  # Kernel (fallback / generic "UGREEN")
  if [ -z "$cand" ] || ! echo "$cand" | grep -qiE '(DH|DXP|DX)[0-9]{3,4}'; then
    dm="$(dmesg 2>/dev/null | grep -m1 -E 'Hardware name:|Machine model:' | sed -E 's/.*(Hardware name:|Machine model:)[[:space:]]*//')"
    if [ -n "$dm" ]; then
      cand="$dm"
    fi
  fi

  cand="$(echo "$cand" | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  echo "$cand"
}


# Global arrays (will be populated)
HDD_DRIVES=()
INTERNAL_HDD_DRIVES=()
USB_HDD_DRIVES=()
USB_TESTABLE_DRIVES=()
USB_EXCLUDED_DRIVES=()
NVME_DRIVES=()
STARTED_HDD_DRIVES=()
STARTED_NVME_DRIVES=()
ABORTED_NVME_DRIVES=()
ABORT_FAILED_NVME_DRIVES=()
NVME_ABORT_ATTEMPTED_DRIVES=()
NVME_STALL_ABORT_ATTEMPTED_DRIVES=()

declare -A NVME_LAST_COMPLETION=()
declare -A NVME_SAME_COMPLETION_POLLS=()

array_contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

DRIVE_LABEL_CACHE_FILE="/tmp/ugreen-smart-report_drive_labels_${$}.txt"

build_drive_label_cache() {
  local raw_model
  raw_model="$(get_raw_model_string)"

  "$PYTHON_BIN" -u - "$raw_model" "$NAS_MODEL_OVERRIDE" "${INTERNAL_HDD_DRIVES[@]}" "${USB_HDD_DRIVES[@]}" "${USB_EXCLUDED_DRIVES[@]}" -- "${NVME_DRIVES[@]}" <<'PYEOF' > "$DRIVE_LABEL_CACHE_FILE" 2>/dev/null || true
import json, os, re, subprocess, sys

IS_EN = str(os.environ.get("LANGUAGE", "de")).lower().startswith("en")

raw_model = sys.argv[1] if len(sys.argv) > 1 else ""
model_override = sys.argv[2] if len(sys.argv) > 2 else ""
args = sys.argv[3:]

if "--" in args:
    sep = args.index("--")
    hdd_devices = args[:sep]
    nvme_devices = args[sep + 1:]
else:
    hdd_devices = [d for d in args if re.match(r"^/dev/sd", d or "")]
    nvme_devices = [d for d in args if re.match(r"^/dev/nvme\d+$", d or "")]

all_devices = hdd_devices + nvme_devices


def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
        return (p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip())
    except Exception:
        return (999, "", "")


def first_line(s: str) -> str:
    lines = (s or "").splitlines()
    return lines[0] if lines else ""


def normalize_model(raw: str) -> str:
    r = (raw or "").upper()
    r = r.replace("UGREEN", " ").replace("DEFAULT STRING", " ").replace("/", " ")
    r = re.sub(r"\s+", " ", r).strip()
    if model_override.strip():
        return model_override.strip().upper()
    tokens = r.replace(" ", "")
    for k in ("DXP480TPLUS","DX4700","IDX6011PRO","IDX6011","DH4300PLUS","DH2300","DXP2800GT","DXP2800","DXP4800GT","DXP4800PRO","DXP4800PLUS","DXP4800","DXP6800ULTRA","DXP6800PRO","DXP6800PLUS","DXP8800ULTRA","DXP8800PRO","DXP8800PLUS"):
        if k in tokens:
            return k
    m = re.search(r"(IDX[0-9]{4}PRO|IDX[0-9]{4}|DH[0-9]{4}PLUS|DH[0-9]{4}|DXP[0-9]{4}ULTRA|DXP[0-9]{4}GT|DXP[0-9]{4}T?PLUS|DXP[0-9]{4}PRO|DXP[0-9]{4}|DX[0-9]{4})", tokens)
    return m.group(1) if m else "UGREEN"

MODEL = normalize_model(raw_model)


def parse_lsblk_pairs(line: str):
    return {m.group(1): m.group(2) for m in re.finditer(r'(\w+)="([^"]*)"', line or "")}


def list_sd_disk_records():

    rc, out, _ = run(["lsblk", "-dn", "-P", "-o", "NAME,TYPE,TRAN,HOTPLUG,RM,ROTA,SIZE,VENDOR,MODEL,SERIAL"], timeout=5)
    records = []
    for line in out.splitlines():
        rec = parse_lsblk_pairs(line)
        name = rec.get("NAME", "")
        typ = rec.get("TYPE", "")
        tran = (rec.get("TRAN", "") or "").lower()
        if typ != "disk" or not name.startswith("sd"):
            continue
        records.append({
            "path": "/dev/" + name,
            "name": name,
            "tran": tran,
            "hotplug": int(rec.get("HOTPLUG") or 0),
            "rm": int(rec.get("RM") or 0),
            "rota": int(rec.get("ROTA") or 0),
            "vendor": (rec.get("VENDOR") or "").strip(),
            "model": (rec.get("MODEL") or "").strip(),
            "serial": (rec.get("SERIAL") or "").strip(),
            "is_usb": tran == "usb",
        })
    return records


def get_udev_props(dev: str):
    rc, out, _ = run(["udevadm", "info", "--query=property", "--name", dev], timeout=8)
    props = {}
    for ln in out.splitlines():
        if "=" in ln:
            k, v = ln.split("=", 1)
            props[k] = v
    return props


def classify_usb_record(rec):
    props = get_udev_props(rec["path"])
    combo = " ".join([rec.get("vendor", ""), rec.get("model", ""), props.get("ID_VENDOR", ""), props.get("ID_MODEL", "")]).lower()
    if props.get("ID_DRIVE_FLASH_SD") == "1" or props.get("ID_DRIVE_MEDIA_FLASH_SD") == "1":
        return "sdcard"
    if "genesys" in combo and "massstorageclass" in combo:
        return "sdcard"
    if "sd card reader" in combo or "card reader" in combo:
        return "sdcard"
    if props.get("ID_ATA") == "1":
        return "usb_ssd" if int(rec.get("rota", 1) or 1) == 0 else "usb_hdd"
    if int(rec.get("rm", 0) or 0) == 1 and int(rec.get("hotplug", 0) or 0) == 1:
        return "usb_stick"
    return "usb_unknown"


def usb_kind_text(kind: str, is_en: bool = False) -> str:
    if is_en:
        return {
            "sdcard": "SD card/card reader",
            "usb_stick": "USB flash drive",
            "usb_hdd": "External USB HDD",
            "usb_ssd": "External USB SSD",
            "usb_unknown": "USB/removable drive",
        }.get(kind, "USB/removable drive")
    return {
        "sdcard": "SD-Karte/Kartenleser",
        "usb_stick": "USB-Stick",
        "usb_hdd": "Externe USB-HDD",
        "usb_ssd": "Externe USB-SSD",
        "usb_unknown": "USB-/Wechsellaufwerk",
    }.get(kind, "USB-/Wechsellaufwerk")


def list_nvme_ctrl():
    ctrl = []
    rc, out, _ = run(["bash", "-lc", "ls -1 /dev/disk/by-path/*nvme-* 2>/dev/null | grep -v part | sort"], timeout=5)
    if out.strip():
        for path in out.splitlines():
            rc2, real, _ = run(["readlink", "-f", path], timeout=5)
            base = os.path.basename((real or "").strip())
            m = re.match(r"^(nvme\d+)n\d+$", base)
            if m:
                ctrl_dev = "/dev/" + m.group(1)
                if os.path.exists(ctrl_dev) and ctrl_dev not in ctrl:
                    ctrl.append(ctrl_dev)
    if ctrl:
        return ctrl
    rc, out, _ = run(["bash", "-lc", "ls -1 /dev/nvme[0-9]* 2>/dev/null | grep -E '^/dev/nvme[0-9]+$' | sort -V"], timeout=5)
    return [line.strip() for line in out.splitlines() if line.strip()]


def findmnt_src(mountpoint: str) -> str:
    rc, out, _ = run(["findmnt", "-n", "-o", "SOURCE", mountpoint], timeout=5)
    return first_line(out)


def pkname(dev: str) -> str:
    rc, out, _ = run(["lsblk", "-no", "PKNAME", dev], timeout=5)
    return first_line(out)


def system_disk_base():
    for mp in ("/rom", "/", "/overlay"):
        src = findmnt_src(mp)
        if src.startswith("/dev/"):
            pk = pkname(src)
            if pk:
                return "/dev/" + pk
            return src
    return ""


sd_records = list_sd_disk_records()
selected_set = set(all_devices)
internal_hdd_devices = [r["path"] for r in sd_records if not r.get("is_usb") and r["path"] in selected_set]
usb_records = [r for r in sd_records if r.get("is_usb") and r["path"] in selected_set]
for rec in usb_records:
    rec["usb_kind"] = classify_usb_record(rec)
usb_label_map = {rec["path"]: f"USB{idx}" for idx, rec in enumerate(usb_records, start=1)}

lsblk_scsi = {}
host_to_dev = {}
bay_mapping = {}
try:
    rc, out, _ = run(["lsblk", "-S", "-x", "hctl", "-o", "NAME,HCTL,TRAN,MODEL,SERIAL", "-J"], timeout=5)
    if out:
        data = json.loads(out)
        for dev in data.get("blockdevices", []):
            name = dev.get("name")
            if not name:
                continue
            lsblk_scsi["/dev/" + name] = {
                "hctl": dev.get("hctl") or "",
                "tran": (dev.get("tran") or "").strip(),
                "model": (dev.get("model") or "").strip(),
                "serial": (dev.get("serial") or "").strip(),
            }
    hosts = set()
    for path, info in lsblk_scsi.items():
        if path not in set(internal_hdd_devices):
            continue
        hctl = info.get("hctl") or ""
        host_str = hctl.split(":")[0] if ":" in hctl else ""
        if host_str.isdigit():
            host = int(host_str)
            host_to_dev[host] = path
            hosts.add(host)
    bay_count = (max(hosts) + 1) if hosts else len(internal_hdd_devices)
    for host in range(bay_count):
        dev = host_to_dev.get(host)
        if dev:
            bay_mapping[dev] = host + 1
except Exception:
    bay_mapping = {}

sys_base = system_disk_base()
sys_nvme_ctrl = ""
if isinstance(sys_base, str) and sys_base.startswith("/dev/nvme"):
    base_name = os.path.basename(sys_base)
    m = re.match(r"^(nvme\d+)n\d+(?:p\d+)?$", base_name)
    if m:
        sys_nvme_ctrl = "/dev/" + m.group(1)

all_nvme = list_nvme_ctrl()
ordered_nvme = [d for d in nvme_devices if d in all_nvme]
for d in all_nvme:
    if d in nvme_devices and d not in ordered_nvme:
        ordered_nvme.append(d)
user_nvme_devices = [d for d in ordered_nvme if d != sys_nvme_ctrl]
report_nvme_devices = list(user_nvme_devices)
if sys_nvme_ctrl and sys_nvme_ctrl in ordered_nvme:
    report_nvme_devices.append(sys_nvme_ctrl)
system_nvme_slot = 3 if (MODEL.startswith("DXP") or MODEL.startswith("IDX")) and sys_nvme_ctrl else (len(user_nvme_devices) + 1 if sys_nvme_ctrl else 0)

def nvme_by_path_name(dev: str) -> str:
    """Return the stable /dev/disk/by-path name for an NVMe controller."""
    m = re.match(r"^/dev/(nvme\d+)$", dev or "")
    if not m:
        return ""
    disk_node = f"/dev/{m.group(1)}n1"
    rc, out, _ = run(
        ["bash", "-lc", "ls -1 /dev/disk/by-path/*nvme-* 2>/dev/null | grep -v part | sort"],
        timeout=5,
    )
    for path in out.splitlines():
        rc2, real, _ = run(["readlink", "-f", path], timeout=5)
        if (real or "").strip() == disk_node:
            return os.path.basename(path.strip())
    return ""


def nvme_user_label(dev: str, generic_index: int) -> str:
    """Use verified physical U.2 labels on DXP4800 GT; otherwise a safe logical label."""
    path_name = nvme_by_path_name(dev)
    if MODEL == "DXP4800GT":
        if "pci-0000:01:00.0-nvme-1" in path_name:
            return "U.2 Bay 1" if IS_EN else "U.2-Schacht 1"
        if "pci-0000:02:00.0-nvme-1" in path_name:
            return "U.2 Bay 2" if IS_EN else "U.2-Schacht 2"
        return f"M.2 NVMe {generic_index}" if IS_EN else f"M.2-NVMe {generic_index}"
    return f"NVME{generic_index}"

nvme_label_map = {}
user_slot_idx = 1
for dev in report_nvme_devices:
    if sys_nvme_ctrl and dev == sys_nvme_ctrl:
        nvme_label_map[dev] = f"NVME{system_nvme_slot} {'System drive' if IS_EN else 'Systemlaufwerk'}" if system_nvme_slot else ({'System drive' if IS_EN else 'Systemlaufwerk'})
    else:
        nvme_label_map[dev] = nvme_user_label(dev, user_slot_idx)
        user_slot_idx += 1

nvme_info = {}
rc, out, _ = run(["lsblk", "-d", "-J", "-o", "NAME,MODEL,SERIAL"], timeout=5)
if out:
    try:
        data = json.loads(out)
        for dev in data.get("blockdevices", []):
            name = dev.get("name") or ""
            if re.match(r"^nvme\d+n\d+$", name):
                nvme_info["/dev/" + name] = {"model": (dev.get("model") or "").strip(), "serial": (dev.get("serial") or "").strip()}
    except Exception:
        pass


def _nvme_disk_node(dev: str) -> str:
    m = re.match(r"^/dev/(nvme\d+)$", dev or "")
    return f"/dev/{m.group(1)}n1" if m else dev


def drive_label(dev: str) -> str:
    if re.match(r"^/dev/nvme\d+$", dev or ""):
        parts = [nvme_label_map.get(dev, os.path.basename(dev))]
        info = nvme_info.get(_nvme_disk_node(dev), {})
        if info.get("model"):
            parts.append(info["model"])
        if info.get("serial"):
            parts.append(info["serial"])
        return " / ".join([p for p in parts if p])
    rec = next((r for r in sd_records if r["path"] == dev), None)
    parts = []
    if dev in bay_mapping:
        parts.append(f"{'Bay' if IS_EN else 'Schacht'} {bay_mapping[dev]}")
        info = lsblk_scsi.get(dev, {})
        if info.get("model"):
            parts.append(info["model"])
        if info.get("serial"):
            parts.append(info["serial"])
        return " / ".join([p for p in parts if p])
    if rec and rec.get("is_usb"):
        parts.append(usb_label_map.get(dev, os.path.basename(dev)))
        parts.append(usb_kind_text(rec.get("usb_kind") or "usb_unknown", IS_EN))
        if rec.get("model"):
            parts.append(rec["model"])
        if rec.get("serial"):
            parts.append(rec["serial"])
        return " / ".join([p for p in parts if p])
    return dev

for dev in all_devices:
    print(f"{dev}\t{drive_label(dev)}")
PYEOF
}

get_cached_device_label() {
  local dev="$1" line
  [ -n "$dev" ] || return 0
  if [ -f "$DRIVE_LABEL_CACHE_FILE" ]; then
    line="$(awk -F $'\t' -v d="$dev" '$1 == d {print $2; exit}' "$DRIVE_LABEL_CACHE_FILE" 2>/dev/null || true)"
    if [ -n "$line" ]; then
      printf '%s' "$line"
      return 0
    fi
  fi
  printf '%s' "$dev"
}

format_device_list() {
  local sep="" out="" dev label
  for dev in "$@"; do
    [ -n "$dev" ] || continue
    label="$(get_cached_device_label "$dev")"
    out+="${sep}${label}"
    sep=" ; "
  done
  if [ -n "$out" ]; then
    printf '%s' "$out"
  else
    printf '%s' "$(tr_text 'keine' 'none')"
  fi
}

cleanup_drive_label_cache() {
  rm -f "$DRIVE_LABEL_CACHE_FILE" 2>/dev/null || true
}

trap cleanup_drive_label_cache EXIT

usb_drive_kind() {
  local dev="$1"
  local props vendor model rm hotplug rota combo

  props="$(udevadm info --query=property --name="$dev" 2>/dev/null || true)"
  vendor="$(lsblk -dn -o VENDOR "$dev" 2>/dev/null | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  model="$(lsblk -dn -o MODEL "$dev" 2>/dev/null | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  rm="$(lsblk -dn -o RM "$dev" 2>/dev/null | awk 'NR==1{print $1}')"
  hotplug="$(lsblk -dn -o HOTPLUG "$dev" 2>/dev/null | awk 'NR==1{print $1}')"
  rota="$(lsblk -dn -o ROTA "$dev" 2>/dev/null | awk 'NR==1{print $1}')"
  combo="$(printf '%s %s
%s' "$vendor" "$model" "$props" | tr '[:upper:]' '[:lower:]')"

  if printf '%s
' "$props" | grep -qE '^ID_DRIVE_FLASH_SD=1$|^ID_DRIVE_MEDIA_FLASH_SD=1$'; then
    printf '%s
' 'sdcard'
    return 0
  fi

  if printf '%s
' "$combo" | grep -qiE 'genesys.*massstorageclass|sd[[:space:]-]*card[[:space:]-]*reader|card[[:space:]-]*reader'; then
    printf '%s
' 'sdcard'
    return 0
  fi

  if printf '%s
' "$props" | grep -q '^ID_ATA=1$'; then
    if [ "${rota:-1}" = "0" ]; then
      printf '%s
' 'usb_ssd'
    else
      printf '%s
' 'usb_hdd'
    fi
    return 0
  fi

  if [ "${rm:-0}" = "1" ] && [ "${hotplug:-0}" = "1" ]; then
    printf '%s
' 'usb_stick'
    return 0
  fi

  printf '%s
' 'usb_unknown'
}

detect_hdd_drives() {
  local dev tran kind
  HDD_DRIVES=()
  INTERNAL_HDD_DRIVES=()
  USB_HDD_DRIVES=()
  USB_TESTABLE_DRIVES=()
  USB_EXCLUDED_DRIVES=()

  while read -r name typ tran; do
    [ "$typ" = "disk" ] || continue
    case "$name" in
      sd*)
        dev="/dev/$name"
        tran="$(printf '%s' "${tran:-}" | tr '[:upper:]' '[:lower:]')"
        if [ "$tran" = "usb" ]; then
          if ! is_true "$INCLUDE_USB_DRIVES"; then
            continue
          fi
          USB_HDD_DRIVES+=("$dev")
          kind="$(usb_drive_kind "$dev")"
          case "$kind" in
            usb_stick|sdcard)
              USB_EXCLUDED_DRIVES+=("$dev")
              ;;
            *)
              USB_TESTABLE_DRIVES+=("$dev")
              HDD_DRIVES+=("$dev")
              ;;
          esac
        else
          INTERNAL_HDD_DRIVES+=("$dev")
          HDD_DRIVES+=("$dev")
        fi
        ;;
      *) : ;;
    esac
  done < <(lsblk -dn -o NAME,TYPE,TRAN 2>/dev/null || true)
}


detect_nvme_drives() {
  NVME_DRIVES=()

  # preferred: by-path for stable slot order
  if [ -d /dev/disk/by-path ]; then
    mapfile -t _paths < <(ls -1 /dev/disk/by-path/*nvme-* 2>/dev/null | grep -v 'part' | sort || true)
    if [ "${#_paths[@]}" -gt 0 ]; then
      for p in "${_paths[@]}"; do
        real="$(readlink -f "$p" 2>/dev/null || true)"   # e.g. /dev/nvme0n1
        base="$(basename "$real")"
        # base: nvme0n1  -> controller: /dev/nvme0
        ctrl="/dev/$(echo "$base" | sed -E 's/^(nvme[0-9]+)n[0-9]+$/\\1/')"
        if [ -e "$ctrl" ]; then
          # dedupe
          if [[ " ${NVME_DRIVES[*]} " != *" $ctrl "* ]]; then
            NVME_DRIVES+=("$ctrl")
          fi
        fi
      done
    fi
  fi

  # Fallback: /dev/nvmeX
  if [ "${#NVME_DRIVES[@]}" -eq 0 ]; then
    for ctrl in /dev/nvme[0-9]*; do
      [[ "$ctrl" =~ ^/dev/nvme[0-9]+$ ]] || continue
      [ -e "$ctrl" ] || continue
      NVME_DRIVES+=("$ctrl")
    done
    # sortiert
    IFS=$'\n' NVME_DRIVES=($(printf '%s\n' "${NVME_DRIVES[@]}" | sort -V))
    unset IFS
  fi
}

detect_all_drives() {
  detect_hdd_drives
  detect_nvme_drives
}

have_nvme_cli() {
  command -v nvme >/dev/null 2>&1
}

nvme_test_code() {
  case "$1" in
    short) printf '%s' '1' ;;
    long) printf '%s' '2' ;;
    abort) printf '%s' '0xf' ;;
    *) return 1 ;;
  esac
}

start_nvme_test() {
  local dev="$1" type="$2" code rc
  if have_nvme_cli; then
    code="$(nvme_test_code "$type" 2>/dev/null || true)"
    if [ -n "$code" ]; then
      nvme device-self-test "$dev" -s "$code" >/dev/null 2>&1
      rc=$?
      if [ "$rc" -eq 0 ]; then
        return 0
      fi
    fi
  fi
  smartctl -t "$type" -d nvme "$dev" >/dev/null 2>&1
}

abort_nvme_test() {
  local dev="$1"
  if have_nvme_cli; then
    nvme device-self-test "$dev" -s 0xf >/dev/null 2>&1 && return 0
  fi
  smartctl -X -d nvme "$dev" >/dev/null 2>&1
}

get_nvme_current_operation() {
  local dev="$1" out line raw val
  if ! have_nvme_cli; then
    return 1
  fi
  out="$(nvme self-test-log "$dev" 2>/dev/null || true)"
  line="$(printf '%s
' "$out" | grep -i 'Current operation' | head -n 1 || true)"
  [ -n "$line" ] || return 1
  raw="$(printf '%s' "$line" | awk -F: '{print $2}' | tr -d '[:space:]')"
  case "$raw" in
    0x*|0X*)
      val=$((16#${raw#0x}))
      ;;
    [0-9]*)
      val="$raw"
      ;;
    *)
      return 1
      ;;
  esac
  printf '%s' "$val"
}

get_nvme_current_completion() {
  local dev="$1" out line val rem

  if have_nvme_cli; then
    out="$(nvme self-test-log "$dev" 2>/dev/null || true)"
    line="$(printf '%s\n' "$out" | grep -i 'Current Completion' | head -n 1 || true)"
    val="$(printf '%s' "$line" | sed -nE 's/.*:[[:space:]]*([0-9]+)%.*/\1/p')"
    if [ -n "$val" ]; then
      printf '%s' "$val"
      return 0
    fi
  fi

  out="$(smartctl -a -d nvme "$dev" 2>/dev/null || true)"
  line="$(printf '%s\n' "$out" | grep -i 'Self-test status' | head -n 1 || true)"
  rem="$(printf '%s' "$line" | sed -nE 's/.* ([0-9]+)% remaining.*/\1/p')"
  if [ -n "$rem" ]; then
    printf '%s' "$((100 - rem))"
    return 0
  fi

  return 1
}

get_nvme_stall_min_elapsed() {
  local type="$1"
  if [ "$type" = "short" ]; then
    printf '%s' "$NVME_STALL_MIN_ELAPSED_SHORT_MIN"
  else
    printf '%s' "$NVME_STALL_MIN_ELAPSED_LONG_MIN"
  fi
}

get_nvme_stall_polls() {
  local type="$1"
  if [ "$type" = "short" ]; then
    printf '%s' "$NVME_STALL_POLLS_SHORT"
  else
    printf '%s' "$NVME_STALL_POLLS_LONG"
  fi
}

attempt_abort_stalled_nvme_tests() {
  local type="$1"
  local elapsed="$2"
  local min_elapsed stall_polls
  local dev completion last count

  is_true "$NVME_STALL_DETECTION" || return 0
  [ "${#STARTED_NVME_DRIVES[@]}" -gt 0 ] || return 0

  min_elapsed="$(get_nvme_stall_min_elapsed "$type")"
  stall_polls="$(get_nvme_stall_polls "$type")"

  [ "$elapsed" -ge "$min_elapsed" ] 2>/dev/null || return 0

  for dev in "${STARTED_NVME_DRIVES[@]}"; do
    [ -n "$dev" ] || continue
    array_contains "$dev" "${NVME_STALL_ABORT_ATTEMPTED_DRIVES[@]}" && continue
    if ! is_nvme_test_running "$dev"; then
      continue
    fi

    completion="$(get_nvme_current_completion "$dev" 2>/dev/null || true)"
    [ -n "$completion" ] || continue

    last="${NVME_LAST_COMPLETION[$dev]-}"
    count="${NVME_SAME_COMPLETION_POLLS[$dev]-0}"

    if [ -z "$last" ] || [ "$completion" != "$last" ]; then
      NVME_LAST_COMPLETION["$dev"]="$completion"
      NVME_SAME_COMPLETION_POLLS["$dev"]=1
      continue
    fi

    count=$((count + 1))
    NVME_SAME_COMPLETION_POLLS["$dev"]="$count"

    if [ "$count" -lt "$stall_polls" ]; then
      continue
    fi

    NVME_STALL_ABORT_ATTEMPTED_DRIVES+=("$dev")
    log "$(tr_text "NVMe-Fortschritt hängt auf $(get_cached_device_label "$dev") bei ${completion}% seit ${count} Polls. Abort des NVMe-Selbsttests wird versucht ..." "NVMe progress is stuck on $(get_cached_device_label "$dev") at ${completion}% for ${count} polls. Attempting to abort the NVMe self-test ...")"

    abort_nvme_test "$dev" || true
    sleep 2

    if is_nvme_test_running "$dev"; then
      ABORT_FAILED_NVME_DRIVES+=("$dev")
      log "$(tr_text "WARN: NVMe-Selbsttest auf $(get_cached_device_label "$dev") läuft trotz Stillstands-Abort weiter." "WARN: NVMe self-test on $(get_cached_device_label "$dev") is still running after the stall abort attempt.")"
    else
      ABORTED_NVME_DRIVES+=("$dev")
      log "$(tr_text "NVMe-Selbsttest auf $(get_cached_device_label "$dev") wurde wegen festhängendem Fortschritt beendet." "NVMe self-test on $(get_cached_device_label "$dev") was stopped due to stalled progress.")"
    fi
  done
}

########################################
# SMART-Tests start & dynamic Waiting
########################################

get_ata_poll_minutes() {
  local type="$1"  # short | long
  local label max_minutes dev out line minutes

  if [ "$type" = "short" ]; then
    label="Short self-test routine recommended polling time"
  else
    label="Extended self-test routine recommended polling time"
  fi

  max_minutes=0

  for dev in "${HDD_DRIVES[@]}"; do
    [ -n "$dev" ] || continue
    out="$(smartctl -c "$dev" 2>/dev/null || true)"
    line="$(printf '%s\n' "$out" | grep -F "$label" | head -n 1 || true)"
    if [ -n "$line" ]; then
      minutes="$(echo "$line" | grep -oE '([0-9]+)[[:space:]]*minutes' | grep -oE '^[0-9]+' | head -n 1)"
      if [ -z "$minutes" ]; then
        minutes="$(echo "$line" | grep -oE '\([[:space:]]*[0-9]+' | tr -cd '0-9' | head -n 1)"
      fi
      if [ -n "$minutes" ] && [ "$minutes" -gt "$max_minutes" ]; then
        max_minutes="$minutes"
      fi
    fi
  done

  if [ "$max_minutes" -eq 0 ]; then
    if [ "$type" = "short" ]; then
      max_minutes=10
    else
      max_minutes=600
    fi
  fi

  echo "$max_minutes"
}

start_smart_tests() {
  local type="$1"
  STARTED_HDD_DRIVES=()
  STARTED_NVME_DRIVES=()
  ABORTED_NVME_DRIVES=()
  ABORT_FAILED_NVME_DRIVES=()
  NVME_ABORT_ATTEMPTED_DRIVES=()
  NVME_STALL_ABORT_ATTEMPTED_DRIVES=()
  unset NVME_LAST_COMPLETION NVME_SAME_COMPLETION_POLLS
  declare -gA NVME_LAST_COMPLETION=()
  declare -gA NVME_SAME_COMPLETION_POLLS=()

  for dev in "${HDD_DRIVES[@]}"; do
    [ -n "$dev" ] || continue
    log "$(tr_text "Starte HDD-${type^}test auf $(get_cached_device_label "$dev") ..." "Starting HDD ${type^} test on $(get_cached_device_label "$dev") ...")"
    if smartctl -t "$type" "$dev" >/dev/null 2>&1; then
      STARTED_HDD_DRIVES+=("$dev")
    else
      log "$(tr_text "WARN: Fehler beim Start von smartctl -t $type $(get_cached_device_label "$dev")" "WARN: Failed to start smartctl -t $type $(get_cached_device_label "$dev")")"
    fi
    sleep 5
  done

  for dev in "${NVME_DRIVES[@]}"; do
    [ -n "$dev" ] || continue
    log "$(tr_text "Starte NVMe-${type^}test auf $(get_cached_device_label "$dev") ..." "Starting NVMe ${type^} test on $(get_cached_device_label "$dev") ...")"
    if start_nvme_test "$dev" "$type"; then
      STARTED_NVME_DRIVES+=("$dev")
    else
      log "$(tr_text "WARN: Fehler beim Start des NVMe-${type^}tests auf $(get_cached_device_label "$dev")" "WARN: Failed to start NVMe ${type^} test on $(get_cached_device_label "$dev")")"
    fi
    sleep 5
  done
}

is_ata_test_running() {
  local dev="$1" out
  out="$(smartctl -c "$dev" 2>/dev/null || true)"
  printf '%s\n' "$out" | grep -qi 'Self-test routine in progress'
}

is_nvme_test_running() {
  local dev="$1" out
  out="$(smartctl -a -d nvme "$dev" 2>/dev/null || true)"

  if printf '%s\n' "$out" | grep -qi 'No self-test in progress'; then
    return 1
  fi

  if printf '%s\n' "$out" | grep -qiE 'self[- ]test.*in progress|short self[- ]test.*in progress|extended self[- ]test.*in progress'; then
    return 0
  fi

  if printf '%s\n' "$out" | grep -qiE 'Current operation[[:space:]]*:[[:space:]]*0x0'; then
    return 1
  fi

  if printf '%s\n' "$out" | grep -qiE 'Current operation[[:space:]]*:[[:space:]]*0x[1-9a-f]'; then
    return 0
  fi

  return 1
}

get_running_test_devices_for_list() {
  local dev
  for dev in "$@"; do
    [ -n "$dev" ] || continue
    if [[ "$dev" =~ ^/dev/nvme[0-9]+$ ]]; then
      if is_nvme_test_running "$dev"; then
        printf '%s\n' "$dev"
      fi
    else
      if is_ata_test_running "$dev"; then
        printf '%s\n' "$dev"
      fi
    fi
  done
}

get_running_test_devices_started() {
  get_running_test_devices_for_list "${STARTED_HDD_DRIVES[@]}" "${STARTED_NVME_DRIVES[@]}"
}

get_running_test_devices_all() {
  get_running_test_devices_for_list "${HDD_DRIVES[@]}" "${NVME_DRIVES[@]}"
}

attempt_abort_stuck_nvme_tests() {
  local max_minutes="$1"
  local dev

  [ "${#STARTED_NVME_DRIVES[@]}" -gt 0 ] || return 0
  [ "$max_minutes" -gt 0 ] 2>/dev/null || return 0

  for dev in "${STARTED_NVME_DRIVES[@]}"; do
    [ -n "$dev" ] || continue
    array_contains "$dev" "${NVME_ABORT_ATTEMPTED_DRIVES[@]}" && continue
    if ! is_nvme_test_running "$dev"; then
      continue
    fi

    NVME_ABORT_ATTEMPTED_DRIVES+=("$dev")
    log "$(tr_text "Maximale NVMe-Wartezeit (${max_minutes} Minuten) überschritten auf $(get_cached_device_label "$dev"). Abort des NVMe-Selbsttests wird versucht ..." "Maximum NVMe wait time (${max_minutes} minutes) exceeded on $(get_cached_device_label "$dev"). Attempting to abort the NVMe self-test ...")"

    abort_nvme_test "$dev" || true
    sleep 2

    if is_nvme_test_running "$dev"; then
      ABORT_FAILED_NVME_DRIVES+=("$dev")
      log "$(tr_text "WARN: NVMe-Selbsttest auf $(get_cached_device_label "$dev") läuft trotz Abort-Versuch weiter." "WARN: NVMe self-test on $(get_cached_device_label "$dev") is still running after the abort attempt.")"
    else
      ABORTED_NVME_DRIVES+=("$dev")
      log "$(tr_text "NVMe-Selbsttest auf $(get_cached_device_label "$dev") wurde nach Überschreiten der maximalen Wartezeit beendet." "NVMe self-test on $(get_cached_device_label "$dev") was stopped after exceeding the maximum wait time.")"
    fi
  done
}

wait_for_tests() {
  local type="$1" base_minutes step_minutes elapsed nvme_max_minutes stall_min_elapsed stall_polls
  local hdd_count="${#HDD_DRIVES[@]}"
  local nvme_count="${#NVME_DRIVES[@]}"
  local started_count=0
  local running_devices running_list
  local recommended_logged="false"

  if [ "$hdd_count" -gt 0 ]; then
    base_minutes="$(get_ata_poll_minutes "$type")"
  else
    if [ "$type" = "short" ]; then
      base_minutes="$NVME_MAX_WAIT_SHORT_MIN"
    else
      base_minutes="$NVME_MAX_WAIT_LONG_MIN"
    fi
  fi

  if [ "$type" = "short" ]; then
    step_minutes=1
    nvme_max_minutes="$NVME_MAX_WAIT_SHORT_MIN"
  else
    step_minutes=10
    nvme_max_minutes="$NVME_MAX_WAIT_LONG_MIN"
  fi

  stall_min_elapsed="$(get_nvme_stall_min_elapsed "$type")"
  stall_polls="$(get_nvme_stall_polls "$type")"

  elapsed=0
  started_count=$(( ${#STARTED_HDD_DRIVES[@]} + ${#STARTED_NVME_DRIVES[@]} ))

  log "$(tr_text "Empfohlene Wartezeit: ${base_minutes} Minuten (HDDs: ${hdd_count}, NVMe: ${nvme_count})." "Recommended wait time: ${base_minutes} minutes (HDDs: ${hdd_count}, NVMe: ${nvme_count}).")"
  if [ "${#STARTED_NVME_DRIVES[@]}" -gt 0 ]; then
    log "$(tr_text "Maximale NVMe-Wartezeit: ${nvme_max_minutes} Minuten. Danach wird für noch laufende NVMe-Selbsttests ein Abort versucht." "Maximum NVMe wait time: ${nvme_max_minutes} minutes. After that, an abort will be attempted for any NVMe self-tests still running.")"
    if is_true "$NVME_STALL_DETECTION"; then
      log "$(tr_text "NVMe-Stillstandserkennung aktiv ab ${stall_min_elapsed} Minuten und ${stall_polls} gleichen Polls." "NVMe stall detection active from ${stall_min_elapsed} minutes and ${stall_polls} identical polls.")"
    fi
  fi
  log "$(tr_text "Prüfe jetzt alle ${step_minutes} Minuten, bis alle gestarteten Tests beendet sind." "Checking every ${step_minutes} minutes until all started tests are finished.")"
  log "$(tr_text "Teststart: $(date '+%d.%m.%Y %H:%M:%S')" "Test start: $(date '+%Y-%m-%d %H:%M:%S')")"

  if [ "$started_count" -eq 0 ]; then
    log "$(tr_text "Es wurde kein SMART-Test erfolgreich gestartet. Fahre direkt mit dem Report fort." "No SMART test could be started successfully. Continuing with the report.")"
    return 0
  fi

  while :; do
    mapfile -t running_devices < <(get_running_test_devices_started)

    if [ "${#running_devices[@]}" -eq 0 ]; then
      log "$(tr_text "Alle gestarteten SMART-Tests sind abgeschlossen. Erzeuge jetzt den Report." "All started SMART tests are finished. Generating the report now.")"
      return 0
    fi

    running_list="$(format_device_list "${running_devices[@]}")"

    if [ "${#STARTED_NVME_DRIVES[@]}" -gt 0 ] && is_true "$NVME_STALL_DETECTION"; then
      attempt_abort_stalled_nvme_tests "$type" "$elapsed"
      mapfile -t running_devices < <(get_running_test_devices_started)
      if [ "${#running_devices[@]}" -eq 0 ]; then
        log "$(tr_text "Alle gestarteten SMART-Tests sind abgeschlossen. Erzeuge jetzt den Report." "All started SMART tests are finished. Generating the report now.")"
        return 0
      fi
      running_list="$(format_device_list "${running_devices[@]}")"
    fi

    if [ "${#STARTED_NVME_DRIVES[@]}" -gt 0 ] && [ "$elapsed" -ge "$nvme_max_minutes" ]; then
      attempt_abort_stuck_nvme_tests "$nvme_max_minutes"
      mapfile -t running_devices < <(get_running_test_devices_started)
      if [ "${#running_devices[@]}" -eq 0 ]; then
        log "$(tr_text "Alle gestarteten SMART-Tests sind abgeschlossen. Erzeuge jetzt den Report." "All started SMART tests are finished. Generating the report now.")"
        return 0
      fi
      running_list="$(format_device_list "${running_devices[@]}")"
    fi

    if [ "$elapsed" -ge "$base_minutes" ] && [ "$recommended_logged" != "true" ]; then
      log "$(tr_text "Die empfohlene Wartezeit (${base_minutes} Minuten) ist erreicht, aber folgende Tests laufen noch: ${running_list}. Es wird weiter gewartet, bis diese abgeschlossen sind." "The recommended wait time (${base_minutes} minutes) has been reached, but the following tests are still running: ${running_list}. Waiting will continue until they are finished.")"
      recommended_logged="true"
    fi

    log "$(tr_text "SMART-Tests laufen noch auf: ${running_list} (bisher ${elapsed} Minuten). Warte weitere ${step_minutes} Minuten ..." "SMART tests are still running on: ${running_list} (elapsed ${elapsed} minutes). Waiting another ${step_minutes} minutes ...")"
    sleep "${step_minutes}m"
    elapsed=$(( elapsed + step_minutes ))
  done
}

send_notice_mail_python() {
  local mode="$1"
  local notice_type="$2"
  local detail_text="$3"
  local raw_model model_override custom_name
  raw_model="$(get_raw_model_string)"
  model_override="${NAS_MODEL_OVERRIDE}"
  custom_name="${NAS_CUSTOM_NAME}"

  "$PYTHON_BIN" -u - "$mode" "$notice_type" "$detail_text" "$raw_model" "$model_override" "$custom_name" <<'PYEOF'
import smtplib, datetime, sys, re, os, subprocess, html
from email.mime.text import MIMEText

mode = sys.argv[1] or ""
notice_type = sys.argv[2] or ""
detail_text = sys.argv[3] or ""
raw_model = sys.argv[4] or ""
model_override = sys.argv[5] or ""
custom_name = sys.argv[6] or ""

SMTP_SERVER = os.environ.get("SMTP_SERVER", "")
SMTP_PORT   = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER   = os.environ.get("SMTP_USER", "")
SMTP_PASS   = os.environ.get("SMTP_PASS", "")
MAIL_FROM   = os.environ.get("MAIL_FROM", "")
MAIL_TO     = os.environ.get("MAIL_TO", "")
SCRIPT_VERSION = os.environ.get("SCRIPT_VERSION", "")
LANGUAGE = os.environ.get("LANGUAGE", "de")
SMTP_USE_TLS = os.environ.get("SMTP_USE_TLS", "true").lower() == "true"
SMTP_USE_SSL = os.environ.get("SMTP_USE_SSL", "false").lower() == "true"
DEBUG_SMTP = os.environ.get("DEBUG_SMTP", "false").lower() == "true"
IS_EN = str(LANGUAGE).lower().startswith("en")

def tr(de: str, en: str) -> str:
    return en if IS_EN else de

def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
        return (p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip())
    except Exception:
        return (999, "", "")

def first_line(s: str) -> str:
    return (s or "").splitlines()[0] if (s or "").splitlines() else ""

def normalize_model(raw: str) -> str:
    r = (raw or "").upper()
    r = r.replace("UGREEN", " ").replace("DEFAULT STRING", " ").replace("/", " ")
    r = re.sub(r"\s+", " ", r).strip()
    if model_override.strip():
        return model_override.strip().upper()
    tokens = r.replace(" ", "")
    for k in ("DXP480TPLUS","DX4700","IDX6011PRO","IDX6011","DH4300PLUS","DH2300","DXP2800GT","DXP2800","DXP4800GT","DXP4800PRO","DXP4800PLUS","DXP4800","DXP6800ULTRA","DXP6800PRO","DXP6800PLUS","DXP8800ULTRA","DXP8800PRO","DXP8800PLUS"):
        if k in tokens:
            return k
    m = re.search(r"(IDX[0-9]{4}PRO|IDX[0-9]{4}|DH[0-9]{4}PLUS|DH[0-9]{4}|DXP[0-9]{4}ULTRA|DXP[0-9]{4}GT|DXP[0-9]{4}T?PLUS|DXP[0-9]{4}PRO|DXP[0-9]{4}|DX[0-9]{4})", tokens)
    return m.group(1) if m else "UGREEN"

MODEL = normalize_model(raw_model)
tag = f"{MODEL} - {custom_name.strip()}" if custom_name.strip() else MODEL
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S" if IS_EN else "%d.%m.%Y %H:%M:%S")

def parse_lsblk_pairs(line: str):
    return {m.group(1): m.group(2) for m in re.finditer(r'(\w+)="([^"]*)"', line or "")}

def list_sd_disk_records():
    rc, out, _ = run(["lsblk", "-dn", "-P", "-o", "NAME,TYPE,TRAN,HOTPLUG,RM,ROTA,SIZE,VENDOR,MODEL,SERIAL"], timeout=5)
    records = []
    for line in out.splitlines():
        rec = parse_lsblk_pairs(line)
        name = rec.get("NAME", "")
        typ = rec.get("TYPE", "")
        tran = (rec.get("TRAN", "") or "").lower()
        if typ != "disk" or not name.startswith("sd"):
            continue
        records.append({
            "path": "/dev/" + name,
            "name": name,
            "tran": tran,
            "hotplug": int(rec.get("HOTPLUG") or 0),
            "rm": int(rec.get("RM") or 0),
            "rota": int(rec.get("ROTA") or 0),
            "vendor": (rec.get("VENDOR") or "").strip(),
            "model": (rec.get("MODEL") or "").strip(),
            "serial": (rec.get("SERIAL") or "").strip(),
            "is_usb": tran == "usb",
        })
    return records

def get_udev_props(dev: str):
    rc, out, _ = run(["udevadm", "info", "--query=property", "--name", dev], timeout=8)
    props = {}
    for ln in out.splitlines():
        if "=" in ln:
            k, v = ln.split("=", 1)
            props[k] = v
    return props

def classify_usb_record(rec):
    props = get_udev_props(rec["path"])
    combo = " ".join([rec.get("vendor", ""), rec.get("model", ""), props.get("ID_VENDOR", ""), props.get("ID_MODEL", "")]).lower()
    if props.get("ID_DRIVE_FLASH_SD") == "1" or props.get("ID_DRIVE_MEDIA_FLASH_SD") == "1":
        return "sdcard"
    if "genesys" in combo and "massstorageclass" in combo:
        return "sdcard"
    if "sd card reader" in combo or "card reader" in combo:
        return "sdcard"
    if props.get("ID_ATA") == "1":
        return "usb_ssd" if int(rec.get("rota", 1) or 1) == 0 else "usb_hdd"
    if int(rec.get("rm", 0) or 0) == 1 and int(rec.get("hotplug", 0) or 0) == 1:
        return "usb_stick"
    return "usb_unknown"

def usb_kind_text(kind: str) -> str:
    return {
        "sdcard": tr("SD-Karte/Kartenleser", "SD card/card reader"),
        "usb_stick": tr("USB-Stick", "USB flash drive"),
        "usb_hdd": tr("Externe USB-HDD", "External USB HDD"),
        "usb_ssd": tr("Externe USB-SSD", "External USB SSD"),
        "usb_unknown": tr("USB-/Wechsellaufwerk", "USB/removable drive"),
    }.get(kind, tr("USB-/Wechsellaufwerk", "USB/removable drive"))

def list_nvme_ctrl():
    ctrl = []
    rc, out, _ = run(["bash", "-lc", "ls -1 /dev/disk/by-path/*nvme-* 2>/dev/null | grep -v part | sort"], timeout=5)
    if out.strip():
        for path in out.splitlines():
            rc2, real, _ = run(["readlink", "-f", path], timeout=5)
            base = os.path.basename((real or "").strip())
            m = re.match(r"^(nvme\d+)n\d+$", base)
            if m:
                ctrl_dev = "/dev/" + m.group(1)
                if os.path.exists(ctrl_dev) and ctrl_dev not in ctrl:
                    ctrl.append(ctrl_dev)
    if ctrl:
        return ctrl
    rc, out, _ = run(["bash", "-lc", "ls -1 /dev/nvme[0-9]* 2>/dev/null | grep -E '^/dev/nvme[0-9]+$' | sort -V"], timeout=5)
    return [line.strip() for line in out.splitlines() if line.strip()]

def findmnt_src(mountpoint: str) -> str:
    rc, out, _ = run(["findmnt", "-n", "-o", "SOURCE", mountpoint], timeout=5)
    return first_line(out)

def pkname(dev: str) -> str:
    rc, out, _ = run(["lsblk", "-no", "PKNAME", dev], timeout=5)
    return first_line(out)

def system_disk_base():
    for mp in ("/rom", "/", "/overlay"):
        src = findmnt_src(mp)
        if src.startswith("/dev/"):
            pk = pkname(src)
            if pk:
                return "/dev/" + pk
            return src
    return ""

sd_records = list_sd_disk_records()
internal_hdd_devices = [r["path"] for r in sd_records if not r.get("is_usb")]
usb_records = [r for r in sd_records if r.get("is_usb")]
for rec in usb_records:
    rec["usb_kind"] = classify_usb_record(rec)
usb_label_map = {rec["path"]: f"USB{idx}" for idx, rec in enumerate(usb_records, start=1)}

lsblk_scsi = {}
host_to_dev = {}
bay_mapping = {}
try:
    rc, out, _ = run(["lsblk", "-S", "-x", "hctl", "-o", "NAME,HCTL,TRAN,MODEL,SERIAL", "-J"], timeout=5)
    if out:
        data = __import__('json').loads(out)
        for dev in data.get("blockdevices", []):
            name = dev.get("name")
            if not name:
                continue
            lsblk_scsi["/dev/" + name] = {
                "hctl": dev.get("hctl") or "",
                "tran": (dev.get("tran") or "").strip(),
                "model": (dev.get("model") or "").strip(),
                "serial": (dev.get("serial") or "").strip(),
            }
    hosts = set()
    for path, info in lsblk_scsi.items():
        if path not in set(internal_hdd_devices):
            continue
        hctl = info.get("hctl") or ""
        host_str = hctl.split(":")[0] if ":" in hctl else ""
        if host_str.isdigit():
            host = int(host_str)
            host_to_dev[host] = path
            hosts.add(host)
    bay_count = (max(hosts) + 1) if hosts else len(internal_hdd_devices)
    for host in range(bay_count):
        dev = host_to_dev.get(host)
        if dev:
            bay_mapping[dev] = host + 1
except Exception:
    bay_mapping = {}

sys_base = system_disk_base()
sys_nvme_ctrl = ""
if isinstance(sys_base, str) and sys_base.startswith("/dev/nvme"):
    base_name = os.path.basename(sys_base)
    m = re.match(r"^(nvme\d+)n\d+(?:p\d+)?$", base_name)
    if m:
        sys_nvme_ctrl = "/dev/" + m.group(1)

nvme_devices = list_nvme_ctrl()
user_nvme_devices = [d for d in nvme_devices if d != sys_nvme_ctrl]
user_nvme_devices = sorted(user_nvme_devices, key=lambda d: int(re.match(r"^/dev/nvme(\d+)$", d).group(1)) if re.match(r"^/dev/nvme(\d+)$", d) else 999)
report_nvme_devices = list(user_nvme_devices)
if sys_nvme_ctrl and sys_nvme_ctrl in nvme_devices:
    report_nvme_devices.append(sys_nvme_ctrl)
system_nvme_slot = 3 if (MODEL.startswith("DXP") or MODEL.startswith("IDX")) and sys_nvme_ctrl else (len(user_nvme_devices) + 1 if sys_nvme_ctrl else 0)

def nvme_by_path_name(dev: str) -> str:
    """Return the stable /dev/disk/by-path name for an NVMe controller."""
    m = re.match(r"^/dev/(nvme\d+)$", dev or "")
    if not m:
        return ""
    disk_node = f"/dev/{m.group(1)}n1"
    rc, out, _ = run(
        ["bash", "-lc", "ls -1 /dev/disk/by-path/*nvme-* 2>/dev/null | grep -v part | sort"],
        timeout=5,
    )
    for path in out.splitlines():
        rc2, real, _ = run(["readlink", "-f", path], timeout=5)
        if (real or "").strip() == disk_node:
            return os.path.basename(path.strip())
    return ""


def nvme_user_label(dev: str, generic_index: int) -> str:
    """Use verified physical U.2 labels on DXP4800 GT; otherwise a safe logical label."""
    path_name = nvme_by_path_name(dev)
    if MODEL == "DXP4800GT":
        if "pci-0000:01:00.0-nvme-1" in path_name:
            return tr("U.2-Schacht 1", "U.2 Bay 1")
        if "pci-0000:02:00.0-nvme-1" in path_name:
            return tr("U.2-Schacht 2", "U.2 Bay 2")
        return tr(f"M.2-NVMe {generic_index}", f"M.2 NVMe {generic_index}")
    return f"NVME{generic_index}"

nvme_label_map = {}
user_slot_idx = 1
for dev in report_nvme_devices:
    if sys_nvme_ctrl and dev == sys_nvme_ctrl:
        nvme_label_map[dev] = f"NVME{system_nvme_slot} {tr('Systemlaufwerk', 'System drive')}" if system_nvme_slot else tr('Systemlaufwerk', 'System drive')
    else:
        nvme_label_map[dev] = nvme_user_label(dev, user_slot_idx)
        user_slot_idx += 1

nvme_info = {}
rc, out, _ = run(["lsblk", "-d", "-J", "-o", "NAME,MODEL,SERIAL"], timeout=5)
if out:
    try:
        data = __import__('json').loads(out)
        for dev in data.get("blockdevices", []):
            name = dev.get("name") or ""
            if re.match(r"^nvme\d+n\d+$", name):
                nvme_info["/dev/" + name] = {"model": (dev.get("model") or "").strip(), "serial": (dev.get("serial") or "").strip()}
    except Exception:
        pass

def _nvme_disk_node(dev: str) -> str:
    m = re.match(r"^/dev/(nvme\d+)$", dev or "")
    return f"/dev/{m.group(1)}n1" if m else dev

def drive_label(dev: str) -> str:
    if re.match(r"^/dev/nvme\d+$", dev or ""):
        parts = [nvme_label_map.get(dev, os.path.basename(dev))]
        info = nvme_info.get(_nvme_disk_node(dev), {})
        if info.get("model"):
            parts.append(info["model"])
        if info.get("serial"):
            parts.append(info["serial"])
        return " / ".join([p for p in parts if p])
    rec = next((r for r in sd_records if r["path"] == dev), None)
    parts = []
    if dev in bay_mapping:
        parts.append(f"{'Bay' if IS_EN else 'Schacht'} {bay_mapping[dev]}")
        info = lsblk_scsi.get(dev, {})
        if info.get("model"):
            parts.append(info["model"])
        if info.get("serial"):
            parts.append(info["serial"])
        return " / ".join([p for p in parts if p])
    if rec and rec.get("is_usb"):
        parts.append(usb_label_map.get(dev, os.path.basename(dev)))
        parts.append(usb_kind_text(rec.get("usb_kind") or "usb_unknown"))
        if rec.get("model"):
            parts.append(rec["model"])
        if rec.get("serial"):
            parts.append(rec["serial"])
        return " / ".join([p for p in parts if p])
    return dev

raw_devices = [ln.strip() for ln in detail_text.splitlines() if ln.strip()]
if raw_devices:
    detail_html = "<br />".join(html.escape(drive_label(dev)) for dev in raw_devices)
else:
    detail_html = html.escape(detail_text)

if mode == "weekly-short":
    mode_label = tr("Wöchentlicher Kurztest", "Weekly short test")
elif mode == "monthly-long":
    mode_label = tr("Monatlicher Langtest", "Monthly long test")
elif mode == "report-only":
    mode_label = tr("Nur Bericht (ohne Tests)", "Report only (no tests)")
else:
    mode_label = mode

if notice_type == "already-running":
    subject = f"[{tag}] {tr('SMART-Bericht', 'SMART report')} – {tr('Start abgebrochen, SMART-Test läuft bereits', 'Start aborted, SMART test already running')} [{tr('WARNUNG', 'WARNING')}]"
    heading = tr("SMART-Test bereits aktiv", "SMART test already active")
    intro = tr(
        "Ein neuer SMART-Test wurde nicht gestartet, weil bereits mindestens ein SMART-Test aktiv ist.",
        "A new SMART test was not started because at least one SMART test is already active."
    )
    details_label = tr("Bereits laufende Tests", "Tests already running")
    recommendation = tr(
        "Es wurden keine neuen Tests gestartet. Bitte warte bis die laufenden Tests abgeschlossen sind oder nutze bei Bedarf --report-only.",
        "No new tests were started. Please wait until the running tests are finished or use --report-only if needed."
    )
else:
    subject = f"[{tag}] {tr('SMART-Bericht', 'SMART report')} – {tr('Hinweis', 'Notice')} [{tr('WARNUNG', 'WARNING')}]"
    heading = tr("SMART-Hinweis", "SMART notice")
    intro = tr("Es gibt einen Hinweis zum SMART-Skriptlauf.", "There is a notice about the SMART script run.")
    details_label = tr("Details", "Details")
    recommendation = tr("Bitte prüfe die Logdatei für weitere Informationen.", "Please check the log file for more information.")

html_body = f"""<html><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>{subject}</title>
</head><body style="font-family:Segoe UI,Arial,sans-serif;font-size:13px;color:#333333;">
<h2 style="font-weight:600;font-size:18px;margin-bottom:4px;">{heading}</h2>
<p style="margin-top:0;margin-bottom:10px;">
{intro}<br />
{tr("Modus", "Mode")}: {mode_label}<br />
{tr("Erkanntes Modell", "Detected model")}: {MODEL}<br />
{tr("Zeitpunkt", "Timestamp")}: {now}
</p>
<p style="margin-bottom:10px;">
<strong>{details_label}:</strong><br />
{detail_html}
</p>
<p style="font-size:12px;color:#777777;">
{recommendation}<br />
{tr("Erzeugt von", "Generated by")}: ugreen-smart-report.sh v{SCRIPT_VERSION}
</p>
</body></html>"""

msg = MIMEText(html_body, "html", "utf-8")
msg["Subject"] = subject
msg["From"] = MAIL_FROM
msg["To"] = MAIL_TO

try:
    if SMTP_USE_SSL:
        with smtplib.SMTP_SSL(SMTP_SERVER, SMTP_PORT, timeout=30) as server:
            if DEBUG_SMTP:
                server.set_debuglevel(1)
            if SMTP_USER:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
    else:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT, timeout=30) as server:
            if DEBUG_SMTP:
                server.set_debuglevel(1)
            if SMTP_USE_TLS:
                server.starttls()
            if SMTP_USER:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
    print(tr("Hinweis-Mail erfolgreich gesendet.", "Notice email sent successfully."))
except Exception as e:
    import traceback
    print(tr("Fehler beim Versand der Hinweis-Mail:", "Error sending notice email:"), e)
    if DEBUG_SMTP:
        traceback.print_exc()
    sys.exit(1)
PYEOF
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "$(tr_text "WARN: Hinweis-Mail konnte nicht gesendet werden (Python Exit Code: ${rc})." "WARN: Notice email could not be sent (Python exit code: ${rc}).")"
    return "$rc"
  fi
  log "$(tr_text "Hinweis-Mail erfolgreich gesendet." "Notice email sent successfully.")"
}

abort_if_running_tests_exist() {
  local mode="$1"
  local running_devices=()
  local running_list

  mapfile -t running_devices < <(get_running_test_devices_all)

  if [ "${#running_devices[@]}" -eq 0 ]; then
    return 0
  fi

  running_list="$(printf '%s\n' "${running_devices[@]}")"

  if [ "$ABORT_RUNNING_TESTS_BEFORE_START" = "true" ]; then
    log "$(tr_text "WARN: Es laufen bereits SMART-Tests. Versuche diese vor dem Start des neuen Testlaufs abzubrechen ..." "WARN: SMART tests are already running. Trying to abort them before starting the new test run ...")"
    local dev
    for dev in "${running_devices[@]}"; do
      [ -n "$dev" ] || continue
      if [[ "$dev" =~ ^/dev/nvme[0-9]+$ ]]; then
        abort_nvme_test "$dev" || true
      else
        smartctl -X "$dev" >/dev/null 2>&1 || true
      fi
      sleep 2
    done
    sleep 3
    mapfile -t running_devices < <(get_running_test_devices_all)
    if [ "${#running_devices[@]}" -eq 0 ]; then
      log "$(tr_text "Laufende SMART-Tests wurden erfolgreich abgebrochen. Neue Tests werden jetzt gestartet." "Running SMART tests were aborted successfully. New tests will be started now.")"
      return 0
    fi
    running_list="$(printf '%s\n' "${running_devices[@]}")"
    log "$(tr_text "WARN: Nicht alle laufenden SMART-Tests konnten abgebrochen werden. Es werden keine neuen Tests gestartet." "WARN: Not all running SMART tests could be aborted. No new tests will be started.")"
    send_notice_mail_python "$mode" "already-running" "$running_list" || true
    return 1
  fi

  log "$(tr_text "WARN: Es laufen bereits SMART-Tests. Es werden keine neuen Tests gestartet." "WARN: SMART tests are already running. No new tests will be started.")"
  send_notice_mail_python "$mode" "already-running" "$running_list" || true
  return 1
}

send_smart_report_python() {
  local mode="$1" raw_model model_override custom_name emmc_check emmc_read
  raw_model="$(get_raw_model_string)"
  if [ "$mode" = "report-only" ] && is_true "${EMMC_ENABLE_CHECK}" && is_true "${EMMC_ENABLE_READTEST}"; then
    log "$(tr_text 'Hinweis: eMMC-Lesetest wird im Report-Only-Modus übersprungen.' 'Note: eMMC read test is skipped in report-only mode.')"
  fi
  model_override="${NAS_MODEL_OVERRIDE}"
  custom_name="${NAS_CUSTOM_NAME}"
  emmc_check="${EMMC_ENABLE_CHECK}"
  emmc_read="${EMMC_ENABLE_READTEST}"
  local nvme_aborted_export nvme_abort_failed_export
  nvme_aborted_export="$(IFS='|'; printf '%s' "${ABORTED_NVME_DRIVES[*]-}")"
  nvme_abort_failed_export="$(IFS='|'; printf '%s' "${ABORT_FAILED_NVME_DRIVES[*]-}")"

  NVME_ABORTED_DRIVES="${nvme_aborted_export}" \
  NVME_ABORT_FAILED_DRIVES="${nvme_abort_failed_export}" \
  "$PYTHON_BIN" -u - "$mode" "$raw_model" "$model_override" "$custom_name" "$emmc_check" "$emmc_read" <<'PYEOF'
import subprocess, json, datetime, smtplib, sys, os, re, time
from email.mime.text import MIMEText

mode = sys.argv[1]
raw_model = sys.argv[2] or ""
model_override = sys.argv[3] or ""
custom_name = sys.argv[4] or ""
emmc_check = (sys.argv[5] or "").lower() == "true"
emmc_read  = (sys.argv[6] or "").lower() == "true"
emmc_read_skipped_report_only = False
if mode == "report-only" and emmc_read:
    emmc_read = False
    emmc_read_skipped_report_only = True

SMTP_SERVER = os.environ.get("SMTP_SERVER", "")
SMTP_PORT   = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER   = os.environ.get("SMTP_USER", "")
SMTP_PASS   = os.environ.get("SMTP_PASS", "")
MAIL_FROM   = os.environ.get("MAIL_FROM", "")
MAIL_TO     = os.environ.get("MAIL_TO", "")
SCRIPT_VERSION = os.environ.get("SCRIPT_VERSION", "")
LANGUAGE = os.environ.get("LANGUAGE", "de")
SMTP_USE_TLS = os.environ.get("SMTP_USE_TLS", "true").lower() == "true"
SMTP_USE_SSL = os.environ.get("SMTP_USE_SSL", "false").lower() == "true"
DEBUG_SMTP = os.environ.get("DEBUG_SMTP", "false").lower() == "true"
DEBUG_REPORT_MAIL = os.environ.get("DEBUG_REPORT_MAIL", "false").lower() == "true"
DEBUG_SAVE_REPORT_HTML = os.environ.get("DEBUG_SAVE_REPORT_HTML", "false").lower() == "true"
DEBUG_REPORT_DUMP_DIR = os.environ.get("DEBUG_REPORT_DUMP_DIR", "/tmp")
NVME_ABORTED_DRIVES = set(filter(None, os.environ.get("NVME_ABORTED_DRIVES", "").split("|")))
NVME_ABORT_FAILED_DRIVES = set(filter(None, os.environ.get("NVME_ABORT_FAILED_DRIVES", "").split("|")))
IS_EN = str(LANGUAGE).lower().startswith("en")

def tr(de: str, en: str) -> str:
    return en if IS_EN else de


def progress_log(de: str, en: str) -> None:
    msg = tr(de, en)
    fmt = "%Y-%m-%d %H:%M:%S" if IS_EN else "%d.%m.%Y %H:%M:%S"
    line = f"[{datetime.datetime.now().strftime(fmt)}] {msg}"
    print(line, flush=True)
    log_file = os.environ.get("LOG_FILE", "")
    if log_file:
        try:
            with open(log_file, "a", encoding="utf-8") as fh:
                fh.write(line + "\n")
        except Exception:
            pass

def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
        return (p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip())
    except Exception:
        return (999, "", "")

def first_line(s: str) -> str:
    return (s or "").splitlines()[0] if (s or "").splitlines() else ""

def normalize_model(raw: str) -> str:
    r = (raw or "").upper()
    r = r.replace("UGREEN", " ")
    r = r.replace("DEFAULT STRING", " ")
    r = r.replace("/", " ")
    r = re.sub(r"\s+", " ", r).strip()

    # harter override
    if model_override.strip():
        return model_override.strip().upper()

    # bekannte Modelle (robust)
    tokens = r.replace(" ", "")
    # DXP480TPlus
    if "DXP480TPLUS" in tokens or ("DXP480T" in tokens and "PLUS" in tokens):
        return "DXP480TPLUS"

    if "DX4700" in tokens:
        return "DX4700"
    if "IDX6011PRO" in tokens or ("IDX6011" in tokens and " PRO" in r):
        return "IDX6011PRO"
    if "IDX6011" in tokens:
        return "IDX6011"
    if "DH2300" in tokens:
        return "DH2300"
    if "DH4300PLUS" in tokens:
        return "DH4300PLUS"
    if "DXP2800GT" in tokens or ("DXP2800" in tokens and " GT" in r):
        return "DXP2800GT"
    if "DXP2800" in tokens:
        return "DXP2800"
    # DXP4800
    if "DXP4800GT" in tokens or ("DXP4800" in tokens and " GT" in r):
        return "DXP4800GT"
    if "DXP4800PRO" in tokens or ("DXP4800" in tokens and " PRO" in r):
        return "DXP4800PRO"
    if "DXP4800PLUS" in tokens:
        return "DXP4800PLUS"
    if "DXP4800" in tokens:
        return "DXP4800"
    # 6800
    if "DXP6800ULTRA" in tokens or ("DXP6800" in tokens and " ULTRA" in r):
        return "DXP6800ULTRA"
    if "DXP6800PRO" in tokens or ("DXP6800" in tokens and " PRO" in r):
        return "DXP6800PRO"
    if "DXP6800PLUS" in tokens:
        return "DXP6800PLUS"
    # 8800
    if "DXP8800ULTRA" in tokens or ("DXP8800" in tokens and " ULTRA" in r):
        return "DXP8800ULTRA"
    if "DXP8800PRO" in tokens or ("DXP8800" in tokens and " PRO" in r):
        return "DXP8800PRO"
    if "DXP8800PLUS" in tokens:
        return "DXP8800PLUS"

    # Fallback: aus raw irgendwas Sinnvolles
    m = re.search(r"(IDX[0-9]{4}PRO|IDX[0-9]{4}|DH[0-9]{4}PLUS|DH[0-9]{4}|DXP[0-9]{4}ULTRA|DXP[0-9]{4}GT|DXP[0-9]{4}T?PLUS|DXP[0-9]{4}PRO|DXP[0-9]{4}|DX[0-9]{4}T?PLUS|DX[0-9]{4}PRO|DX[0-9]{4})", tokens)
    if m:
        return m.group(1)
    return "UGREEN"

MODEL = normalize_model(raw_model)

FEATURES = {
    "DH2300":        {"hdd_bays": 2, "emmc": True,  "nvme": 0, "os_on_nvme": False},
    "DH4300PLUS":    {"hdd_bays": 4, "emmc": True,  "nvme": 0, "os_on_nvme": False},
    "DXP2800":       {"hdd_bays": 2, "emmc": True,  "nvme": 2, "os_on_nvme": False},
    "DXP2800GT":     {"hdd_bays": 2, "emmc": True,  "nvme": 4, "os_on_nvme": False},
    "DXP4800":       {"hdd_bays": 4, "emmc": True,  "nvme": 2, "os_on_nvme": False},
    "DXP4800GT":     {"hdd_bays": 4, "emmc": True,  "nvme": 4, "os_on_nvme": False},
    "DX4700":        {"hdd_bays": 4, "emmc": True,  "nvme": 2, "os_on_nvme": False},
    "DXP4800PRO":    {"hdd_bays": 4, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "DXP4800PLUS":   {"hdd_bays": 4, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "DXP6800PLUS":   {"hdd_bays": 6, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "DXP6800PRO":    {"hdd_bays": 6, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "DXP6800ULTRA":  {"hdd_bays": 6, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "DXP8800PLUS":   {"hdd_bays": 8, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "DXP8800PRO":    {"hdd_bays": 8, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "DXP8800ULTRA":  {"hdd_bays": 8, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "IDX6011":       {"hdd_bays": 6, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "IDX6011PRO":    {"hdd_bays": 6, "emmc": False, "nvme": 3, "os_on_nvme": True},
    "DXP480TPLUS":   {"hdd_bays": 0, "emmc": False, "nvme": 5, "os_on_nvme": True},
}

expected = FEATURES.get(MODEL, {"hdd_bays": None, "emmc": None, "nvme": None, "os_on_nvme": None})

def display_name():
    if custom_name.strip():
        return f"{MODEL} - {custom_name.strip()}"
    return MODEL

NOW = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S" if IS_EN else "%d.%m.%Y %H:%M:%S")

# --------------------------------------------------
# Drive Discovery (laufend)
# --------------------------------------------------
def parse_lsblk_pairs(line: str):
    return {m.group(1): m.group(2) for m in re.finditer(r'(\w+)="([^"]*)"', line or "")}

def list_sd_disk_records():
    rc, out, _ = run(["lsblk", "-dn", "-P", "-o", "NAME,TYPE,TRAN,HOTPLUG,RM,ROTA,SIZE,VENDOR,MODEL,SERIAL"], timeout=5)
    records = []
    for line in out.splitlines():
        rec = parse_lsblk_pairs(line)
        name = rec.get("NAME", "")
        typ = rec.get("TYPE", "")
        tran = (rec.get("TRAN", "") or "").lower()
        if typ != "disk" or not name.startswith("sd"):
            continue
        records.append({
            "path": "/dev/" + name,
            "name": name,
            "tran": tran,
            "hotplug": int(rec.get("HOTPLUG") or 0),
            "rm": int(rec.get("RM") or 0),
            "rota": int(rec.get("ROTA") or 0),
            "vendor": (rec.get("VENDOR") or "").strip(),
            "model": (rec.get("MODEL") or "").strip(),
            "serial": (rec.get("SERIAL") or "").strip(),
            "is_usb": tran == "usb",
        })
    return records

def get_udev_props(dev: str):
    rc, out, _ = run(["udevadm", "info", "--query=property", "--name", dev], timeout=8)
    props = {}
    for ln in out.splitlines():
        if "=" in ln:
            k, v = ln.split("=", 1)
            props[k] = v
    return props

def classify_usb_record(rec):
    props = get_udev_props(rec["path"])
    combo = " ".join([rec.get("vendor", ""), rec.get("model", ""), props.get("ID_VENDOR", ""), props.get("ID_MODEL", "")]).lower()
    if props.get("ID_DRIVE_FLASH_SD") == "1" or props.get("ID_DRIVE_MEDIA_FLASH_SD") == "1":
        return "sdcard"
    if "genesys" in combo and "massstorageclass" in combo:
        return "sdcard"
    if "sd card reader" in combo or "card reader" in combo:
        return "sdcard"
    if props.get("ID_ATA") == "1":
        return "usb_ssd" if int(rec.get("rota", 1) or 1) == 0 else "usb_hdd"
    if int(rec.get("rm", 0) or 0) == 1 and int(rec.get("hotplug", 0) or 0) == 1:
        return "usb_stick"
    return "usb_unknown"

def usb_kind_text(kind: str) -> str:
    return {
        "sdcard": tr("SD-Karte/Kartenleser", "SD card/card reader"),
        "usb_stick": tr("USB-Stick", "USB flash drive"),
        "usb_hdd": tr("Externe USB-HDD", "External USB HDD"),
        "usb_ssd": tr("Externe USB-SSD", "External USB SSD"),
        "usb_unknown": tr("USB-/Wechsellaufwerk", "USB/removable drive"),
    }.get(kind, tr("USB-/Wechsellaufwerk", "USB/removable drive"))

def usb_kind_note(kind: str) -> str:
    return {
        "sdcard": tr("SD-Karte/Kartenleser, SMART-Selbsttest nicht unterstützt", "SD card/card reader, SMART self-test not supported"),
        "usb_stick": tr("USB-Stick, SMART-Selbsttest nicht unterstützt", "USB flash drive, SMART self-test not supported"),
        "usb_hdd": tr("Externe USB-HDD", "External USB HDD"),
        "usb_ssd": tr("Externe USB-SSD", "External USB SSD"),
        "usb_unknown": tr("USB-/Wechsellaufwerk", "USB/removable drive"),
    }.get(kind, tr("USB-/Wechsellaufwerk", "USB/removable drive"))

def list_nvme_ctrl():
    # preferred: by-path for stable order
    ctrl = []
    rc, out, _ = run(["bash", "-lc", "ls -1 /dev/disk/by-path/*nvme-* 2>/dev/null | grep -v part | sort"], timeout=5)
    if out.strip():
        for p in out.splitlines():
            rc2, real, _ = run(["readlink", "-f", p], timeout=5)
            base = os.path.basename(real.strip())
            m = re.match(r"^(nvme\d+)n\d+$", base)
            if m:
                c = "/dev/" + m.group(1)
                if os.path.exists(c) and c not in ctrl:
                    ctrl.append(c)
    if ctrl:
        return ctrl

    # fallback: /dev/nvmeX
    rc, out, _ = run(["bash", "-lc", "ls -1 /dev/nvme[0-9]* 2>/dev/null | grep -E '^/dev/nvme[0-9]+$' | sort -V"], timeout=5)
    return [l.strip() for l in out.splitlines() if l.strip()]

sd_records = list_sd_disk_records()
include_usb = os.environ.get("INCLUDE_USB_DRIVES", "false").lower() in ("true", "1", "yes", "ja", "on")
internal_hdd_devices = [r["path"] for r in sd_records if not r.get("is_usb")]
usb_records = [r for r in sd_records if r.get("is_usb")] if include_usb else []
for rec in usb_records:
    rec["usb_kind"] = classify_usb_record(rec)
usb_hdd_devices = [r["path"] for r in usb_records]
usb_testable_devices = [r["path"] for r in usb_records if (r.get("usb_kind") or "") not in ("sdcard", "usb_stick")]
usb_excluded_devices = [r["path"] for r in usb_records if (r.get("usb_kind") or "") in ("sdcard", "usb_stick")]
hdd_devices = list(internal_hdd_devices) + list(usb_testable_devices)
nvme_devices = list_nvme_ctrl()

# --------------------------------------------------
# Detect system disk (for 'UGOS SSD' label / eMMC)
# --------------------------------------------------
def findmnt_src(mountpoint: str) -> str:
    rc, out, _ = run(["findmnt", "-n", "-o", "SOURCE", mountpoint], timeout=5)
    return first_line(out)

def pkname(dev: str) -> str:
    rc, out, _ = run(["lsblk", "-no", "PKNAME", dev], timeout=5)
    return first_line(out)

def system_disk_base():
    for mp in ("/rom", "/", "/overlay"):
        src = findmnt_src(mp)
        if src.startswith("/dev/"):
            pk = pkname(src)
            if pk:
                return "/dev/" + pk
            return src
    return ""

sys_base = system_disk_base()  # e.g. /dev/mmcblk0 or /dev/nvme2n1
sys_nvme_ctrl = ""
if isinstance(sys_base, str) and sys_base.startswith("/dev/nvme"):
    base_name = os.path.basename(sys_base)
    m = re.match(r"^(nvme\d+)n\d+(?:p\d+)?$", base_name)
    if m:
        sys_nvme_ctrl = "/dev/" + m.group(1)
    elif re.match(r"^nvme\d+$", base_name):
        sys_nvme_ctrl = "/dev/" + base_name

emmc_present = os.path.exists("/dev/mmcblk0")

# --------------------------------------------------
# lsblk: HCTL / MODEL / SERIAL read + Bay-Mapping (HDD)
# --------------------------------------------------
lsblk_scsi = {}
host_to_dev = {}
bay_mapping = {}
host_placeholder = {}
bay_count = 0

def _safe_int(val, default=None):
    try:
        return int(val)
    except Exception:
        return default

try:
    proc = subprocess.run(
        ["lsblk", "-S", "-x", "hctl", "-o", "NAME,HCTL,MODEL,SERIAL", "-J"],
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    if proc.stdout:
        data = json.loads(proc.stdout)
        for dev in data.get("blockdevices", []):
            name = dev.get("name")
            if not name:
                continue
            path = "/dev/" + name
            lsblk_scsi[path] = {
                "hctl": dev.get("hctl") or "",
                "model": dev.get("model") or "",
                "serial": dev.get("serial") or "",
            }

    configured = [d for d in internal_hdd_devices if d]
    configured_set = set(configured)
    hosts = set()

    for path, info in lsblk_scsi.items():
        if path not in configured_set:
            continue
        hctl = info.get("hctl") or ""
        host_str = hctl.split(":")[0] if ":" in hctl else ""
        host = _safe_int(host_str)
        if host is None:
            continue
        host_to_dev[host] = path
        hosts.add(host)

    if hosts:
        bay_count = max(hosts) + 1
    else:
        bay_count = len(configured)

    expected_bays = expected.get("hdd_bays")
    if isinstance(expected_bays, int) and expected_bays > bay_count:
        bay_count = expected_bays

    actual_devs = set(host_to_dev.values())
    placeholder_devs = [d for d in configured if d not in actual_devs]
    missing_hosts = [h for h in range(bay_count) if h not in host_to_dev]

    for host, dev in zip(missing_hosts, placeholder_devs):
        host_placeholder[host] = dev

    for host in range(bay_count):
        dev = host_to_dev.get(host) or host_placeholder.get(host)
        if dev:
            bay_mapping[dev] = host + 1

except Exception:
    lsblk_scsi = {}
    host_to_dev = {}
    bay_mapping = {}
    host_placeholder = {}
    bay_count = 0

# --------------------------------------------------
# NVMe Model/Serial via lsblk (Disk-Node nvmeXn1)
# --------------------------------------------------
nvme_info = {}
try:
    proc = subprocess.run(
        ["lsblk", "-d", "-J", "-o", "NAME,MODEL,SERIAL"],
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    if proc.stdout:
        data = json.loads(proc.stdout)
        for dev in data.get("blockdevices", []):
            name = dev.get("name") or ""
            if not re.match(r"^nvme\d+n\d+$", name):
                continue
            nvme_info["/dev/" + name] = {
                "model": (dev.get("model") or "").strip(),
                "serial": (dev.get("serial") or "").strip(),
            }
except Exception:
    nvme_info = {}

def drive_label(dev: str, is_nvme: bool = False) -> str:
    parts = []
    if not is_nvme:
        bay = bay_mapping.get(dev)
        if bay is not None:
            parts.append(f"{tr('Schacht', 'Bay')} {bay}")
        info = lsblk_scsi.get(dev, {})
        model = (info.get("model") or "").strip()
        serial = (info.get("serial") or "").strip()
        if model:
            parts.append(model)
        if serial:
            parts.append(serial)
    return " / ".join([p for p in parts if p])

# --------------------------------------------------
# NVMe numbering
# DXP/iDX models keep the UGOS system SSD fixed as NVME3.
# Only installed user NVMe drives are shown. Empty user slots are skipped.
# Example with one user NVMe + system SSD: NVME1, NVME3 Systemdisk
# Example with two user NVMe + system SSD: NVME1, NVME2, NVME3 Systemdisk
# --------------------------------------------------
def _nvme_sort_key(dev: str) -> int:
    m = re.match(r"^/dev/nvme(\d+)$", dev or "")
    return int(m.group(1)) if m else 999

user_nvme_devices = [d for d in nvme_devices if d != sys_nvme_ctrl]
user_nvme_devices = sorted(user_nvme_devices, key=_nvme_sort_key)
report_nvme_devices = list(user_nvme_devices)
if sys_nvme_ctrl and sys_nvme_ctrl in nvme_devices:
    report_nvme_devices.append(sys_nvme_ctrl)

def _fixed_system_nvme_slot(model: str, has_system: bool) -> int:
    if not has_system:
        return 0
    m = (model or "").upper()
    if m.startswith("DXP") or m.startswith("IDX"):
        return 3
    return len(user_nvme_devices) + 1

system_nvme_slot = _fixed_system_nvme_slot(MODEL, bool(sys_nvme_ctrl and sys_nvme_ctrl in nvme_devices))


def nvme_by_path_name(dev: str) -> str:
    """Return the stable /dev/disk/by-path name for an NVMe controller."""
    m = re.match(r"^/dev/(nvme\d+)$", dev or "")
    if not m:
        return ""
    disk_node = f"/dev/{m.group(1)}n1"
    rc, out, _ = run(
        ["bash", "-lc", "ls -1 /dev/disk/by-path/*nvme-* 2>/dev/null | grep -v part | sort"],
        timeout=5,
    )
    for path in out.splitlines():
        rc2, real, _ = run(["readlink", "-f", path], timeout=5)
        if (real or "").strip() == disk_node:
            return os.path.basename(path.strip())
    return ""


def nvme_user_label(dev: str, generic_index: int) -> str:
    """Use verified physical U.2 labels on DXP4800 GT; otherwise a safe logical label."""
    path_name = nvme_by_path_name(dev)
    if MODEL == "DXP4800GT":
        if "pci-0000:01:00.0-nvme-1" in path_name:
            return tr("U.2-Schacht 1", "U.2 Bay 1")
        if "pci-0000:02:00.0-nvme-1" in path_name:
            return tr("U.2-Schacht 2", "U.2 Bay 2")
        return tr(f"M.2-NVMe {generic_index}", f"M.2 NVMe {generic_index}")
    return f"NVME{generic_index}"

nvme_label_map = {}
user_slot_idx = 1
for dev in report_nvme_devices:
    if sys_nvme_ctrl and dev == sys_nvme_ctrl:

        nvme_label_map[dev] = (
            f"NVME{system_nvme_slot} {tr('Systemlaufwerk', 'System drive')}"
            if system_nvme_slot else tr('Systemlaufwerk', 'System drive')
        )
    else:
        nvme_label_map[dev] = nvme_user_label(dev, user_slot_idx)
        user_slot_idx += 1

def _nvme_disk_node(dev: str) -> str:
    m = re.match(r"^/dev/(nvme\d+)$", dev or "")
    if m:
        return f"/dev/{m.group(1)}n1"
    return dev or ""

def drive_label_nvme(dev: str) -> str:
    parts = [nvme_label_map.get(dev, "NVME")]
    info = nvme_info.get(_nvme_disk_node(dev), {})
    model = (info.get("model") or "").strip()
    serial = (info.get("serial") or "").strip()
    if model:
        parts.append(model)
    if serial:
        parts.append(serial)
    return " / ".join([p for p in parts if p])

# --------------------------------------------------
# SMART-Infos einsammeln
# --------------------------------------------------
def smartctl_json(args):
    try:
        proc = subprocess.run(
            ["smartctl", "-j"] + args,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        if proc.returncode != 0 and not proc.stdout:
            return None
        return json.loads(proc.stdout or "{}")
    except Exception:
        return None

def _raw_attr(attr_tbl, attr_id):
    a = attr_tbl.get(attr_id, {})
    raw = a.get("raw", {}).get("value", 0)
    try:
        return int(str(raw).split()[0])
    except Exception:
        try:
            return int(raw)
        except Exception:
            return 0

def _read_hdd(dev, label, base_note=""):
    j = smartctl_json(["-a", dev])
    if not j:
        note = base_note or tr("Keine SMART-Ausgabe", "No SMART output")
        if base_note and tr("Keine SMART-Ausgabe", "No SMART output") not in note:
            note = f"{base_note}, {tr('keine SMART-Ausgabe', 'no SMART output')}"
        return {"dev": dev, "label": label, "health": tr("Nicht verfügbar", "Not available"), "health_state": "na", "temp": "", "realloc": "", "pending": "", "uncor": "", "crc": "", "note": note}

    passed = j.get("smart_status", {}).get("passed", None)
    if passed is True:
        health = tr("BESTANDEN", "PASSED")
        health_state = "passed"
    elif passed is False:
        health = tr("FEHLER", "FAILED")
        health_state = "failed"
    else:
        health = tr("Unbekannt", "Unknown")
        health_state = "unknown"

    temp = ""
    if "temperature" in j:
        temp = j["temperature"].get("current", "")
    elif "ata_smart_attributes" in j:
        for a in j["ata_smart_attributes"].get("table", []):
            if a.get("id") == 194:
                temp = a.get("raw", {}).get("value", "")
                break

    attr_tbl = {}
    for a in j.get("ata_smart_attributes", {}).get("table", []):
        attr_tbl[a.get("id")] = a

    realloc = _raw_attr(attr_tbl, 5)
    pending = _raw_attr(attr_tbl, 197)
    uncor   = _raw_attr(attr_tbl, 198)
    crc     = _raw_attr(attr_tbl, 199)

    return {"dev": dev, "label": label, "health": health, "health_state": health_state, "temp": temp, "realloc": realloc, "pending": pending, "uncor": uncor, "crc": crc, "note": base_note or ""}

def collect_hdd():
    rows = []
    if bay_count <= 0:
        for dev in internal_hdd_devices:
            label = drive_label(dev, False)
            rows.append(_read_hdd(dev, label))
        return rows

    for host in range(bay_count):
        bay = host + 1
        dev = host_to_dev.get(host) or host_placeholder.get(host)
        if dev is None:
            rows.append({"dev": "", "label": f"{tr('Schacht', 'Bay')} {bay}", "health": tr("Kein Laufwerk", "No drive"), "health_state": "empty", "temp": "", "realloc": "", "pending": "", "uncor": "", "crc": "", "note": tr("Kein Laufwerk im Schacht", "No drive in bay")})
            continue
        label = drive_label(dev, False)
        rows.append(_read_hdd(dev, label))
    return rows

def collect_usb():
    rows = []
    for rec in usb_records:
        dev = rec["path"]
        kind = rec.get("usb_kind") or classify_usb_record(rec)
        label = drive_label(dev, False)
        note = usb_kind_note(kind)
        if kind in ("sdcard", "usb_stick"):
            rows.append({
                "dev": dev,
                "label": label,
                "health": tr("Nicht unterstützt", "Not supported"),
                "health_state": "unsupported",
                "temp": "",
                "realloc": 0,
                "pending": 0,
                "uncor": 0,
                "crc": 0,
                "note": note,
            })
            continue
        rows.append(_read_hdd(dev, label, note))
    return rows

def collect_nvme():
    rows = []
    for dev in report_nvme_devices:
        label = drive_label_nvme(dev)
        note_parts = []
        max_wait_aborted = dev in NVME_ABORTED_DRIVES
        max_wait_abort_failed = dev in NVME_ABORT_FAILED_DRIVES

        if max_wait_aborted:
            note_parts.append(tr(
                "Selbsttest vom Skript abgebrochen",
                "Self-test aborted by script"
            ))
        elif max_wait_abort_failed:
            note_parts.append(tr(
                "Selbsttest läuft noch, Abort durch Skript versucht",
                "Self-test still running, abort attempted by script"
            ))

        j = smartctl_json(["-a", "-d", "nvme", dev])
        if not j:
            note_parts.append(tr("Keine SMART-Ausgabe", "No SMART output"))
            rows.append({
                "dev": dev,
                "label": label,
                "health": tr("Nicht verfügbar", "Not available"),
                "health_state": "na",
                "temp": "",
                "life_left": "",
                "media_err": "",
                "err_log": "",
                "note": " | ".join([p for p in note_parts if p]),
                "max_wait_aborted": max_wait_aborted,
                "max_wait_abort_failed": max_wait_abort_failed,
            })
            continue

        health = "OK"
        health_state = "ok"
        crit = j.get("critical_warning", 0)
        try:
            crit_val = int(crit)
        except Exception:
            crit_val = 0
        if crit_val != 0:
            health = tr("WARNUNG", "WARNING")
            health_state = "warn"

        temp = ""
        if "temperature" in j:
            temp = j["temperature"].get("current", "")
        elif "nvme_smart_health_information_log" in j:
            temp = j["nvme_smart_health_information_log"].get("temperature", "")

        nv = j.get("nvme_smart_health_information_log", {})
        used_pct = nv.get("percentage_used", None)
        life_left = ""
        if isinstance(used_pct, (int, float)):
            life_left = max(0, 100 - int(used_pct))

        media_err = nv.get("media_errors", 0)
        err_log   = nv.get("num_err_log_entries", 0)

        rows.append({
            "dev": dev,
            "label": label,
            "health": health,
            "health_state": health_state,
            "temp": temp,
            "life_left": life_left,
            "media_err": media_err,
            "err_log": err_log,
            "note": " | ".join([p for p in note_parts if p]),
            "max_wait_aborted": max_wait_aborted,
            "max_wait_abort_failed": max_wait_abort_failed,
        })
    return rows

hdd_rows = collect_hdd()
usb_rows = collect_usb()
nvme_rows = collect_nvme()

# --------------------------------------------------
# eMMC Check
# --------------------------------------------------
emmc_rows = []
emmc_status = tr("Nicht verfügbar", "Not available")
emmc_state = "na"
emmc_note = ""
emmc_dd_summary = ""
emmc_overlay = ""
emmc_name = ""
emmc_cid = ""
emmc_errors = []

def filter_emmc_errors(lines: str):
    errs = []
    for ln in lines.splitlines():
        l = ln.lower()
        if "crc32 instructions" in l:
            continue
        if ("mmc" not in l) and ("mmcblk" not in l):
            continue
        # nur echte Fehlerindikatoren
        if re.search(r"(i/o error|timeout|crc error|blk_update_request|end_request|error -\\d+)", l):
            errs.append(ln)
    return errs

if emmc_check and emmc_present:
    # Infos
    try:
        with open("/sys/block/mmcblk0/device/name", "r") as f:
            emmc_name = f.read().strip()
    except Exception:
        emmc_name = ""
    try:
        with open("/sys/block/mmcblk0/device/cid", "r") as f:
            emmc_cid = f.read().strip()
    except Exception:
        emmc_cid = ""

    emmc_overlay = findmnt_src("/overlay")
    if not emmc_overlay.startswith("/dev/"):
        emmc_overlay = "/dev/mmcblk0p9" if os.path.exists("/dev/mmcblk0p9") else ""

    # eMMC-Lesetest / eMMC read test
    if emmc_read and emmc_overlay:
        size_bytes = 0
        rc_size, out_size, _ = run(["blockdev", "--getsize64", emmc_overlay], timeout=10)
        if rc_size == 0:
            try:
                size_bytes = int(first_line(out_size))
            except Exception:
                size_bytes = 0

        size_hint = ""
        if size_bytes > 0:
            size_hint = f" ({size_bytes / (1024 ** 3):.1f} GiB)"
        progress_log(
            f"Starte vollständigen eMMC-Lesetest auf {emmc_overlay}{size_hint}. Der Vorgang kann einige Minuten dauern ...",
            f"Starting full eMMC read test on {emmc_overlay}{size_hint}. This may take several minutes ...",
        )

        started = time.monotonic()
        try:
            proc = subprocess.run(
                ["dd", f"if={emmc_overlay}", "of=/dev/null", "bs=4M", "status=none"],
                capture_output=True,
                text=True,
                timeout=900,
                check=False,
            )
            rc = proc.returncode
        except Exception:
            rc = 999
        elapsed = max(0.001, time.monotonic() - started)

        if rc == 0:
            emmc_status = "OK"
            emmc_state = "ok"
            if size_bytes > 0:
                decimal_gb = size_bytes / 1_000_000_000
                binary_gib = size_bytes / (1024 ** 3)
                rate_mb = (size_bytes / elapsed) / 1_000_000
                emmc_dd_summary = tr(
                    f"{size_bytes} Bytes ({decimal_gb:.1f} GB, {binary_gib:.1f} GiB) gelesen, {elapsed:.3f} s, {rate_mb:.0f} MB/s",
                    f"{size_bytes} bytes ({decimal_gb:.1f} GB, {binary_gib:.1f} GiB) read, {elapsed:.3f} s, {rate_mb:.0f} MB/s",
                )
            else:
                emmc_dd_summary = tr("Lesetest erfolgreich abgeschlossen", "Read test completed successfully")
            progress_log(
                f"eMMC-Lesetest auf {emmc_overlay} erfolgreich abgeschlossen ({elapsed:.1f} Sekunden).",
                f"eMMC read test on {emmc_overlay} completed successfully ({elapsed:.1f} seconds).",
            )
        else:
            progress_log(
                f"WARNUNG: eMMC-Lesetest auf {emmc_overlay} fehlgeschlagen (dd-Exitcode {rc}).",
                f"WARNING: eMMC read test on {emmc_overlay} failed (dd exit code {rc}).",
            )
            emmc_status = tr("KRITISCH", "CRITICAL")
            emmc_state = "crit"
            emmc_note = tr(f"dd-Exitcode: {rc}", f"dd exit code: {rc}")
    else:
        if emmc_read_skipped_report_only:
            emmc_status = tr("Übersprungen", "Skipped")
            emmc_state = "skipped"
            emmc_note = tr("Im Modus „Nur Bericht“ nicht ausgeführt", "Not performed in report-only mode")
        else:
            emmc_status = tr("Deaktiviert", "Disabled")
            emmc_state = "disabled"
            emmc_note = tr("eMMC-Lesetest deaktiviert", "eMMC read test disabled")

    # Kernel errors (seit Boot)
    rc, out, _ = run(["dmesg", "-T"], timeout=10)
    emmc_errors = filter_emmc_errors(out)

elif emmc_check and not emmc_present:
    emmc_status = tr("Nicht vorhanden", "Not present")
    emmc_state = "absent"
    emmc_note = tr("Keine eMMC vorhanden", "No eMMC present")
else:
    emmc_status = tr("Deaktiviert", "Disabled")
    emmc_state = "disabled"
    emmc_note = tr("eMMC-Prüfung deaktiviert", "eMMC check disabled")

# --------------------------------------------------
# Gesamtstatus (Warnlogik)
# --------------------------------------------------
status_level = "OK"
def bump_status(new_level):
    order = {"OK": 0, "WARN": 1, "CRIT": 2}
    global status_level
    if order.get(new_level, 0) > order.get(status_level, 0):
        status_level = new_level

for r in hdd_rows + usb_rows:
    if r.get("health_state") == "failed":
        bump_status("CRIT")
        continue
    for key, thr in (("realloc", 0), ("pending", 0), ("uncor", 0)):
        v = r.get(key)
        if isinstance(v, int) and v > thr:
            bump_status("WARN")
    crc = r.get("crc")
    if isinstance(crc, int) and crc >= 100:
        bump_status("WARN")

for r in nvme_rows:
    if r.get("health_state") == "warn":
        bump_status("WARN")
    media_err = r.get("media_err")
    err_log   = r.get("err_log")
    life_left = r.get("life_left")
    if isinstance(media_err, int) and media_err >= 1:
        bump_status("WARN")
    if isinstance(err_log, int) and err_log >= 10:
        bump_status("WARN")
    if isinstance(life_left, int) and life_left <= 10:
        bump_status("WARN")
    if r.get("max_wait_aborted") or r.get("max_wait_abort_failed"):
        bump_status("WARN")

# eMMC Status einbeziehen
if emmc_check and emmc_present and emmc_read:
    if emmc_state == "crit":
        bump_status("CRIT")
if emmc_errors:
    bump_status("WARN")

if mode == "weekly-short":
    mode_label = tr("Wöchentlicher Kurztest", "Weekly short test")
elif mode == "monthly-long":
    mode_label = tr("Monatlicher Langtest", "Monthly long test")
elif mode == "report-only":
    mode_label = tr("Nur Bericht (ohne Tests)", "Report only (no tests)")
else:
    mode_label = mode

subject_tag = display_name()
report_title = tr("SMART-Bericht", "SMART report")
status_label = {
    "OK": "OK",
    "WARN": tr("WARNUNG", "WARNING"),
    "CRIT": tr("KRITISCH", "CRITICAL"),
}.get(status_level, status_level)
subject = f"[{subject_tag}] {report_title} – {mode_label} [{status_label}]"

def esc(s):
    return "" if s is None else str(s)

def td(value, highlight=False):
    base = "padding:4px 6px;border:1px solid #dddddd;font-size:12px;text-align:center;white-space:nowrap;"
    if highlight:
        base += "background-color:#ffe6e6;font-weight:bold;"
    return f'<td style=\"{base}\">{esc(value)}</td>'

html_parts = []
html_parts.append("<html><head>")
html_parts.append('<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />')
html_parts.append(f"<title>{esc(subject)}</title>")
html_parts.append('</head><body style="font-family:Segoe UI,Arial,sans-serif;font-size:13px;color:#333333;">')


html_parts.append(f'<h2 style="font-weight:600;font-size:18px;margin-bottom:4px;">{esc(tr("SMART-Bericht für", "SMART report for"))} {esc(subject_tag)}</h2>')

hdd_count = len([d for d in internal_hdd_devices if d])
usb_hdd_count = len([d for d in usb_hdd_devices if d])
usb_excluded_count = len([d for d in usb_excluded_devices if d])
nvme_count = len([d for d in nvme_devices if d])
bay_count_display = bay_count if bay_count > 0 else hdd_count

exp_hdd = expected.get("hdd_bays")
exp_nvme = expected.get("nvme")
exp_emmc = expected.get("emmc")
exp_osnv = expected.get("os_on_nvme")

html_parts.append(
    f'<p style="margin-top:0;margin-bottom:10px;">'

    f'{esc(tr("Modus", "Mode"))}: {esc(mode_label)}<br />'
    f'{esc(tr("Status", "Status"))}: <strong>{esc(status_label)}</strong><br />'
    f'{esc(tr("Zeitpunkt", "Timestamp"))}: {esc(NOW)}<br />'
    f'{esc(tr("Erkanntes Modell", "Detected model"))}: {esc(MODEL)}<br />'
    f'{esc(tr("Anzahl HDD-Schächte (ermittelt)", "Number of HDD bays (detected)"))}: {esc(bay_count_display)}'
    + (f' ({esc(tr("Modellvorgabe", "model specification"))}: {exp_hdd})' if isinstance(exp_hdd, int) else '') + '<br />'
    f'{esc(tr("Anzahl interner HDDs", "Number of internal HDDs"))}: {esc(hdd_count)}<br />'
    f'{esc(tr("USB-Laufwerke einbeziehen", "Include USB drives"))}: {esc(tr("Ja", "Yes") if include_usb else tr("Nein", "No"))}<br />'
    + (f'{esc(tr("Anzahl gefundener USB-/Wechsellaufwerke", "Number of USB/removable drives found"))}: {esc(usb_hdd_count)}<br />' if include_usb else '')
    + (f'{esc(tr("Davon ohne SMART-Selbsttest (USB-Sticks/SD-Karten)", "Without SMART self-test support (USB flash drives/SD cards)"))}: {esc(usb_excluded_count)}<br />' if include_usb and usb_hdd_count > 0 else '')
    + f'{esc(tr("Anzahl gefundener NVMe-Laufwerke", "Number of NVMe drives found"))}: {esc(nvme_count)}<br />'
    + (f'{esc(tr("Maximal unterstützte NVMe-Laufwerke", "Maximum supported NVMe drives"))}: {exp_nvme}<br />' if isinstance(exp_nvme, int) else '')
    + (f'{esc(tr("NVMe-Ausstattung", "NVMe configuration"))}: {esc(tr("2 × M.2-Steckplätze und bis zu 2 × U.2-Kombischächte", "2 × M.2 slots and up to 2 × U.2 combo bays"))}<br />' if MODEL in ("DXP2800GT", "DXP4800GT") else '')
    + f'{esc(tr("Systemlaufwerk", "System drive"))}: {esc(sys_base or tr("Unbekannt", "Unknown"))}<br />'
    f'eMMC {esc(tr("vorhanden", "present"))}: {esc(tr("Ja", "Yes") if emmc_present else tr("Nein", "No"))}'
    f'</p>'
)


html_parts.append(f'<p style="margin-bottom:12px;">{esc(tr("Dieser Bericht zeigt eine Übersicht der SMART-Werte deiner Laufwerke. Kritische Werte werden farblich hervorgehoben.", "This report shows an overview of the SMART values of your drives. Critical values are highlighted."))}</p>')

# HDD-Tabelle

html_parts.append(f'<h3 style="font-size:15px;margin-bottom:4px;margin-top:16px;">{esc(tr("HDD-Laufwerke", "HDD drives"))}</h3>')
html_parts.append('<table style="border-collapse:collapse;width:100%;max-width:1000px;">')
html_parts.append("<tr>")

for name in (
    tr("Laufwerk", "Drive"),
    tr("Zustand", "Health"),
    tr("Temperatur (°C)", "Temperature (°C)"),
    tr("Neu zugewiesen", "Reallocated"),
    tr("Ausstehend", "Pending"),
    tr("Nicht korrigierbar", "Uncorrectable"),
    "CRC",
    tr("Hinweis", "Note"),
):
    html_parts.append(f'<th style="padding:5px 7px;border:1px solid #dddddd;background-color:#f3f3f3;font-size:12px;">{name}</th>')
html_parts.append("</tr>")

if hdd_rows:
    for r in hdd_rows:
        html_parts.append("<tr>")
        html_parts.append(td(r["label"]))
        html_parts.append(td(r["health"], highlight=(r.get("health_state") == "failed")))
        html_parts.append(td(r["temp"]))
        html_parts.append(td(r["realloc"], highlight=isinstance(r["realloc"], int) and r["realloc"] > 0))
        html_parts.append(td(r["pending"], highlight=isinstance(r["pending"], int) and r["pending"] > 0))
        html_parts.append(td(r["uncor"], highlight=isinstance(r["uncor"], int) and r["uncor"] > 0))
        crc_val = r["crc"]
        html_parts.append(td(crc_val, highlight=isinstance(crc_val, int) and crc_val >= 100))
        html_parts.append(td(r["note"]))
        html_parts.append("</tr>")
else:

    html_parts.append(f'<tr><td colspan="8" style="padding:5px 7px;border:1px solid #dddddd;font-size:12px;">{esc(tr("Keine HDD-Laufwerke gefunden.", "No HDD drives found."))}</td></tr>')
html_parts.append("</table>")

# USB-/Wechsellaufwerke
if include_usb and usb_rows:

    html_parts.append(f'<h3 style="font-size:15px;margin-bottom:4px;margin-top:18px;">{esc(tr("USB-/Wechsellaufwerke", "USB/removable drives"))}</h3>')
    html_parts.append('<table style="border-collapse:collapse;width:100%;max-width:1000px;">')
    html_parts.append("<tr>")

    for name in (
        tr("Laufwerk", "Drive"),
        tr("Zustand", "Health"),
        tr("Temperatur (°C)", "Temperature (°C)"),
        tr("Neu zugewiesen", "Reallocated"),
        tr("Ausstehend", "Pending"),
        tr("Nicht korrigierbar", "Uncorrectable"),
        "CRC",
        tr("Hinweis", "Note"),
    ):
        html_parts.append(f'<th style="padding:5px 7px;border:1px solid #dddddd;background-color:#f3f3f3;font-size:12px;">{name}</th>')
    html_parts.append("</tr>")

    for r in usb_rows:
        html_parts.append("<tr>")
        html_parts.append(td(r["label"]))
        html_parts.append(td(r["health"], highlight=(r.get("health_state") == "failed")))
        html_parts.append(td(r["temp"]))
        html_parts.append(td(r["realloc"], highlight=isinstance(r["realloc"], int) and r["realloc"] > 0))
        html_parts.append(td(r["pending"], highlight=isinstance(r["pending"], int) and r["pending"] > 0))
        html_parts.append(td(r["uncor"], highlight=isinstance(r["uncor"], int) and r["uncor"] > 0))
        crc_val = r["crc"]
        html_parts.append(td(crc_val, highlight=isinstance(crc_val, int) and crc_val >= 100))
        html_parts.append(td(r["note"]))
        html_parts.append("</tr>")
    html_parts.append("</table>")

# NVMe-Tabelle
if nvme_rows:

    html_parts.append(f'<h3 style="font-size:15px;margin-bottom:4px;margin-top:18px;">{esc(tr("NVMe-Laufwerke", "NVMe drives"))}</h3>')
    html_parts.append('<table style="border-collapse:collapse;width:100%;max-width:1000px;">')
    html_parts.append("<tr>")

    for name in (
        tr("Laufwerk", "Drive"),
        tr("Zustand", "Health"),
        tr("Temperatur (°C)", "Temperature (°C)"),
        tr("Restlebensdauer (%)", "Remaining life (%)"),
        tr("Medienfehler", "Media errors"),
        tr("Fehlerprotokolleinträge", "Error log entries"),
        tr("Hinweis", "Note"),
    ):
        html_parts.append(f'<th style="padding:5px 7px;border:1px solid #dddddd;background-color:#f3f3f3;font-size:12px;">{name}</th>')
    html_parts.append("</tr>")

    for r in nvme_rows:
        html_parts.append("<tr>")
        html_parts.append(td(r["label"]))
        html_parts.append(td(r["health"], highlight=(r.get("health_state") == "warn")))
        html_parts.append(td(r["temp"]))
        life_left = r["life_left"]
        html_parts.append(td(life_left, highlight=isinstance(life_left, int) and life_left <= 10))
        media_err = r["media_err"]
        html_parts.append(td(media_err, highlight=isinstance(media_err, int) and media_err >= 1))
        err_log = r["err_log"]
        html_parts.append(td(err_log, highlight=isinstance(err_log, int) and err_log >= 10))
        html_parts.append(td(r["note"]))
        html_parts.append("</tr>")
    html_parts.append("</table>")

# eMMC Abschnitt
if emmc_check and emmc_present:

    html_parts.append(f'<h3 style="font-size:15px;margin-bottom:4px;margin-top:18px;">{esc(tr("System (eMMC)", "System (eMMC)"))}</h3>')
    html_parts.append('<table style="border-collapse:collapse;width:100%;max-width:1000px;">')
    html_parts.append("<tr>")

    for name in (
        tr("Gerät", "Device"),
        tr("Name", "Name"),
        "CID",
        tr("Overlay-Gerät", "Overlay device"),
        tr("Lesetest", "Read test"),
        tr("dd-Zusammenfassung", "dd summary"),
        tr("Kernel-Fehler", "Kernel errors"),
    ):
        html_parts.append(f'<th style="padding:5px 7px;border:1px solid #dddddd;background-color:#f3f3f3;font-size:12px;">{name}</th>')
    html_parts.append("</tr>")

    kerr = "<br/>".join(esc(e) for e in emmc_errors[:5]) if emmc_errors else ""
    html_parts.append("<tr>")
    html_parts.append(td("/dev/mmcblk0" if emmc_present else "N/A"))
    html_parts.append(td(emmc_name or ""))
    html_parts.append(td(emmc_cid or ""))
    html_parts.append(td(emmc_overlay or ""))
    html_parts.append(td(emmc_status, highlight=(emmc_state == "crit")))
    html_parts.append(td(emmc_dd_summary or emmc_note or ""))
    html_parts.append(td(kerr, highlight=bool(emmc_errors)))
    html_parts.append("</tr>")
    html_parts.append("</table>")


html_parts.append(f'<p style="margin-top:18px;font-size:11px;color:#777777;">{esc(tr("Hinweis", "Note"))}: {esc(tr("Dieser Bericht wurde automatisch vom Skript ugreen-smart-report.sh erstellt", "This report was generated automatically by the script ugreen-smart-report.sh"))} v{SCRIPT_VERSION}.</p>')
html_parts.append("</body></html>")

html_body = "".join(html_parts)

msg = MIMEText(html_body, "html", "utf-8")
msg["Subject"] = subject
msg["From"] = MAIL_FROM
msg["To"] = MAIL_TO

if DEBUG_REPORT_MAIL:
    print(f"DEBUG_REPORT: subject={subject}", flush=True)
    print(f"DEBUG_REPORT: from={MAIL_FROM} to={MAIL_TO}", flush=True)
    print(f"DEBUG_REPORT: sys_base={sys_base}", flush=True)
    print(f"DEBUG_REPORT: sys_nvme_ctrl={sys_nvme_ctrl}", flush=True)
    print(f"DEBUG_REPORT: report_nvme_devices={report_nvme_devices}", flush=True)
    print(f"DEBUG_REPORT: nvme_label_map={nvme_label_map}", flush=True)
    print(f"DEBUG_REPORT: html_bytes={len(html_body.encode('utf-8'))}", flush=True)
    print(f"DEBUG_REPORT: mime_bytes={len(msg.as_bytes())}", flush=True)

if DEBUG_SAVE_REPORT_HTML:
    try:
        os.makedirs(DEBUG_REPORT_DUMP_DIR, exist_ok=True)
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        html_path = os.path.join(DEBUG_REPORT_DUMP_DIR, f"ugreen-smart-report_{ts}.html")
        eml_path = os.path.join(DEBUG_REPORT_DUMP_DIR, f"ugreen-smart-report_{ts}.eml")
        with open(html_path, "w", encoding="utf-8") as f:
            f.write(html_body)
        with open(eml_path, "wb") as f:
            f.write(msg.as_bytes())
        print(f"DEBUG_REPORT: saved_html={html_path}", flush=True)
        print(f"DEBUG_REPORT: saved_eml={eml_path}", flush=True)
    except Exception as dump_exc:
        print("DEBUG_REPORT: dump_failed:", dump_exc, flush=True)

try:
    if SMTP_USE_SSL:
        with smtplib.SMTP_SSL(SMTP_SERVER, SMTP_PORT, timeout=30) as server:
            if DEBUG_SMTP:
                server.set_debuglevel(1)
            if SMTP_USER:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
    else:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT, timeout=30) as server:
            if DEBUG_SMTP:
                server.set_debuglevel(1)
            if SMTP_USE_TLS:
                server.starttls()
            if SMTP_USER:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
    print(tr("E-Mail erfolgreich gesendet.", "Email sent successfully."))
    if DEBUG_REPORT_MAIL:
        print("DEBUG_REPORT: message submitted successfully", flush=True)
except Exception as e:
    import traceback
    print(tr("Fehler beim E-Mail-Versand:", "Error sending email:"), e)
    if DEBUG_SMTP:
        traceback.print_exc()
    sys.exit(1)
PYEOF
  rc=$?
  if [ "$rc" -ne 0 ]; then
    log "$(tr_text "ERROR: Report-Mail fehlgeschlagen (Python Exit Code: ${rc})." "ERROR: Report email failed (Python exit code: ${rc}).")"
    return "$rc"
  fi
  log "$(tr_text "Report-Mail erfolgreich gesendet." "Report email sent successfully.")"
}

send_test_mail_python() {
  local raw_model model_override custom_name rc
  raw_model="$(get_raw_model_string)"
  model_override="${NAS_MODEL_OVERRIDE}"
  custom_name="${NAS_CUSTOM_NAME}"
  if is_en; then
    "$PYTHON_BIN" -u - "$raw_model" "$model_override" "$custom_name" <<'PYEOF'
import smtplib, datetime, sys, re, os
from email.mime.text import MIMEText

raw_model = sys.argv[1] or ""
model_override = sys.argv[2] or ""
custom_name = sys.argv[3] or ""

SMTP_SERVER = os.environ.get("SMTP_SERVER", "")
SMTP_PORT   = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER   = os.environ.get("SMTP_USER", "")
SMTP_PASS   = os.environ.get("SMTP_PASS", "")
MAIL_FROM   = os.environ.get("MAIL_FROM", "")
MAIL_TO     = os.environ.get("MAIL_TO", "")
SCRIPT_VERSION = os.environ.get("SCRIPT_VERSION", "")
LANGUAGE = os.environ.get("LANGUAGE", "de")
SMTP_USE_TLS = os.environ.get("SMTP_USE_TLS", "true").lower() == "true"
SMTP_USE_SSL = os.environ.get("SMTP_USE_SSL", "false").lower() == "true"
DEBUG_SMTP = os.environ.get("DEBUG_SMTP", "false").lower() == "true"

def normalize_model(raw: str) -> str:
    r = (raw or "").upper().replace("UGREEN", " ").replace("/", " ")
    r = re.sub(r"\s+", " ", r).strip()
    if model_override.strip():
        return model_override.strip().upper()
    tokens = r.replace(" ", "")
    for k in ("DXP480TPLUS","DXP8800ULTRA","DXP8800PRO","DXP8800PLUS","DXP6800ULTRA","DXP6800PRO","DXP6800PLUS","DXP4800GT","DXP4800PRO","DXP4800PLUS","DXP4800","DXP2800GT","DXP2800","IDX6011PRO","IDX6011","DH4300PLUS","DH2300","DX4700"):
        if k in tokens:
            return k
    m = re.search(r"(IDX[0-9]{4}PRO|IDX[0-9]{4}|DH[0-9]{4}PLUS|DH[0-9]{4}|DXP[0-9]{4}ULTRA|DXP[0-9]{4}GT|DXP[0-9]{4}T?PLUS|DXP[0-9]{4}PRO|DXP[0-9]{4}|DX[0-9]{4})", tokens)
    return m.group(1) if m else "UGREEN"

MODEL = normalize_model(raw_model)
tag = f"{MODEL} - {custom_name.strip()}" if custom_name.strip() else MODEL

now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
subject = f"[{tag}] TEST: SMART email notification"
html_body = f"""<html><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>{subject}</title>
</head><body style="font-family:Segoe UI,Arial,sans-serif;font-size:13px;color:#333333;">
<h2 style="font-weight:600;font-size:18px;margin-bottom:4px;">Test email from SMART script</h2>
<p style="margin-top:0;margin-bottom:10px;">
This message confirms that email sending from the script ugreen-smart-report.sh v{SCRIPT_VERSION} works.<br />
Detected model: {MODEL}<br />
Timestamp: {now}
</p>
<p style="font-size:12px;color:#777777;">
If you received this email, your email configuration is working.
</p>
</body></html>"""

msg = MIMEText(html_body, "html", "utf-8")
msg["Subject"] = subject
msg["From"] = MAIL_FROM
msg["To"] = MAIL_TO

try:
    if SMTP_USE_SSL:
        with smtplib.SMTP_SSL(SMTP_SERVER, SMTP_PORT, timeout=30) as server:
            if DEBUG_SMTP:
                server.set_debuglevel(1)
            if SMTP_USER:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
    else:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT, timeout=30) as server:
            if DEBUG_SMTP:
                server.set_debuglevel(1)
            if SMTP_USE_TLS:
                server.starttls()
            if SMTP_USER:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
    print("Test email sent successfully.")
except Exception as e:
    import traceback
    print("Error sending test email:", e)
    if DEBUG_SMTP:
        traceback.print_exc()
    sys.exit(1)
PYEOF
  else
    "$PYTHON_BIN" -u - "$raw_model" "$model_override" "$custom_name" <<'PYEOF'
import smtplib, datetime, sys, re, os
from email.mime.text import MIMEText

raw_model = sys.argv[1] or ""
model_override = sys.argv[2] or ""
custom_name = sys.argv[3] or ""

SMTP_SERVER = os.environ.get("SMTP_SERVER", "")
SMTP_PORT   = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER   = os.environ.get("SMTP_USER", "")
SMTP_PASS   = os.environ.get("SMTP_PASS", "")
MAIL_FROM   = os.environ.get("MAIL_FROM", "")
MAIL_TO     = os.environ.get("MAIL_TO", "")
SCRIPT_VERSION = os.environ.get("SCRIPT_VERSION", "")
LANGUAGE = os.environ.get("LANGUAGE", "de")
SMTP_USE_TLS = os.environ.get("SMTP_USE_TLS", "true").lower() == "true"
SMTP_USE_SSL = os.environ.get("SMTP_USE_SSL", "false").lower() == "true"
DEBUG_SMTP = os.environ.get("DEBUG_SMTP", "false").lower() == "true"

def normalize_model(raw: str) -> str:
    r = (raw or "").upper().replace("UGREEN", " ").replace("/", " ")
    r = re.sub(r"\s+", " ", r).strip()
    if model_override.strip():
        return model_override.strip().upper()
    tokens = r.replace(" ", "")
    for k in ("DXP480TPLUS","DXP8800ULTRA","DXP8800PRO","DXP8800PLUS","DXP6800ULTRA","DXP6800PRO","DXP6800PLUS","DXP4800GT","DXP4800PRO","DXP4800PLUS","DXP4800","DXP2800GT","DXP2800","IDX6011PRO","IDX6011","DH4300PLUS","DH2300","DX4700"):
        if k in tokens:
            return k
    m = re.search(r"(IDX[0-9]{4}PRO|IDX[0-9]{4}|DH[0-9]{4}PLUS|DH[0-9]{4}|DXP[0-9]{4}ULTRA|DXP[0-9]{4}GT|DXP[0-9]{4}T?PLUS|DXP[0-9]{4}PRO|DXP[0-9]{4}|DX[0-9]{4})", tokens)
    return m.group(1) if m else "UGREEN"

MODEL = normalize_model(raw_model)
tag = f"{MODEL} - {custom_name.strip()}" if custom_name.strip() else MODEL

now = datetime.datetime.now().strftime("%d.%m.%Y %H:%M:%S")
subject = f"[{tag}] TEST: SMART-Mailbenachrichtigung"
html_body = f"""<html><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>{subject}</title>
</head><body style="font-family:Segoe UI,Arial,sans-serif;font-size:13px;color:#333333;">
<h2 style="font-weight:600;font-size:18px;margin-bottom:4px;">Test-E-Mail vom SMART-Skript</h2>
<p style="margin-top:0;margin-bottom:10px;">
Diese Nachricht bestätigt, dass der E-Mail-Versand vom Skript ugreen-smart-report.sh v{SCRIPT_VERSION} funktioniert.<br />
Erkanntes Modell: {MODEL}<br />
Zeitpunkt: {now}
</p>
<p style="font-size:12px;color:#777777;">
Wenn diese E-Mail angekommen ist, ist die Mailkonfiguration in Ordnung.
</p>
</body></html>"""

msg = MIMEText(html_body, "html", "utf-8")
msg["Subject"] = subject
msg["From"] = MAIL_FROM
msg["To"] = MAIL_TO

try:
    if SMTP_USE_SSL:
        with smtplib.SMTP_SSL(SMTP_SERVER, SMTP_PORT, timeout=30) as server:
            if DEBUG_SMTP:
                server.set_debuglevel(1)
            if SMTP_USER:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
    else:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT, timeout=30) as server:
            if DEBUG_SMTP:
                server.set_debuglevel(1)
            if SMTP_USE_TLS:
                server.starttls()
            if SMTP_USER:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
    print("Test-E-Mail erfolgreich gesendet.")
except Exception as e:
    import traceback
    print("Fehler beim Versand der Test-E-Mail:", e)
    if DEBUG_SMTP:
        traceback.print_exc()
    sys.exit(1)
PYEOF
  fi
  rc=$?
  if [ "$rc" -ne 0 ]; then
    log "$(tr_text "ERROR: Test-Mail fehlgeschlagen (Python Exit Code: ${rc})." "ERROR: Test email failed (Python exit code: ${rc}).")"
    return "$rc"
  fi
  log "$(tr_text "Test-Mail erfolgreich gesendet." "Test email sent successfully.")"
}

require_root
detect_python
setup_logging
export SMTP_SERVER SMTP_PORT SMTP_USER SMTP_PASS MAIL_FROM MAIL_TO SMTP_USE_TLS SMTP_USE_SSL SCRIPT_VERSION DEBUG_SMTP DEBUG_REPORT_MAIL DEBUG_SAVE_REPORT_HTML DEBUG_REPORT_DUMP_DIR INCLUDE_USB_DRIVES LOG_FILE LANGUAGE

detect_all_drives
build_drive_label_cache
MODE="monthly-long"
case "${1:-}" in
  "" )
    MODE="monthly-long"
    ;;
  --help|-h|--)
    show_help
    exit 0
    ;;
  --weekly-short)
    MODE="weekly-short"
    ;;
  --monthly-long)
    MODE="monthly-long"
    ;;
  --report-only)
    MODE="report-only"
    ;;
  --test-mail)
    log "$(tr_text 'Sende Test-Mail ...' 'Sending test email ...')"
    if ! send_test_mail_python; then
      log "$(tr_text 'ERROR: Test-Mail fehlgeschlagen.' 'ERROR: Test email failed.')"
      exit 1
    fi
    exit 0
    ;;
  *)
    echo "$(tr_text "Unbekannte Option: ${1}" "Unknown option: ${1}")"
    echo
    show_help
    exit 1
    ;;
esac
log "$(tr_text "Starte UGREEN SMART Report Skript v${SCRIPT_VERSION}." "Starting UGREEN SMART report script v${SCRIPT_VERSION}.")"
log "$(tr_text "USB-Laufwerke einbeziehen: ${INCLUDE_USB_DRIVES}" "Include USB drives: ${INCLUDE_USB_DRIVES}")"
log "$(tr_text "SMTP-Debug aktiv: ${DEBUG_SMTP}" "SMTP debug enabled: ${DEBUG_SMTP}")"
log "$(tr_text "Report-Debug aktiv: ${DEBUG_REPORT_MAIL}" "Report debug enabled: ${DEBUG_REPORT_MAIL}")"
log "$(tr_text "Report-Dump aktiv: ${DEBUG_SAVE_REPORT_HTML}" "Report dump enabled: ${DEBUG_SAVE_REPORT_HTML}")"
log "$(tr_text "Laufende Tests vor einem neuen Testlauf abbrechen: ${ABORT_RUNNING_TESTS_BEFORE_START}" "Abort running tests before starting a new test run: ${ABORT_RUNNING_TESTS_BEFORE_START}")"
log "$(tr_text "Maximale NVMe-Wartezeit Short: ${NVME_MAX_WAIT_SHORT_MIN} Minuten" "Maximum NVMe wait time short: ${NVME_MAX_WAIT_SHORT_MIN} minutes")"
log "$(tr_text "Maximale NVMe-Wartezeit Long: ${NVME_MAX_WAIT_LONG_MIN} Minuten" "Maximum NVMe wait time long: ${NVME_MAX_WAIT_LONG_MIN} minutes")"
log "$(tr_text "NVMe-Stillstandserkennung aktiv: ${NVME_STALL_DETECTION}" "NVMe stall detection enabled: ${NVME_STALL_DETECTION}")"
log "$(tr_text "NVMe-Stillstand Short: ab ${NVME_STALL_MIN_ELAPSED_SHORT_MIN} Minuten und ${NVME_STALL_POLLS_SHORT} gleichen Polls" "NVMe stall short: from ${NVME_STALL_MIN_ELAPSED_SHORT_MIN} minutes and ${NVME_STALL_POLLS_SHORT} identical polls")"
log "$(tr_text "NVMe-Stillstand Long: ab ${NVME_STALL_MIN_ELAPSED_LONG_MIN} Minuten und ${NVME_STALL_POLLS_LONG} gleichen Polls" "NVMe stall long: from ${NVME_STALL_MIN_ELAPSED_LONG_MIN} minutes and ${NVME_STALL_POLLS_LONG} identical polls")"
log "$(tr_text "Gefundene interne HDDs: ${#INTERNAL_HDD_DRIVES[@]} -> $(format_device_list "${INTERNAL_HDD_DRIVES[@]}")" "Detected internal HDDs: ${#INTERNAL_HDD_DRIVES[@]} -> $(format_device_list "${INTERNAL_HDD_DRIVES[@]}")")"
if is_true "$INCLUDE_USB_DRIVES"; then
  log "$(tr_text "Gefundene USB-/Wechsellaufwerke: ${#USB_HDD_DRIVES[@]} -> $(format_device_list "${USB_HDD_DRIVES[@]}")" "Detected USB/removable drives: ${#USB_HDD_DRIVES[@]} -> $(format_device_list "${USB_HDD_DRIVES[@]}")")"
  log "$(tr_text "Davon ohne SMART-Selbsttest (USB-Sticks/SD-Karten): ${#USB_EXCLUDED_DRIVES[@]} -> $(format_device_list "${USB_EXCLUDED_DRIVES[@]}")" "Of these without SMART self-test (USB flash drives/SD cards): ${#USB_EXCLUDED_DRIVES[@]} -> $(format_device_list "${USB_EXCLUDED_DRIVES[@]}")")"
fi
log "$(tr_text "Für SMART-Tests berücksichtigte HDDs: ${#HDD_DRIVES[@]} -> $(format_device_list "${HDD_DRIVES[@]}")" "HDDs considered for SMART tests: ${#HDD_DRIVES[@]} -> $(format_device_list "${HDD_DRIVES[@]}")")"
log "$(tr_text "Gefundene NVMe: ${#NVME_DRIVES[@]} -> $(format_device_list "${NVME_DRIVES[@]}")" "Detected NVMe: ${#NVME_DRIVES[@]} -> $(format_device_list "${NVME_DRIVES[@]}")")"
log "RAW Model String: $(get_raw_model_string)"

if [ "$MODE" = "weekly-short" ]; then
  if ! abort_if_running_tests_exist weekly-short; then
    log "$(tr_text 'Abbruch: Es läuft bereits ein SMART-Test. Weekly-Short wird nicht neu gestartet.' 'Aborting: A SMART test is already running. Weekly short test will not be started again.')"
    exit 2
  fi
  log "$(tr_text 'Starte wöchentlichen SMART-Kurztest (Mode: weekly-short).' 'Starting weekly SMART short test (mode: weekly-short).')"
  start_smart_tests short
  wait_for_tests short
  if ! send_smart_report_python weekly-short; then
    log "$(tr_text 'ERROR: Weekly-Report fehlgeschlagen.' 'ERROR: Weekly report failed.')"
    exit 1
  fi
  log "$(tr_text 'Weekly-Short abgeschlossen.' 'Weekly short test completed.')"
elif [ "$MODE" = "report-only" ]; then
  log "$(tr_text 'Starte reinen Reportlauf ohne neue SMART-Tests (Mode: report-only).' 'Starting report-only run without starting new SMART tests (mode: report-only).')"
  if ! send_smart_report_python report-only; then
    log "$(tr_text 'ERROR: Report-Only fehlgeschlagen.' 'ERROR: Report-only run failed.')"
    exit 1
  fi
  log "$(tr_text 'Report-Only abgeschlossen.' 'Report-only completed.')"
else
  if ! abort_if_running_tests_exist monthly-long; then
    log "$(tr_text 'Abbruch: Es läuft bereits ein SMART-Test. Monthly-Long wird nicht neu gestartet.' 'Aborting: A SMART test is already running. Monthly long test will not be started again.')"
    exit 2
  fi
  log "$(tr_text 'Starte monatlichen SMART-Langtest (Mode: monthly-long).' 'Starting monthly SMART long test (mode: monthly-long).')"
  start_smart_tests long
  wait_for_tests long
  if ! send_smart_report_python monthly-long; then
    log "$(tr_text 'ERROR: Monthly-Report fehlgeschlagen.' 'ERROR: Monthly report failed.')"
    exit 1
  fi
  log "$(tr_text 'Monthly-Long abgeschlossen.' 'Monthly long test completed.')"
  if [ "$SHUTDOWN_AFTER_LONG" = "true" ]; then
    log "$(tr_text 'SHUTDOWN_AFTER_LONG=true → System wird heruntergefahren.' 'SHUTDOWN_AFTER_LONG=true → shutting down the system.')"
    shutdown -h now || true
  fi
fi
