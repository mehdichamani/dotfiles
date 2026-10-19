#!/usr/bin/env bash
# ==============================================================================
# Omarchy Btrfs & LUKS Automated Disaster Recovery Engine
# ==============================================================================
# Target: Any Live Linux Environment (CachyOS, Arch, Omarchy, etc.)
# Usage:
#   sudo ./restore.sh [TARGET_DISK] [BACKUP_PATH]
# Examples:
#   sudo ./restore.sh /dev/vda /mnt/backup
#   sudo ./restore.sh /dev/nvme0n1 /run/media/liveuser/TUF_Backup
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be executed as root (sudo)."
    exit 1
fi

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}        Omarchy Btrfs & LUKS Full System Disaster Recovery       ${NC}"
echo -e "${CYAN}================================================================${NC}"

# ------------------------------------------------------------------------------
# 1. Target Disk Detection
# ------------------------------------------------------------------------------
TARGET_DISK="${1:-}"

if [[ -z "${TARGET_DISK}" ]]; then
    echo -e "\n${YELLOW}Available block devices:${NC}"
    lsblk -d -o NAME,SIZE,TYPE,MODEL
    echo ""
    read -rp "Enter target disk to restore Omarchy onto (e.g. /dev/vda or /dev/nvme0n1): " TARGET_DISK
fi

if [[ ! -b "${TARGET_DISK}" ]]; then
    log_error "Target disk '${TARGET_DISK}' is not a valid block device!"
    exit 1
fi

log_warn "ALL EXISTING DATA ON ${TARGET_DISK} WILL BE COMPLETELY DESTROYED!"
read -rp "Type 'YES' (all uppercase) to proceed: " CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
    log_info "Operation cancelled by user."
    exit 0
fi

# ------------------------------------------------------------------------------
# 2. Locate Backup Repository
# ------------------------------------------------------------------------------
BACKUP_DIR="${2:-}"

find_backup_dir() {
    # Check if already specified or standard mounts
    local candidates=(
        "${BACKUP_DIR}"
        "/run/media/*/*/snapshots"
        "/mnt/*/snapshots"
        "/media/*/*/snapshots"
        "/mnt/tuf_backup/snapshots"
    )
    for c in "${candidates[@]}"; do
        for d in $c; do
            if [[ -d "${d}" ]]; then
                echo "$(dirname "${d}")"
                return 0
            fi
        done
    done

    # Probe unmounted btrfs partitions containing snapshots
    for dev in $(lsblk -lno PATH,FSTYPE | awk '$2=="btrfs"{print $1}'); do
        local mpoint="/tmp/probe_backup_$$"
        mkdir -p "${mpoint}"
        if mount -o ro "${dev}" "${mpoint}" 2>/dev/null; then
            if [[ -d "${mpoint}/snapshots" ]]; then
                echo "${mpoint}"
                return 0
            fi
            umount "${mpoint}" 2>/dev/null || true
        fi
        rmdir "${mpoint}" 2>/dev/null || true
    done
    return 1
}

if [[ -z "${BACKUP_DIR}" ]] || [[ ! -d "${BACKUP_DIR}/snapshots" ]]; then
    log_info "Searching for backup repository..."
    BACKUP_DIR=$(find_backup_dir || echo "")
fi

if [[ -z "${BACKUP_DIR}" ]] || [[ ! -d "${BACKUP_DIR}/snapshots" ]]; then
    log_error "Could not find backup repository containing /snapshots!"
    read -rp "Please enter the mount path of the backup partition: " BACKUP_DIR
fi

if [[ ! -d "${BACKUP_DIR}/snapshots" ]]; then
    log_error "Invalid backup path: ${BACKUP_DIR}/snapshots does not exist."
    exit 1
fi

log_ok "Backup repository found at: ${BACKUP_DIR}"

# Find latest snapshots
LATEST_ROOT_SNAP=$(find "${BACKUP_DIR}/snapshots" -maxdepth 1 -name "root_*" | sort -V | tail -n 1)
LATEST_HOME_SNAP=$(find "${BACKUP_DIR}/snapshots" -maxdepth 1 -name "home_*" | sort -V | tail -n 1)

