#!/usr/bin/env python3
import os
import sys
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor

def get_configured_repos():
    repos = []
    # 1. Config file if exists (~/.config/omarchy/git-repos.json)
    config_file = os.path.expanduser("~/.config/omarchy/git-repos.json")
    if os.path.isfile(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    for r in data:
                        p = os.path.expanduser(r) if isinstance(r, str) else os.path.expanduser(r.get("path", ""))
                        if p and os.path.isdir(p) and p not in repos:
                            repos.append(p)
        except Exception:
            pass

    # 2. Defaults if empty or complementary
    chezmoi_path = os.path.expanduser("~/.local/share/chezmoi")
    if os.path.isdir(os.path.join(chezmoi_path, ".git")) and chezmoi_path not in repos:
        repos.append(chezmoi_path)

    projects_dir = os.path.expanduser("~/projects")
    if os.path.isdir(projects_dir):
        try:
            for entry in sorted(os.listdir(projects_dir)):
                full_path = os.path.join(projects_dir, entry)
                if os.path.isdir(os.path.join(full_path, ".git")) and full_path not in repos:
                    repos.append(full_path)
        except Exception:
            pass

    return repos

def inspect_repo(repo_path):
    p = os.path.expanduser(repo_path)
    name = os.path.basename(p)
    if not os.path.isdir(os.path.join(p, ".git")):
        return None

    try:
        res = subprocess.run(
            ["git", "-C", p, "status", "--porcelain=v2", "--branch"],
            capture_output=True,
            text=True,
            timeout=3
        )
        if res.returncode != 0:
            return {
                "name": name,
                "path": p,
                "branch": "?",
                "error": res.stderr.strip() or "git error",
                "isError": True,
                "isDirty": False,
                "hasSync": False,
                "isClean": False,
                "ahead": 0,
                "behind": 0,
                "staged": 0,
                "unstaged": 0,
                "untracked": 0
            }

        branch = "HEAD"
        ahead = 0
        behind = 0
        staged = 0
        unstaged = 0
        untracked = 0

        for line in res.stdout.splitlines():
            if line.startswith("# branch.head "):
                branch = line.split()[2]
            elif line.startswith("# branch.ab "):
                parts = line.split()
                try:
                    ahead = int(parts[2].replace("+", ""))
                    behind = int(parts[3].replace("-", ""))
                except Exception:
                    pass
            elif line.startswith("1 ") or line.startswith("2 "):
                parts = line.split()
                if len(parts) > 1:
                    sub = parts[1]
                    if len(sub) >= 2:
                        if sub[0] != ".":
                            staged += 1
                        if sub[1] != ".":
                            unstaged += 1
            elif line.startswith("? "):
                untracked += 1
            elif line.startswith("u "):
                unstaged += 1

        is_dirty = (staged > 0 or unstaged > 0 or untracked > 0)
        has_sync = (ahead > 0 or behind > 0)

        return {
            "name": name,
            "path": p,
            "branch": branch,
            "ahead": ahead,
            "behind": behind,
            "staged": staged,
            "unstaged": unstaged,
            "untracked": untracked,
            "isDirty": is_dirty,
            "hasSync": has_sync,
            "isClean": not is_dirty and not has_sync,
            "isError": False
        }
    except Exception as e:
        return {
            "name": name,
            "path": p,
            "branch": "?",
            "error": str(e),
            "isError": True,
            "isDirty": False,
            "hasSync": False,
            "isClean": False,
            "ahead": 0,
            "behind": 0,
            "staged": 0,
            "unstaged": 0,
            "untracked": 0
        }

def main():
    repos = get_configured_repos()
    results = []
    with ThreadPoolExecutor(max_workers=min(12, max(len(repos), 1))) as executor:
        for r in executor.map(inspect_repo, repos):
            if r:
                results.append(r)

    # Sort repos: dirty/sync first, then name
    def sort_key(item):
        dirty_priority = 0 if item["isDirty"] else (1 if item["hasSync"] else (3 if item["isClean"] else 2))
        return (dirty_priority, item["name"].lower())

    results.sort(key=sort_key)

    total_count = len(results)
    dirty_count = sum(1 for r in results if r["isDirty"])
    sync_count = sum(1 for r in results if r["hasSync"])
    clean_count = sum(1 for r in results if r["isClean"])
    error_count = sum(1 for r in results if r.get("isError"))

    output = {
        "repos": results,
        "totalCount": total_count,
        "dirtyCount": dirty_count,
        "syncCount": sync_count,
        "cleanCount": clean_count,
        "errorCount": error_count,
        "attentionCount": dirty_count + sync_count
    }
    print(json.dumps(output))

if __name__ == "__main__":
    main()
