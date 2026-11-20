#!/usr/bin/env python3
"""
ssh_vault_core.py - Unified Backend for SSH & Secrets Vault Manager (`sm`)

Provides core operations for:
  - P2P Mesh Sync between active devices (s24, work, winvm, etc.)
  - Cloud Remote Operations (push/send & pull/get) to Cloudflare KV Vault
  - Zero-Knowledge Multi-way Diff & Status inspection
  - Cloud Snapshot History inspection
"""

from __future__ import annotations

import argparse
import concurrent.futures
import getpass
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Set, Tuple

# Terminal colors
BOLD = "\033[1m"
GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
CYAN = "\033[0;36m"
RED = "\033[0;31m"
MAGENTA = "\033[0;35m"
DIM = "\033[2m"
RESET = "\033[0m"

IGNORE_PATTERNS = {
    "known_hosts",
    "known_hosts.old",
    ".DS_Store",
    ".git",
    "authorized_keys.old",
}


def get_current_host_name() -> str:
    """Reads current host name from ~/.config/name or platform fallback."""
    name_file = Path.home() / ".config" / "name"
    if name_file.exists():
        try:
            val = name_file.read_text(encoding="utf-8").strip()
            if val:
                return val
        except Exception:
            pass
    return socket.gethostname().split(".")[0]


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
        import tomllib

        with open(p, "rb") as f:
            data = tomllib.load(f)
            return data.get("devices", {})
    except Exception as e:
        print(f"{YELLOW}⚠️ Error loading {p}: {e}{RESET}", file=sys.stderr)
        return {}


def load_vault_config() -> Tuple[str, Optional[str]]:
    """Reads VAULT_URL and optional SYNC_TOKEN from ~/.ssh/secrets/cf-ssh-sync.env."""
    env_file = Path.home() / ".ssh" / "secrets" / "cf-ssh-sync.env"
    vault_url = "https://ssh.ajbv.ir"
    sync_token = None
    if env_file.exists():
        try:
            for line in env_file.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line.startswith("VAULT_URL="):
                    val = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if val:
                        vault_url = val
                elif line.startswith("SYNC_TOKEN="):
                    val = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if val:
                        sync_token = val
        except Exception:
            pass
    return vault_url, sync_token


def should_ignore(rel_path: str) -> bool:
    name = Path(rel_path).name
    if name in IGNORE_PATTERNS or name.endswith(".tmp") or name.endswith(".swp"):
        return True
    return False


def get_dir_file_hashes(base_dir: Path) -> Dict[str, str]:
    """Recursively computes SHA256 of all relevant files in base_dir."""
    file_hashes = {}
    if not base_dir.exists():
        return file_hashes

    for root, _, files in os.walk(base_dir):
        for f in files:
            full_path = Path(root) / f
            rel_path = str(full_path.relative_to(base_dir))
            if should_ignore(rel_path):
                continue
            try:
                content = full_path.read_bytes()
                file_hashes[rel_path] = hashlib.sha256(content).hexdigest()
            except Exception as e:
                print(f"{YELLOW}⚠️ Could not read {rel_path}: {e}{RESET}", file=sys.stderr)
    return file_hashes


def apply_permissions(ssh_dir: Path):
    """Applies strict security permissions (700 for directories, 600 for secrets/keys, 644 for pub)."""
    try:
        ssh_dir.chmod(0o700)
        for root, dirs, files in os.walk(ssh_dir):
            for d in dirs:
                (Path(root) / d).chmod(0o700)
            for f in files:
                p = Path(root) / f
                if p.suffix == ".pub":
                    p.chmod(0o644)
                else:
                    p.chmod(0o600)
    except Exception as e:
        print(f"{YELLOW}⚠️ Notice applying permissions: {e}{RESET}")


def resolve_ssh_host(target: str) -> str:
    """
    Resolves host name using mesh_core.py and devices.toml if available.
    For example, 's24' will probe and resolve to the fastest active route.
    """
    scripts_dir = Path.home() / ".config" / "scripts"
    mesh_script = scripts_dir / "mesh_core.py"
    if mesh_script.exists():
        try:
            cmd = [sys.executable, str(mesh_script), "resolve", target]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                data = json.loads(res.stdout)
                route = data.get("route")
                if route:
                    return route
        except Exception:
            pass
    return target


