#!/usr/bin/env bash
# Termux Backup & Restore Tool with Interactive Selection & Progress Bar
set -e

BACKUP_DIR="/sdcard/termux-backup"
TARGET_DIR="/data/data/com.termux/files"

mkdir -p "$BACKUP_DIR"

action="${1:-backup}"

case "$action" in
    backup)
        filename="termux-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
        dest="$BACKUP_DIR/$filename"
        echo -e "\033[36m📦 Creating Full Termux Backup:\033[0m $filename"
        echo -e "\033[33m⏳ Calculating total size...\033[0m"
        
        # Calculate size for pv progress bar
        total_size=$(du -sb "$TARGET_DIR/home" "$TARGET_DIR/usr" 2>/dev/null | awk '{s+=$1} END {print s}')
        
        echo -e "\033[32m🚀 Archiving ($((total_size / 1024 / 1024)) MB)...\033[0m"
        
        if command -v pv >/dev/null 2>&1; then
            tar -cpf - --preserve-permissions -C "$TARGET_DIR" ./home ./usr 2>/dev/null \
                | pv -p -t -e -r -b -s "$total_size" \
                | gzip > "$dest"
        else
            tar -zcf "$dest" --preserve-permissions -C "$TARGET_DIR" ./home ./usr
        fi
        
        echo -e "\n\033[32m✅ Backup successfully saved to:\033[0m $dest"
        ;;

    restore)
        # Find all backup files sorted by modification time (newest first)
        mapfile -t backups < <(ls -t "$BACKUP_DIR"/termux-backup-*.tar.gz 2>/dev/null)
        
        if [ ${#backups[@]} -eq 0 ]; then
            echo -e "\033[31m❌ No backup files found in $BACKUP_DIR\033[0m"
            exit 1
        fi

        selected_file=""
        if [ ${#backups[@]} -eq 1 ]; then
            selected_file="${backups[0]}"
            echo -e "\033[36mℹ️ Found 1 backup:\033[0m $(basename "$selected_file")"
        else
            echo -e "\033[36m📋 Available Backups:\033[0m"
            for i in "${!backups[@]}"; do
                bname=$(basename "${backups[$i]}")
                bsize=$(du -h "${backups[$i]}" | cut -f1)
                echo -e "  \033[33m[$((i + 1))]\033[0m $bname \033[90m($bsize)\033[0m"
            done
            
            echo -ne "\n\033[32m👉 Select backup number to restore [1-${#backups[@]}] (Default: 1): \033[0m"
            read -r choice
            choice="${choice:-1}"
            
            if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
                echo -e "\033[31m❌ Invalid choice. Aborting.\033[0m"
                exit 1
            fi
            
            selected_file="${backups[$((choice - 1))]}"
        fi

        echo -e "\n\033[33m⚠️  Restoring:\033[0m $(basename "$selected_file")"
        echo -ne "\033[31mAre you sure you want to restore and overwrite current environment? (y/N): \033[0m"
        read -r confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            echo "Cancelled."
            exit 0
        fi

        file_size=$(stat -c%s "$selected_file" 2>/dev/null || wc -c < "$selected_file")
        
        echo -e "\033[32m🚀 Extracting with progress...\033[0m"
        if command -v pv >/dev/null 2>&1; then
            pv -p -t -e -r -b -s "$file_size" "$selected_file" \
                | tar -zxf - -C "$TARGET_DIR" --recursive-unlink --preserve-permissions
        else
            tar -zxf "$selected_file" -C "$TARGET_DIR" --recursive-unlink --preserve-permissions
        fi

        echo -e "\n\033[32m✅ Restore completed successfully! Please restart Termux.\033[0m"
        ;;

    *)
        echo "Usage: termux-backup-tool.sh [backup|restore]"
        exit 1
        ;;
esac
