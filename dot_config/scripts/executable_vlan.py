#!/usr/bin/env python3
"""
Multi-VLAN Cisco Trunk and vNIC Manager for Linux (NetworkManager).
Mirrors the functionality of Documents/PowerShell/Functions/vlan.ps1.

Manages 802.1Q VLAN sub-interfaces on eno1 with predefined MAC addresses,
DHCP reservations, and internet route metric prioritization:
  - eno1.400 (VLAN 400): MAC 00:15:5D:01:C8:05, Metric 100 (Primary Internet)
  - eno1.500 (VLAN 500): MAC 00:15:5D:01:C8:06, Metric 200 (Secondary Internet)
  - eno1.100 (VLAN 100): MAC 00:15:5D:01:C8:0F, Metric 300 (Edari / Internal)
  - eno1     (Native):   MAC 00:15:5D:01:C8:0E, Metric 400 (Cisco Mgmt / Untagged)
"""

import argparse
import subprocess
import sys
import time

# --- Configuration Constants ---
PARENT_DEV = "eno1"

NATIVE_SETTINGS = {
    "mac": "00:15:5D:01:C8:0E",
    "metric": 400,
    "desc": "Native VLAN (Cisco Mgmt / Untagged)",
}

VLAN_DEFS = {
    "400": {
        "id": 400,
        "name": "eno1.400",
        "mac": "00:15:5D:01:C8:05",  # DHCP Reservation 172.20.0.100
        "metric": 100,  # Priority 1 for Default Gateway / Internet
        "method": "auto",
        "desc": "VLAN 400 - Primary Internet (172.20.0.100)",
    },
    "500": {
        "id": 500,
        "name": "eno1.500",
        "mac": "00:15:5D:01:C8:06",  # DHCP Reservation 192.168.1.100
        "metric": 200,  # Priority 2 for Default Gateway / Internet
        "method": "auto",
        "routes": ["10.50.0.0/24 192.168.1.1"],  # Static route via VLAN 500 gateway
        "desc": "VLAN 500 - Secondary Internet (192.168.1.100)",
    },
    "100": {
        "id": 100,
        "name": "eno1.100",
        "mac": "00:15:5D:01:C8:0F",
        "metric": 300,  # Priority 3
        "method": "auto",
        "routes": [],
        "desc": "VLAN 100 - Edari / Internal",
    },
}

# --- ANSI Colors ---
C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_CYAN = "\033[1;36m"
C_GREEN = "\033[1;32m"
C_YELLOW = "\033[1;33m"
C_RED = "\033[1;31m"
C_GRAY = "\033[0;90m"


