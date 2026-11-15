#!/usr/bin/env python3
"""
ssh_vault_diff.py - Zero-Knowledge SSH & Secrets Vault Diff Tool

Compares ~/.ssh and ~/.ssh/secrets across:
  - Local host vs Cloud Vault (latest or specific historical snapshot)
  - Local host vs Remote SSH host (e.g., s24, work, winvm)
  - Remote host vs Remote host (e.g., s24 vs work)
  - Historical Cloud snapshot vs Cloud snapshot (e.g., v1 vs v2)
"""

import argparse
import getpass
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import urllib.error
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

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
    import socket
    return socket.gethostname().split(".")[0]

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
    """Recursively computes SHA256 of all files in base_dir."""
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
        # Match exact flags used by get.sh / send.sh:
        # openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass pass:"$PASSPHRASE"
        cmd_decrypt = [
            "openssl", "enc", "-d", "-aes-256-cbc",
            "-pbkdf2", "-salt",
            "-in", enc_path,
            "-out", dec_path,
            "-pass", f"pass:{passphrase}"
        ]
        res = subprocess.run(cmd_decrypt, capture_output=True)
        if res.returncode != 0:
            # Fallback attempt without -salt or with older defaults if needed
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

        # Detect archive format (tar.gz, tar, zip)
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

        # Normalize directory: handle nested 'ssh' or '.ssh' directories created by send.sh
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
    """Downloads encrypted vault from cloud and unpacks it."""
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
        # Save passphrase in cache for secondary cloud comparisons if needed
        passphrase_cache["pass"] = passphrase
    return success