if [[ -z "${LATEST_ROOT_SNAP}" ]]; then
    log_error "No root snapshot found in ${BACKUP_DIR}/snapshots!"
    exit 1
fi

log_info "Selected Root Snapshot: $(basename "${LATEST_ROOT_SNAP}")"
if [[ -n "${LATEST_HOME_SNAP}" ]]; then
    log_info "Selected Home Snapshot: $(basename "${LATEST_HOME_SNAP}")"
fi

# Find latest boot archive
LATEST_BOOT_ARCHIVE=$(find "${BACKUP_DIR}/boot_backups" -maxdepth 1 -name "boot_*.tar.zst" 2>/dev/null | sort -V | tail -n 1 || echo "")
if [[ -z "${LATEST_BOOT_ARCHIVE}" ]]; then
    log_error "No boot archive found in ${BACKUP_DIR}/boot_backups!"
    exit 1
fi
log_info "Selected Boot Archive: $(basename "${LATEST_BOOT_ARCHIVE}")"

# ------------------------------------------------------------------------------
# 3. Partitioning Target Disk
# ------------------------------------------------------------------------------
log_info "Partitioning ${TARGET_DISK}..."
# Unmount and close any existing LUKS / mounts on target
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
cryptsetup close root 2>/dev/null || true

# Close any active dm devices on target disk
for dm in $(lsblk -lno NAME,TYPE "${TARGET_DISK}" 2>/dev/null | awk '$2=="crypt"{print $1}'); do
    cryptsetup close "${dm}" 2>/dev/null || true
done

# Format GPT: Partition 1 = 2GB EFI, Partition 2 = Rest for Root (LUKS)
wipefs -af "${TARGET_DISK}" 2>/dev/null || true
sgdisk --zap-all "${TARGET_DISK}" 2>/dev/null || true
sgdisk --clear "${TARGET_DISK}" 2>/dev/null || true
sgdisk -n 1:0:+2G -t 1:ef00 -c 1:"EFI System Partition" "${TARGET_DISK}"
sgdisk -n 2:0:0   -t 2:8309 -c 2:"Linux LUKS /" "${TARGET_DISK}"

udevadm settle 2>/dev/null || sleep 2
partprobe "${TARGET_DISK}" 2>/dev/null || sleep 2
udevadm settle 2>/dev/null || sleep 1

# Handle partition naming (e.g. nvme0n1p1 vs vda1)
if [[ "${TARGET_DISK}" =~ [0-9]$ ]]; then
    EFI_PART="${TARGET_DISK}p1"
    ROOT_PART="${TARGET_DISK}p2"
else
    EFI_PART="${TARGET_DISK}1"
    ROOT_PART="${TARGET_DISK}2"
fi

log_ok "Partitions created:"
log_info "  EFI Partition:  ${EFI_PART}"
log_info "  Root Partition: ${ROOT_PART}"

# ------------------------------------------------------------------------------
# 4. Format EFI & Setup LUKS
# ------------------------------------------------------------------------------
log_info "Formatting EFI partition (${EFI_PART}) as FAT32..."
mkfs.vfat -F32 -n "BOOT" "${EFI_PART}"

echo ""
log_warn "Configure LUKS Encryption password for ${ROOT_PART}:"
cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "${ROOT_PART}"

log_info "Opening LUKS container as 'root'..."
cryptsetup open "${ROOT_PART}" root

# ------------------------------------------------------------------------------
# 5. Format Btrfs on /dev/mapper/root
# ------------------------------------------------------------------------------
log_info "Creating Btrfs filesystem on /dev/mapper/root..."
mkfs.btrfs -f -L "omarchy_root" /dev/mapper/root

# ------------------------------------------------------------------------------
# 6. Mount Top-Level Btrfs & Restore Subvolumes
# ------------------------------------------------------------------------------
MNT_TOP="/mnt/btrfs_root_top"
mkdir -p "${MNT_TOP}"
mount -o compress=zstd:3 /dev/mapper/root "${MNT_TOP}"

