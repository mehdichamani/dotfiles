#!/usr/bin/env python3
"""
Mesh Core - Unified backend for SSH connections, port forwarding/tunnels,
and Git peer-to-peer mesh sync across multiple devices.
Designed for Python 3.14+ standard library (no external pip dependencies).
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tomllib
from typing import Any, Dict, List, Optional, Tuple


def get_devices_toml_path() -> Path:
    live = Path.home() / ".ssh" / "devices.toml"
    if live.is_file():
        return live
    repo = Path.home() / ".local" / "share" / "chezmoi" / "dot_ssh" / "devices.toml"
    if repo.is_file():
        return repo
    return live


def load_devices() -> Dict[str, Any]:
    p = get_devices_toml_path()
    if not p.is_file():
        return {}
    try:
        with open(p, "rb") as f:
            data = tomllib.load(f)
            return data.get("devices", {})
    except Exception as e:
        print(f"Error loading {p}: {e}", file=sys.stderr)
        return {}


def get_ssh_config_host_info(host: str) -> Tuple[str, int]:
    """Retrieve hostname and port for host alias via ssh -G."""
    try:
        res = subprocess.run(
            ["ssh", "-G", host],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
        hn = host
        pt = 22
        for line in res.stdout.splitlines():
            line = line.strip()
            if line.startswith("hostname "):
                hn = line.split(maxsplit=1)[1].strip()
            elif line.startswith("port "):
                try:
                    pt = int(line.split(maxsplit=1)[1].strip())
                except ValueError:
                    pass
        return hn, pt
    except Exception:
        return host, 22


def probe_single_route(route: str, timeout: float = 2.5) -> bool:
    """Fast TCP socket connect probe. Returns True if route is reachable."""
    hn, pt = get_ssh_config_host_info(route)
    try:
        with socket.create_connection((hn, pt), timeout=timeout):
            return True
    except OSError:
        return False


def probe_fastest_route(routes: List[str], max_wait: float = 3.0) -> Optional[str]:
    """Probes candidate routes concurrently and returns the first one that connects."""
    if not routes:
        return None
    if len(routes) == 1:
        return routes[0]

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(routes)) as executor:
        future_to_route = {
            executor.submit(probe_single_route, r, max_wait): r for r in routes
        }
        for future in concurrent.futures.as_completed(
            future_to_route, timeout=max_wait + 0.5
        ):
            route = future_to_route[future]
            try:
                if future.result():
                    executor.shutdown(wait=False, cancel_futures=True)
                    return route
            except Exception:
                pass
    return None


def get_local_host_id() -> str:
    name_file = Path.home() / ".config" / "name"
    if name_file.is_file():
        try:
            val = name_file.read_text().strip().lower()
            if val:
                return val
        except Exception:
            pass
    return socket.gethostname().split(".")[0].lower()


# ----------------------------------------------------------------------
# CLI Commands
# ----------------------------------------------------------------------


def cmd_resolve(args: argparse.Namespace) -> int:
    """Resolve target and action into exact SSH command line arguments."""
    devices = load_devices()
    target_key = args.target.lower()

    matched_key = None
    dev = None
    for k, v in devices.items():
        if k.lower() == target_key or v.get("name", "").lower() == target_key:
            matched_key = k
            dev = v
            break

    # If target is not in devices.toml, return as-is
    if not dev:
        output = {
            "target": args.target,
            "route": args.target,
            "type": "direct",
            "ssh_args": args.extra_args,
        }
        print(json.dumps(output))
        return 0

    routes = dev.get("routes", [])
    if not routes and dev.get("ip"):
        routes = [dev["ip"]]

    best_route = None
    if routes:
        if args.skip_probe or len(routes) == 1:
            best_route = routes[0]
        else:
            best_route = probe_fastest_route(routes) or routes[0]
    else:
        best_route = matched_key

    # Check action (tunnel or named command or raw args)
    action = args.action.lower() if args.action else ""
    tunnels = dev.get("tunnels", {})
    commands = dev.get("commands", {})

    action_type = "shell"
    ssh_args: List[str] = []

    if action in tunnels:
        action_type = f"tunnel:{action}"
        # Tunnel arguments string from toml (e.g. "-N -L 3390:localhost:3389")
        ssh_args.extend(tunnels[action].split())
        ssh_args.extend(args.extra_args)
    elif action in commands:
        action_type = f"command:{action}"
        ssh_args.append(commands[action])
        ssh_args.extend(args.extra_args)
    elif action:
        # Check if action is a custom port forward spec (e.g. -L or 8080)
        if action.isdigit():
            action_type = "tunnel:custom"
            ssh_args.extend(["-N", "-L", f"{action}:localhost:{action}"])
            ssh_args.extend(args.extra_args)
        elif ":" in action and all(p.isdigit() for p in action.split(":", 1)):
            action_type = "tunnel:custom"
            p1, p2 = action.split(":", 1)
            ssh_args.extend(["-N", "-L", f"{p1}:localhost:{p2}"])
            ssh_args.extend(args.extra_args)
        else:
            action_type = "custom"
            ssh_args.append(args.action)
            ssh_args.extend(args.extra_args)
    else:
        ssh_args.extend(args.extra_args)

    output = {
        "target": matched_key,
        "name": dev.get("name", matched_key),
        "device_type": dev.get("type", "workstation"),
        "os": dev.get("os", "linux"),
        "shell": dev.get("shell", "bash"),
        "route": best_route,
        "action_type": action_type,
        "ssh_args": ssh_args,
    }
    print(json.dumps(output))
    return 0


def cmd_list_nodes(args: argparse.Namespace) -> int:
    devices = load_devices()
    if args.format == "json":
        print(json.dumps(devices, indent=2))
        return 0

    # Human / FZF menu format
    for k, v in devices.items():
        t = v.get("type", "workstation")
        icon = (
            "📱"
            if t == "mobile"
            else (
                "💻"
                if t in ("workstation", "server")
                else ("📡" if t == "radio" else ("🌐" if t == "router" else "🔌"))
            )
        )
        name = v.get("name", k)
        desc = f" - {v.get('desc')}" if v.get("desc") else ""
        ip = f" ({v.get('ip')})" if v.get("ip") else ""
        print(f"{k:<20} │ {icon} {name}{ip}{desc}")
    return 0


def cmd_list_actions(args: argparse.Namespace) -> int:
    devices = load_devices()
    target = args.target.lower()
    dev = next((v for k, v in devices.items() if k.lower() == target), {})
    if not dev:
        print("🐚 SSH Shell")
        return 0

    print("🐚 SSH Shell")
    tunnels = dev.get("tunnels", {})
    for t, val in tunnels.items():
        icon = "🖥️ " if t == "rdp" else ("🖼️ " if t == "vnc" else ("🍿" if t == "jellyfin" else "🔌"))
        print(f"{icon} {t:<12} │ Tunnel: {val}")

    commands = dev.get("commands", {})
    for c, val in commands.items():
        print(f"⚡ {c:<12} │ Exec: {val}")
    return 0


def cmd_preview(args: argparse.Namespace) -> int:
    devices = load_devices()
    target = args.target.lower()
    dev = next((v for k, v in devices.items() if k.lower() == target), {})
    if not dev:
        print(f"Node: {args.target}")
        return 0

    print(f"\033[1;36m=== {dev.get('name', target)} ({target}) ===\033[0m\n")
    print(f"\033[1;33mType:\033[0m        {dev.get('type', 'workstation')}")
    print(f"\033[1;33mDescription:\033[0m {dev.get('desc', '-')}")
    print(f"\033[1;33mOS / Shell:\033[0m  {dev.get('os', '-')} / {dev.get('shell', '-')}")
    if dev.get("ip"):
        print(f"\033[1;33mIP:\033[0m          {dev.get('ip')}")
    if dev.get("routes"):
        print(f"\033[1;33mRoutes:\033[0m      {', '.join(dev.get('routes', []))}")
    if dev.get("sync"):
        print(f"\033[1;33mSync Repo:\033[0m   {dev.get('sync')}")

    tunnels = dev.get("tunnels", {})
    if tunnels:
        print("\n\033[1;32m🔌 Tunnels (SSH -L):\033[0m")
        for t, v in tunnels.items():
            print(f"  • \033[1;36m{t:<10}\033[0m -> {v}")

    commands = dev.get("commands", {})
    if commands:
        print("\n\033[1;32m⚡ Named Commands:\033[0m")
        for c, v in commands.items():
            print(f"  • \033[1;36m{c:<10}\033[0m -> {v}")
    return 0


def cmd_complete(args: argparse.Namespace) -> int:
    devices = load_devices()
    ctype = args.comp_type

    if ctype in ("targets", "nodes"):
        for k in devices.keys():
            print(k)
        for v in devices.values():
            if v.get("ip"):
                print(v["ip"])
    elif ctype == "actions" and args.target:
        target = args.target.lower()
        dev = next(
            (v for k, v in devices.items() if k.lower() == target),
            {},
        )
        for t in dev.get("tunnels", {}).keys():
            print(t)
        for c in dev.get("commands", {}).keys():
            print(c)
    elif ctype == "sync_peers":
        for k, v in devices.items():
            if v.get("sync") is True:
                print(k)
    return 0


# ----------------------------------------------------------------------
# Dotsync Mesh Sync Logic
# ----------------------------------------------------------------------


def cmd_dotsync(args: argparse.Namespace) -> int:
    devices = load_devices()
    repo_dir = Path.home() / ".local" / "share" / "chezmoi"
    if not (repo_dir / ".git").is_dir():
        print(f"Error: {repo_dir} is not a git repository.", file=sys.stderr)
        return 1

    local_id = get_local_host_id()
    peers = {k: v for k, v in devices.items() if v.get("sync") is True}

    if args.target:
        t_key = args.target.lower()
        if t_key not in peers:
            print(f"Error: Peer '{args.target}' not found with sync=true.")
            return 1
        sync_peers = {t_key: peers[t_key]}
    else:
        sync_peers = {k: v for k, v in peers.items() if k.lower() != local_id}

    if not sync_peers:
        print("No remote peers to sync with.")
        return 0

    print(
        f"\033[1;35m== Dotsync P2P Mesh (Host: {local_id}) ==\033[0m",
        file=sys.stderr,
    )

    # Check local dirty
    status_out = subprocess.run(
        ["git", "-C", str(repo_dir), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()

    if status_out:
        print(
            "\033[1;33mNotice: Uncommitted local changes will be left untouched.\033[0m"
        )

    for peer_key, dev in sync_peers.items():
        print(f"\n\033[1;34m--- Syncing with peer: {peer_key} ---\033[0m")
        routes = dev.get("routes", [peer_key])
        best_route = probe_fastest_route(routes)
        if not best_route:
            print(f"\033[1;31m✕ Unreachable: all routes {routes} failed.\033[0m")
            continue

        peer_repo = dev.get("repo", "~/.local/share/chezmoi")
        remote_url = f"{best_route}:{peer_repo}"

        # Ensure git remote exists
        subprocess.run(
            ["git", "-C", str(repo_dir), "remote", "set-url", peer_key, remote_url],
            capture_output=True,
            check=False,
        )
        if (
            subprocess.run(
                ["git", "-C", str(repo_dir), "remote", "get-url", peer_key],
                capture_output=True,
                check=False,
            ).returncode
            != 0
        ):
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo_dir),
                    "remote",
                    "add",
                    peer_key,
                    remote_url,
                ],
                check=False,
            )

        branch = (
            subprocess.run(
                ["git", "-C", str(repo_dir), "rev-parse", "--abbrev-ref", "HEAD"],
                capture_output=True,
                text=True,
                check=False,
            ).stdout.strip()
            or "main"
        )

        print(f"Connected via \033[1;32m{best_route}\033[0m. Fetching metadata...")
        fetch_res = subprocess.run(
            [
                "git",
                "-C",
                str(repo_dir),
                "fetch",
                peer_key,
                f"+refs/heads/{branch}:refs/remotes/{peer_key}/{branch}",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if fetch_res.returncode != 0:
            print(f"\033[1;31mFetch failed:\033[0m {fetch_res.stderr.strip()}")
            continue

        remote_ref = f"{peer_key}/{branch}"
        behind = int(
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo_dir),
                    "rev-list",
                    "--count",
                    f"HEAD..{remote_ref}",
                ],
                capture_output=True,
                text=True,
                check=False,
            ).stdout.strip()
            or "0"
        )
        ahead = int(
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo_dir),
                    "rev-list",
                    "--count",
                    f"{remote_ref}..HEAD",
                ],
                capture_output=True,
                text=True,
                check=False,
            ).stdout.strip()
            or "0"
        )

        if args.dry_run:
            print(
                f"  Status: \033[1;36mAhead: {ahead}\033[0m | \033[1;35mBehind: {behind}\033[0m"
            )
            continue

        if ahead == 0 and behind == 0:
            print(f"  \033[1;32m✓ In sync with {peer_key}.\033[0m")
        elif ahead > 0 and behind == 0:
            print(
                f"  Local is ahead by {ahead} commit(s). Pushing to {peer_key}..."
            )
            push_res = subprocess.run(
                ["git", "-C", str(repo_dir), "push", peer_key, branch]
            )
            if push_res.returncode == 0:
                print(f"  \033[1;32m✓ Successfully pushed to {peer_key}.\033[0m")
        elif behind > 0 and ahead == 0:
            print(
                f"  Peer {peer_key} is ahead by {behind} commit(s). Fast-forward pulling..."
            )
            pull_res = subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo_dir),
                    "pull",
                    "--ff-only",
                    peer_key,
                    branch,
                ]
            )
            if pull_res.returncode == 0:
                print(f"  \033[1;32m✓ Fast-forward pull successful.\033[0m")
        else:
            print(
                f"\033[1;33m⚠️ Diverged history! Ahead: {ahead}, Behind: {behind}\033[0m"
            )
            print("  [1] Rebase & Push")
            print("  [2] Push Force (overwrite remote)")
            print("  [3] Pull Force (overwrite local)")
            print("  [4] Abort (default)")
            choice = input("  Select action [1/2/3/4]: ").strip()
            if choice in ("1", "rebase"):
                subprocess.run(
                    ["git", "-C", str(repo_dir), "rebase", remote_ref],
                    check=True,
                )
                subprocess.run(
                    ["git", "-C", str(repo_dir), "push", peer_key, branch],
                    check=True,
                )
                print(f"  \033[1;32m✓ Rebase and sync complete.\033[0m")
            elif choice in ("2", "push"):
                subprocess.run(
                    [
                        "git",
                        "-C",
                        str(repo_dir),
                        "push",
                        "--force",
                        peer_key,
                        branch,
                    ],
                    check=True,
                )
                print(f"  \033[1;32m✓ Force push complete.\033[0m")
            elif choice in ("3", "pull"):
                subprocess.run(
                    ["git", "-C", str(repo_dir), "reset", "--hard", remote_ref],
                    check=True,
                )
                print(f"  \033[1;32m✓ Local reset to remote state.\033[0m")
            else:
                print("  Aborted.")

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Mesh Core SSH & Dotsync Engine"
    )
    subparsers = parser.add_subparsers(dest="cmd")

    # resolve
    p_res = subparsers.add_parser("resolve")
    p_res.add_argument("target", help="Device key or route")
    p_res.add_argument("action", nargs="?", default="", help="Tunnel or command")
    p_res.add_argument(
        "--skip-probe",
        action="store_true",
        help="Skip route network probing",
    )
    p_res.add_argument(
        "extra_args",
        nargs=argparse.REMAINDER,
        help="Remaining ssh arguments",
    )

    # list-nodes
    p_list = subparsers.add_parser("list-nodes")
    p_list.add_argument("--format", choices=["fzf", "json"], default="fzf")

    # list-actions
    p_act = subparsers.add_parser("list-actions")
    p_act.add_argument("target", help="Device target")

    # preview
    p_prev = subparsers.add_parser("preview")
    p_prev.add_argument("target", help="Device target")

    # complete
    p_comp = subparsers.add_parser("complete")
    p_comp.add_argument(
        "comp_type", choices=["targets", "actions", "sync_peers"]
    )
    p_comp.add_argument("target", nargs="?", default="")

    # dotsync
    p_sync = subparsers.add_parser("dotsync")
    p_sync.add_argument("target", nargs="?", default="")
    p_sync.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="Check differences only",
    )

    args = parser.parse_args()
    if args.cmd == "resolve":
        return cmd_resolve(args)
    elif args.cmd == "list-nodes":
        return cmd_list_nodes(args)
    elif args.cmd == "list-actions":
        return cmd_list_actions(args)
    elif args.cmd == "preview":
        return cmd_preview(args)
    elif args.cmd == "complete":
        return cmd_complete(args)
    elif args.cmd == "dotsync":
        return cmd_dotsync(args)
    else:
        parser.print_help()
        return 0


if __name__ == "__main__":
    sys.exit(main())
