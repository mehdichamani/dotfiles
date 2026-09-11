#!/usr/bin/env bash
# ==============================================================================
# Btrfs Live Backup & 15-Day Incremental Cycle Manager
# ==============================================================================
# Docs: ~/Notes/Tech/Linux/Btrfs-Backup.md
# Workspace Source: ~/.local/share/chezmoi/dot_config/scripts/executable_btrfs-backup.sh
# Target: ~/.config/scripts/btrfs-backup.sh
#
# Features:
#   - Automatic drive detection & smart automount checking (UUID based)
#   - 15-day cycle retention (Day 1 Full, Days 2-14 Incremental via 'btrfs send -p')
#   - Full backup of /boot partition and NVRAM EFI boot entries
#   - 24-hour cooldown prevention (with --force bypass)
#   - Safe pruning of previous cycles only after 100% successful new full backup
#   - JSON status reporting for Omarchy Shell widget & live monitoring
#   - Safe drive ejection helper
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration & Constants
# ------------------------------------------------------------------------------
readonly BACKUP_UUID="33a3cf69-9264-4d71-8d96-16dc1a72b39a"
readonly BACKUP_MOUNT="/mnt/tuf_backup"
readonly SNAPSHOT_DIR="${BACKUP_MOUNT}/snapshots"
readonly BOOT_BACKUP_DIR="${BACKUP_MOUNT}/boot_backups"
readonly LOCAL_SNAP_DIR="/.snapshots"
readonly STATE_FILE="${BACKUP_MOUNT}/backup_state.json"
# Ensure state directory is in the real user home even when executed via sudo/root
if [[ -n "${SUDO_USER:-}" ]]; then
    readonly USER_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
elif [[ $EUID -eq 0 && "${HOME:-}" == "/root" ]]; then
    readonly USER_HOME="$(getent passwd 1000 | cut -d: -f6)"
else
    readonly USER_HOME="${HOME:-$(getent passwd 1000 | cut -d: -f6)}"
fi
readonly STATUS_STATE_DIR="${USER_HOME}/.local/state/btrfs-backup"
readonly STATUS_JSON="${STATUS_STATE_DIR}/status.json"
readonly LOG_FILE="/var/log/btrfs-backup.log"
readonly MAX_CYCLE_DAYS=15
readonly COOLDOWN_SECONDS=86400  # 24 hours

# Source subvolumes
readonly ROOT_MOUNT="/"
readonly HOME_MOUNT="/home"

# Flags
FORCE_RUN=false
DRY_RUN=false
STATUS_ONLY=false
PROBE_ONLY=false
EJECT_ONLY=false

# ------------------------------------------------------------------------------
# Logging & Output Helpers
# ------------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "${msg}"
    if [[ -w "$(dirname "${LOG_FILE}")" ]] || [[ $EUID -eq 0 ]]; then
        echo "${msg}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# ------------------------------------------------------------------------------
# Desktop Notification Helper (Wayland / Systemd / Multi-user safe)
# ------------------------------------------------------------------------------
notify_desktop() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}" # low, normal, critical
    local icon="${4:-drive-harddisk}"

    local target_user="${SUDO_USER:-unreal}"
    if [[ -z "${target_user}" || "${target_user}" == "root" ]]; then
        target_user=$(who | awk '$2 ~ /tty|pts/ {print $1}' | head -n 1)
        [[ -z "${target_user}" ]] && target_user="unreal"
    fi
    local target_uid
    target_uid=$(id -u "${target_user}" 2>/dev/null || echo 1000)
    local bus_addr="unix:path=/run/user/${target_uid}/bus"

    if command -v notify-send >/dev/null 2>&1; then
        if [[ $EUID -eq 0 && -n "${target_user}" && "${target_user}" != "root" ]]; then
            sudo -u "${target_user}" \
                DBUS_SESSION_BUS_ADDRESS="${bus_addr}" \
                XDG_RUNTIME_DIR="/run/user/${target_uid}" \
                notify-send -a "Btrfs Backup" -u "${urgency}" -i "${icon}" "${title}" "${message}" 2>/dev/null || true
        else
            notify-send -a "Btrfs Backup" -u "${urgency}" -i "${icon}" "${title}" "${message}" 2>/dev/null || true
        fi
    fi
}

