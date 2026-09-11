# WinApps / Windows Docker VM Setup & Guide

This guide details how to set up, configure, and maintain the Docker-based Windows VM environment (`WinApps`) managed via Chezmoi.

---

## 1. System Requirements & APT Dependencies

On a fresh Ubuntu installation, run the following commands to install required dependencies and set up permissions:

### Step 1: Install Required Packages
```bash
sudo apt update
sudo apt install -y freerdp2-x11 libnotify-bin docker.io docker-compose-plugin
```

* **`docker.io` & `docker-compose-plugin`**: Provides the Docker Engine and `docker compose` CLI.
* **`freerdp2-x11`** (or `freerdp3-x11` on newer Ubuntu releases): Provides `xfreerdp` used by the `winvm` launcher script for RDP connectivity.
* **`libnotify-bin`**: Provides `notify-send` for desktop status notifications.

### Step 2: Enable Docker & User Permissions
Add your user to the `docker` and `kvm` groups so Docker and KVM acceleration run without `sudo`:

```bash
# Enable and start Docker daemon
sudo systemctl enable --now docker

# Add current user to required groups
sudo usermod -aG docker,kvm $USER
```
> **Note**: Log out and log back in (or restart your session) for group membership changes to take effect.

---

## 2. Environment Variables & Credentials (`.env`)

The `compose.yml` file uses environment variables for Windows login credentials, loaded from `.env` (stored as `dot_env` in Chezmoi).

### Example `.env` File
Create or verify `~/docker/winapps/.env`:

```env
USERNAME=MyWindowsUser
PASSWORD=MyWindowsPassword
```

### Syncing Credentials with `winvm` Script
The automated launcher script (`~/.config/scripts/winvm`) connects using RDP. Ensure the credentials defined in `~/.config/scripts/winvm` match your `.env`:

```bash
# Inside ~/.config/scripts/winvm
RDP_USER="MyWindowsUser"
RDP_PASS="MyWindowsPassword"
```

---

## 3. Windows Version & Custom ISO Setup

### Default Windows Downloads
By default, `dockur/windows` downloads and installs the version specified by `VERSION` in `compose.yml` (e.g. `VERSION: "tiny11"` or `VERSION: "11"`).

### Installing a Custom ISO
To use a custom ISO file (e.g. `tiny11_25H2_Oct25.iso`):

1. Copy your `.iso` file into the `~/docker/winapps/` directory.
2. In `compose.yml`, mount the ISO to `/custom.iso`:

```yaml
    volumes:
      - data:/storage
      - ${HOME}:/shared
      - ./tiny11_25H2_Oct25.iso:/custom.iso   # Mount custom ISO here
```

> **Note**: When `/custom.iso` is mounted, `dockur/windows` automatically ignores the `VERSION` environment variable and boots from your custom ISO.

---

## 4. Hardware Resources & Configuration

You can customize the allocated VM resources in `compose.yml`:

```yaml
    environment:
      VERSION: "tiny11"
      RAM_SIZE: "4G"       # RAM allocated (e.g., 4G, 8G)
      CPU_CORES: "4"      # CPU cores allocated
      DISK_SIZE: "64G"    # Primary C: drive storage size
```

### Network Ports
* **VNC Web Interface**: `http://127.0.0.1:8006` (Useful during Windows installation / setup).
* **RDP Port**: `127.0.0.1:33389` (Used by `xfreerdp` / `winvm` launcher).

### Host Storage Integration
Your Linux home directory is automatically shared inside the Windows VM at `\\host.lan\Data` via the volume mapping:
```yaml
- ${HOME}:/shared
```

---

## 5. Chezmoi Integration & Desktop Launcher

When applying your Chezmoi dotfiles (`chezmoi apply`), the following components are deployed automatically:

| Path in Chezmoi Repo | Target Destination | Description |
| :--- | :--- | :--- |
| `docker/winapps/compose.yml` | `~/docker/winapps/compose.yml` | Docker Compose configuration |
| `docker/winapps/dot_env` | `~/docker/winapps/.env` | Credentials file |
| `docker/winapps/guide.md` | `~/docker/winapps/guide.md` | This documentation guide |
| `dot_config/scripts/executable_winvm` | `~/.config/scripts/winvm` | Launcher script (auto `chmod +x`) |
| `private_dot_local/private_share/private_applications/winvm.desktop` | `~/.local/share/applications/winvm.desktop` | Application menu shortcut |
| `private_dot_local/private_share/icons/hicolor/scalable/apps/winvm.svg` | `~/.local/share/icons/hicolor/scalable/apps/winvm.svg` | App icon |

### Launching the VM
* **From Application Launcher**: Click **WindowsVM (docker)** in your app menu.
* **From Terminal**: Run `winvm` (or `~/.config/scripts/winvm`).

The launcher script will:
1. Start the Docker container via `docker compose up -d` if not running.
2. Wait for the RDP port to become available.
3. Open an RDP session via `xfreerdp`.
4. Automatically shut down the VM container 30 minutes after closing the RDP window.
