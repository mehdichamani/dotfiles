#!/usr/bin/env python3
"""
Cisco Switches Interactive Telnet Connection Helper
Cross-platform: Linux, Windows, macOS, Android (Termux)
Loads switches inventory from ~/.ssh/devices.toml and credentials from ~/.config/secrets/sw.env
"""

from pathlib import Path
import os
import sys
import socket
import select
import shutil
import subprocess

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        tomllib = None

CONFIG_FILE = Path.home() / ".config" / "secrets" / "sw.env"
EXAMPLE_FILE = Path.home() / ".config" / "secrets" / "sw.env.example"
DEVICES_FILE = Path.home() / ".ssh" / "devices.toml"
FALLBACK_DEVICES_FILE = Path.home() / ".local" / "share" / "chezmoi" / "dot_ssh" / "devices.toml"


def load_config():
    if not CONFIG_FILE.is_file():
        print(f"\n❌ Error: Configuration file not found at:\n   {CONFIG_FILE}")
        print("\nPlease create this file with your switch credentials:")
        if EXAMPLE_FILE.is_file():
            print(f"   cp {EXAMPLE_FILE} {CONFIG_FILE}")
        else:
            print("   SWITCH_USER=")
            print("   SWITCH_PASS=your_switch_password_here\n")
        sys.exit(1)

    user = ""
    password = ""

    try:
        for line in CONFIG_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip().strip("'\"")
                if k == "SWITCH_USER":
                    user = v
                elif k == "SWITCH_PASS":
                    password = v
    except Exception as e:
        print(f"\n❌ Error reading credentials file ({CONFIG_FILE}): {e}")
        sys.exit(1)

    if not password:
        print(f"\n❌ Error: SWITCH_PASS is missing or empty in:\n   {CONFIG_FILE}")
        sys.exit(1)

    return user, password


def parse_switches():
    dev_path = DEVICES_FILE if DEVICES_FILE.is_file() else FALLBACK_DEVICES_FILE
    if not dev_path.is_file():
        print(f"\n❌ Error: Devices inventory file not found at {DEVICES_FILE}")
        sys.exit(1)

    switches = []
    try:
        if tomllib:
            with open(dev_path, "rb") as f:
                data = tomllib.load(f)
            raw_switches = data.get("telnet", {}).get("switches", [])
            for item in raw_switches:
                switches.append({
                    "ip": item.get("ip", ""),
                    "name": item.get("name", item.get("ip", "")),
                    "desc": item.get("desc", "")
                })
        else:
            # Simple fallback parser if tomllib is missing
            content = dev_path.read_text(encoding="utf-8")
            import re
            blocks = re.findall(r'\[\[telnet\.switches\]\](.*?)(?=\[\[|\Z)', content, re.DOTALL)
            for block in blocks:
                ip_m = re.search(r'ip\s*=\s*["\']([^"\']+)["\']', block)
                name_m = re.search(r'name\s*=\s*["\']([^"\']+)["\']', block)
                desc_m = re.search(r'desc\s*=\s*["\']([^"\']+)["\']', block)
                if ip_m:
                    ip = ip_m.group(1)
                    name = name_m.group(1) if name_m else ip
                    desc = desc_m.group(1) if desc_m else ""
                    switches.append({"ip": ip, "name": name, "desc": desc})
    except Exception as e:
        print(f"\n❌ Error reading devices inventory ({dev_path}): {e}")
        sys.exit(1)

    return switches


def select_switch(switches, target=None):
    if target:
        target_lower = target.lower()
        # 1. Exact match name or IP
        for sw in switches:
            if sw["name"].lower() == target_lower or sw["ip"] == target:
                return sw
        # 2. Substring match
        matches = [sw for sw in switches if target_lower in sw["name"].lower() or target_lower in sw["desc"].lower()]
        if len(matches) == 1:
            return matches[0]
        elif len(matches) > 1:
            print(f"\n🔍 Ambiguous switch target '{target}'. Matches:")
            for m in matches:
                print(f"   - {m['name']} ({m['ip']}) - {m['desc']}")
            print("\nPlease specify the exact name or index.")
            sys.exit(1)
        else:
            print(f"\n❌ No switch matching '{target}' found.")
            sys.exit(1)

    # Interactive menu
    print("\n" + "=" * 55)
    print("🔌  CISCO SWITCHES TELNET MANAGER")
    print("=" * 55)
    print(f" {'#':<3} | {'Switch Name':<16} | {'IP Address':<15} | {'Description'}")
    print("-" * 55)
    for idx, sw in enumerate(switches, 1):
        desc = f"({sw['desc']})" if sw["desc"] else ""
        print(f" {idx:<3} | {sw['name']:<16} | {sw['ip']:<15} | {desc}")
    print("=" * 55)

    while True:
        try:
            choice = input(f"\n👉 Select switch number [1-{len(switches)}] or 'q' to quit: ").strip()
            if choice.lower() in ("q", "quit", "exit"):
                sys.exit(0)
            if choice.isdigit() and 1 <= int(choice) <= len(switches):
                return switches[int(choice) - 1]
            print("⚠️ Invalid selection. Please enter a valid number.")
        except (KeyboardInterrupt, EOFError):
            print("\nAborted.")
            sys.exit(0)


