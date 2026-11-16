---
name: ntfs-fix
description: Diagnose and resolve NTFS drive mount failures on Arch / Omarchy Linux, including missing ntfs3/ntfs-3g helpers, dirty volume flags, Fast Startup lockups, and ntfsprogs utilities.
---

# NTFS Mount Troubleshooting & Repair on Arch / Omarchy

When external HDDs, SSDs, or USB flash drives with NTFS file systems fail to mount in file managers (Nautilus, Dolphin, Thunar, etc.) or via `udisksctl` / `mount`, use this playbook.

---

## 1. Quick Diagnostic Checklist

Check the partition table and kernel logs to identify the exact cause:

```fish
# Check drive identifier and filesystem
lsblk -f /dev/sdX

# Check kernel messages for failure details
sudo dmesg | grep -iE "ntfs|volume is dirty"
# Or via journalctl
journalctl -k -n 30 --no-pager
```

### Common Symptoms & Causes:
1. **`wrong fs type, bad option, bad superblock... missing codepage or helper program`**
   - **Cause:** Neither `ntfs-3g` nor `ntfs3` is configured for userspace auto-mounting, or userspace helper tools are missing.
2. **`volume is dirty and "force" flag is not set! / It is recommended to use chkdsk`**
   - **Cause:** Drive was disconnected from Windows without Safely Remove, or Windows Fast Startup / Hibernation left the NTFS volume in a dirty state. Modern kernel driver `ntfs3` strictly refuses to mount dirty volumes without `-o force`.

---

## 2. Definitive Fix for "Volume is Dirty" (ntfsfix)

> [!IMPORTANT]
> On Arch Linux / Omarchy, `ntfsfix` is **NOT** inside `ntfs-3g`. It is packaged in **`ntfsprogs`**.

Run the following commands to install the utilities and clear the dirty bit / NTFS volume log:

```fish
# 1. Install ntfsprogs (contains ntfsfix, mkntfs, etc.)
sudo pacman -S --needed ntfsprogs

# 2. Clear dirty flag and schedule consistency check
sudo ntfsfix -d /dev/sdX1
```

Flags explained:
- `-d`: Clear the volume dirty flag.
- (Optionally `-b` to clear bad clusters).

After running `ntfsfix -d`, the drive can be mounted normally:
```fish
udisksctl mount -b /dev/sdX1
```

---

## 3. Alternative: Mount with `ntfs3` and `force`

If unable or unwilling to run `ntfsfix` immediately, the kernel's built-in `ntfs3` driver can mount a dirty volume read/write by explicitly forcing it:

```fish
sudo mount -t ntfs3 -o force /dev/sdX1 /mnt/<target_dir>/
```

---

## 4. Modernizing udisks2 to use `ntfs3` by Default

Omarchy / Arch Linux kernels include the fast in-kernel `ntfs3` module (`CONFIG_NTFS3_FS=m`). To configure `udisks2` to prefer `ntfs3` over legacy userspace FUSE (`ntfs-3g`):

```fish
sudo mkdir -p /etc/udisks2/mount_options.conf.d
echo -e "[defaults]\nntfs_drivers=ntfs3" | sudo tee /etc/udisks2/mount_options.conf.d/ntfs.conf
sudo systemctl restart udisks2
```
