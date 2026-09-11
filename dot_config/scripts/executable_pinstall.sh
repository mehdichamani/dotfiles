#!/usr/bin/env bash
# ==============================================================================
# pinstall.sh - Portable Application Installer for Omarchy / Linux
# ==============================================================================
# Installs standalone binaries, AppImages, or archives (.zip, .7z, .tar.*, etc.)
# into ~/.local/share/<AppName>, creates XDG Desktop entries, discovers icons,
# flattens nested archive roots, manages metadata receipts (.pinstall.json),
# and supports listing and clean uninstallation.
# ==============================================================================

set -eo pipefail

# --- Color Definitions ---
if [[ -t 1 ]]; then
    COLOR_RESET=$'\033[0m'
    COLOR_BOLD=$'\033[1m'
    COLOR_DIM=$'\033[2m'
    COLOR_CYAN=$'\033[36m'
    COLOR_GREEN=$'\033[32m'
    COLOR_YELLOW=$'\033[33m'
    COLOR_RED=$'\033[31m'
    COLOR_MAGENTA=$'\033[35m'
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_CYAN=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_MAGENTA=""
fi

# --- Helper Output Functions ---
info() {
    printf "${COLOR_CYAN}>>> %s${COLOR_RESET}\n" "$*"
}

success() {
    printf "${COLOR_GREEN}✓ %s${COLOR_RESET}\n" "$*"
}

warn() {
    printf "${COLOR_YELLOW}⚠️  %s${COLOR_RESET}\n" "$*" >&2
}

err() {
    printf "${COLOR_RED}✗ Error: %s${COLOR_RESET}\n" "$*" >&2
}