def telnet_session_pty(ip, port, user, password):
    """Handles raw telnet interaction via PTY and auto-login."""
    try:
        import pty
        import termios
        import tty
    except ImportError:
        # Fallback for Windows
        return telnet_session_socket(ip, port, user, password)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(4)
    try:
        s.connect((ip, port))
    except Exception as e:
        print(f"\n❌ Connection to {ip}:{port} failed: {e}")
        return 1

    print(f" Connected! Negotiating authentication...")

    # Automatic login negotiation
    buffer = b""
    logged_in = False
    s.settimeout(0.5)

    # Cisco telnet IAC negotiations
    for _ in range(30):
        try:
            data = s.recv(1024)
            if not data:
                break
            
            # Filter telnet IAC options (DO/DONT/WILL/WONT)
            clean_bytes = bytearray()
            i = 0
            while i < len(data):
                if data[i] == 255:  # IAC
                    if i + 2 < len(data):
                        cmd = data[i + 1]
                        opt = data[i + 2]
                        if cmd == 253:  # DO -> WONT
                            s.sendall(bytes([255, 252, opt]))
                        elif cmd == 251:  # WILL -> DONT
                            s.sendall(bytes([255, 254, opt]))
                        i += 3
                        continue
                    else:
                        break
                clean_bytes.append(data[i])
                i += 1
            
            buffer += bytes(clean_bytes)
            text = buffer.decode("latin1", errors="ignore").lower()

            if "username:" in text:
                s.sendall(user.encode("ascii") + b"\r\n")
                buffer = b""
            elif "password:" in text:
                s.sendall(password.encode("ascii") + b"\r\n")
                buffer = b""
                logged_in = True
                break
        except socket.timeout:
            if logged_in or b">" in buffer or b"#" in buffer:
                break
            continue
        except Exception:
            break

    print("🔐 Authenticated. Terminal attached (Press Ctrl+] or Ctrl+C or type 'exit' to disconnect).\n")
    s.setblocking(True)

    old_tty = termios.tcgetattr(sys.stdin)
    try:
        tty.setraw(sys.stdin.fileno())
        while True:
            r, _, _ = select.select([s, sys.stdin], [], [])
            if s in r:
                data = s.recv(4096)
                if not data:
                    break
                # Filter residual IAC
                clean = bytearray()
                i = 0
                while i < len(data):
                    if data[i] == 255 and i + 2 < len(data):
                        i += 3
                        continue
                    clean.append(data[i])
                    i += 1
                os.write(sys.stdout.fileno(), bytes(clean))
            if sys.stdin in r:
                char = os.read(sys.stdin.fileno(), 1)
                if not char:
                    break
                if char == b"\x1d":  # Ctrl+]
                    break
                if char == b"\n":
                    s.sendall(b"\r\n")
                else:
                    s.sendall(char)
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_tty)
        s.close()
    print("\n\n🔌 Connection closed.")
    return 0


def telnet_session_socket(ip, port, user, password):
    """Cross-platform socket fallback (Windows/Termux basic)."""
    import threading

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    try:
        s.connect((ip, port))
    except Exception as e:
        print(f"\n❌ Connection failed: {e}")
        return 1

    print(f" Connected to {ip} via Telnet socket...")

    stop_event = threading.Event()

    def receiver():
        buffer = b""
        while not stop_event.is_set():
            try:
                data = s.recv(2048)
                if not data:
                    break
                
                clean = bytearray()
                i = 0
                while i < len(data):
                    if data[i] == 255 and i + 2 < len(data):
                        cmd, opt = data[i+1], data[i+2]
                        if cmd == 253:
                            s.sendall(bytes([255, 252, opt]))
                        elif cmd == 251:
                            s.sendall(bytes([255, 254, opt]))
                        i += 3
                        continue
                    clean.append(data[i])
                    i += 1
                
                text = bytes(clean).decode("latin1", errors="ignore")
                sys.stdout.write(text)
                sys.stdout.flush()

                buffer += bytes(clean)
                t_low = buffer.decode("latin1", errors="ignore").lower()
                if "username:" in t_low:
                    s.sendall(user.encode("ascii") + b"\r\n")
                    buffer = b""
                elif "password:" in t_low:
                    s.sendall(password.encode("ascii") + b"\r\n")
                    buffer = b""
            except socket.timeout:
                continue
            except Exception:
                break
        stop_event.set()

    t = threading.Thread(target=receiver, daemon=True)
    t.start()

    try:
        while not stop_event.is_set():
            line = sys.stdin.readline()
            if not line:
                break
            s.sendall(line.encode("ascii", errors="ignore"))
    except KeyboardInterrupt:
        pass
    finally:
        stop_event.set()
        s.close()
    return 0


def main():
    target = None
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg in ("-h", "--help"):
            print("Usage: sw [switch_name | switch_ip | list_number]")
            print("       sw --list")
            print("Connect to Cisco switch via Telnet using ~/.config/secrets/sw.env credentials.")
            sys.exit(0)
        elif arg in ("-l", "--list", "list"):
            switches = parse_switches()
            print("\n📋 Cisco Switches Inventory (from ~/.ssh/devices.toml):")
            for idx, sw in enumerate(switches, 1):
                desc = f"- {sw['desc']}" if sw['desc'] else ""
                print(f"  {idx:2d}. {sw['name']:<16} ({sw['ip']}) {desc}")
            print()
            sys.exit(0)
        else:
            target = arg

    user, password = load_config()
    switches = parse_switches()
    if not switches:
        print("❌ No switches found in ~/.ssh/devices.toml.")
        sys.exit(1)

    selected = select_switch(switches, target)
    print(f"\n🔌 Connecting to {selected['name']} ({selected['ip']})...")
    telnet_session_pty(selected["ip"], 23, user, password)


if __name__ == "__main__":
    main()