def resolve_ssh_host(target: str) -> str:
    """
    Resolves host name using mesh_core.py and devices.toml if available.
    For example, 's24' will probe and resolve to 's24-500' or fastest active route.
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
    """Extracts ~/.ssh from a live remote host over SSH without touching disk on remote."""
    resolved_route = resolve_ssh_host(host)
    route_display = f"'{host}' (via {resolved_route})" if resolved_route != host else f"'{host}'"
    print(f"{CYAN}📡 Fetching ~/.ssh from live host {route_display} via SSH...{RESET}")

    # Run tar on remote and stream archive to stdout
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

    # If user explicitly asks for current host name (e.g. 'work' when running on work), or 'local', 'self', '.'
    if s in ("local", "self", "me", ".", "") or (s == current_host and default_is_local):
        return ("local", None)
    if s == "cloud" or s == "vault":
        return ("cloud", None)
    if s.startswith("cloud:v") or s.startswith("vault:v"):
        v = int(s.split(":v", 1)[1])
        return ("cloud", v)
    if s.startswith("v") and s[1:].isdigit():
        return ("cloud", int(s[1:]))
    return (f"remote:{s}", None)

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

def restore_cloud_to_local(cloud_dir: Path):
    """Restores/merges extracted cloud vault into local ~/.ssh."""
    local_ssh = Path.home() / ".ssh"
    print(f"\n{BOLD}{CYAN}📥 Restoring Cloud Vault to local {local_ssh}...{RESET}")

    # Copy files
    for item in cloud_dir.iterdir():
        if should_ignore(item.name):
            continue
        dest = local_ssh / item.name
        if item.is_dir():
            shutil.copytree(str(item), str(dest), dirs_exist_ok=True)
        else:
            shutil.copy2(str(item), str(dest))

    apply_permissions(local_ssh)
    print(f"{GREEN}✔ Successfully restored vault files into {local_ssh} and applied strict permissions (700/600).{RESET}\n")

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

        # Copy local .ssh excluding known_hosts
        for item in local_ssh.iterdir():
            if should_ignore(item.name):
                continue
            dest = stage_ssh / item.name
            if item.is_dir():
                shutil.copytree(str(item), str(dest), dirs_exist_ok=True)
            else:
                shutil.copy2(str(item), str(dest))

        enc_path = Path(temp_stage) / "payload.enc"

        # tar -> openssl enc
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
                import urllib.parse
                upload_url += f"?token={urllib.parse.quote(token)}"

            headers = {"Content-Type": "application/octet-stream"}
            if token:
                headers["X-Sync-Token"] = token

            print(f"{CYAN}🌐 Uploading encrypted payload to {vault_url}...{RESET}")
            req = urllib.request.Request(upload_url, data=payload_bytes, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=20) as resp:
                if resp.status in (200, 201):
                    print(f"{GREEN}✔ Successfully uploaded encrypted vault payload to Cloudflare KV!{RESET}\n")
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

def prompt_sync_action(
    left_kind: str,
    left_name: str,
    left_dir: Path,
    right_kind: str,
    right_name: str,
    right_dir: Path,
    vault_url: str,
    sync_token: Optional[str],
    passphrase_cache: dict
):
    """Offers interactive synchronization options between local and cloud when applicable."""
    is_local_cloud = (left_kind == "local" and right_kind == "cloud") or (left_kind == "cloud" and right_kind == "local")
    if not is_local_cloud or not sys.stdout.isatty():
        return

    local_side = "left" if left_kind == "local" else "right"
    cloud_dir = right_dir if local_side == "left" else left_dir

    print(f"\n{BOLD}⚡ Available Actions:{RESET}")
    print(f"  {CYAN}[1]{RESET} Send from local to cloud  (Encrypt & Push local ~/.ssh to Cloud Vault)")
    print(f"  {CYAN}[2]{RESET} Get from cloud to local   (Restore Cloud Vault into local ~/.ssh)")
    print(f"  {DIM}[q]{RESET} Quit / No action")

    try:
        choice = input(f"\n{BOLD}Select an action [1/2/q] (default: q): {RESET}").strip().lower()
    except (KeyboardInterrupt, EOFError):
        print("")
        return

    if choice == "1":
        confirm = input(f"{YELLOW}⚠️  Are you sure you want to overwrite Cloud Vault with local ~/.ssh? [y/N]: {RESET}").strip().lower()
        if confirm in ("y", "yes"):
            upload_local_to_cloud(vault_url, sync_token, passphrase_cache)
        else:
            print("Cancelled.")
    elif choice == "2":
        confirm = input(f"{YELLOW}⚠️  Are you sure you want to restore Cloud Vault to local ~/.ssh? [y/N]: {RESET}").strip().lower()
        if confirm in ("y", "yes"):
            restore_cloud_to_local(cloud_dir)
        else:
            print("Cancelled.")

def compare_directories(left_name: str, left_dir: Path, right_name: str, right_dir: Path, interactive_diff: bool = False) -> bool:
    """Compares two extracted directories and displays summary & diffs. Returns True if identical."""
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

    print(f"\n{BOLD}{'=' * 65}{RESET}")
    print(f"{BOLD}📊 Comparison Summary: {CYAN}{left_name}{RESET} {BOLD}vs{RESET} {CYAN}{right_name}{RESET}")
    print(f"{BOLD}{'=' * 65}{RESET}\n")

    if not modified and not only_left and not only_right:
        print(f"  {GREEN}✔ 100% IDENTICAL - Both sides match completely ({len(synced)} files).{RESET}\n")
        return

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

    # Inspect interactive diff
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

def main():
    parser = argparse.ArgumentParser(
        description="Zero-Knowledge comparison tool for ~/.ssh & ~/.ssh/secrets across hosts and cloud snapshots.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ssh-diff                        # Compare local ~/.ssh with Cloud Vault (latest)
  ssh-diff --cloud -v 1           # Compare local ~/.ssh with Cloud snapshot v1
  ssh-diff --history              # View available Cloud snapshot versions
  ssh-diff s24                    # Compare local ~/.ssh with live host 's24'
  ssh-diff s24 work               # Compare live host 's24' with live host 'work'
  ssh-diff s24 cloud              # Compare live host 's24' with Cloud Vault (latest)
  ssh-diff cloud:v1 cloud:v2      # Compare historical Cloud snapshot v1 with v2
        """
    )
    parser.add_argument("target1", nargs="?", default="local", help="First target (local, cloud, cloud:v1, or host name like s24)")
    parser.add_argument("target2", nargs="?", default=None, help="Second target (default: cloud if target1 is local/host, or local if target1 is cloud)")
    parser.add_argument("-v", "--version", type=int, default=None, help="Cloud version number (1 to 5) when comparing with cloud")
    parser.add_argument("-d", "--diff", action="store_true", help="Automatically show detailed line diff without prompting")
    parser.add_argument("-l", "--history", action="store_true", help="List cloud snapshot history versions and exit")

    args = parser.parse_args()
    vault_url, sync_token = load_vault_config()
    current_host = get_current_host_name()

    # Mode 1: List Cloud Snapshot History
    if args.history:
        print(f"{BOLD}📦 Cloud Vault History ({vault_url}){RESET}")
        history = fetch_history(vault_url)
        if not history:
            print(f"{YELLOW}No snapshot history available or failed to reach worker.{RESET}")
            return
        print(f"\n{'VER':<8} {'TIMESTAMP (UTC)':<28} {'SIZE':<12}")
        print("-" * 50)
        for h in history:
            ver_label = "Latest" if h.get("version") == 0 else f"v{h.get('version')}"
            ts = h.get("timestamp", "-")
            sz = f"{h.get('size', 0):,} bytes"
            print(f"{BOLD}{ver_label:<8}{RESET} {ts:<28} {sz:<12}")
        print("\n💡 Tip: Compare with any snapshot using: ssh-diff -v <version_num>")
        return

    # Determine default target2 if omitted
    t1_str = args.target1
    t2_str = args.target2
    if t2_str is None:
        if t1_str == "local":
            t2_str = f"cloud:v{args.version}" if args.version else "cloud"
        elif t1_str.startswith("cloud"):
            t2_str = "local"
        else:
            # target1 is a host (e.g., s24), compare with local by default or cloud if specified
            t2_str = f"cloud:v{args.version}" if args.version else "local"

    k1, v1 = parse_target(t1_str, default_is_local=True)
    k2, v2 = parse_target(t2_str, default_is_local=False)

    # Honor global --version flag if comparing with cloud and version not explicit
    if args.version:
        if k1 == "cloud" and v1 is None:
            v1 = args.version
        if k2 == "cloud" and v2 is None:
            v2 = args.version

    # Set up temporary directory for extracting payloads
    with tempfile.TemporaryDirectory(prefix="ssh_diff_") as temp_base:
        temp_path = Path(temp_base)
        dir1 = temp_path / "target1"
        dir2 = temp_path / "target2"
        dir1.mkdir(parents=True, exist_ok=True)
        dir2.mkdir(parents=True, exist_ok=True)

        passphrase_cache = {}

        # Resolve target 1
        name1 = t1_str
        if k1 == "local":
            name1 = f"local ({current_host})"
            local_ssh = Path.home() / ".ssh"
            # Reference local files
            dir1 = local_ssh
        elif k1 == "cloud":
            name1 = f"cloud (v{v1})" if v1 else "cloud (latest)"
            if not extract_cloud_target(vault_url, v1, dir1, passphrase_cache):
                sys.exit(1)
        elif k1.startswith("remote:"):
            host = k1.split(":", 1)[1]
            name1 = f"remote:{host}"
            if not extract_remote_target(host, dir1):
                sys.exit(1)

        # Resolve target 2
        name2 = t2_str
        if k2 == "local":
            name2 = f"local ({current_host})"
            local_ssh = Path.home() / ".ssh"
            dir2 = local_ssh
        elif k2 == "cloud":
            name2 = f"cloud (v{v2})" if v2 else "cloud (latest)"
            if not extract_cloud_target(vault_url, v2, dir2, passphrase_cache):
                sys.exit(1)
        elif k2.startswith("remote:"):
            host = k2.split(":", 1)[1]
            name2 = f"remote:{host}"
            if not extract_remote_target(host, dir2):
                sys.exit(1)

        # Perform comparison
        compare_directories(name1, dir1, name2, dir2, interactive_diff=args.diff)

        # Offer interactive sync actions when applicable
        prompt_sync_action(
            k1, name1, dir1,
            k2, name2, dir2,
            vault_url, sync_token, passphrase_cache
        )

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nAborted.")
        sys.exit(130)