def extract_remote_target(host: str, target_dir: Path) -> bool:
    """Extracts ~/.ssh from a live remote host over SSH stream into target_dir."""
    resolved_route = resolve_ssh_host(host)
    route_display = f"'{host}' (via {resolved_route})" if resolved_route != host else f"'{host}'"
    print(f"{CYAN}📡 Fetching ~/.ssh from live host {route_display} via SSH...{RESET}")

    remote_cmd = "tar -cz -C \"$HOME/.ssh\" --exclude 'known_hosts*' ."
    ssh_cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=7", resolved_route, remote_cmd]

    try:
        proc = subprocess.Popen(ssh_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        tar_cmd = ["tar", "-xz", "-C", str(target_dir)]
        tar_proc = subprocess.Popen(tar_cmd, stdin=proc.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        proc.stdout.close()
        _, tar_err = tar_proc.communicate()
        _, ssh_err = proc.communicate()

        if proc.returncode != 0:
            err_msg = ssh_err.decode().strip()
            print(f"{RED}❌ Failed to connect to host '{host}': {err_msg}{RESET}")
            return False
        if tar_proc.returncode != 0:
            print(f"{RED}❌ Failed to unpack files from host '{host}': {tar_err.decode().strip()}{RESET}")
            return False
        return True
    except Exception as e:
        print(f"{RED}❌ Error running SSH command: {e}{RESET}")
        return False


def decrypt_payload(ciphertext_bytes: bytes, target_dir: Path, passphrase: Optional[str] = None) -> bool:
    """Decrypts AES-256-CBC ciphertext into target_dir."""
    if not passphrase:
        try:
            passphrase = getpass.getpass(f"{CYAN}🔒 Enter master passphrase for cloud vault: {RESET}")
        except (KeyboardInterrupt, EOFError):
            print("\nAborted.")
            sys.exit(1)

    if not passphrase:
        print(f"{RED}❌ Passphrase cannot be empty.{RESET}", file=sys.stderr)
        return False

    with tempfile.NamedTemporaryFile("wb", delete=False) as enc_file, \
         tempfile.NamedTemporaryFile("wb", delete=False) as dec_file:
        enc_path = enc_file.name
        dec_path = dec_file.name
        enc_file.write(ciphertext_bytes)

    try:
        cmd_decrypt = [
            "openssl", "enc", "-d", "-aes-256-cbc",
            "-pbkdf2", "-salt",
            "-in", enc_path,
            "-out", dec_path,
            "-pass", f"pass:{passphrase}"
        ]
        res = subprocess.run(cmd_decrypt, capture_output=True)
        if res.returncode != 0:
            fallback_cmd = [
                "openssl", "enc", "-d", "-aes-256-cbc",
                "-pbkdf2",
                "-in", enc_path,
                "-out", dec_path,
                "-pass", f"pass:{passphrase}"
            ]
            res = subprocess.run(fallback_cmd, capture_output=True)
            if res.returncode != 0:
                print(f"{RED}❌ Decryption failed. Incorrect passphrase or corrupted payload.{RESET}", file=sys.stderr)
                return False

        dec_bytes = Path(dec_path).read_bytes()[:4]
        if dec_bytes.startswith(b"\x1f\x8b"):
            cmd_untar = ["tar", "-xzf", dec_path, "-C", str(target_dir)]
            res_tar = subprocess.run(cmd_untar, capture_output=True)
            if res_tar.returncode != 0:
                print(f"{RED}❌ Failed to unpack tar.gz archive.{RESET}", file=sys.stderr)
                return False
        elif dec_bytes.startswith(b"PK\x03\x04"):
            shutil.unpack_archive(dec_path, str(target_dir), "zip")
        else:
            cmd_untar = ["tar", "-xf", dec_path, "-C", str(target_dir)]
            res_tar = subprocess.run(cmd_untar, capture_output=True)
            if res_tar.returncode != 0:
                print(f"{RED}❌ Failed to unpack tar archive.{RESET}", file=sys.stderr)
                return False

        # Normalize directory: handle nested 'ssh' or '.ssh' directories
        for sub in ("ssh", ".ssh"):
            nested = target_dir / sub
            if nested.is_dir():
                for item in nested.iterdir():
                    dest = target_dir / item.name
                    if dest.exists():
                        if dest.is_dir():
                            shutil.rmtree(dest)
                        else:
                            dest.unlink()
                    shutil.move(str(item), str(target_dir))
                nested.rmdir()

        return True
    except Exception as e:
        print(f"{RED}❌ Extraction error: {e}{RESET}", file=sys.stderr)
        return False
    finally:
        if os.path.exists(enc_path):
            os.unlink(enc_path)
        if os.path.exists(dec_path):
            os.unlink(dec_path)


def extract_cloud_target(vault_url: str, version: Optional[int], target_dir: Path, passphrase_cache: dict) -> bool:
    """Downloads encrypted vault from Cloudflare KV and unpacks it."""
    url = f"{vault_url.rstrip('/')}/data"
    if version is not None and version > 0:
        url += f"?v={version}"

    label = f"cloud (v{version})" if version else "cloud (latest)"
    print(f"{CYAN}🌐 Fetching {label} from {url}...{RESET}")

    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (cf-ssh-sync/client)"}
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"{RED}❌ No snapshot found on cloud for version {version or 'latest'}.{RESET}")
        else:
            print(f"{RED}❌ HTTP Error {e.code}: {e.reason}{RESET}")
        return False
    except Exception as e:
        print(f"{RED}❌ Network connection failed: {e}{RESET}")
        return False

    passphrase = passphrase_cache.get("pass")
    success = decrypt_payload(data, target_dir, passphrase=passphrase)
    if success and not passphrase:
        passphrase_cache["pass"] = passphrase
    return success


def upload_local_to_cloud(vault_url: str, sync_token: Optional[str], passphrase_cache: dict) -> bool:
    """Encrypts local ~/.ssh and uploads payload to Cloudflare KV."""
    local_ssh = Path.home() / ".ssh"
    if not local_ssh.is_dir():
        print(f"{RED}❌ Local directory {local_ssh} does not exist.{RESET}", file=sys.stderr)
        return False

    passphrase = passphrase_cache.get("pass")
    if not passphrase:
        try:
            passphrase = getpass.getpass(f"{CYAN}🔒 Enter encryption passphrase for uploading to cloud: {RESET}")
        except (KeyboardInterrupt, EOFError):
            print("\nAborted.")
            return False

    if not passphrase:
        print(f"{RED}❌ Passphrase cannot be empty.{RESET}", file=sys.stderr)
        return False

    token = sync_token
    if not token:
        try:
            token = getpass.getpass(f"{YELLOW}🔑 Enter SYNC_TOKEN (press Enter if not required): {RESET}").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nAborted.")
            return False

    print(f"\n{BOLD}{CYAN}🚀 Archiving & encrypting ~/.ssh with AES-256-CBC...{RESET}")
    with tempfile.TemporaryDirectory(prefix="ssh_upload_") as temp_stage:
        stage_ssh = Path(temp_stage) / "ssh"
        stage_ssh.mkdir(parents=True, exist_ok=True)

        for item in local_ssh.iterdir():
            if should_ignore(item.name):
                continue
            dest = stage_ssh / item.name
            if item.is_dir():
                shutil.copytree(str(item), str(dest), dirs_exist_ok=True)
            else:
                shutil.copy2(str(item), str(dest))

        enc_path = Path(temp_stage) / "payload.enc"

        tar_cmd = ["tar", "--exclude=.git", "--exclude=known_hosts*", "-C", temp_stage, "-czf", "-", "."]
        enc_cmd = [
            "openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-salt",
            "-pass", f"pass:{passphrase}",
            "-out", str(enc_path)
        ]

        try:
            p_tar = subprocess.Popen(tar_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            p_enc = subprocess.Popen(enc_cmd, stdin=p_tar.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            p_tar.stdout.close()
            _, enc_err = p_enc.communicate()
            _, tar_err = p_tar.communicate()

            if p_tar.returncode != 0 or p_enc.returncode != 0:
                print(f"{RED}❌ Encryption failed: {enc_err.decode().strip() or tar_err.decode().strip()}{RESET}")
                return False

            payload_bytes = enc_path.read_bytes()
            upload_url = f"{vault_url.rstrip('/')}/data"
            if token:
                upload_url += f"?token={urllib.parse.quote(token)}"

            headers = {
                "Content-Type": "application/octet-stream",
                "User-Agent": "Mozilla/5.0 (cf-ssh-sync/client)",
            }
            if token:
                headers["X-Sync-Token"] = token

            print(f"{CYAN}🌐 Uploading encrypted payload to {vault_url}...{RESET}")
            req = urllib.request.Request(upload_url, data=payload_bytes, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=20) as resp:
                if resp.status in (200, 201):
                    print(f"{GREEN}✔ Successfully pushed encrypted vault payload to Cloudflare KV!{RESET}\n")
                    return True
                else:
                    print(f"{RED}❌ Upload returned HTTP {resp.status}{RESET}")
                    return False
        except urllib.error.HTTPError as e:
            if e.code == 401:
                print(f"{RED}❌ Unauthorized (401): Invalid or missing SYNC_TOKEN.{RESET}")
            else:
                print(f"{RED}❌ HTTP Error {e.code}: {e.reason}{RESET}")
            return False
        except Exception as e:
            print(f"{RED}❌ Upload error: {e}{RESET}")
            return False


def restore_cloud_to_local(cloud_dir: Path):
    """Restores/merges extracted cloud vault into local ~/.ssh."""
    local_ssh = Path.home() / ".ssh"
    print(f"\n{BOLD}{CYAN}📥 Restoring Cloud Vault to local {local_ssh}...{RESET}")

    for item in cloud_dir.iterdir():
        if should_ignore(item.name):
            continue
        dest = local_ssh / item.name
        if item.is_dir():
            shutil.copytree(str(item), str(dest), dirs_exist_ok=True)
        else:
            shutil.copy2(str(item), str(dest))

    apply_permissions(local_ssh)
    print(f"{GREEN}✔ Successfully pulled vault files into {local_ssh} with strict permissions (700/600).{RESET}\n")


def fetch_history(vault_url: str) -> List[dict]:
    """Fetches snapshot history from Cloudflare Worker KV."""
    api_url = f"{vault_url.rstrip('/')}/api/history"
    req = urllib.request.Request(
        api_url,
        headers={"User-Agent": "Mozilla/5.0 (cf-ssh-sync/client)"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read().decode("utf-8")
            return json.loads(data)
    except Exception as e:
        print(f"{RED}❌ Failed to fetch cloud history: {e}{RESET}", file=sys.stderr)
        return []


def compare_directories(
    left_name: str,
    left_dir: Path,
    right_name: str,
    right_dir: Path,
    interactive_diff: bool = False
) -> Tuple[bool, Dict[str, List[str]]]:
    """
    Compares two extracted directories and displays summary & diffs.
    Returns (is_identical, diff_summary_dict).
    """
    left_files = get_dir_file_hashes(left_dir)
    right_files = get_dir_file_hashes(right_dir)

    all_keys = sorted(set(left_files.keys()).union(set(right_files.keys())))

    synced: List[str] = []
    modified: List[str] = []
    only_left: List[str] = []
    only_right: List[str] = []

    for k in all_keys:
        in_left = k in left_files
        in_right = k in right_files

        if in_left and in_right:
            if left_files[k] == right_files[k]:
                synced.append(k)
            else:
                modified.append(k)
        elif in_left:
            only_left.append(k)
        else:
            only_right.append(k)

    diff_summary = {
        "synced": synced,
        "modified": modified,
        "only_left": only_left,
        "only_right": only_right,
    }

    print(f"\n{BOLD}{'=' * 65}{RESET}")
    print(f"{BOLD}📊 Comparison Summary: {CYAN}{left_name}{RESET} {BOLD}vs{RESET} {CYAN}{right_name}{RESET}")
    print(f"{BOLD}{'=' * 65}{RESET}\n")

    if not modified and not only_left and not only_right:
        print(f"  {GREEN}✔ 100% IDENTICAL - Both sides match completely ({len(synced)} files).{RESET}\n")
        return True, diff_summary

    print(f"  {GREEN}● Synced (Identical):{RESET}   {len(synced)}")
    print(f"  {YELLOW}● Modified (Changed):{RESET}   {len(modified)}")
    print(f"  {MAGENTA}● Only in {left_name}:{RESET}    {len(only_left)}")
    print(f"  {CYAN}● Only in {right_name}:{RESET}   {len(only_right)}")
    print("-" * 65)

    if modified:
        print(f"\n{YELLOW}{BOLD}⚠️ Modified Files (Different Hashes):{RESET}")
        for f in modified:
            print(f"  {YELLOW}[MODIFIED]{RESET} {f}")

    if only_left:
        print(f"\n{MAGENTA}{BOLD}➕ Exists only in {left_name}:{RESET}")
        for f in only_left:
            print(f"  {MAGENTA}[ONLY {left_name}]{RESET} {f}")

    if only_right:
        print(f"\n{CYAN}{BOLD}➕ Exists only in {right_name}:{RESET}")
        for f in only_right:
            print(f"  {CYAN}[ONLY {right_name}]{RESET} {f}")

    print(f"\n{BOLD}{'=' * 65}{RESET}")

    if interactive_diff or (modified and sys.stdout.isatty()):
        prompt = f"\n{BOLD}🔍 View line-by-line diff for modified files? [y/N]: {RESET}"
        if interactive_diff:
            confirm = "y"
        else:
            try:
                confirm = input(prompt).strip().lower()
            except (KeyboardInterrupt, EOFError):
                confirm = "n"

        if confirm in ("y", "yes"):
            for f in modified:
                l_file = left_dir / f
                r_file = right_dir / f
                print(f"\n{CYAN}--- {left_name}/{f}{RESET}")
                print(f"{CYAN}+++ {right_name}/{f}{RESET}")
                cmd = ["git", "diff", "--no-index", "--color=always", str(l_file), str(r_file)]
                subprocess.run(cmd)

    return False, diff_summary


def parse_target(target_str: str, default_is_local: bool = False) -> Tuple[str, Optional[int]]:
    """
    Parses a target string into (kind, version).
    Possible outputs:
      ('local', None)
      ('cloud', None)      # latest
      ('cloud', 1)         # version 1
      ('remote:<host>', None)
    """
    s = target_str.strip()
    current_host = get_current_host_name()

    if s in ("local", "self", "me", ".", "") or (s == current_host and default_is_local):
        return ("local", None)
    if s in ("cloud", "vault", "remote", "origin"):
        return ("cloud", None)
    if s.startswith("cloud:v") or s.startswith("vault:v"):
        v = int(s.split(":v", 1)[1])
        return ("cloud", v)
    if s.startswith("v") and s[1:].isdigit():
        return ("cloud", int(s[1:]))
    return (f"remote:{s}", None)


# ==============================================================================
# SUBCOMMAND IMPLEMENTATIONS
# ==============================================================================


def cmd_push(args: argparse.Namespace) -> int:
    """Archiving, encrypting and uploading local ~/.ssh & secrets to Cloud Vault."""
    vault_url, sync_token = load_vault_config()
    print(f"{BOLD}{MAGENTA}== Push SSH & Secrets to Cloud Vault ({vault_url}) =={RESET}")
    passphrase_cache = {}
    success = upload_local_to_cloud(vault_url, sync_token, passphrase_cache)
    return 0 if success else 1


def cmd_pull(args: argparse.Namespace) -> int:
    """Downloads cloud vault snapshot into temporary staging, shows diff and restores."""
    vault_url, _ = load_vault_config()
    current_host = get_current_host_name()
    local_ssh = Path.home() / ".ssh"

    ver = args.version
    ver_label = f"v{ver}" if ver else "latest"
    print(f"{BOLD}{CYAN}== Pull SSH & Secrets from Cloud Vault ({ver_label}) =={RESET}")

    with tempfile.TemporaryDirectory(prefix="ssh_pull_") as temp_stage:
        stage_dir = Path(temp_stage) / "vault"
        stage_dir.mkdir(parents=True, exist_ok=True)
        passphrase_cache = {}

        if not extract_cloud_target(vault_url, ver, stage_dir, passphrase_cache):
            return 1

        is_identical, _ = compare_directories(f"local ({current_host})", local_ssh, f"cloud ({ver_label})", stage_dir, interactive_diff=args.diff)

        if is_identical:
            print(f"{GREEN}✔ Local ~/.ssh is already completely up to date with cloud ({ver_label}).{RESET}")
            return 0

        if args.dry_run:
            print(f"\n{YELLOW}Dry-run mode: skipped applying changes.{RESET}")
            return 0

        if not args.yes:
            try:
                confirm = input(f"\n{YELLOW}⚠️  Apply changes from cloud ({ver_label}) to local {local_ssh}? [y/N]: {RESET}").strip().lower()
            except (KeyboardInterrupt, EOFError):
                print("\nCancelled.")
                return 130
            if confirm not in ("y", "yes"):
                print("Aborted.")
                return 0

        restore_cloud_to_local(stage_dir)
        return 0


def sync_peer_p2p(
    peer: str,
    dry_run: bool = False,
    interactive_diff: bool = False,
    mirror_mode: bool = False,
) -> bool:
    """Syncs ~/.ssh with a specific live peer device over SSH."""
    current_host = get_current_host_name()
    local_ssh = Path.home() / ".ssh"

    with tempfile.TemporaryDirectory(prefix=f"ssh_sync_{peer}_") as temp_stage:
        remote_stage = Path(temp_stage) / peer
        remote_stage.mkdir(parents=True, exist_ok=True)

        if not extract_remote_target(peer, remote_stage):
            return False

        is_identical, diff_summary = compare_directories(
            f"local ({current_host})",
            local_ssh,
            f"peer:{peer}",
            remote_stage,
            interactive_diff=interactive_diff,
        )

        if is_identical:
            print(f"{GREEN}✔ Local ~/.ssh and peer '{peer}' are already identical.{RESET}\n")
            return True

        if dry_run:
            print(f"{YELLOW}Dry-run: changes between local and {peer} displayed above.{RESET}\n")
            return True

        only_remote_files = diff_summary.get("only_right", [])

        # Direct mirror push via CLI flag --mirror
        if mirror_mode:
            return execute_peer_push(peer, local_ssh, only_remote_files, mirror=True)

        print(f"\n{BOLD}⚡ P2P Sync Options for {peer}:{RESET}")
        print(f"  {CYAN}[1]{RESET} Pull: Update local ~/.ssh from {peer}")
        print(f"  {CYAN}[2]{RESET} Push: Update remote {peer} from local ~/.ssh (additive)")
        if only_remote_files:
            print(f"  {MAGENTA}[3]{RESET} Push & Mirror: Overwrite and delete {len(only_remote_files)} extra file(s) on {peer}")
        print(f"  {DIM}[q]{RESET} Skip / No action")

        valid_choices = ["1", "2", "q"]
        prompt_choices = "1/2/q"
        if only_remote_files:
            valid_choices.append("3")
            prompt_choices = "1/2/3/q"

        try:
            choice = input(f"\n{BOLD}Select sync action with {peer} [{prompt_choices}] (default: q): {RESET}").strip().lower()
        except (KeyboardInterrupt, EOFError):
            print("")
            return True

        if choice == "1":
            confirm = input(f"{YELLOW}⚠️  Overwrite local files with copies from '{peer}'? [y/N]: {RESET}").strip().lower()
            if confirm in ("y", "yes"):
                restore_cloud_to_local(remote_stage)
            else:
                print("Cancelled.")
        elif choice == "2":
            confirm = input(f"{YELLOW}⚠️  Push local ~/.ssh to overwrite files on '{peer}'? [y/N]: {RESET}").strip().lower()
            if confirm in ("y", "yes"):
                execute_peer_push(peer, local_ssh, only_remote_files, mirror=False)
            else:
                print("Cancelled.")
        elif choice == "3" and only_remote_files:
            print(f"\n{MAGENTA}{BOLD}Files to be deleted on '{peer}':{RESET}")
            for f in only_remote_files:
                print(f"  {RED}✖  {f}{RESET}")
            confirm = input(f"{RED}{BOLD}⚠️  Are you sure you want to PUSH & MIRROR (this deletes {len(only_remote_files)} file(s) on '{peer}')? [y/N]: {RESET}").strip().lower()
            if confirm in ("y", "yes"):
                execute_peer_push(peer, local_ssh, only_remote_files, mirror=True)
            else:
                print("Cancelled.")
        return True


def execute_peer_push(peer: str, local_ssh: Path, prune_files: List[str], mirror: bool = False) -> bool:
    """Streams local files to remote peer and optionally deletes extra files on remote."""
    resolved = resolve_ssh_host(peer)
    action_label = "Push & Mirror" if mirror else "Push"
    print(f"{CYAN}🚀 Streaming local ~/.ssh to remote {peer} ({resolved}) [{action_label}]...{RESET}")

    tar_cmd = ["tar", "-cz", "--exclude=known_hosts*", "-C", str(local_ssh), "."]
    remote_cmd = 'tar -xz -C "$HOME/.ssh"'
    ssh_cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", resolved, remote_cmd]

    try:
        p1 = subprocess.Popen(tar_cmd, stdout=subprocess.PIPE)
        p2 = subprocess.Popen(ssh_cmd, stdin=p1.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        p1.stdout.close()
        _, err = p2.communicate()
        if p2.returncode != 0:
            print(f"{RED}❌ Push to peer '{peer}' failed: {err.decode().strip()}{RESET}\n")
            return False

        if mirror and prune_files:
            print(f"{MAGENTA}🧹 Pruning {len(prune_files)} extra file(s) on remote '{peer}'...{RESET}")
            quoted_files = " ".join(shlex.quote(f) for f in prune_files)
            dirs = sorted(
                list(set(str(Path(f).parent) for f in prune_files if "/" in f)),
                key=lambda x: len(x),
                reverse=True,
            )
            rm_dirs = " && ".join(f"rmdir -p {shlex.quote(d)} 2>/dev/null || true" for d in dirs)
            prune_cmd = f'cd "$HOME/.ssh" && rm -f {quoted_files}'
            if rm_dirs:
                prune_cmd += f" && {rm_dirs}"

            del_ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", resolved, prune_cmd]
            res_del = subprocess.run(del_ssh, capture_output=True, text=True)
            if res_del.returncode == 0:
                print(f"{GREEN}✔ Extra files deleted on '{peer}'.{RESET}")
            else:
                print(f"{YELLOW}⚠️ Notice during file deletion on '{peer}': {res_del.stderr.strip()}{RESET}")

        print(f"{GREEN}✔ Successfully synced local ~/.ssh to peer '{peer}'!{RESET}\n")
        return True
    except Exception as e:
        print(f"{RED}❌ Sync push error: {e}{RESET}\n")
        return False


def cmd_sync(args: argparse.Namespace) -> int:
    """P2P Mesh Sync across active devices defined with sync=true in devices.toml."""
    devices = load_devices()
    current_host = get_current_host_name()

    sync_peers = {k: v for k, v in devices.items() if v.get("sync") is True and k.lower() != current_host.lower()}

    if args.peer:
        p_key = args.peer.lower()
        if p_key in devices:
            target_peers = {p_key: devices[p_key]}
        else:
            target_peers = {p_key: {"name": args.peer}}
    else:
        target_peers = sync_peers

    if not target_peers:
        print(f"{YELLOW}No syncable peer devices found in devices.toml.{RESET}")
        return 0

    print(f"{BOLD}{MAGENTA}== P2P SSH & Secrets Mesh Sync (Host: {current_host}) =={RESET}")
    print(f"Target peers: {', '.join(target_peers.keys())}\n")

    overall_success = True
    for peer in target_peers:
        ok = sync_peer_p2p(
            peer,
            dry_run=args.dry_run,
            interactive_diff=args.diff,
            mirror_mode=getattr(args, "mirror", False),
        )
        if not ok:
            overall_success = False

    return 0 if overall_success else 1


def cmd_diff(args: argparse.Namespace) -> int:
    """Multi-way comparison between local, peers, and cloud snapshots."""
    vault_url, sync_token = load_vault_config()
    current_host = get_current_host_name()

    t1_str = args.target1
    t2_str = args.target2

    if t2_str is None:
        if t1_str == "local":
            t2_str = f"cloud:v{args.version}" if args.version else "cloud"
        elif t1_str.startswith("cloud"):
            t2_str = "local"
        else:
            t2_str = f"cloud:v{args.version}" if args.version else "local"

    k1, v1 = parse_target(t1_str, default_is_local=True)
    k2, v2 = parse_target(t2_str, default_is_local=False)

    if args.version:
        if k1 == "cloud" and v1 is None:
            v1 = args.version
        if k2 == "cloud" and v2 is None:
            v2 = args.version

    with tempfile.TemporaryDirectory(prefix="ssh_diff_") as temp_base:
        temp_path = Path(temp_base)
        dir1 = temp_path / "target1"
        dir2 = temp_path / "target2"
        dir1.mkdir(parents=True, exist_ok=True)
        dir2.mkdir(parents=True, exist_ok=True)

        passphrase_cache = {}

        name1 = t1_str
        if k1 == "local":
            name1 = f"local ({current_host})"
            dir1 = Path.home() / ".ssh"
        elif k1 == "cloud":
            name1 = f"cloud (v{v1})" if v1 else "cloud (latest)"
            if not extract_cloud_target(vault_url, v1, dir1, passphrase_cache):
                return 1
        elif k1.startswith("remote:"):
            host = k1.split(":", 1)[1]
            name1 = f"remote:{host}"
            if not extract_remote_target(host, dir1):
                return 1

        name2 = t2_str
        if k2 == "local":
            name2 = f"local ({current_host})"
            dir2 = Path.home() / ".ssh"
        elif k2 == "cloud":
            name2 = f"cloud (v{v2})" if v2 else "cloud (latest)"
            if not extract_cloud_target(vault_url, v2, dir2, passphrase_cache):
                return 1
        elif k2.startswith("remote:"):
            host = k2.split(":", 1)[1]
            name2 = f"remote:{host}"
            if not extract_remote_target(host, dir2):
                return 1

        compare_directories(name1, dir1, name2, dir2, interactive_diff=args.diff)
        return 0


def cmd_status(args: argparse.Namespace) -> int:
    """Quick dirty check of local files against latest Cloud Vault snapshot."""
    vault_url, _ = load_vault_config()
    current_host = get_current_host_name()
    local_ssh = Path.home() / ".ssh"

    print(f"{BOLD}🔍 Inspecting local status against Cloud Vault ({vault_url})...{RESET}")
    with tempfile.TemporaryDirectory(prefix="ssh_status_") as temp_stage:
        stage_dir = Path(temp_stage) / "cloud"
        stage_dir.mkdir(parents=True, exist_ok=True)
        passphrase_cache = {}

        if not extract_cloud_target(vault_url, None, stage_dir, passphrase_cache):
            return 1

        local_files = get_dir_file_hashes(local_ssh)
        cloud_files = get_dir_file_hashes(stage_dir)

        all_keys = sorted(set(local_files.keys()).union(set(cloud_files.keys())))
        modified = [k for k in all_keys if k in local_files and k in cloud_files and local_files[k] != cloud_files[k]]
        only_local = [k for k in all_keys if k in local_files and k not in cloud_files]
        only_cloud = [k for k in all_keys if k in cloud_files and k not in local_files]

        if not modified and not only_local and not only_cloud:
            print(f"{GREEN}✔ Local ~/.ssh is clean and in sync with Cloud Vault.{RESET}")
            return 0

        print(f"\n{BOLD}Status breakdown:{RESET}")
        for f in modified:
            print(f"  {YELLOW}M  {f}{RESET}")
        for f in only_local:
            print(f"  {MAGENTA}+  {f} (local only - run 'sm push' to upload){RESET}")
        for f in only_cloud:
            print(f"  {CYAN}-  {f} (cloud only - run 'sm pull' to download){RESET}")
        return 0


def cmd_history(args: argparse.Namespace) -> int:
    """Lists available snapshot history on Cloud Vault."""
    vault_url, _ = load_vault_config()
    print(f"{BOLD}📦 Cloud Vault History ({vault_url}){RESET}")
    history = fetch_history(vault_url)
    if not history:
        print(f"{YELLOW}No snapshot history available or failed to reach worker.{RESET}")
        return 1

    print(f"\n{'VER':<8} {'TIMESTAMP (UTC)':<28} {'SIZE':<12}")
    print("-" * 50)
    for h in history:
        ver_label = "Latest" if h.get("version") == 0 else f"v{h.get('version')}"
        ts = h.get("timestamp", "-")
        sz = f"{h.get('size', 0):,} bytes"
        print(f"{BOLD}{ver_label:<8}{RESET} {ts:<28} {sz:<12}")
    print("\n💡 Tip: Pull or diff any snapshot using: sm pull -v <num>  or  sm diff -v <num>")
    return 0


def main():
    parser = argparse.ArgumentParser(
        prog="sm",
        description="Unified SSH & Secrets Vault Manager (Mesh Sync, Cloud Push/Pull, Zero-Knowledge Diff)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="subcommand", help="Subcommand to execute")

    # push / send
    p_push = subparsers.add_parser("push", aliases=["send"], help="Encrypt and upload local ~/.ssh & secrets to Cloud Vault")

    # pull / get
    p_pull = subparsers.add_parser("pull", aliases=["get"], help="Download, inspect diff and restore Cloud Vault into local ~/.ssh")
    p_pull.add_argument("-v", "--version", type=int, default=None, help="Cloud version number (e.g. 1, 2) to pull")
    p_pull.add_argument("-n", "--dry-run", action="store_true", help="Preview changes without writing to disk")
    p_pull.add_argument("-y", "--yes", action="store_true", help="Apply without asking for confirmation")
    p_pull.add_argument("-d", "--diff", action="store_true", help="Show detailed line-by-line diff directly")

    # sync
    p_sync = subparsers.add_parser("sync", help="P2P Mesh sync ~/.ssh directly with active peer devices")
    p_sync.add_argument("peer", nargs="?", default="", help="Specific peer host (e.g. s24, work) or empty for all mesh peers")
    p_sync.add_argument("-n", "--dry-run", action="store_true", help="Preview differences without writing")
    p_sync.add_argument("-d", "--diff", action="store_true", help="Show detailed line-by-line diff directly")
    p_sync.add_argument("-m", "--mirror", action="store_true", help="Directly push and mirror (delete files on peer that do not exist locally)")

    # diff
    p_diff = subparsers.add_parser("diff", help="Compare ~/.ssh between local, cloud snapshots, or peer devices")
    p_diff.add_argument("target1", nargs="?", default="local", help="First target (local, cloud, cloud:v1, or host name like s24)")
    p_diff.add_argument("target2", nargs="?", default=None, help="Second target (default: cloud or local)")
    p_diff.add_argument("-v", "--version", type=int, default=None, help="Cloud version number (1 to 5)")
    p_diff.add_argument("-d", "--diff", action="store_true", help="Show line-by-line diff immediately")

    # status
    subparsers.add_parser("status", help="Quick dirty check of local files against latest Cloud Vault snapshot")

    # history
    subparsers.add_parser("history", help="List cloud snapshot history versions")

    args = parser.parse_args()

    if not args.subcommand:
        parser.print_help()
        return 0

    sub = args.subcommand
    if sub in ("push", "send"):
        return cmd_push(args)
    elif sub in ("pull", "get"):
        return cmd_pull(args)
    elif sub == "sync":
        return cmd_sync(args)
    elif sub == "diff":
        return cmd_diff(args)
    elif sub == "status":
        return cmd_status(args)
    elif sub == "history":
        return cmd_history(args)
    else:
        parser.print_help()
        return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nAborted.")
        sys.exit(130)