# --- Show Help ---
show_help() {
    cat <<EOF
${COLOR_BOLD}${COLOR_CYAN}===================================================================
        Portable Application Installer for Omarchy / Linux
===================================================================${COLOR_RESET}

${COLOR_BOLD}Usage:${COLOR_RESET}
  pinstall [source|url|github_repo] [options]
  pinstall -l | --list
  pinstall -u | --uninstall [name] [options]

${COLOR_BOLD}Management Options:${COLOR_RESET}
  -l, --list                List all installed portable applications and their details.
  -u, --uninstall [name]    Uninstall an application (removes files, desktop entry, and PATH link).
                            If no name is provided, prompts with an interactive list.
  -y, --yes                 Skip confirmation prompts during uninstallation.

${COLOR_BOLD}Installation Options:${COLOR_RESET}
  -s, --source <src>        Path to archive/binary, direct download URL, or GitHub repo/release.
                            (e.g., 'owner/repo', 'owner/repo@v1.0', 'https://github.com/...', 'https://...').
                            If omitted, scans current directory for installable packages.
  -n, --name <string>       Custom application name and installation folder name.
                            Defaults to a cleaned version of the archive/binary filename.
  -e, --exec, --bin <name>  Specific executable binary inside the package to target.
                            If omitted and multiple executables exist, prompts interactively.
  -i, --icon <path>         Path to a custom icon file (.png, .svg, .ico).
                            Defaults to automatic detection inside the package.
  -c, --category <cat>      Desktop categories (e.g. 'Network;Utility;', 'Development;').
                            Default: 'Utility;'
  -p, --password <pass>     Password for encrypted archives (.zip, .7z, .rar).
      --path, --add-to-path Creates a symlink in ~/.local/bin (in your PATH).
      --no-desktop          Skips creating ~/.local/share/applications/*.desktop entry.
  -t, --terminal            Sets Terminal=true in desktop entry (for CLI/TUI tools).
  -f, --force               Overwrites existing installation folder without prompting.
  -h, --help                Displays this help message.

${COLOR_BOLD}Supported Formats & Sources:${COLOR_RESET}
  GitHub Repos: GitHub repository (e.g. 'jgraph/drawio-desktop', 'fastfetch-cli/fastfetch')
  Direct URLs:  HTTP/HTTPS links to release archives, AppImages, or binaries
  Archives:     .zip, .7z, .rar, .tar, .tar.gz, .tgz, .tar.xz, .txz, .tar.zst, .tar.bz2, .tbz2, .iso
  Executables:  .AppImage, ELF binaries, standalone scripts

${COLOR_BOLD}Examples:${COLOR_RESET}
  1) Install from GitHub repository (auto-discovers latest Linux release):
     $ pinstall fastfetch-cli/fastfetch --add-to-path
     $ pinstall https://github.com/jgraph/drawio-desktop
     $ pinstall obsidianmd/obsidian-releases@v1.7.7

  2) Install from direct download URL:
     $ pinstall https://github.com/fastfetch-cli/fastfetch/releases/download/2.38.0/fastfetch-linux-amd64.tar.gz --add-to-path

  3) Install from local archive:
     $ pinstall PattN-linux-64.zip
     $ pinstall sing-box-1.9.0-linux-amd64.tar.gz --add-to-path

  4) Scan and select interactively from current directory:
     $ cd ~/Downloads
     $ pinstall

  5) List or uninstall installed portable applications:
     $ pinstall --list
     $ pinstall --uninstall "Obsidian" -y

${COLOR_BOLD}${COLOR_CYAN}===================================================================${COLOR_RESET}
EOF
}

# --- Format File Size ---
format_size() {
    local bytes="$1"
    if (( bytes >= 1073741824 )); then
        printf "%.2f GB" "$(awk -v b="$bytes" 'BEGIN { print b/1073741824 }')"
    elif (( bytes >= 1048576 )); then
        printf "%.2f MB" "$(awk -v b="$bytes" 'BEGIN { print b/1048576 }')"
    elif (( bytes >= 1024 )); then
        printf "%.1f KB" "$(awk -v b="$bytes" 'BEGIN { print b/1024 }')"
    else
        printf "%d B" "$bytes"
    fi
}

# --- Clean Application Name (Strips Format / Architecture / OS Noise) ---
clean_app_name() {
    local raw="$1"
    local clean
    clean="$(basename "$raw")"

    # 1. Strip compound and standard archive/binary format extensions
    case "${clean,,}" in
        *.tar.gz)   clean="${clean%???????}" ;;
        *.tar.xz)   clean="${clean%???????}" ;;
        *.tar.zst)  clean="${clean%????????}" ;;
        *.tar.bz2)  clean="${clean%????????}" ;;
        *.tgz)      clean="${clean%????}" ;;
        *.txz)      clean="${clean%????}" ;;
        *.tbz2)     clean="${clean%?????}" ;;
        *.zip)      clean="${clean%????}" ;;
        *.7z)       clean="${clean%???}" ;;
        *.rar)      clean="${clean%????}" ;;
        *.iso)      clean="${clean%????}" ;;
        *.appimage) clean="${clean%?????????}" ;;
        *.bin)      clean="${clean%????}" ;;
        *.exe)      clean="${clean%????}" ;;
        *.*)        clean="${clean%.*}" ;;
    esac

    # 2. Strip common release tags, OS platforms, architectures, and packaging noise
    # e.g., -linux-64, _linux_x86_64, -amd64, -x64, -x86, -arm64, -aarch64, -portable, -setup, -standalone, -desktop
    # Using sed with case-insensitive extended regex
    local filtered
    filtered="$(echo "$clean" | sed -E -e 's/[-._](linux|windows|win32|win64|darwin|macos|osx)[-._]?(64|32|x64|x86_64|amd64|x86|arm64|armv7l|aarch64|universal|amd|arm)?//Ig' \
                                     -e 's/[-._](x86_64|amd64|x64|x86|arm64|aarch64|armv7l|64bit|32bit|64|32)//Ig' \
                                     -e 's/[-._](portable|standalone|desktop|setup|bin|static|musl|glibc)//Ig' \
                                     -e 's/[-._]v?[0-9]+(\.[0-9]+)*([-_]?(beta|alpha|rc|patch|preview)?[0-9]*)?//Ig' \
                                     -e 's/[-._]+$//g' \
                                     -e 's/^[-._]+//g')"

    # Fallback to original clean if filtered string becomes empty
    if [[ -n "$filtered" ]]; then
        clean="$filtered"
    fi

    echo "$clean"
}

# --- Slugify for Filenames ---
slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'
}

# --- Extract Field from .pinstall.json (safe bash parser) ---
get_receipt_field() {
    local file="$1"
    local key="$2"
    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi
    grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | head -n 1 | sed -E "s/\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/" || echo ""
}

# --- Discover All Installed Portable Apps ---
# Populates global arrays: INSTALLED_APP_NAMES, INSTALLED_APP_DIRS, INSTALLED_APP_RECEIPTS
discover_installed_apps() {
    INSTALLED_APP_NAMES=()
    INSTALLED_APP_DIRS=()
    INSTALLED_APP_RECEIPTS=()

    local base_dir="$HOME/.local/share"
    [[ ! -d "$base_dir" ]] && return

    # First look for directories with .pinstall.json
    while IFS= read -r -d '' receipt; do
        local dir
        dir="$(dirname "$receipt")"
        local name
        name="$(get_receipt_field "$receipt" "name")"
        [[ -z "$name" ]] && name="$(basename "$dir")"
        INSTALLED_APP_NAMES+=("$name")
        INSTALLED_APP_DIRS+=("$dir")
        INSTALLED_APP_RECEIPTS+=("$receipt")
    done < <(find "$base_dir" -mindepth 2 -maxdepth 2 -name ".pinstall.json" -print0 2>/dev/null | sort -z)

    # Also detect non-receipt directories if a matching .desktop file references it
    # This ensures backward compatibility with earlier pinstall versions
    while IFS= read -r -d '' dir; do
        local dname
        dname="$(basename "$dir")"
        # Skip standard XDG dirs
        if [[ "$dname" =~ ^(applications|icons|sounds|themes|fonts|mime|Trash|flatpak|keyrings|icc|recently-used.xbel)$ ]]; then
            continue
        fi
        if [[ -f "$dir/.pinstall.json" ]]; then
            continue
        fi

        # Check if any .desktop file in ~/.local/share/applications references this path
        local matching_desktop
        matching_desktop="$(grep -rnwl "$HOME/.local/share/applications" -e "$dir" 2>/dev/null | head -n 1 || true)"
        if [[ -n "$matching_desktop" ]]; then
            INSTALLED_APP_NAMES+=("$dname")
            INSTALLED_APP_DIRS+=("$dir")
            INSTALLED_APP_RECEIPTS+=("")
        fi
    done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
}

# --- Action: List Installed Portable Apps ---
list_installed_apps() {
    discover_installed_apps

    local count="${#INSTALLED_APP_NAMES[@]}"
    printf "\n${COLOR_BOLD}${COLOR_CYAN}===================================================================${COLOR_RESET}\n"
    printf "${COLOR_BOLD}${COLOR_CYAN}         INSTALLED PORTABLE APPLICATIONS (%d found)                 ${COLOR_RESET}\n" "$count"
    printf "${COLOR_BOLD}${COLOR_CYAN}===================================================================${COLOR_RESET}\n"

    if (( count == 0 )); then
        printf "  ${COLOR_DIM}No portable applications installed in ~/.local/share yet.${COLOR_RESET}\n"
        printf "${COLOR_BOLD}${COLOR_CYAN}===================================================================${COLOR_RESET}\n\n"
        return 0
    fi

    printf "  ${COLOR_BOLD}%-24s %-10s %-18s %-12s %-16s${COLOR_RESET}\n" "Application Name" "Size" "CLI Command" "Desktop Menu" "Installed Date"
    printf "  ${COLOR_DIM}----------------------------------------------------------------------------------${COLOR_RESET}\n"

    for i in "${!INSTALLED_APP_NAMES[@]}"; do
        local name="${INSTALLED_APP_NAMES[$i]}"
        local dir="${INSTALLED_APP_DIRS[$i]}"
        local receipt="${INSTALLED_APP_RECEIPTS[$i]}"

        # Calculate directory size
        local size_bytes
        size_bytes=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo 0)
        local size_str
        size_str="$(format_size "$size_bytes")"

        local bin_cmd="-"
        local desktop_status="No"
        local install_date="-"

        if [[ -n "$receipt" && -f "$receipt" ]]; then
            local bin_link
            bin_link="$(get_receipt_field "$receipt" "bin_link")"
            if [[ -n "$bin_link" ]]; then
                bin_cmd="$(basename "$bin_link")"
                [[ -e "$bin_link" ]] || bin_cmd="${bin_cmd} (broken)"
            fi

            local desktop_f
            desktop_f="$(get_receipt_field "$receipt" "desktop_file")"
            if [[ -n "$desktop_f" && -f "$desktop_f" ]]; then
                desktop_status="Yes"
            fi

            install_date="$(get_receipt_field "$receipt" "installed_at")"
            if [[ -n "$install_date" ]]; then
                install_date="${install_date%%T*}"
            else
                install_date="-"
            fi
        else
            # Legacy fallback check
            local slug
            slug="$(slugify "$name")"
            if [[ -f "$HOME/.local/share/applications/${slug}.desktop" ]]; then
                desktop_status="Yes"
            fi
            # Check ~/.local/bin for symlinks pointing inside dir
            while IFS= read -r -d '' link; do
                local target
                target="$(readlink -f "$link" 2>/dev/null || true)"
                if [[ "$target" == "$dir"* ]]; then
                    bin_cmd="$(basename "$link")"
                    break
                fi
            done < <(find "$HOME/.local/bin" -maxdepth 1 -type l -print0 2>/dev/null)
        fi

        # Truncate strings nicely if needed
        local display_name="$name"
        (( ${#display_name} > 23 )) && display_name="${display_name:0:20}..."
        (( ${#bin_cmd} > 17 )) && bin_cmd="${bin_cmd:0:15}.."

        printf "  %-24s %-10s %-18s %-12s %-16s\n" "$display_name" "$size_str" "$bin_cmd" "$desktop_status" "$install_date"
    done

    printf "  ${COLOR_DIM}----------------------------------------------------------------------------------${COLOR_RESET}\n"
    printf "  ${COLOR_DIM}Tip: Run 'pinstall -u <name>' or 'pinstall -u' to remove an application.${COLOR_RESET}\n"
    printf "${COLOR_BOLD}${COLOR_CYAN}===================================================================${COLOR_RESET}\n\n"
}

# --- Action: Uninstall Application ---
uninstall_app() {
    local target_query="$1"
    local auto_confirm="$2"

    discover_installed_apps
    local count="${#INSTALLED_APP_NAMES[@]}"

    if (( count == 0 )); then
        warn "No portable applications found to uninstall in ~/.local/share."
        return 0
    fi

    local selected_idx=-1

    if [[ -n "$target_query" ]]; then
        # Search by exact name, case-insensitive name, or slug
        local query_slug
        query_slug="$(slugify "$target_query")"

        for i in "${!INSTALLED_APP_NAMES[@]}"; do
            local cur_name="${INSTALLED_APP_NAMES[$i]}"
            local cur_slug
            cur_slug="$(slugify "$cur_name")"
            local cur_dir
            cur_dir="$(basename "${INSTALLED_APP_DIRS[$i]}")"

            if [[ "${cur_name,,}" == "${target_query,,}" || "$cur_slug" == "$query_slug" || "${cur_dir,,}" == "${target_query,,}" ]]; then
                selected_idx=$i
                break
            fi
        done

        # Substring search if exact match not found
        if (( selected_idx < 0 )); then
            for i in "${!INSTALLED_APP_NAMES[@]}"; do
                local cur_name="${INSTALLED_APP_NAMES[$i]}"
                if [[ "${cur_name,,}" == *"${target_query,,}"* ]]; then
                    selected_idx=$i
                    break
                fi
            done
        fi

        if (( selected_idx < 0 )); then
            err "Application matching '$target_query' not found in installed portable applications."
            printf "Run 'pinstall --list' to see installed applications.\n"
            exit 1
        fi
    else
        # Interactive selection menu
        printf "\n${COLOR_CYAN}📦 Select an application to uninstall:${COLOR_RESET}\n"
        printf "${COLOR_DIM}------------------------------------------------------------------------${COLOR_RESET}\n"
        for i in "${!INSTALLED_APP_NAMES[@]}"; do
            local name="${INSTALLED_APP_NAMES[$i]}"
            local dir="${INSTALLED_APP_DIRS[$i]}"
            local size_bytes
            size_bytes=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo 0)
            local size_str
            size_str="$(format_size "$size_bytes")"
            printf "  [${COLOR_BOLD}%d${COLOR_RESET}] %-40s %10s\n" "$((i + 1))" "$name" "$size_str"
        done
        printf "${COLOR_DIM}------------------------------------------------------------------------${COLOR_RESET}\n"

        read -r -p "Enter selection (1-${count}) or 'q' to cancel: " sel_choice
        if [[ "$sel_choice" =~ ^[Qq]$ || -z "$sel_choice" ]]; then
            echo "Uninstallation cancelled."
            exit 0
        fi

        if ! [[ "$sel_choice" =~ ^[0-9]+$ ]] || (( sel_choice < 1 || sel_choice > count )); then
            err "Invalid selection: '$sel_choice'"
            exit 1
        fi

        selected_idx=$((sel_choice - 1))
    fi

    local app_name="${INSTALLED_APP_NAMES[$selected_idx]}"
    local app_dir="${INSTALLED_APP_DIRS[$selected_idx]}"
    local receipt_file="${INSTALLED_APP_RECEIPTS[$selected_idx]}"

    # Discover linked resources (from receipt or fallback detection)
    local desktop_path=""
    local bin_link_path=""

    if [[ -n "$receipt_file" && -f "$receipt_file" ]]; then
        desktop_path="$(get_receipt_field "$receipt_file" "desktop_file")"
        bin_link_path="$(get_receipt_field "$receipt_file" "bin_link")"
    fi

    # Fallback checks if receipt was missing or fields empty
    if [[ -z "$desktop_path" || ! -f "$desktop_path" ]]; then
        local candidate_slug
        candidate_slug="$(slugify "$app_name")"
        if [[ -f "$HOME/.local/share/applications/${candidate_slug}.desktop" ]]; then
            desktop_path="$HOME/.local/share/applications/${candidate_slug}.desktop"
        fi
    fi

    if [[ -z "$bin_link_path" || ! -e "$bin_link_path" ]]; then
        # Check ~/.local/bin for symlinks pointing to app_dir
        while IFS= read -r -d '' link; do
            local target
            target="$(readlink -f "$link" 2>/dev/null || true)"
            if [[ "$target" == "$app_dir"* ]]; then
                bin_link_path="$link"
                break
            fi
        done < <(find "$HOME/.local/bin" -maxdepth 1 -type l -print0 2>/dev/null)
    fi

    printf "\n${COLOR_BOLD}${COLOR_YELLOW}===================================================================${COLOR_RESET}\n"
    printf "${COLOR_BOLD}${COLOR_YELLOW}               UNINSTALL CONFIRMATION                              ${COLOR_RESET}\n"
    printf "${COLOR_BOLD}${COLOR_YELLOW}===================================================================${COLOR_RESET}\n"
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "App Name" "$app_name"
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "Directory to remove" "$app_dir"

    if [[ -n "$desktop_path" && -f "$desktop_path" ]]; then
        printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "Desktop entry" "$desktop_path"
    fi

    if [[ -n "$bin_link_path" && -e "$bin_link_path" ]]; then
        printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "PATH Symlink" "$bin_link_path"
    fi
    printf "${COLOR_BOLD}${COLOR_YELLOW}===================================================================${COLOR_RESET}\n"

    if [[ "$auto_confirm" != true ]]; then
        read -r -p "Are you sure you want to completely remove '$app_name'? [y/N]: " confirm_remove
        if ! [[ "$confirm_remove" =~ ^[Yy]$ ]]; then
            warn "Uninstallation cancelled by user."
            exit 0
        fi
    fi

    info "Removing application '$app_name'..."

    # 1. Remove PATH symlink
    if [[ -n "$bin_link_path" && -e "$bin_link_path" ]]; then
        rm -f "$bin_link_path"
        success "Removed PATH symlink: $bin_link_path"
    fi

    # 2. Remove desktop file
    if [[ -n "$desktop_path" && -f "$desktop_path" ]]; then
        rm -f "$desktop_path"
        success "Removed desktop entry: $desktop_path"
        if command -v update-desktop-database >/dev/null 2>&1; then
            update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
        fi
    fi

    # 3. Remove application directory
    if [[ -d "$app_dir" ]]; then
        rm -rf "$app_dir"
        success "Removed directory: $app_dir"
    fi

    printf "\n${COLOR_GREEN}✓ Successfully uninstalled '$app_name'.${COLOR_RESET}\n\n"
}

# --- Parse Arguments ---
ACTION="install"
UNINSTALL_TARGET=""
AUTO_CONFIRM=false

SOURCE=""
APP_NAME=""
TARGET_EXEC_PARAM=""
CUSTOM_ICON=""
CATEGORIES="Utility;"
PASSWORD=""
ADD_TO_PATH=false
NO_DESKTOP=false
TERMINAL_APP=false
FORCE=false
IS_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            ACTION="list"
            shift
            ;;
        -u|--uninstall|--remove)
            ACTION="uninstall"
            if [[ -n "$2" && "$2" != -* ]]; then
                UNINSTALL_TARGET="$2"
                shift 2
            else
                shift
            fi
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -s|--source)
            SOURCE="$2"
            shift 2
            ;;
        -n|--name)
            APP_NAME="$2"
            shift 2
            ;;
        -e|--exec|--bin)
            TARGET_EXEC_PARAM="$2"
            shift 2
            ;;
        -i|--icon)
            CUSTOM_ICON="$2"
            shift 2
            ;;
        -c|--category|--categories)
            CATEGORIES="$2"
            [[ "$CATEGORIES" != *";" ]] && CATEGORIES="${CATEGORIES};"
            shift 2
            ;;
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        --path|--add-to-path)
            ADD_TO_PATH=true
            shift
            ;;
        --no-desktop|--no-shortcut)
            NO_DESKTOP=true
            shift
            ;;
        -t|--terminal)
            TERMINAL_APP=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -*)
            err "Unknown option: $1"
            echo "Run 'pinstall --help' for usage instructions."
            exit 1
            ;;
        *)
            if [[ "$ACTION" == "uninstall" && -z "$UNINSTALL_TARGET" ]]; then
                UNINSTALL_TARGET="$1"
            elif [[ -z "$SOURCE" ]]; then
                SOURCE="$1"
            else
                err "Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# --- Temporary Directory Management ---
TEMP_DOWNLOAD_DIR=""
cleanup_temp_dir() {
    if [[ -n "$TEMP_DOWNLOAD_DIR" && -d "$TEMP_DOWNLOAD_DIR" ]]; then
        rm -rf "$TEMP_DOWNLOAD_DIR"
    fi
}
trap cleanup_temp_dir EXIT INT TERM

# --- Detect System Architecture ---
detect_system_arch() {
    local arch
    arch="$(uname -m 2>/dev/null || echo "x86_64")"
    case "$arch" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "armv7l" ;;
        i386|i686) echo "x86" ;;
        *) echo "$arch" ;;
    esac
}

# --- Check if input is a direct URL ---
is_url() {
    [[ "$1" =~ ^https?:// ]]
}

# --- Parse GitHub Repo Shorthand or URL ---
# Returns: <owner>/<repo> or empty
parse_github_repo() {
    local input="$1"
    # Match https://github.com/owner/repo or http://github.com/owner/repo (with optional /releases... or .git)
    if [[ "$input" =~ ^https?://github\.com/([^/]+)/([^/#?]+) ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]%.git}"
        repo="${repo%%/releases*}"
        echo "${owner}/${repo}"
        return 0
    fi

    # Match gh:owner/repo
    if [[ "$input" =~ ^gh:([^/]+)/([^/@#]+) ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    # Match owner/repo or owner/repo@tag (must not be an existing local file)
    if [[ ! -e "$input" && "$input" =~ ^([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)(@[^/]+)?$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    return 1
}

# --- Resolve GitHub Tag if specified ---
parse_github_tag() {
    local input="$1"
    if [[ "$input" =~ @([^/]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$input" =~ /releases/tag/([^/#?]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# --- Query Public GitHub Releases API and Select Asset ---
# Populates: GITHUB_ASSET_URL, GITHUB_ASSET_NAME, GITHUB_APP_NAME
resolve_github_release_asset() {
    local repo="$1"
    local tag="$2"

    local api_url
    if [[ -n "$tag" ]]; then
        api_url="https://api.github.com/repos/${repo}/releases/tags/${tag}"
        info "Querying public GitHub release tag '${tag}' for '${repo}'..."
    else
        api_url="https://api.github.com/repos/${repo}/releases/latest"
        info "Querying latest public GitHub release for '${repo}'..."
    fi

    local response
    local http_code
    response="$(curl -s -L -w "\n%{http_code}" -H "User-Agent: pinstall" "$api_url" 2>/dev/null || true)"
    http_code="$(echo "$response" | tail -n 1)"
    local json_body
    json_body="$(echo "$response" | sed '$d')"

    if [[ "$http_code" != "200" ]]; then
        err "GitHub API returned status $http_code for repository '${repo}'."
        if echo "$json_body" | grep -qi "API rate limit exceeded"; then
            err "GitHub API rate limit reached for unauthenticated requests. Please provide a direct download URL."
        elif echo "$json_body" | grep -qi "Not Found"; then
            err "Repository or release not found. Please verify '${repo}'."
        fi
        exit 1
    fi

    # Extract release tag name
    local release_tag=""
    if [[ "$json_body" =~ \"tag_name\":[[:space:]]*\"([^\"]+)\" ]]; then
        release_tag="${BASH_REMATCH[1]}"
        info "Found release: ${COLOR_BOLD}${release_tag}${COLOR_RESET}"
    fi

    # Parse assets using python or grep
    local raw_assets=()
    if command -v python3 >/dev/null 2>&1; then
        local parsed_output
        parsed_output="$(printf '%s' "$json_body" | python3 -c '
import sys, json
try:
    data = json.loads(sys.stdin.read())
    for a in data.get("assets", []):
        n = a.get("name", "")
        u = a.get("browser_download_url", "")
        s = a.get("size", 0)
        if n and u:
            print(f"{n}\t{u}\t{s}")
except Exception:
    pass
')"
        while IFS=$'\t' read -r name durl size; do
            [[ -n "$name" && -n "$durl" ]] && raw_assets+=("${name}|${durl}|${size}")
        done <<< "$parsed_output"
    else
        # Fallback parser using grep/sed
        local parsed_lines
        parsed_lines="$(echo "$json_body" | grep -E '"(name|browser_download_url|size)":' || true)"
        local cur_name=""
        local cur_url=""
        local cur_size="0"
        while IFS= read -r line; do
            if [[ "$line" =~ \"name\":[[:space:]]*\"([^\"]+)\" ]]; then
                cur_name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ \"browser_download_url\":[[:space:]]*\"([^\"]+)\" ]]; then
                cur_url="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ \"size\":[[:space:]]*([0-9]+) ]]; then
                cur_size="${BASH_REMATCH[1]}"
                if [[ -n "$cur_name" && -n "$cur_url" ]]; then
                    raw_assets+=("${cur_name}|${cur_url}|${cur_size}")
                    cur_name=""
                    cur_url=""
                    cur_size="0"
                fi
            fi
        done <<< "$parsed_lines"
    fi

    if [[ ${#raw_assets[@]} -eq 0 ]]; then
        err "No downloadable release assets found in GitHub release for '${repo}'."
        exit 1
    fi

    local sys_arch
    sys_arch="$(detect_system_arch)"

    # Filter Linux assets
    local compatible_assets=()
    for item in "${raw_assets[@]}"; do
        local aname="${item%%|*}"
        local lower_name="${aname,,}"

        # Exclude windows / mac / android / ios / source code packages
        local exclude_pat='(\.exe|\.msi|\.dmg|\.pkg|\.deb|\.rpm|\.apk|\.ipa|windows|win32|win64|darwin|macos|osx|\.sha256|\.sig|\.asc|\.txt|\.md|\.json)$'
        if [[ "$lower_name" =~ $exclude_pat ]]; then
            continue
        fi

        # Architecture matching: filter out obvious mismatch
        if [[ "$sys_arch" == "x86_64" ]]; then
            local non_x86='(arm64|aarch64|armv7|armhf|i386|i686|32bit|win)'
            if [[ "$lower_name" =~ $non_x86 ]]; then
                continue
            fi
        elif [[ "$sys_arch" == "arm64" ]]; then
            local non_arm='(x86_64|amd64|x64|i386|i686|armv7|armhf)'
            if [[ "$lower_name" =~ $non_arm ]]; then
                continue
            fi
        fi

        # Check if supported archive or binary
        local archive_pat='(\.appimage|\.tar\.gz|\.tgz|\.tar\.xz|\.txz|\.tar\.zst|\.tar\.bz2|\.zip|\.7z|\.tar)$'
        local linux_bin_pat='(linux|amd64|x86_64|arm64|aarch64)'
        if [[ "$lower_name" =~ $archive_pat ]] || { [[ "$lower_name" =~ $linux_bin_pat ]] && [[ ! "$lower_name" =~ \. ]]; }; then
            compatible_assets+=("$item")
        fi
    done

    # Fallback to all non-windows/non-mac assets if no exact linux matches found
    if [[ ${#compatible_assets[@]} -eq 0 ]]; then
        local generic_exclude='(\.exe|\.msi|\.dmg|\.pkg|\.deb|\.rpm|\.sha256|\.sig|\.asc)'
        for item in "${raw_assets[@]}"; do
            local aname="${item%%|*}"
            local lower_name="${aname,,}"
            if [[ ! "$lower_name" =~ $generic_exclude ]]; then
                compatible_assets+=("$item")
            fi
        done
    fi

    if [[ ${#compatible_assets[@]} -eq 0 ]]; then
        err "No compatible Linux release assets found in '${repo}'."
        exit 1
    fi

    local chosen_asset=""
    if [[ ${#compatible_assets[@]} -eq 1 ]]; then
        chosen_asset="${compatible_assets[0]}"
        local a_name="${chosen_asset%%|*}"
        success "Auto-selected release asset: ${COLOR_BOLD}${a_name}${COLOR_RESET}"
    else
        printf "\n${COLOR_CYAN}📦 Multiple release assets found for '%s':${COLOR_RESET}\n" "$repo"
        printf "${COLOR_DIM}------------------------------------------------------------------------${COLOR_RESET}\n"
        for i in "${!compatible_assets[@]}"; do
            local entry="${compatible_assets[$i]}"
            local a_name
            a_name="$(echo "$entry" | cut -d'|' -f1)"
            local a_size
            a_size="$(echo "$entry" | cut -d'|' -f3)"
            local size_str
            size_str="$(format_size "$a_size")"
            printf "  [${COLOR_BOLD}%d${COLOR_RESET}] %-46s %10s\n" "$((i + 1))" "$a_name" "$size_str"
        done
        printf "${COLOR_DIM}------------------------------------------------------------------------${COLOR_RESET}\n"

        local asset_count="${#compatible_assets[@]}"
        read -r -p "Enter selection (1-${asset_count}) [Default: 1]: " sel_asset
        [[ -z "$sel_asset" ]] && sel_asset="1"

        if ! [[ "$sel_asset" =~ ^[0-9]+$ ]] || (( sel_asset < 1 || sel_asset > asset_count )); then
            err "Invalid selection: '$sel_asset'"
            exit 1
        fi
        chosen_asset="${compatible_assets[$((sel_asset - 1))]}"
    fi

    GITHUB_ASSET_NAME="$(echo "$chosen_asset" | cut -d'|' -f1)"
    GITHUB_ASSET_URL="$(echo "$chosen_asset" | cut -d'|' -f2)"
    GITHUB_APP_NAME="$(basename "$repo")"
}

# --- Download URL to Temporary Location ---
download_url_asset() {
    local url="$1"
    local filename="$2"

    TEMP_DOWNLOAD_DIR="$(mktemp -d -t pinstall-XXXXXX)"
    local target_path="$TEMP_DOWNLOAD_DIR/$filename"

    info "Downloading '$filename'..."
    info "From: $url"

    if ! curl -fL --progress-bar -H "User-Agent: pinstall" -o "$target_path" "$url"; then
        err "Download failed from: '$url'"
        exit 1
    fi

    success "Download completed: $(format_size "$(stat -c%s "$target_path" 2>/dev/null || wc -c < "$target_path" 2>/dev/null || echo 0)")"
    SOURCE="$target_path"
}

# --- Route Actions ---
if [[ "$ACTION" == "list" ]]; then
    list_installed_apps
    exit 0
fi

if [[ "$ACTION" == "uninstall" ]]; then
    uninstall_app "$UNINSTALL_TARGET" "$AUTO_CONFIRM"
    exit 0
fi

# Track source metadata
ORIGINAL_SOURCE_URL=""
ORIGINAL_GITHUB_REPO=""

# --- Check if Source is a GitHub Repository or URL ---
if [[ -n "$SOURCE" ]]; then
    # Check if direct GitHub release download link
    if [[ "$SOURCE" =~ ^https?://github\.com/[^/]+/[^/]+/releases/download/ ]]; then
        ORIGINAL_SOURCE_URL="$SOURCE"
        filename="$(basename "${SOURCE%%\?*}")"
        download_url_asset "$SOURCE" "$filename"
    # Check if GitHub repository / release URL or shorthand (e.g. 'owner/repo' or 'https://github.com/owner/repo')
    elif parsed_repo="$(parse_github_repo "$SOURCE")"; then
        ORIGINAL_GITHUB_REPO="$parsed_repo"
        tag="$(parse_github_tag "$SOURCE")"
        resolve_github_release_asset "$parsed_repo" "$tag"
        ORIGINAL_SOURCE_URL="$GITHUB_ASSET_URL"
        [[ -z "$APP_NAME" ]] && APP_NAME="$GITHUB_APP_NAME"
        download_url_asset "$GITHUB_ASSET_URL" "$GITHUB_ASSET_NAME"
    # Check if generic direct HTTP/HTTPS URL
    elif is_url "$SOURCE"; then
        ORIGINAL_SOURCE_URL="$SOURCE"
        filename="$(basename "${SOURCE%%\?*}")"
        [[ -z "$filename" || "$filename" == "/" ]] && filename="downloaded-app.bin"
        download_url_asset "$SOURCE" "$filename"
    fi
fi

# --- Interactive Package Selection if Source is omitted ---
if [[ -z "$SOURCE" ]]; then
    IS_INTERACTIVE=true
    current_dir="$(pwd)"
    
    # Find candidate archives and executables in current directory
    candidates=()
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        base="$(basename "$file")"
        # Skip installer itself or common scripts
        if [[ "$base" =~ ^(pinstall|pinstall\.sh|PortableInstaller|with-proxy|withproxy|noproxy).* ]]; then
            continue
        fi
        candidates+=("$file")
    done < <(find . -maxdepth 1 -type f \( \
        -iname "*.zip" -o -iname "*.7z" -o -iname "*.rar" -o \
        -iname "*.tar" -o -iname "*.tar.gz" -o -iname "*.tgz" -o \
        -iname "*.tar.xz" -o -iname "*.txz" -o -iname "*.tar.zst" -o \
        -iname "*.tar.bz2" -o -iname "*.tbz2" -o -iname "*.iso" -o \
        -iname "*.AppImage" \) 2>/dev/null | sort -f)

    # Also check for standalone executable binaries
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        base="$(basename "$file")"
        if [[ "$base" =~ ^(pinstall|pinstall\.sh|PortableInstaller|with-proxy|withproxy|noproxy).* ]]; then
            continue
        fi
        # Check if file is ELF executable and not already in candidates
        if file -b "$file" 2>/dev/null | grep -q "ELF.*executable"; then
            candidates+=("$file")
        fi
    done < <(find . -maxdepth 1 -type f -executable ! -name "*.*" 2>/dev/null | sort -f)

    candidate_count="${#candidates[@]}"

    if (( candidate_count == 0 )); then
        warn "No supported archives or portable binaries found in: $current_dir"
        printf "Usage: pinstall <source_archive_or_binary> [options]\n"
        printf "       pinstall --list\n"
        printf "       pinstall --uninstall [name]\n"
        exit 1
    fi

    printf "\n${COLOR_CYAN}📦 Found %d installable package(s) in: %s${COLOR_RESET}\n" "$candidate_count" "$current_dir"
    printf "${COLOR_DIM}------------------------------------------------------------------------${COLOR_RESET}\n"

    for i in "${!candidates[@]}"; do
        item="${candidates[$i]}"
        size_bytes=$(stat -c%s "$item" 2>/dev/null || wc -c < "$item" 2>/dev/null || echo 0)
        size_str="$(format_size "$size_bytes")"
        base_name="$(basename "$item")"
        printf "  [${COLOR_BOLD}%d${COLOR_RESET}] %-42s %10s\n" "$((i + 1))" "$base_name" "$size_str"
    done
    printf "${COLOR_DIM}------------------------------------------------------------------------${COLOR_RESET}\n"

    if (( candidate_count == 1 )); then
        read -r -p "Enter selection [Default: 1] or 'q' to quit: " choice
        [[ -z "$choice" ]] && choice="1"
    else
        read -r -p "Enter selection (1-${candidate_count}) or 'q' to quit: " choice
    fi

    if [[ "$choice" =~ ^[Qq]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > candidate_count )); then
        err "Invalid selection: '$choice'"
        exit 1
    fi

    SOURCE="${candidates[$((choice - 1))]}"
fi

# Resolve source path
if [[ ! -f "$SOURCE" ]]; then
    err "Source file not found: '$SOURCE'"
    exit 1
fi
SOURCE_PATH="$(realpath "$SOURCE")"
SOURCE_FILENAME="$(basename "$SOURCE_PATH")"

# --- Determine App Name ---
if [[ -z "$APP_NAME" ]]; then
    suggested_name="$(clean_app_name "$SOURCE_FILENAME")"
    if [[ "$IS_INTERACTIVE" == true ]]; then
        read -r -p "Enter application name [Default: '${suggested_name}']: " user_name
        if [[ -n "${user_name// }" ]]; then
            APP_NAME="${user_name#"${user_name%%[![:space:]]*}"}"
            APP_NAME="${APP_NAME%"${APP_NAME##*[![:space:]]}"}"
        else
            APP_NAME="$suggested_name"
        fi
    else
        APP_NAME="$suggested_name"
    fi
fi

APP_SLUG="$(slugify "$APP_NAME")"
[[ -z "$APP_SLUG" ]] && APP_SLUG="portable-app"

# Prompt for AddToPath interactively if not already set
if [[ "$IS_INTERACTIVE" == true && "$ADD_TO_PATH" == false ]]; then
    read -r -p "Create terminal symlink in ~/.local/bin (PATH)? [y/N]: " path_choice
    if [[ "$path_choice" =~ ^[Yy]$ ]]; then
        ADD_TO_PATH=true
    fi
fi

# --- Target Paths ---
INSTALL_BASE="$HOME/.local/share"
APP_DEST_DIR="$INSTALL_BASE/$APP_NAME"

info "Processing '$APP_NAME' from '$SOURCE_FILENAME'..."

# Handle existing installation directory
if [[ -d "$APP_DEST_DIR" ]]; then
    if [[ "$FORCE" == true ]]; then
        warn "Directory '$APP_DEST_DIR' already exists. Overwriting (--force specified)..."
        rm -rf "$APP_DEST_DIR"
    else
        read -r -p "Directory '$APP_DEST_DIR' already exists. Overwrite? [y/N]: " overwrite_choice
        if [[ "$overwrite_choice" =~ ^[Yy]$ ]]; then
            rm -rf "$APP_DEST_DIR"
        else
            warn "Installation aborted by user."
            exit 0
        fi
    fi
fi

mkdir -p "$APP_DEST_DIR"

# --- Determine Type & Extract / Copy ---
is_archive=false
case "${SOURCE_FILENAME,,}" in
    *.zip|*.7z|*.rar|*.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tar.bz2|*.tbz2|*.iso)
        is_archive=true
        ;;
esac

if [[ "$is_archive" == true ]]; then
    info "Extracting archive to '$APP_DEST_DIR'..."

    extracted=false

    # Primary extractor for tar archives
    case "${SOURCE_FILENAME,,}" in
        *.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tar.bz2|*.tbz2)
            if command -v tar >/dev/null 2>&1; then
                if tar -xf "$SOURCE_PATH" -C "$APP_DEST_DIR" 2>/dev/null; then
                    extracted=true
                    success "Extracted successfully using tar."
                fi
            fi
            ;;
    esac

    # Primary extractor for other archives (or if tar failed): 7z
    if [[ "$extracted" == false ]] && (command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1); then
        SEVEN_ZIP_BIN="$(command -v 7z || command -v 7za)"
        curr_pass="$PASSWORD"
        max_attempts=3
        attempt=0

        while [[ "$extracted" == false ]] && (( attempt < max_attempts )); do
            attempt=$((attempt + 1))
            pass_opt=()
            if [[ -n "$curr_pass" ]]; then
                pass_opt=("-p${curr_pass}")
            else
                pass_opt=("-p")
            fi

            set +e
            seven_out="$("$SEVEN_ZIP_BIN" x -y -aoa -o"$APP_DEST_DIR" "${pass_opt[@]}" "$SOURCE_PATH" 2>&1)"
            status=$?
            set -e

            if (( status == 0 )); then
                extracted=true
                success "Extracted successfully using 7-Zip."

                # If 7z unpacked a single .tar archive (e.g. from .tar.gz), unpack that .tar file
                nested_tar="$(find "$APP_DEST_DIR" -maxdepth 1 -type f -name "*.tar" 2>/dev/null | head -n 1 || true)"
                if [[ -n "$nested_tar" && -f "$nested_tar" ]]; then
                    if command -v tar >/dev/null 2>&1; then
                        info "Extracting nested tar archive '$(basename "$nested_tar")'..."
                        if tar -xf "$nested_tar" -C "$APP_DEST_DIR" 2>/dev/null; then
                            rm -f "$nested_tar"
                        fi
                    fi
                fi
                break
            fi

            # Check if failure is password-related
            if echo "$seven_out" | grep -qiE "(wrong password|enter password|encrypted|data error in encrypted|can not open encrypted)"; then
                if [[ -n "$curr_pass" ]]; then
                    warn "Incorrect password provided (Attempt $attempt of $max_attempts)."
                fi
                if (( attempt < max_attempts )); then
                    read -r -s -p "Archive is password protected. Enter password (or 'q' to cancel): " entered_pass
                    echo
                    if [[ "$entered_pass" =~ ^[Qq]$ || -z "$entered_pass" ]]; then
                        warn "Extraction cancelled by user."
                        break
                    fi
                    curr_pass="$entered_pass"
                fi
            else
                warn "7-Zip extraction encountered an error (code $status): $seven_out"
                break
            fi
        done
    fi

    # Fallback: unzip
    if [[ "$extracted" == false && "${SOURCE_FILENAME,,}" == *.zip ]]; then
        if command -v unzip >/dev/null 2>&1; then
            info "Attempting fallback extraction with unzip..."
            if unzip -q -o "$SOURCE_PATH" -d "$APP_DEST_DIR" 2>/dev/null; then
                extracted=true
                success "Extracted successfully using unzip."
            fi
        fi
    fi

    if [[ "$extracted" == false ]]; then
        err "Failed to extract '$SOURCE_FILENAME'."
        rm -rf "$APP_DEST_DIR"
        exit 1
    fi

    # --- Flatten Single Root Directory ---
    # If the archive only contains a single subfolder, flatten it
    top_entries=("$APP_DEST_DIR"/*)
    if [[ ${#top_entries[@]} -eq 1 && -d "${top_entries[0]}" ]]; then
        nested_dir="${top_entries[0]}"
        info "Flattening redundant single root folder '$(basename "$nested_dir")'..."
        # Move hidden and visible items
        shopt -s dotglob
        mv "$nested_dir"/* "$APP_DEST_DIR"/ 2>/dev/null || true
        shopt -u dotglob
        rmdir "$nested_dir" 2>/dev/null || true
    fi

else
    # Standalone Binary / AppImage
    info "Installing executable file to '$APP_DEST_DIR'..."
    cp -p "$SOURCE_PATH" "$APP_DEST_DIR/$SOURCE_FILENAME"
    chmod +x "$APP_DEST_DIR/$SOURCE_FILENAME"
fi

# --- Set Executable Permissions on All ELF Binaries & Scripts ---
info "Setting executable permissions on binaries..."
while IFS= read -r -d '' file; do
    # Check if file is ELF or shell script or AppImage
    ftype="$(file -b "$file" 2>/dev/null || true)"
    if echo "$ftype" | grep -qiE "(ELF|executable|script|AppImage)"; then
        chmod +x "$file" 2>/dev/null || true
    fi
done < <(find "$APP_DEST_DIR" -type f -print0)

# --- Detect Primary Executable Binary ---
candidates_exec=()

if [[ -n "$TARGET_EXEC_PARAM" ]]; then
    # Look for specified name
    while IFS= read -r f; do
        [[ -n "$f" ]] && candidates_exec+=("$f")
    done < <(find "$APP_DEST_DIR" -maxdepth 3 -type f -name "*$TARGET_EXEC_PARAM*" -executable 2>/dev/null)
fi

if [[ ${#candidates_exec[@]} -eq 0 ]]; then
    # Auto-detect candidates: search root of app and maxdepth 2
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        fname="$(basename "$f")"
        # Filter out common helper, crash reporter, or lib files
        if [[ "$fname" =~ ^(lib.*\.so.*|uninstall.*|unins.*|helper|crashpad.*|elevate.*|.*\.sh)$ ]]; then
            continue
        fi
        ftype="$(file -b "$f" 2>/dev/null || true)"
        if echo "$ftype" | grep -qiE "(ELF.*executable|AppImage)"; then
            candidates_exec+=("$f")
        fi
    done < <(find "$APP_DEST_DIR" -maxdepth 2 -type f -executable 2>/dev/null)
fi

TARGET_EXEC_PATH=""

if [[ ${#candidates_exec[@]} -eq 1 ]]; then
    TARGET_EXEC_PATH="${candidates_exec[0]}"
    success "Detected primary executable: $(basename "$TARGET_EXEC_PATH")"
elif [[ ${#candidates_exec[@]} -gt 1 ]]; then
    # Try exact match with app name slug or source base
    for c in "${candidates_exec[@]}"; do
        cbase="$(basename "$c")"
        if [[ "${cbase,,}" == "${APP_SLUG,,}" || "${cbase,,}" == "${APP_NAME,,}" ]]; then
            TARGET_EXEC_PATH="$c"
            break
        fi
    done

    if [[ -z "$TARGET_EXEC_PATH" ]]; then
        printf "\n${COLOR_YELLOW}Multiple executable binaries found. Please select the primary application binary:${COLOR_RESET}\n"
        for i in "${!candidates_exec[@]}"; do
            rel_path="${candidates_exec[$i]#"$APP_DEST_DIR"/}"
            printf "  [${COLOR_BOLD}%d${COLOR_RESET}] %s\n" "$((i + 1))" "$rel_path"
        done

        read -r -p "Enter number (1-${#candidates_exec[@]}) [Default: 1]: " sel_exec
        [[ -z "$sel_exec" ]] && sel_exec="1"
        if [[ "$sel_exec" =~ ^[0-9]+$ ]] && (( sel_exec >= 1 && sel_exec <= ${#candidates_exec[@]} )); then
            TARGET_EXEC_PATH="${candidates_exec[$((sel_exec - 1))]}"
        else
            TARGET_EXEC_PATH="${candidates_exec[0]}"
        fi
    fi
    success "Selected primary executable: $(basename "$TARGET_EXEC_PATH")"
else
    # Fallback: check if standalone file or any file with +x
    any_exec="$(find "$APP_DEST_DIR" -type f -executable 2>/dev/null | head -n 1 || true)"
    if [[ -n "$any_exec" ]]; then
        TARGET_EXEC_PATH="$any_exec"
        warn "Using fallback executable: $(basename "$TARGET_EXEC_PATH")"
    fi
fi

# Ensure executable bit
if [[ -n "$TARGET_EXEC_PATH" && -f "$TARGET_EXEC_PATH" ]]; then
    chmod +x "$TARGET_EXEC_PATH"
fi

# --- Icon Detection ---
ICON_PATH=""

if [[ -n "$CUSTOM_ICON" && -f "$CUSTOM_ICON" ]]; then
    ICON_PATH="$(realpath "$CUSTOM_ICON")"
else
    # Search for icon files in extracted folder
    icon_candidates=()
    while IFS= read -r icon; do
        [[ -n "$icon" ]] && icon_candidates+=("$icon")
    done < <(find "$APP_DEST_DIR" -maxdepth 3 -type f \( -iname "*.png" -o -iname "*.svg" \) 2>/dev/null)

    if [[ ${#icon_candidates[@]} -gt 0 ]]; then
        # Prefer icon matching AppName or 'icon', 'logo', 'app'
        for ic in "${icon_candidates[@]}"; do
            icbase="$(basename "$ic")"
            if [[ "${icbase,,}" =~ (${APP_SLUG,,}|icon|logo|app|${APP_NAME,,}) ]]; then
                ICON_PATH="$ic"
                break
            fi
        done
        # Fallback to first found icon
        if [[ -z "$ICON_PATH" ]]; then
            ICON_PATH="${icon_candidates[0]}"
        fi
    else
        # Fallback generic system icon
        ICON_PATH="application-x-executable"
    fi
fi

# --- Create Desktop Entry ---
DESKTOP_FILE=""

if [[ "$NO_DESKTOP" == false && -n "$TARGET_EXEC_PATH" ]]; then
    DESKTOP_FILE="$HOME/.local/share/applications/${APP_SLUG}.desktop"
    info "Creating desktop entry at '$DESKTOP_FILE'..."
    mkdir -p "$HOME/.local/share/applications"

    terminal_flag="false"
    if [[ "$TERMINAL_APP" == true ]]; then
        terminal_flag="true"
    fi

    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_NAME} Portable Application
Exec=${TARGET_EXEC_PATH} %u
Path=${APP_DEST_DIR}
Icon=${ICON_PATH}
Terminal=${terminal_flag}
Type=Application
Categories=${CATEGORIES}
StartupWMClass=$(basename "$TARGET_EXEC_PATH")
EOF

    chmod +x "$DESKTOP_FILE"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi
    success "Desktop entry created and indexed in Omarchy application menu."
fi

# --- Add to PATH via ~/.local/bin Symlink ---
BIN_LINK_PATH=""
if [[ "$ADD_TO_PATH" == true && -n "$TARGET_EXEC_PATH" ]]; then
    mkdir -p "$HOME/.local/bin"
    bin_name="$(basename "$TARGET_EXEC_PATH")"
    BIN_LINK_PATH="$HOME/.local/bin/$bin_name"

    ln -sf "$TARGET_EXEC_PATH" "$BIN_LINK_PATH"
    chmod +x "$BIN_LINK_PATH"
    success "Created PATH symlink: $BIN_LINK_PATH -> $TARGET_EXEC_PATH"
fi

# --- Write Metadata Receipt (.pinstall.json) ---
RECEIPT_FILE="$APP_DEST_DIR/.pinstall.json"
INSTALL_TIMESTAMP="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"

cat > "$RECEIPT_FILE" <<EOF
{
  "name": "${APP_NAME}",
  "slug": "${APP_SLUG}",
  "source_file": "${SOURCE_FILENAME}",
  "source_url": "${ORIGINAL_SOURCE_URL}",
  "github_repo": "${ORIGINAL_GITHUB_REPO}",
  "install_dir": "${APP_DEST_DIR}",
  "exec_path": "${TARGET_EXEC_PATH}",
  "desktop_file": "${DESKTOP_FILE}",
  "bin_link": "${BIN_LINK_PATH}",
  "icon_path": "${ICON_PATH}",
  "categories": "${CATEGORIES}",
  "installed_at": "${INSTALL_TIMESTAMP}"
}
EOF

# --- Final Summary Report ---
printf "\n${COLOR_BOLD}${COLOR_GREEN}===================================================================${COLOR_RESET}\n"
printf "${COLOR_BOLD}${COLOR_GREEN}           INSTALLATION SUMMARY REPORT                             ${COLOR_RESET}\n"
printf "${COLOR_BOLD}${COLOR_GREEN}===================================================================${COLOR_RESET}\n"
printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "App Name" "$APP_NAME"
printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "Installed Directory" "$APP_DEST_DIR"

if [[ -n "$ORIGINAL_SOURCE_URL" ]]; then
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "Downloaded From" "$ORIGINAL_SOURCE_URL"
fi

if [[ -n "$TARGET_EXEC_PATH" ]]; then
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "Target Binary" "$TARGET_EXEC_PATH"
fi

if [[ "$NO_DESKTOP" == false && -f "$DESKTOP_FILE" ]]; then
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "Desktop Entry (.desktop)" "$DESKTOP_FILE"
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "Working Path (Path=)" "$APP_DEST_DIR"
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "App Icon" "$ICON_PATH"
else
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "Desktop Entry" "[Skipped / Disabled]"
fi

if [[ -n "$BIN_LINK_PATH" ]]; then
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s (%s)\n" "CLI Command (PATH)" "$(basename "$BIN_LINK_PATH")" "$BIN_LINK_PATH"
else
    printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "CLI Command (PATH)" "[None - run with --add-to-path if needed]"
fi

printf "  ${COLOR_BOLD}%-20s${COLOR_RESET} : %s\n" "Metadata Receipt" "$RECEIPT_FILE"
printf "${COLOR_BOLD}${COLOR_GREEN}===================================================================${COLOR_RESET}\n"
printf "${COLOR_CYAN}✓ App successfully registered in Omarchy applications list.${COLOR_RESET}\n"
printf "${COLOR_DIM}Tip: You can uninstall anytime with 'pinstall --uninstall \"%s\"'${COLOR_RESET}\n\n" "$APP_NAME"