log_info "Restoring Root Snapshot into subvolume '@'..."
btrfs send "${LATEST_ROOT_SNAP}" | btrfs receive "${MNT_TOP}/"
received_root="${MNT_TOP}/$(basename "${LATEST_ROOT_SNAP}")"
btrfs subvolume snapshot "${received_root}" "${MNT_TOP}/@"
btrfs subvolume delete "${received_root}"

if [[ -n "${LATEST_HOME_SNAP}" ]]; then
    log_info "Restoring Home Snapshot into subvolume '@home'..."
    btrfs send "${LATEST_HOME_SNAP}" | btrfs receive "${MNT_TOP}/"
    received_home="${MNT_TOP}/$(basename "${LATEST_HOME_SNAP}")"
    btrfs subvolume snapshot "${received_home}" "${MNT_TOP}/@home"
    btrfs subvolume delete "${received_home}"
else
    log_info "Creating empty '@home' subvolume..."
    btrfs subvolume create "${MNT_TOP}/@home"
fi

log_info "Creating operational auxiliary subvolumes (@log, @pkg)..."
btrfs subvolume create "${MNT_TOP}/@log"
btrfs subvolume create "${MNT_TOP}/@pkg"

umount "${MNT_TOP}"
rmdir "${MNT_TOP}"

# ------------------------------------------------------------------------------
# 7. Mount Restored System Tree
# ------------------------------------------------------------------------------
log_info "Mounting target filesystem hierarchy to /mnt..."
mkdir -p /mnt
mount -o subvol=@,compress=zstd:3 /dev/mapper/root /mnt
mkdir -p /mnt/home /mnt/var/log /mnt/var/cache/pacman/pkg /mnt/boot

mount -o subvol=@home,compress=zstd:3 /dev/mapper/root /mnt/home
mount -o subvol=@log,compress=zstd:3 /dev/mapper/root /mnt/var/log
mount -o subvol=@pkg,compress=zstd:3 /dev/mapper/root /mnt/var/cache/pacman/pkg
mount "${EFI_PART}" /mnt/boot

# ------------------------------------------------------------------------------
# 8. Extract Boot Archive
# ------------------------------------------------------------------------------
log_info "Extracting /boot partition archive (${LATEST_BOOT_ARCHIVE})..."
tar --zstd -xpf "${LATEST_BOOT_ARCHIVE}" -C /mnt/boot

# ------------------------------------------------------------------------------
# 9. Dynamic Auto-Correction of UUID & PARTUUID
# ------------------------------------------------------------------------------
log_info "Reading new disk and filesystem UUIDs..."
NEW_EFI_UUID=$(blkid -s UUID -o value "${EFI_PART}")
NEW_LUKS_PARTUUID=$(blkid -s PARTUUID -o value "${ROOT_PART}")
NEW_BTRFS_UUID=$(blkid -s UUID -o value /dev/mapper/root)

log_info "  New EFI UUID:         ${NEW_EFI_UUID}"
log_info "  New LUKS PARTUUID:    ${NEW_LUKS_PARTUUID}"
log_info "  New Btrfs UUID:       ${NEW_BTRFS_UUID}"

# 9.1 Update /boot/limine.conf
if [[ -f /mnt/boot/limine.conf ]]; then
    log_info "Auto-updating /boot/limine.conf..."
    # Replace old PARTUUID in cryptdevice parameter
    sed -i -E "s/cryptdevice=PARTUUID=[a-fA-F0-9-]+:root/cryptdevice=PARTUUID=${NEW_LUKS_PARTUUID}:root/g" /mnt/boot/limine.conf
    # Disable stale resume offset to prevent hang on restored swap
    sed -i -E "s/resume_offset=[0-9]+//g" /mnt/boot/limine.conf
    log_ok "limine.conf updated successfully."
else
    log_warn "/boot/limine.conf not found!"
fi