# ------------------------------------------------------------------------------
# JSON Status Helper
# ------------------------------------------------------------------------------
update_status_json() {
    local status="${1:-idle}"
    local message="${2:-}"
    local backup_type="${3:-unknown}"
    local cycle_day="${4:-0}"
    local cycle_id="${5:-unknown}"

    local disk_mounted="false"
    local storage_used=0
    local storage_avail=0
    local storage_used_h="0B"
    local storage_avail_h="0B"
    local total_snaps=0

    # Detect if drive partition is connected
    local dev_part
    dev_part=$(blkid -U "${BACKUP_UUID}" 2>/dev/null || true)
    local is_connected="false"
    [[ -n "${dev_part}" ]] && is_connected="true"

    # Find active mountpoint if any
    local active_mount=""
    if [[ -n "${dev_part}" ]]; then
        active_mount=$(findmnt -rn -t btrfs -S "${dev_part}" -o TARGET 2>/dev/null | head -n 1 || true)
    fi

    if [[ -n "${active_mount}" && -d "${active_mount}" ]]; then
        disk_mounted="true"
        # Read storage usage in bytes
        if command -v df >/dev/null 2>&1; then
            storage_used=$(df -B1 "${active_mount}" 2>/dev/null | awk 'NR==2 {print $3}' || echo 0)
            storage_avail=$(df -B1 "${active_mount}" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
            storage_used_h=$(df -h "${active_mount}" 2>/dev/null | awk 'NR==2 {print $3}' || echo "0B")
            storage_avail_h=$(df -h "${active_mount}" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0B")
        fi
        if [[ -d "${active_mount}/snapshots" ]] && [[ -r "${active_mount}/snapshots" ]]; then
            total_snaps=$(find "${active_mount}/snapshots" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l || echo 0)
        fi
        if [[ ${total_snaps} -eq 0 ]] && [[ -f "${active_mount}/status.json" ]] && command -v jq >/dev/null 2>&1; then
            total_snaps=$(jq -r '.total_snapshots // 0' "${active_mount}/status.json" 2>/dev/null || echo 0)
        fi
    elif [[ -f "${STATUS_JSON}" ]] && command -v jq >/dev/null 2>&1; then
        # Preserve cached values when unmounted
        storage_used=$(jq -r '.storage_used_bytes // 0' "${STATUS_JSON}" 2>/dev/null || echo 0)
        storage_avail=$(jq -r '.storage_avail_bytes // 0' "${STATUS_JSON}" 2>/dev/null || echo 0)
        storage_used_h=$(jq -r '.storage_used_human // "0B"' "${STATUS_JSON}" 2>/dev/null || echo "0B")
        storage_avail_h=$(jq -r '.storage_avail_human // "0B"' "${STATUS_JSON}" 2>/dev/null || echo "0B")
        total_snaps=$(jq -r '.total_snapshots // 0' "${STATUS_JSON}" 2>/dev/null || echo 0)
        if [[ "${cycle_day}" -eq 0 ]]; then
            cycle_day=$(jq -r '.cycle_day // 0' "${STATUS_JSON}" 2>/dev/null || echo 0)
        fi
        if [[ "${cycle_id}" == "unknown" || "${cycle_id}" == "none" ]]; then
            cycle_id=$(jq -r '.cycle_id // "none"' "${STATUS_JSON}" 2>/dev/null || echo "none")
        fi
        if [[ "${backup_type}" == "unknown" || "${backup_type}" == "none" ]]; then
            backup_type=$(jq -r '.last_backup_type // "none"' "${STATUS_JSON}" 2>/dev/null || echo "none")
        fi
    fi

    local last_ts="null"
    if [[ -n "${active_mount}" ]]; then
        if [[ -f "${active_mount}/backup_state.json" ]] && command -v jq >/dev/null 2>&1; then
            last_ts=$(jq -r '.last_success_timestamp // empty' "${active_mount}/backup_state.json" 2>/dev/null || echo "null")
        elif [[ -f "${active_mount}/status.json" ]] && command -v jq >/dev/null 2>&1; then
            last_ts=$(jq -r '.last_success_timestamp // empty' "${active_mount}/status.json" 2>/dev/null || echo "null")
        fi
    elif [[ -f "${STATUS_JSON}" ]] && command -v jq >/dev/null 2>&1; then
        last_ts=$(jq -r '.last_success_timestamp // empty' "${STATUS_JSON}" 2>/dev/null || echo "null")
    fi

    local json_payload
    json_payload=$(cat <<EOF
{
  "status": "${status}",
  "message": "${message}",
  "last_backup_type": "${backup_type}",
  "cycle_day": ${cycle_day:-0},
  "cycle_id": "${cycle_id:-unknown}",
  "total_snapshots": ${total_snaps:-0},
  "backup_disk_uuid": "${BACKUP_UUID}",
  "backup_disk_connected": ${is_connected},
  "backup_disk_mounted": ${disk_mounted},
  "mount_point": "${active_mount}",
  "storage_used_bytes": ${storage_used:-0},
  "storage_avail_bytes": ${storage_avail:-0},
  "storage_used_human": "${storage_used_h:-0B}",
  "storage_avail_human": "${storage_avail_h:-0B}",
  "last_success_timestamp": ${last_ts:-null},
  "updated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
)

    # Persist atomically to ~/.local/state/btrfs-backup/status.json
    mkdir -p "${STATUS_STATE_DIR}" 2>/dev/null || true
    echo "${json_payload}" > "${STATUS_JSON}.tmp" 2>/dev/null && mv -f "${STATUS_JSON}.tmp" "${STATUS_JSON}" 2>/dev/null || true
    chmod 644 "${STATUS_JSON}" 2>/dev/null || true
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        chown -R "${SUDO_USER}:" "${STATUS_STATE_DIR}" 2>/dev/null || true
    fi
    
    # If backup partition is mounted and writable, keep a copy there too
    if [[ -n "${active_mount}" && -d "${active_mount}" && -w "${active_mount}" ]]; then
        echo "${json_payload}" > "${active_mount}/status.json.tmp" 2>/dev/null && mv -f "${active_mount}/status.json.tmp" "${active_mount}/status.json" 2>/dev/null || true
    fi

    echo "${json_payload}"
}

# ------------------------------------------------------------------------------
# Check Privileges
# ------------------------------------------------------------------------------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (or via sudo)."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Safe Eject All Partitions of External Drive
# ------------------------------------------------------------------------------
safe_eject_drive() {
    require_root
    log_info "Initiating safe eject for backup drive (${BACKUP_UUID})..."

    # Find the parent disk device for this UUID
    local dev_part
    dev_part=$(blkid -U "${BACKUP_UUID}" 2>/dev/null || true)
    if [[ -z "${dev_part}" ]]; then
        log_warn "Backup partition with UUID ${BACKUP_UUID} was not found."
        echo "Drive is not connected or already removed."
        notify_desktop "Drive Not Found" "Backup drive is not connected or already removed." "low" "drive-harddisk"
        exit 0
    fi

    local parent_disk
    parent_disk=$(lsblk -no PKNAME "${dev_part}" 2>/dev/null || true)
    if [[ -z "${parent_disk}" ]]; then
        parent_disk=$(basename "${dev_part}" | sed 's/[0-9]*$//')
    fi

    local target_disk="/dev/${parent_disk}"
    log_info "Found parent block device: ${target_disk}"

    # Sync any pending writes
    sync

    # Stop systemd automount & mount units to prevent immediate auto-remounting
    systemctl stop mnt-tuf_backup.automount 2>/dev/null || true
    systemctl stop mnt-tuf_backup.mount 2>/dev/null || true

    # Unmount all mountpoints under parent disk and all its partitions
    for part in $(lsblk -nrpo NAME "${target_disk}" 2>/dev/null); do
        while findmnt -rn "${part}" >/dev/null 2>&1; do
            local mp
            mp=$(findmnt -n -o TARGET "${part}" | head -n 1)
            log_info "Unmounting ${part} from ${mp}..."
            umount "${mp}" 2>/dev/null || umount -l "${mp}" 2>/dev/null || break
        done
    done

    # Ensure /mnt/tuf_backup specifically is unmounted
    while findmnt -rn "${BACKUP_MOUNT}" >/dev/null 2>&1; do
        umount "${BACKUP_MOUNT}" 2>/dev/null || umount -l "${BACKUP_MOUNT}" 2>/dev/null || break
    done

    # Sync again
    sync
    log_info "All partitions on ${target_disk} have been cleanly unmounted."
    echo "✓ Safe to disconnect drive (${target_disk})."
    notify_desktop "Drive Safely Ejected" "External backup SSD is unmounted. Safe to unplug." "normal" "media-eject"
    update_status_json "ejected" "Drive safely unmounted and ready for removal." "none" 0 "none"
}

# ------------------------------------------------------------------------------
# Mount Verification & Preparation
# ------------------------------------------------------------------------------
ensure_backup_mounted() {
    local dev_part
    dev_part=$(blkid -U "${BACKUP_UUID}" 2>/dev/null || true)
    if [[ -z "${dev_part}" ]]; then
        log_warn "Target backup drive with UUID ${BACKUP_UUID} is absent/disconnected."
        notify_desktop "Btrfs Backup Cancelled" "External backup SSD is absent or disconnected. Backup skipped." "normal" "drive-harddisk"
        update_status_json "disconnected" "Backup cancelled: External backup SSD absent/disconnected." "none" 0 "none"
        exit 0
    fi

    local current_mount
    current_mount=$(findmnt -rn -t btrfs -S "${dev_part}" -o TARGET 2>/dev/null | head -n 1 || true)

    if [[ -n "${current_mount}" && -d "${current_mount}" ]]; then
        log_info "Backup drive is already mounted at: ${current_mount}"
        if [[ "${current_mount}" != "${BACKUP_MOUNT}" ]]; then
            # If mounted elsewhere, ensure BACKUP_MOUNT is available or create a symlink / bind mount
            mkdir -p "${BACKUP_MOUNT}"
            if ! findmnt -rn "${BACKUP_MOUNT}" >/dev/null 2>&1; then
                mount --bind "${current_mount}" "${BACKUP_MOUNT}" 2>/dev/null || true
            fi
        fi
    else
        log_info "Mounting backup partition (${dev_part}) to ${BACKUP_MOUNT}..."
        mkdir -p "${BACKUP_MOUNT}"
        mount -t btrfs -o compress=zstd:3 "${dev_part}" "${BACKUP_MOUNT}" || {
            log_error "Failed to mount ${BACKUP_MOUNT} on ${dev_part}."
            notify_desktop "Btrfs Backup Failed" "Failed to mount backup partition on external SSD." "critical" "dialog-error"
            update_status_json "error" "Failed to mount backup partition." "unknown" 0 "unknown"
            exit 2
        }
    fi

    # Ensure required destination directories exist
    mkdir -p "${SNAPSHOT_DIR}" "${BOOT_BACKUP_DIR}" "${LOCAL_SNAP_DIR}"
    chmod 755 "${SNAPSHOT_DIR}" "${BOOT_BACKUP_DIR}" 2>/dev/null || true
    chmod 700 "${LOCAL_SNAP_DIR}" 2>/dev/null || true
}

# Safely unmount backup repository partition
unmount_backup_repo() {
    if findmnt -rn "${BACKUP_MOUNT}" >/dev/null 2>&1; then
        sync
        log_info "Unmounting ${BACKUP_MOUNT}..."
        umount "${BACKUP_MOUNT}" 2>/dev/null || umount -l "${BACKUP_MOUNT}" 2>/dev/null || true
    fi
}

# Probe drive metadata manually on demand (drive stays mounted)
probe_and_update_state() {
    require_root
    log_info "Probing backup drive state on demand..."

    local dev_part
    dev_part=$(blkid -U "${BACKUP_UUID}" 2>/dev/null || true)
    if [[ -z "${dev_part}" ]]; then
        log_warn "Backup partition (${BACKUP_UUID}) is not currently connected."
        update_status_json "disconnected" "External backup drive disconnected." "none" 0 "none"
        echo "Drive not connected."
        return 0
    fi

    # Ensure mounted to refresh metadata
    ensure_backup_mounted
    read_state
    local current_status="idle"
    local current_msg="Drive connected and ready."
    local backup_type="incremental"

    if [[ -f "${BACKUP_MOUNT}/backup_state.json" ]] && command -v jq >/dev/null 2>&1; then
        if [[ "${CYCLE_COUNT}" -eq 1 ]]; then
            backup_type="full"
        else
            backup_type="incremental"
        fi
    elif [[ -f "${BACKUP_MOUNT}/status.json" ]] && command -v jq >/dev/null 2>&1; then
        current_status=$(jq -r '.status // "idle"' "${BACKUP_MOUNT}/status.json" 2>/dev/null || echo "idle")
        backup_type=$(jq -r '.last_backup_type // "incremental"' "${BACKUP_MOUNT}/status.json" 2>/dev/null || echo "incremental")
        current_msg=$(jq -r '.message // "Drive connected."' "${BACKUP_MOUNT}/status.json" 2>/dev/null || echo "Drive connected.")
    fi

    # Record state into persistent local state file
    update_status_json "${current_status}" "${current_msg}" "${backup_type}" "${CYCLE_COUNT:-0}" "${CURRENT_CYCLE_ID:-none}"
    
    echo "✓ Backup drive metadata refreshed successfully."
}

# ------------------------------------------------------------------------------
# State File Management
# ------------------------------------------------------------------------------
read_state() {
    local dev_part
    dev_part=$(blkid -U "${BACKUP_UUID}" 2>/dev/null || true)
    local active_mount=""
    if [[ -n "${dev_part}" ]]; then
        active_mount=$(findmnt -rn -t btrfs -S "${dev_part}" -o TARGET 2>/dev/null | head -n 1 || true)
    fi

    if [[ -n "${active_mount}" && -d "${active_mount}" ]]; then
        if [[ -f "${active_mount}/backup_state.json" ]] && command -v jq >/dev/null 2>&1; then
            CURRENT_CYCLE_ID=$(jq -r '.current_cycle_id // empty' "${active_mount}/backup_state.json" 2>/dev/null || echo "")
            CYCLE_COUNT=$(jq -r '.cycle_count // 0' "${active_mount}/backup_state.json" 2>/dev/null || echo "0")
            LAST_SUCCESS_TS=$(jq -r '.last_success_timestamp // 0' "${active_mount}/backup_state.json" 2>/dev/null || echo "0")
            PARENT_ROOT_SNAP=$(jq -r '.parent_root_snap // empty' "${active_mount}/backup_state.json" 2>/dev/null || echo "")
            PARENT_HOME_SNAP=$(jq -r '.parent_home_snap // empty' "${active_mount}/backup_state.json" 2>/dev/null || echo "")
        elif [[ -f "${active_mount}/status.json" ]] && command -v jq >/dev/null 2>&1; then
            CURRENT_CYCLE_ID=$(jq -r '.cycle_id // empty' "${active_mount}/status.json" 2>/dev/null || echo "")
            CYCLE_COUNT=$(jq -r '.cycle_day // 0' "${active_mount}/status.json" 2>/dev/null || echo "0")
            LAST_SUCCESS_TS=$(jq -r '.last_success_timestamp // 0' "${active_mount}/status.json" 2>/dev/null || echo "0")
            PARENT_ROOT_SNAP=""
            PARENT_HOME_SNAP=""
        else
            CURRENT_CYCLE_ID=""
            CYCLE_COUNT=0
            LAST_SUCCESS_TS=0
            PARENT_ROOT_SNAP=""
            PARENT_HOME_SNAP=""
        fi
    elif [[ -f "${STATUS_JSON}" ]] && command -v jq >/dev/null 2>&1; then
        CURRENT_CYCLE_ID=$(jq -r '.cycle_id // empty' "${STATUS_JSON}" 2>/dev/null || echo "")
        CYCLE_COUNT=$(jq -r '.cycle_day // 0' "${STATUS_JSON}" 2>/dev/null || echo "0")
        LAST_SUCCESS_TS=$(jq -r '.last_success_timestamp // 0' "${STATUS_JSON}" 2>/dev/null || echo "0")
        PARENT_ROOT_SNAP=""
        PARENT_HOME_SNAP=""
    else
        CURRENT_CYCLE_ID=""
        CYCLE_COUNT=0
        LAST_SUCCESS_TS=0
        PARENT_ROOT_SNAP=""
        PARENT_HOME_SNAP=""
    fi
}

save_state() {
    local cycle_id="$1"
    local cycle_count="$2"
    local parent_root="$3"
    local parent_home="$4"
    local last_ts
    last_ts=$(date +%s)

    local json_state
    json_state=$(cat <<EOF
{
  "current_cycle_id": "${cycle_id}",
  "cycle_count": ${cycle_count},
  "last_success_timestamp": ${last_ts},
  "parent_root_snap": "${parent_root}",
  "parent_home_snap": "${parent_home}",
  "updated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
)
    echo "${json_state}" > "${STATE_FILE}.tmp"
    mv -f "${STATE_FILE}.tmp" "${STATE_FILE}"
}

# ------------------------------------------------------------------------------
# Pruning Old Backup Cycles
# ------------------------------------------------------------------------------
prune_old_cycles() {
    local active_cycle_id="$1"
    log_info "Evaluating previous snapshot cycles for safe pruning (Active Cycle: ${active_cycle_id})..."

    if [[ -d "${SNAPSHOT_DIR}" ]]; then
        for snap in "${SNAPSHOT_DIR}"/*; do
            [[ -e "${snap}" ]] || continue
            local snap_name
            snap_name=$(basename "${snap}")
            # If snapshot belongs to an older cycle, delete safely
            if [[ "${snap_name}" =~ ^(root|home)_([0-9]{8})_([0-9]{6})$ ]]; then
                local snap_cycle="cycle_${BASH_REMATCH[2]}"
                # Only delete if it does NOT match current active cycle prefix
                if [[ "${snap_cycle}" != "${active_cycle_id}" ]]; then
                    log_info "Pruning old snapshot: ${snap}"
                    if [[ "${DRY_RUN}" == "false" ]]; then
                        btrfs subvolume delete "${snap}" || rm -rf "${snap}"
                    else
                        echo "[DRY-RUN] Would prune old snapshot: ${snap}"
                    fi
                fi
            fi
        done
    fi

    # Prune old boot archives
    if [[ -d "${BOOT_BACKUP_DIR}" ]]; then
        for boot_file in "${BOOT_BACKUP_DIR}"/*; do
            [[ -e "${boot_file}" ]] || continue
            local base
            base=$(basename "${boot_file}")
            if [[ "${base}" =~ ^(boot|efibootmgr)_([0-9]{8}) ]]; then
                local file_cycle="cycle_${BASH_REMATCH[2]}"
                if [[ "${file_cycle}" != "${active_cycle_id}" ]]; then
                    log_info "Pruning old boot archive: ${boot_file}"
                    if [[ "${DRY_RUN}" == "false" ]]; then
                        rm -f "${boot_file}"
                    else
                        echo "[DRY-RUN] Would delete old boot file: ${boot_file}"
                    fi
                fi
            fi
        done
    fi
}

# ------------------------------------------------------------------------------
# Cleanup Handler on Exit/Interrupt
# ------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]] && [[ "${STATUS_ONLY}" == "false" ]]; then
        log_error "Backup process aborted with exit code ${exit_code}."
        update_status_json "error" "Backup failed or interrupted (Exit code: ${exit_code})." "failed" 0 "none"
    fi
}
trap cleanup INT TERM

# ------------------------------------------------------------------------------
# Main Backup Execution Routine
# ------------------------------------------------------------------------------
run_backup() {
    require_root
    log_info "================================================================"
    log_info "Starting Btrfs Live Backup Routine..."
    log_info "================================================================"

    ensure_backup_mounted
    read_state

    local now_ts
    now_ts=$(date +%s)
    local time_diff=$(( now_ts - LAST_SUCCESS_TS ))

    # 1. Cooldown Check
    if [[ "${FORCE_RUN}" == "false" ]] && [[ ${LAST_SUCCESS_TS} -gt 0 ]] && [[ ${time_diff} -lt ${COOLDOWN_SECONDS} ]]; then
        local hours_left=$(( (COOLDOWN_SECONDS - time_diff) / 3600 ))
        local mins_left=$(( ((COOLDOWN_SECONDS - time_diff) % 3600) / 60 ))
        log_info "Cooldown active. Last backup was completed $(( time_diff / 3600 ))h $(( (time_diff % 3600) / 60 ))m ago."
        log_info "Next scheduled backup in ${hours_left}h ${mins_left}m. Use --force to bypass."
        update_status_json "idle" "Cooldown active (${hours_left}h ${mins_left}m remaining)." "none" "${CYCLE_COUNT}" "${CURRENT_CYCLE_ID}"
        exit 0
    fi

    update_status_json "running" "Creating snapshots and transferring data..." "evaluating" "${CYCLE_COUNT}" "${CURRENT_CYCLE_ID}"

    local date_tag
    date_tag=$(date '+%Y%m%d_%H%M%S')
    local date_day
    date_day=$(date '+%Y%m%d')

    local new_root_snap="root_${date_tag}"
    local new_home_snap="home_${date_tag}"
    local local_root_snap="${LOCAL_SNAP_DIR}/${new_root_snap}"
    local local_home_snap="${LOCAL_SNAP_DIR}/${new_home_snap}"
    local dest_root_snap="${SNAPSHOT_DIR}/${new_root_snap}"
    local dest_home_snap="${SNAPSHOT_DIR}/${new_home_snap}"

    local is_full_backup=false
    local next_cycle_count=$(( CYCLE_COUNT + 1 ))
    local next_cycle_id="${CURRENT_CYCLE_ID}"

    # Determine if we should perform a Full Backup:
    # - If cycle_count == 0 or >= MAX_CYCLE_DAYS (15)
    # - If no parent snapshot exists or if parent snapshot is missing locally or on destination
    if [[ ${CYCLE_COUNT} -le 0 ]] || [[ ${CYCLE_COUNT} -ge ${MAX_CYCLE_DAYS} ]] || [[ -z "${PARENT_ROOT_SNAP}" ]] || [[ -z "${PARENT_HOME_SNAP}" ]] || [[ ! -d "${LOCAL_SNAP_DIR}/${PARENT_ROOT_SNAP}" ]] || [[ ! -d "${SNAPSHOT_DIR}/${PARENT_ROOT_SNAP}" ]]; then
        is_full_backup=true
        next_cycle_count=1
        next_cycle_id="cycle_${date_day}"
        log_info "Mode: FULL BACKUP (Cycle Day 1 - Cycle ID: ${next_cycle_id})"
    else
        log_info "Mode: INCREMENTAL BACKUP (Cycle Day ${next_cycle_count}/${MAX_CYCLE_DAYS} - Parent: ${PARENT_ROOT_SNAP})"
    fi

    # 2. Step: Create Read-Only Local Snapshots
    log_info "Creating read-only local snapshot for / -> ${local_root_snap}..."
    if [[ "${DRY_RUN}" == "false" ]]; then
        btrfs subvolume snapshot -r "${ROOT_MOUNT}" "${local_root_snap}"
    else
        echo "[DRY-RUN] btrfs subvolume snapshot -r ${ROOT_MOUNT} ${local_root_snap}"
    fi

    log_info "Creating read-only local snapshot for /home -> ${local_home_snap}..."
    if [[ "${DRY_RUN}" == "false" ]]; then
        btrfs subvolume snapshot -r "${HOME_MOUNT}" "${local_home_snap}"
    else
        echo "[DRY-RUN] btrfs subvolume snapshot -r ${HOME_MOUNT} ${local_home_snap}"
    fi

    # 3. Step: Send Snapshots to Target Backup Repository
    if [[ "${is_full_backup}" == "true" ]]; then
        log_info "Sending full root snapshot to external repository..."
        if [[ "${DRY_RUN}" == "false" ]]; then
            btrfs send "${local_root_snap}" | btrfs receive "${SNAPSHOT_DIR}/"
        else
            echo "[DRY-RUN] btrfs send ${local_root_snap} | btrfs receive ${SNAPSHOT_DIR}/"
        fi

        log_info "Sending full home snapshot to external repository..."
        if [[ "${DRY_RUN}" == "false" ]]; then
            btrfs send "${local_home_snap}" | btrfs receive "${SNAPSHOT_DIR}/"
        else
            echo "[DRY-RUN] btrfs send ${local_home_snap} | btrfs receive ${SNAPSHOT_DIR}/"
        fi
    else
        log_info "Sending incremental root diff (Parent: ${PARENT_ROOT_SNAP})..."
        if [[ "${DRY_RUN}" == "false" ]]; then
            btrfs send -p "${LOCAL_SNAP_DIR}/${PARENT_ROOT_SNAP}" "${local_root_snap}" | btrfs receive "${SNAPSHOT_DIR}/"
        else
            echo "[DRY-RUN] btrfs send -p ${LOCAL_SNAP_DIR}/${PARENT_ROOT_SNAP} ${local_root_snap} | btrfs receive ${SNAPSHOT_DIR}/"
        fi

        log_info "Sending incremental home diff (Parent: ${PARENT_HOME_SNAP})..."
        if [[ "${DRY_RUN}" == "false" ]]; then
            btrfs send -p "${LOCAL_SNAP_DIR}/${PARENT_HOME_SNAP}" "${local_home_snap}" | btrfs receive "${SNAPSHOT_DIR}/"
        else
            echo "[DRY-RUN] btrfs send -p ${LOCAL_SNAP_DIR}/${PARENT_HOME_SNAP} ${local_home_snap} | btrfs receive ${SNAPSHOT_DIR}/"
        fi
    fi

    # 4. Step: Backup Boot Partition and NVRAM Boot Entries
    log_info "Archiving /boot partition and EFIBOOTMGR metadata..."
    local boot_archive="${BOOT_BACKUP_DIR}/boot_${date_day}.tar.zst"
    local efi_archive="${BOOT_BACKUP_DIR}/efibootmgr_${date_day}.txt"

    if [[ "${DRY_RUN}" == "false" ]]; then
        tar --zstd -cpf "${boot_archive}" -C /boot .
        efibootmgr -v > "${efi_archive}" 2>/dev/null || true
    else
        echo "[DRY-RUN] tar --zstd -cpf ${boot_archive} -C /boot ."
        echo "[DRY-RUN] efibootmgr -v > ${efi_archive}"
    fi

    # 5. Step: Clean up old local parent snapshots on the host disk
    if [[ -n "${PARENT_ROOT_SNAP}" ]] && [[ "${PARENT_ROOT_SNAP}" != "${new_root_snap}" ]]; then
        if [[ -d "${LOCAL_SNAP_DIR}/${PARENT_ROOT_SNAP}" ]]; then
            log_info "Removing superseded local root snapshot: ${LOCAL_SNAP_DIR}/${PARENT_ROOT_SNAP}"
            if [[ "${DRY_RUN}" == "false" ]]; then
                btrfs subvolume delete "${LOCAL_SNAP_DIR}/${PARENT_ROOT_SNAP}" || true
            fi
        fi
    fi
    if [[ -n "${PARENT_HOME_SNAP}" ]] && [[ "${PARENT_HOME_SNAP}" != "${new_home_snap}" ]]; then
        if [[ -d "${LOCAL_SNAP_DIR}/${PARENT_HOME_SNAP}" ]]; then
            log_info "Removing superseded local home snapshot: ${LOCAL_SNAP_DIR}/${PARENT_HOME_SNAP}"
            if [[ "${DRY_RUN}" == "false" ]]; then
                btrfs subvolume delete "${LOCAL_SNAP_DIR}/${PARENT_HOME_SNAP}" || true
            fi
        fi
    fi

    # 6. Step: If a new Full Backup was completed, safely prune previous cycles on external disk
    if [[ "${is_full_backup}" == "true" ]]; then
        prune_old_cycles "${next_cycle_id}"
    fi

    # 7. Step: Persist State & Update JSON Status
    if [[ "${DRY_RUN}" == "false" ]]; then
        save_state "${next_cycle_id}" "${next_cycle_count}" "${new_root_snap}" "${new_home_snap}"
    fi

    local backup_kind="incremental"
    if [[ "${is_full_backup}" == "true" ]]; then
        backup_kind="full"
    fi

    sync
    log_info "Backup completed successfully! [Type: ${backup_kind}, Cycle: Day ${next_cycle_count}/${MAX_CYCLE_DAYS}]"
    notify_desktop "Btrfs Backup Completed" "Backup completed successfully (${backup_kind}, Day ${next_cycle_count}/${MAX_CYCLE_DAYS})." "normal" "drive-harddisk"
    update_status_json "success" "Backup completed successfully (${backup_kind})." "${backup_kind}" "${next_cycle_count}" "${next_cycle_id}"
}

show_status() {
    read_state
    local current_status="idle"
    local current_msg="Drive connected and ready."
    local backup_type="none"

    local dev_part
    dev_part=$(blkid -U "${BACKUP_UUID}" 2>/dev/null || true)
    local active_mount=""
    if [[ -n "${dev_part}" ]]; then
        active_mount=$(findmnt -rn -t btrfs -S "${dev_part}" -o TARGET 2>/dev/null | head -n 1 || true)
    fi

    if systemctl is-active --quiet btrfs-backup.service 2>/dev/null || pgrep -f "btrfs-backup.sh --force" >/dev/null 2>&1; then
        current_status="running"
        current_msg="Backup process actively running..."
    elif [[ -n "${active_mount}" && -d "${active_mount}" ]]; then
        if [[ -f "${active_mount}/backup_state.json" ]] && command -v jq >/dev/null 2>&1; then
            current_status="idle"
            current_msg="Drive connected and ready."
            if [[ "${CYCLE_COUNT}" -eq 1 ]]; then
                backup_type="full"
            else
                backup_type="incremental"
            fi
        elif [[ -f "${active_mount}/status.json" ]] && command -v jq >/dev/null 2>&1; then
            current_status=$(jq -r '.status // "idle"' "${active_mount}/status.json" 2>/dev/null || echo "idle")
            backup_type=$(jq -r '.last_backup_type // "incremental"' "${active_mount}/status.json" 2>/dev/null || echo "incremental")
            current_msg=$(jq -r '.message // "Drive connected."' "${active_mount}/status.json" 2>/dev/null || echo "Drive connected.")
        fi
    elif [[ -n "${dev_part}" ]]; then
        local prev_status=""
        if [[ -f "${STATUS_JSON}" ]] && command -v jq >/dev/null 2>&1; then
            prev_status=$(jq -r '.status // ""' "${STATUS_JSON}" 2>/dev/null || true)
            backup_type=$(jq -r '.last_backup_type // "incremental"' "${STATUS_JSON}" 2>/dev/null || echo "incremental")
        fi
        if [[ "${prev_status}" == "ejected" ]]; then
            current_status="ejected"
            current_msg="Drive connected (safely ejected)."
        else
            current_status="idle"
            current_msg="Drive connected (unmounted)."
        fi
    else
        current_status="disconnected"
        current_msg="External backup drive absent/disconnected."
    fi

    update_status_json "${current_status}" "${current_msg}" "${backup_type}" "${CYCLE_COUNT:-0}" "${CURRENT_CYCLE_ID:-none}"
}

# ------------------------------------------------------------------------------
# Systemd Installation Helper
# ------------------------------------------------------------------------------
install_systemd() {
    require_root
    log_info "Installing systemd service and timer units..."

    local service_path="/etc/systemd/system/btrfs-backup.service"
    local timer_path="/etc/systemd/system/btrfs-backup.timer"
    local script_path="${USER_HOME}/.config/scripts/btrfs-backup.sh"

    if [[ ! -f "${script_path}" ]]; then
        # Fallback to current script path
        script_path="$(realpath "$0")"
    fi

    log_info "Writing ${service_path} (Target: ${script_path})..."
    cat <<EOF > "${service_path}"
[Unit]
Description=Btrfs Live Backup and 15-Day Incremental Cycle
After=local-fs.target

[Service]
Type=oneshot
ExecStart=${script_path}
StandardOutput=journal
StandardError=journal
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

    log_info "Writing ${timer_path} (Scheduled: Daily at 02:00)..."
    cat <<EOF > "${timer_path}"
[Unit]
Description=Daily Btrfs Live Backup Timer

[Timer]
OnCalendar=*-*-* 22:00:00
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now btrfs-backup.timer
    log_info "Systemd units installed and timer activated successfully!"
    echo "✓ Timer active: $(systemctl is-active btrfs-backup.timer)"
}

# ------------------------------------------------------------------------------
# Help & Argument Parsing
# ------------------------------------------------------------------------------
show_help() {
    cat <<EOF
Usage: btrfs-backup.sh [OPTIONS]

Options:
  -f, --force            Bypass the 24-hour cooldown and perform an immediate backup
  -d, --dry-run          Simulate all operations without modifying disk state
  -s, --status           Display the current JSON backup status and cycle details
  -p, --probe            Temporarily mount and probe drive stats on demand, then unmount
  -e, --eject            Safely unmount all partitions on the external backup drive
      --install-systemd  Install and enable systemd service and daily timer
  -h, --help             Display this help message

Examples:
  sudo btrfs-backup.sh                   # Standard run (honors 24h cooldown)
  sudo btrfs-backup.sh --force           # Immediate instant backup
  sudo btrfs-backup.sh --dry-run         # Dry-run test of backup actions
  sudo btrfs-backup.sh --probe           # Probe stats & unmount
  sudo btrfs-backup.sh --install-systemd # Setup & enable systemd timer
  sudo btrfs-backup.sh --eject           # Safe ejection of external drive
  btrfs-backup.sh --status               # View JSON status for widget/scripting
EOF
}

# Parse CLI arguments
INSTALL_SYSTEMD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE_RUN=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--status)
            STATUS_ONLY=true
            shift
            ;;
        -p|--probe)
            PROBE_ONLY=true
            shift
            ;;
        -e|--eject)
            EJECT_ONLY=true
            shift
            ;;
        --install-systemd)
            INSTALL_SYSTEMD=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        run)
            # Default run action
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main dispatch
if [[ "${STATUS_ONLY}" == "true" ]]; then
    show_status
    exit 0
elif [[ "${PROBE_ONLY}" == "true" ]]; then
    probe_and_update_state
    exit 0
elif [[ "${EJECT_ONLY}" == "true" ]]; then
    safe_eject_drive
    exit 0
elif [[ "${INSTALL_SYSTEMD}" == "true" ]]; then
    install_systemd
    exit 0
else
    run_backup
fi
