#!/usr/bin/env python3
"""
WinApps Event-Driven Hyprland Idle Daemon
Listens to Hyprland's UNIX domain socket (.socket2.sock) for zero-CPU event monitoring.
Manages a 30-minute idle countdown when all Windows VM application windows are closed,
sends Omarchy desktop notifications, and gracefully stops the container after timeout.
"""

import os
import sys
import json
import time
import socket
import select
import signal
import subprocess
import threading
from pathlib import Path

IDLE_TIMEOUT_SECONDS = 1800  # 30 minutes
WARN_TIMEOUT_SECONDS = 300   # 5 minutes remaining (at 25m)
STATE_FILE = Path("/tmp/winapps_state.json")
CMD_SOCK = Path("/tmp/winapps_daemon.sock")
PROJECT_DIR = Path(__file__).resolve().parent
ICON_PATH = PROJECT_DIR / "winapps.png"

# Target window classes / titles for RemoteApp and FreeRDP
WINDOW_TARGETS = ("xfreerdp", "xfreerdp3", "wlfreerdp", "freerdp", "rail:")


class WinAppsDaemon:
    def __init__(self):
        self.running = True
        self.open_windows = set()
        self.state = "stopped"  # "active", "idle", "disabled", "stopped"
        self.remaining_seconds = IDLE_TIMEOUT_SECONDS
        self.warn_sent = False
        self.had_active_windows = False
        self.lock = threading.RLock()

        # Clean old socket if exists
        if CMD_SOCK.exists():
            try:
                CMD_SOCK.unlink()
            except Exception:
                pass

    def send_notification(self, title: str, body: str, urgency: str = "normal", icon: str = None):
        if icon is None:
            icon = str(ICON_PATH) if ICON_PATH.exists() else "winapps"
        try:
            subprocess.run(
                [
                    "notify-send",
                    "-a", "WinApps",
                    "-u", urgency,
                    "-i", icon,
                    title,
                    body,
                ],
                check=False,
            )
        except Exception as e:
            print(f"[ERROR] Failed to send notification: {e}", file=sys.stderr)

    def write_state(self):
        with self.lock:
            data = {
                "state": self.state,
                "remaining": self.remaining_seconds,
                "active_windows": len(self.open_windows),
                "timestamp": int(time.time()),
            }
            try:
                temp_file = STATE_FILE.with_suffix(".tmp")
                temp_file.write_text(json.dumps(data))
                temp_file.replace(STATE_FILE)
            except Exception:
                pass

    def is_container_running(self) -> bool:
        try:
            res = subprocess.run(
                ["docker", "inspect", "-f", "{{.State.Running}}", "WinApps"],
                capture_output=True,
                text=True,
                check=False,
            )
            return res.stdout.strip().lower() == "true"
        except Exception:
            return False

    def stop_container(self):
        print("[INFO] 30m idle timeout reached. Stopping Windows VM container...")
        self.send_notification(
            "Windows VM Stopped",
            "Container stopped due to 30 minutes of inactivity to release resources.",
            urgency="normal",
        )
        subprocess.run(
            ["docker", "compose", "-f", str(PROJECT_DIR / "compose.yml"), "stop"],
            cwd=str(PROJECT_DIR),
            check=False,
        )
        self.state = "stopped"
        self.write_state()

    def sync_initial_windows(self):
        """Perform one-time scan on daemon start to seed active windows."""
        try:
            res = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, check=False)
            if res.returncode == 0 and res.stdout.strip():
                clients = json.loads(res.stdout)
                for client in clients:
                    cls = (client.get("class") or "").lower()
                    addr = client.get("address")
                    if addr and any(target in cls for target in WINDOW_TARGETS):
                        self.open_windows.add(addr)
        except Exception as e:
            print(f"[WARN] Initial client scan failed: {e}", file=sys.stderr)

    def timer_loop(self):
        while self.running:
            time.sleep(1)
            container_alive = self.is_container_running()

            if not container_alive:
                if self.state != "stopped":
                    self.state = "stopped"
                    self.remaining_seconds = IDLE_TIMEOUT_SECONDS
                    self.had_active_windows = False
                    self.write_state()
                continue

            with self.lock:
                if len(self.open_windows) > 0:
                    # Windows are currently open
                    self.had_active_windows = True
                    if self.state != "active":
                        self.state = "active"
                        self.remaining_seconds = IDLE_TIMEOUT_SECONDS
                        self.warn_sent = False
                        self.write_state()
                else:
                    # No windows open, container is running
                    if self.state == "disabled":
                        continue

                    if self.state != "idle":
                        prev_state = self.state
                        # Transition to idle
                        self.state = "idle"
                        self.remaining_seconds = IDLE_TIMEOUT_SECONDS
                        self.warn_sent = False
                        self.write_state()
                        # Only notify if windows were actually open before and just closed
                        if self.had_active_windows or prev_state == "active":
                            self.send_notification(
                                "Windows Apps Closed",
                                "30-minute idle countdown started. Container will stop when timer expires.",
                                urgency="normal",
                            )

                    if self.remaining_seconds > 0:
                        self.remaining_seconds -= 1

                        # 5 minute reminder warning
                        if self.remaining_seconds == WARN_TIMEOUT_SECONDS and not self.warn_sent:
                            self.warn_sent = True
                            self.send_notification(
                                "Windows VM Shutdown Warning",
                                "Only 5 minutes remaining before Windows container stops due to inactivity.",
                                urgency="critical",
                            )

                        if self.remaining_seconds % 5 == 0:
                            self.write_state()

                        if self.remaining_seconds <= 0:
                            self.stop_container()

    def handle_command(self, cmd: str):
        cmd = cmd.strip().lower()
        print(f"[INFO] Received command: {cmd}")
        with self.lock:
            if cmd == "reset":
                self.remaining_seconds = IDLE_TIMEOUT_SECONDS
                self.warn_sent = False
                if self.state == "idle":
                    self.send_notification(
                        "Idle Timer Reset",
                        "Shutdown timeout reset to 30 minutes.",
                    )
                self.write_state()
            elif cmd == "cancel":
                self.state = "disabled"
                self.send_notification(
                    "Auto-Shutdown Cancelled",
                    "Windows VM container will remain running indefinitely.",
                )
                self.write_state()
            elif cmd == "stop":
                self.stop_container()

    def command_listener_loop(self):
        """Listens for manual reset / cancel commands via UNIX domain socket."""
        while self.running:
            server_sock = None
            try:
                if CMD_SOCK.exists():
                    CMD_SOCK.unlink()
                server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                server_sock.bind(str(CMD_SOCK))
                server_sock.listen(5)
                server_sock.settimeout(1.0)

                while self.running:
                    try:
                        conn, _ = server_sock.accept()
                        with conn:
                            data = conn.recv(1024).decode("utf-8", errors="ignore")
                            if data:
                                self.handle_command(data)
                    except socket.timeout:
                        continue
                    except Exception:
                        pass
            except Exception as e:
                time.sleep(1)
            finally:
                if server_sock:
                    try:
                        server_sock.close()
                    except Exception:
                        pass
                if CMD_SOCK.exists():
                    try:
                        CMD_SOCK.unlink()
                    except Exception:
                        pass

    def hyprland_event_loop(self):
        """Connects to Hyprland's UNIX domain socket (.socket2.sock) for instant events."""
        xdg_runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")

        if not his:
            print("[ERROR] HYPRLAND_INSTANCE_SIGNATURE not found. Is Hyprland running?", file=sys.stderr)
            return

        sock_path = Path(xdg_runtime) / "hypr" / his / ".socket2.sock"

        while self.running:
            if not sock_path.exists():
                time.sleep(2)
                continue

            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(str(sock_path))
                print(f"[INFO] Connected to Hyprland event socket: {sock_path}")
                buf = ""

                while self.running:
                    ready, _, _ = select.select([s], [], [], 2.0)
                    if not ready:
                        continue

                    chunk = s.recv(4096).decode("utf-8", errors="ignore")
                    if not chunk:
                        break

                    buf += chunk
                    while "\n" in buf:
                        line, buf = buf.split("\n", 1)
                        self.process_hypr_event(line.strip())

            except Exception as e:
                print(f"[WARN] Socket connection error: {e}. Reconnecting...", file=sys.stderr)
                time.sleep(2)

    def process_hypr_event(self, event_line: str):
        if not event_line:
            return

        if ">>" not in event_line:
            return

        event_type, event_data = event_line.split(">>", 1)

        # Event: openwindow>>WINDOWADDRESS,WORKSPACE,WINDOWCLASS,WINDOWTITLE
        if event_type == "openwindow":
            parts = event_data.split(",")
            if len(parts) >= 3:
                addr = parts[0]
                cls = parts[2].lower()
                if any(target in cls for target in WINDOW_TARGETS):
                    with self.lock:
                        self.open_windows.add(addr)
                        print(f"[INFO] WinApps window opened: {addr} ({cls})")
                        self.state = "active"
                        self.remaining_seconds = IDLE_TIMEOUT_SECONDS
                        self.warn_sent = False
                        self.write_state()

        # Event: closewindow>>WINDOWADDRESS
        elif event_type == "closewindow":
            addr = event_data.strip()
            with self.lock:
                if addr in self.open_windows:
                    self.open_windows.remove(addr)
                    print(f"[INFO] WinApps window closed: {addr}. Remaining windows: {len(self.open_windows)}")
                    self.write_state()


def main():
    daemon = WinAppsDaemon()
    daemon.sync_initial_windows()

    def handle_sig(sig, frame):
        daemon.running = False
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_sig)
    signal.signal(signal.SIGTERM, handle_sig)

    t_timer = threading.Thread(target=daemon.timer_loop, daemon=True)
    t_cmd = threading.Thread(target=daemon.command_listener_loop, daemon=True)
    t_timer.start()
    t_cmd.start()

    print("[INFO] WinApps Hyprland Socket2 Daemon initialized successfully.")
    daemon.hyprland_event_loop()


if __name__ == "__main__":
    main()