# 9.2 Update /etc/fstab
if [[ -f /mnt/etc/fstab ]]; then
    log_info "Auto-updating /mnt/etc/fstab..."
    # Replace old Btrfs UUID
    OLD_BTRFS_UUID=$(awk '$2=="/" && $3=="btrfs" {print $1}' /mnt/etc/fstab | sed 's/UUID=//')
    if [[ -n "${OLD_BTRFS_UUID}" ]]; then
        sed -i "s/${OLD_BTRFS_UUID}/${NEW_BTRFS_UUID}/g" /mnt/etc/fstab
    fi

    # Replace old EFI UUID
    OLD_EFI_UUID=$(awk '$2=="/boot" {print $1}' /mnt/etc/fstab | sed 's/UUID=//')
    if [[ -n "${OLD_EFI_UUID}" ]]; then
        sed -i "s/${OLD_EFI_UUID}/${NEW_EFI_UUID}/g" /mnt/etc/fstab
    fi

    # Comment out swapfile until recreated
    sed -i -E "s|^(/swap/swapfile.*)|# \1 # temporarily disabled after restore|g" /mnt/etc/fstab
    # Comment out any auxiliary secondary disks (/mnt/ssd, etc.)
    sed -i -E "s|^(UUID=[^ ]+[[:space:]]+/mnt/ssd.*)|# \1|g" /mnt/etc/fstab
    log_ok "/etc/fstab updated successfully."
fi

# ------------------------------------------------------------------------------
# 10. Recreate Btrfs Swapfile inside restored system
# ------------------------------------------------------------------------------
log_info "Recreating Btrfs swapfile inside restored system..."
if [[ -d /mnt/swap ]]; then
    btrfs filesystem mkswapfile --size 16g --uuid clear /mnt/swap/swapfile 2>/dev/null || {
        truncate -s 0 /mnt/swap/swapfile 2>/dev/null || true
        chattr +C /mnt/swap/swapfile 2>/dev/null || true
        btrfs property set /mnt/swap/swapfile compression none 2>/dev/null || true
        fallocate -l 16G /mnt/swap/swapfile 2>/dev/null || dd if=/dev/zero of=/mnt/swap/swapfile bs=1M count=16384 status=progress 2>/dev/null || true
        chmod 600 /mnt/swap/swapfile 2>/dev/null || true
        mkswap /mnt/swap/swapfile 2>/dev/null || true
    }
    # Re-enable swapfile in /etc/fstab
    sed -i -E "s|^#[[:space:]]*(/swap/swapfile.*)|\1|g" /mnt/etc/fstab
    log_ok "Swapfile recreated and activated in /etc/fstab."
fi

# ------------------------------------------------------------------------------
# 11. Optional TPM2 Auto-Unlock Enrollment Helper
# ------------------------------------------------------------------------------
if [[ -e /dev/tpmrm0 ]] || [[ -e /dev/tpm0 ]]; then
    echo ""
    log_info "Hardware TPM2 security chip detected on this machine!"
    read -rp "Would you like to enroll TPM2 auto-unlock for ${ROOT_PART}? (y/N): " ENROLL_TPM
    if [[ "${ENROLL_TPM}" =~ ^[Yy]$ ]]; then
        systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 "${ROOT_PART}" && log_ok "TPM2 auto-unlock successfully configured!" || log_warn "TPM2 enrollment skipped or encountered an error."
    fi
fi

# ------------------------------------------------------------------------------
# 12. Sync & Finalization
# ------------------------------------------------------------------------------
log_info "Syncing changes to disk..."
sync

log_info "Unmounting filesystem..."
umount /mnt/boot || true
umount /mnt/home || true
umount /mnt/var/log || true
umount /mnt/var/cache/pacman/pkg || true
umount /mnt || true
cryptsetup close root || true

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}    🎉 Omarchy Recovery Completed Successfully!                ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "You can now reboot into your fully restored Omarchy system!"
echo -e "\n${YELLOW}Post-boot optional tip (on real hardware):${NC}"
echo -e "To re-enroll TPM2 auto-unlock anytime, run:"
echo -e "  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 ${ROOT_PART}"
echo -e "To regenerate Plymouth bootsplash entries, run:"
echo -e "  sudo limine-entry-tool --regenerate"