def run_cmd(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    """Run a system command and return output."""
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed ({' '.join(cmd)}): {res.stderr.strip()}")
    return res


def get_nm_connections() -> dict[str, dict[str, str]]:
    """Return dict of existing NetworkManager connections: {name: {uuid, type, device}}."""
    res = run_cmd(["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE", "connection", "show"])
    conns = {}
    for line in res.stdout.strip().splitlines():
        if not line:
            continue
        parts = line.split(":")
        if len(parts) >= 4:
            name, uuid, c_type, dev = parts[0], parts[1], parts[2], parts[3]
            conns[name] = {"uuid": uuid, "type": c_type, "device": dev}
    return conns


def get_parent_connection() -> str | None:
    """Find existing NetworkManager connection for the parent interface."""
    conns = get_nm_connections()
    for name, data in conns.items():
        if data["device"] == PARENT_DEV and data["type"] == "802-3-ethernet":
            return name
    # Fallback to search by interface name in settings
    for name, data in conns.items():
        if data["type"] == "802-3-ethernet":
            check = run_cmd(["nmcli", "-g", "connection.interface-name", "connection", "show", name], check=False)
            if check.stdout.strip() == PARENT_DEV:
                return name
    return None


def get_interface_ip(ifname: str) -> list[str]:
    """Get list of IPv4 addresses for an interface."""
    res = run_cmd(["ip", "-4", "-br", "addr", "show", ifname], check=False)
    if res.returncode != 0 or not res.stdout.strip():
        return []
    parts = res.stdout.strip().split()
    if len(parts) >= 3:
        return parts[2:]
    return []


def get_interface_mac(ifname: str) -> str:
    """Get MAC address of an interface."""
    res = run_cmd(["cat", f"/sys/class/net/{ifname}/address"], check=False)
    return res.stdout.strip() if res.returncode == 0 else "unknown"


def print_status():
    """Print current status of trunk and VLAN interfaces."""
    print(f"\n{C_CYAN}=== Multi-VLAN Cisco Trunk Status ({PARENT_DEV}) ==={C_RESET}")

    # Check parent
    parent_ip = get_interface_ip(PARENT_DEV)
    parent_mac = get_interface_mac(PARENT_DEV)
    parent_conn = get_parent_connection()
    print(f"\n{C_BOLD}Physical Parent Interface ({PARENT_DEV}):{C_RESET}")
    print(f"  Connection : {parent_conn or 'None'}")
    print(f"  MAC Address: {C_YELLOW}{parent_mac}{C_RESET}")
    print(f"  IP Address : {C_GREEN}{', '.join(parent_ip) if parent_ip else 'Searching / None'}{C_RESET}")

    # Check VLANs
    print(f"\n{C_BOLD}Active VLAN Sub-interfaces:{C_RESET}")
    conns = get_nm_connections()
    for vid, cfg in sorted(VLAN_DEFS.items(), key=lambda x: x[1]["metric"]):
        vname = cfg["name"]
        is_configured = vname in conns
        if is_configured:
            ips = get_interface_ip(vname)
            mac = get_interface_mac(vname)
            ip_str = f"{C_GREEN}{', '.join(ips)}{C_RESET}" if ips else f"{C_YELLOW}DHCP Searching...{C_RESET}"
            print(f"  ✔ {C_BOLD}{vname}{C_RESET} (VLAN {vid}) | MAC: {mac} | Metric: {cfg['metric']} | IP: {ip_str}")
            print(f"    └─ {C_GRAY}{cfg['desc']}{C_RESET}")
        else:
            print(f"  ✖ {C_GRAY}{vname} (VLAN {vid}) | Not configured{C_RESET}")

    # Show Specific Static Routes if configured
    print(f"\n{C_BOLD}Custom Static Routes:{C_RESET}")
    spec_routes = run_cmd(["ip", "-4", "route", "show", "10.50.0.0/24"], check=False)
    if spec_routes.stdout.strip():
        for r in spec_routes.stdout.strip().splitlines():
            print(f"  ✔ {C_GREEN}{r}{C_RESET}")
    else:
        print(f"  {C_GRAY}No static route active for 10.50.0.0/24{C_RESET}")

    # Show Default Routes
    print(f"\n{C_BOLD}Default IPv4 Gateways (Routing Priority):{C_RESET}")
    routes_res = run_cmd(["ip", "-4", "route", "show", "default"], check=False)
    if routes_res.stdout.strip():
        for r in routes_res.stdout.strip().splitlines():
            print(f"  {C_CYAN}{r}{C_RESET}")
    else:
        print(f"  {C_YELLOW}No default route found!{C_RESET}")
    print()


def apply_vlans(selected_vlans: list[str] = None):
    """Create or update VLAN connections and prioritize routes."""
    if selected_vlans is None:
        selected_vlans = ["400", "500", "100"]

    print(f"\n{C_GREEN}🚀 Applying VLAN configuration on {PARENT_DEV}...{C_RESET}")

    # 1. Configure Native Parent connection (eno1)
    parent_conn = get_parent_connection()
    if not parent_conn:
        print(f"{C_YELLOW}⚠️  No active connection for {PARENT_DEV} found. Creating default 'Wired eno1'...{C_RESET}")
        run_cmd([
            "nmcli", "connection", "add", "type", "ethernet",
            "con-name", f"Wired {PARENT_DEV}", "ifname", PARENT_DEV,
            "cloned-mac", NATIVE_SETTINGS["mac"],
            "ipv4.method", "auto", "ipv4.route-metric", str(NATIVE_SETTINGS["metric"]),
        ])
        parent_conn = f"Wired {PARENT_DEV}"
    else:
        print(f"Configuring Native parent connection '{parent_conn}':")
        print(f"  - Setting cloned-mac: {NATIVE_SETTINGS['mac']}")
        print(f"  - Setting route-metric: {NATIVE_SETTINGS['metric']}")
        run_cmd([
            "nmcli", "connection", "modify", parent_conn,
            "802-3-ethernet.cloned-mac-address", NATIVE_SETTINGS["mac"],
            "ipv4.route-metric", str(NATIVE_SETTINGS["metric"]),
        ])
        run_cmd(["nmcli", "connection", "up", parent_conn], check=False)

    # 2. Configure VLAN Sub-interfaces
    conns = get_nm_connections()
    for vid in selected_vlans:
        if vid not in VLAN_DEFS:
            print(f"{C_YELLOW}⚠️  Skipping unknown VLAN {vid}{C_RESET}")
            continue

        cfg = VLAN_DEFS[vid]
        vname = cfg["name"]
        print(f"\n{C_CYAN}Setting up {vname} (VLAN {vid})...{C_RESET}")

        routes_val = ",".join(cfg.get("routes", []))
        if vname in conns:
            print(f"  Updating existing connection '{vname}'...")
            run_cmd([
                "nmcli", "connection", "modify", vname,
                "vlan.parent", PARENT_DEV,
                "vlan.id", str(cfg["id"]),
                "802-3-ethernet.cloned-mac-address", cfg["mac"],
                "ipv4.method", cfg["method"],
                "ipv4.route-metric", str(cfg["metric"]),
                "ipv4.routes", routes_val,
            ])
        else:
            print(f"  Creating new VLAN connection '{vname}'...")
            add_cmd = [
                "nmcli", "connection", "add", "type", "vlan",
                "con-name", vname,
                "ifname", vname,
                "dev", PARENT_DEV,
                "id", str(cfg["id"]),
                "802-3-ethernet.cloned-mac-address", cfg["mac"],
                "ipv4.method", cfg["method"],
                "ipv4.route-metric", str(cfg["metric"]),
            ]
            if routes_val:
                add_cmd.extend(["ipv4.routes", routes_val])
            run_cmd(add_cmd)

        # Activate connection
        print(f"  Activating {vname}...")
        act_res = run_cmd(["nmcli", "connection", "up", vname], check=False)
        if act_res.returncode == 0:
            print(f"  {C_GREEN}✔ {vname} activated successfully.{C_RESET}")
        else:
            print(f"  {C_YELLOW}⚠️  Activation notice: {act_res.stderr.strip()}{C_RESET}")

    print(f"\n{C_YELLOW}Waiting 4 seconds for DHCP leases to populate...{C_RESET}")
    time.sleep(4)
    print_status()


def reset_vlans():
    """Remove VLAN sub-interfaces and restore eno1 to default state."""
    print(f"\n{C_YELLOW}⚠️  Resetting all VLAN sub-interfaces on {PARENT_DEV}...{C_RESET}")

    conns = get_nm_connections()
    for vid, cfg in VLAN_DEFS.items():
        vname = cfg["name"]
        if vname in conns:
            print(f"  Deleting connection: {vname}...")
            run_cmd(["nmcli", "connection", "delete", vname], check=False)

    parent_conn = get_parent_connection()
    if parent_conn:
        print(f"  Reverting parent connection '{parent_conn}' to physical MAC...")
        run_cmd([
            "nmcli", "connection", "modify", parent_conn,
            "802-3-ethernet.cloned-mac-address", "",
            "ipv4.route-metric", "-1",
        ], check=False)
        run_cmd(["nmcli", "connection", "up", parent_conn], check=False)

    print(f"\n{C_GREEN}✔ Reset completed. {PARENT_DEV} returned to standalone state.{C_RESET}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Multi-VLAN Cisco Trunk and vNIC Manager for Linux",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("vlans", nargs="*", help="VLAN IDs to configure (e.g. 100 400 500)")
    parser.add_argument("-s", "--status", action="store_true", help="Show current VLAN status")
    parser.add_argument("-r", "--reset", action="store_true", help="Remove VLANs and reset eno1")

    args = parser.parse_args()

    if args.status:
        print_status()
        return

    if args.reset:
        reset_vlans()
        return

    if args.vlans:
        apply_vlans(args.vlans)
        return

    # Interactive Menu if no arguments passed
    print(f"\n{C_CYAN}=== Multi-VLAN Cisco Trunk Manager ({PARENT_DEV}) ==={C_RESET}")
    print("Select an option:")
    print(f"  {C_GREEN}[1] Apply All VLANs (400, 500, 100 + Native) [RECOMMENDED]{C_RESET}")
    print(f"  {C_CYAN}[2] Show Current Status{C_RESET}")
    print(f"  {C_YELLOW}[r] Reset VLANs (Restore eno1 to standalone){C_RESET}")
    print(f"  {C_GRAY}[q] Quit{C_RESET}")

    try:
        choice = input("\nEnter choice [1/2/r/q, Default: 1]: ").strip().lower()
    except (KeyboardInterrupt, EOFError):
        print()
        return

    if not choice or choice == "1":
        apply_vlans(["400", "500", "100"])
    elif choice == "2":
        print_status()
    elif choice == "r":
        reset_vlans()
    else:
        print("Cancelled.")


if __name__ == "__main__":
    main()
