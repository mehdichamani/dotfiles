#!/bin/bash

# Define the SSH directory
SSH_DIR="$HOME/.ssh"

echo "Applying secure permissions to $SSH_DIR..."

# 1. Secure the directory itself (700: rwx for owner only)
if [ -d "$SSH_DIR" ]; then
    chmod 700 "$SSH_DIR"
    echo "[✔] Directory .ssh set to 700"
else
    echo "[!] Directory $SSH_DIR not found!"
    exit 1
fi

# 2. Secure all private keys (600: rw for owner only)
# This finds files starting with 'id_' and NOT ending in '.pub'
find "$SSH_DIR" -type f \( -name "id_*" ! -name "*.pub" \) -exec chmod 600 {} +
echo "[✔] Private keys set to 600"

# 3. Secure the public keys (644: rw for owner, r for others)
find "$SSH_DIR" -type f -name "*.pub" -exec chmod 644 {} +
echo "[✔] Public keys (.pub) set to 644"

# 4. Secure Authorized Keys and Config files
[ -f "$SSH_DIR/authorized_keys" ] && chmod 600 "$SSH_DIR/authorized_keys" && echo "[✔] authorized_keys set to 600"
[ -f "$SSH_DIR/config" ] && chmod 600 "$SSH_DIR/config" && echo "[✔] SSH config set to 600"
# 5. Remove known_hosts files
if rm -f "$SSH_DIR/known_hosts"* 2>/dev/null; then
    echo "[✔] known_hosts removed"
fi

echo "All done! Your SSH keys are now secure."
