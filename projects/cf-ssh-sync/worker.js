/**
 * Cloudflare Worker for Secure SSH Keys & Secrets Vault Sync
 * 
 * Routes:
 *  - GET  /         : Rich Web UI / CLI instructions
 *  - GET  /send.sh  : Bash script to encrypt and upload ~/.ssh and ~/.config/secrets (Requires token)
 *  - GET  /get.sh   : Bash script to download, decrypt and restore ~/.ssh, secrets, and unlock git-crypt
 *  - GET  /send.ps1 : PowerShell script to encrypt and upload (Windows, Requires token)
 *  - GET  /get.ps1  : PowerShell script to download, decrypt and restore (Windows)
 *  - POST /data     : Stores raw encrypted payload into KV (Requires token)
 *  - GET  /data     : Retrieves raw encrypted payload from KV (Public zero-knowledge ciphertext)
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const pathname = url.pathname;
    const origin = url.origin;

    // Helper to validate Sync Token if configured on worker
    const validateToken = (req) => {
      const serverToken = env.SYNC_TOKEN;
      if (!serverToken) {
        // If no token configured in worker secrets, allow for backward compatibility
        return true;
      }
      const clientToken = url.searchParams.get('token') || req.headers.get('X-Sync-Token');
      return clientToken && clientToken === serverToken;
    };

    // 1. GET /send.sh (Requires token if SYNC_TOKEN is set)
    if (pathname === '/send.sh') {
      if (!validateToken(request)) {
        return new Response('❌ Unauthorized: Missing or invalid token parameter (?token=YOUR_TOKEN)\n', {
          status: 401,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }

      const clientToken = url.searchParams.get('token') || '';
      const tokenQuery = clientToken ? `?token=${encodeURIComponent(clientToken)}` : '';

      const script = `#!/usr/bin/env bash
set -euo pipefail

SSH_DIR="\${HOME}/.ssh"
SECRETS_DIR="\${HOME}/.config/secrets"

if [ ! -d "\$SSH_DIR" ] && [ ! -d "\$SECRETS_DIR" ]; then
  echo "Error: Neither \$SSH_DIR nor \$SECRETS_DIR exists!" >&2
  exit 1
fi

# Ensure openssl and tar are installed
ensure_deps() {
  local missing=()
  command -v openssl >/dev/null 2>&1 || missing+=("openssl")
  command -v tar >/dev/null 2>&1 || missing+=("tar")
  command -v curl >/dev/null 2>&1 || missing+=("curl")

  if [ \${#missing[@]} -ne 0 ]; then
    echo "Missing dependencies: \${missing[*]}"
    echo "Attempting to install..."
    if command -v pkg >/dev/null 2>&1; then
      local termux_pkgs=()
      for pkg in "\${missing[@]}"; do
        [ "\$pkg" = "openssl" ] && termux_pkgs+=("openssl-tool") || termux_pkgs+=("\$pkg")
      done
      pkg install -y "\${termux_pkgs[@]}"
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -Sy --noconfirm "\${missing[@]}"
    elif command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y "\${missing[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "\${missing[@]}"
    elif command -v brew >/dev/null 2>&1; then
      brew install "\${missing[@]}"
    else
      echo "Please install \${missing[*]} manually and rerun." >&2
      exit 1
    fi
  fi
}

ensure_deps

echo "=========================================="
echo "  🔒 Encrypting & Uploading Vault (SSH & Secrets)"
echo "=========================================="

echo -n "Enter encryption passphrase: "
read -s PASSPHRASE </dev/tty
echo ""

if [ -z "\$PASSPHRASE" ]; then
  echo "Error: Passphrase cannot be empty." >&2
  exit 1
fi

TEMP_DIR=$(mktemp -d)
TEMP_ENC=$(mktemp)
trap 'rm -rf "$TEMP_DIR" "$TEMP_ENC"' EXIT

# Prepare clean structure in temporary workspace
if [ -d "\$SSH_DIR" ]; then
  mkdir -p "\$TEMP_DIR/ssh"
  cp -a "\$SSH_DIR/." "\$TEMP_DIR/ssh/"
  echo "✔ Added ~/.ssh contents"
fi

if [ -d "\$SECRETS_DIR" ]; then
  mkdir -p "\$TEMP_DIR/secrets"
  cp -a "\$SECRETS_DIR/." "\$TEMP_DIR/secrets/"
  echo "✔ Added ~/.config/secrets contents"
fi

echo "Archiving and encrypting vault data (AES-256-CBC)..."
tar -C "\$TEMP_DIR" -czf - . | openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"\$PASSPHRASE" -out "\$TEMP_ENC"

echo "Uploading encrypted payload to Cloudflare KV..."
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X POST "${origin}/data${tokenQuery}" \
  -H "Content-Type: application/octet-stream" \
  ${clientToken ? `-H "X-Sync-Token: ${clientToken}" \\` : ''}
  --data-binary "@\$TEMP_ENC")

rm -rf "\$TEMP_DIR" "\$TEMP_ENC"
trap - EXIT

if [ "\$HTTP_CODE" -eq 200 ] || [ "\$HTTP_CODE" -eq 201 ]; then
  echo "✅ Success! Encrypted vault payload uploaded."
else
  echo "❌ Upload failed with HTTP status \$HTTP_CODE." >&2
  exit 1
fi
`;
      return new Response(script, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    // 2. GET /get.sh (Public, zero-knowledge ciphertext decryption)
    if (pathname === '/get.sh') {
      const script = `#!/usr/bin/env bash
set -euo pipefail

SSH_DIR="\${HOME}/.ssh"
SECRETS_DIR="\${HOME}/.config/secrets"

# Ensure openssl, tar, and curl are installed
ensure_deps() {
  local missing=()
  command -v openssl >/dev/null 2>&1 || missing+=("openssl")
  command -v tar >/dev/null 2>&1 || missing+=("tar")
  command -v curl >/dev/null 2>&1 || missing+=("curl")

  if [ \${#missing[@]} -ne 0 ]; then
    echo "Missing dependencies: \${missing[*]}"
    echo "Attempting to install..."
    if command -v pkg >/dev/null 2>&1; then
      local termux_pkgs=()
      for pkg in "\${missing[@]}"; do
        [ "\$pkg" = "openssl" ] && termux_pkgs+=("openssl-tool") || termux_pkgs+=("\$pkg")
      done
      pkg install -y "\${termux_pkgs[@]}"
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -Sy --noconfirm "\${missing[@]}"
    elif command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y "\${missing[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "\${missing[@]}"
    elif command -v brew >/dev/null 2>&1; then
      brew install "\${missing[@]}"
    else
      echo "Please install \${missing[*]} manually and rerun." >&2
      exit 1
    fi
  fi
}

ensure_deps

echo "=========================================="
echo "  🔑 Downloading & Restoring Vault (SSH & Secrets)"
echo "=========================================="

echo -n "Enter decryption passphrase: "
read -s PASSPHRASE </dev/tty
echo ""

if [ -z "\$PASSPHRASE" ]; then
  echo "Error: Passphrase cannot be empty." >&2
  exit 1
fi

echo "Fetching encrypted payload..."
TEMP_FILE=$(mktemp)
TEMP_EXTRACT=$(mktemp -d)
trap 'rm -rf "$TEMP_FILE" "$TEMP_EXTRACT"' EXIT

HTTP_CODE=$(curl -s -w "%{http_code}" -o "\$TEMP_FILE" "${origin}/data")

if [ "\$HTTP_CODE" -ne 200 ]; then
  echo "❌ Failed to download vault payload. HTTP status: \$HTTP_CODE (Payload may not have been uploaded yet)" >&2
  rm -rf "\$TEMP_FILE" "\$TEMP_EXTRACT"
  exit 1
fi

echo "Decrypting and extracting payload..."
if openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass pass:"\$PASSPHRASE" -in "\$TEMP_FILE" | tar -xzf - -C "\$TEMP_EXTRACT"; then
  echo "✅ Decryption successful."
else
  echo "❌ Decryption failed! Check your passphrase." >&2
  rm -rf "\$TEMP_FILE" "\$TEMP_EXTRACT"
  exit 1
fi

# 1. Restore SSH if present in archive (or legacy root archive format)
mkdir -p "\$SSH_DIR"
if [ -d "\$TEMP_EXTRACT/ssh" ]; then
  cp -a "\$TEMP_EXTRACT/ssh/." "\$SSH_DIR/"
  echo "✔ Restored ~/.ssh"
elif [ ! -d "\$TEMP_EXTRACT/secrets" ]; then
  # Legacy payload format where root of tar was directly ~/.ssh
  cp -a "\$TEMP_EXTRACT/." "\$SSH_DIR/"
  echo "✔ Restored ~/.ssh (Legacy format)"
fi

# 2. Restore Secrets if present
if [ -d "\$TEMP_EXTRACT/secrets" ]; then
  mkdir -p "\$SECRETS_DIR"
  cp -a "\$TEMP_EXTRACT/secrets/." "\$SECRETS_DIR/"
  echo "✔ Restored ~/.config/secrets"
fi

# 3. Apply Strict Security Permissions
chmod 700 "\$SSH_DIR" 2>/dev/null || true
find "\$SSH_DIR" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} + 2>/dev/null || true
find "\$SSH_DIR" -type f -name "*.pub" -exec chmod 644 {} + 2>/dev/null || true
[ -f "\$SSH_DIR/config" ] && chmod 600 "\$SSH_DIR/config" 2>/dev/null || true
[ -f "\$SSH_DIR/authorized_keys" ] && chmod 600 "\$SSH_DIR/authorized_keys" 2>/dev/null || true

if [ -d "\$SECRETS_DIR" ]; then
  chmod 700 "\$SECRETS_DIR" 2>/dev/null || true
  find "\$SECRETS_DIR" -type f -exec chmod 600 {} + 2>/dev/null || true
fi
echo "✔ Strict security permissions (700/600) applied."

# 4. Optional fix_permisions.sh execution if present
FIX_PERMS="\$SSH_DIR/fix_permisions.sh"
if [ -f "\$FIX_PERMS" ]; then
  chmod +x "\$FIX_PERMS"
  bash "\$FIX_PERMS"
fi

# 5. Automatically unlock Chezmoi Git-Crypt if key and repo exist
GIT_CRYPT_KEY="\$SECRETS_DIR/chezmoi-git-crypt.key"
CHEZMOI_REPO="\$HOME/.local/share/chezmoi"

if [ -f "\$GIT_CRYPT_KEY" ] && [ -d "\$CHEZMOI_REPO/.git" ]; then
  if command -v git-crypt >/dev/null 2>&1; then
    echo "🔓 Unlocking Chezmoi Git-Crypt repository..."
    if (cd "\$CHEZMOI_REPO" && git-crypt unlock "\$GIT_CRYPT_KEY"); then
      echo "✅ Chezmoi repository decrypted with git-crypt."
    else
      echo "⚠️ Git-crypt unlock returned non-zero code."
    fi
  else
    echo "ℹ️ git-crypt is not installed. Key saved at \$GIT_CRYPT_KEY for manual unlock."
  fi
fi

rm -rf "\$TEMP_FILE" "\$TEMP_EXTRACT"
trap - EXIT

echo "🎉 Done! Your environment, SSH keys and secrets vault are ready."
`;
      return new Response(script, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    // 3. GET /send.ps1 (Windows PowerShell, Requires token if SYNC_TOKEN is set)
    if (pathname === '/send.ps1') {
      if (!validateToken(request)) {
        return new Response('❌ Unauthorized: Missing or invalid token parameter (?token=YOUR_TOKEN)\n', {
          status: 401,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }

      const clientToken = url.searchParams.get('token') || '';
      const tokenQuery = clientToken ? `?token=${encodeURIComponent(clientToken)}` : '';

      const script = `$ErrorActionPreference = 'Stop'
$sshDir = Join-Path $HOME ".ssh"
$secretsDir = Join-Path $HOME ".config\\secrets"

if (-not (Test-Path $sshDir) -and -not (Test-Path $secretsDir)) {
    Write-Error "Neither $sshDir nor $secretsDir exists!"
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  🔒 Encrypting & Uploading Vault (Windows)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$pass = Read-Host "Enter encryption passphrase" -AsSecureString
$passBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($passBSTR)

if ([string]::IsNullOrEmpty($plainPass)) {
    Write-Error "Passphrase cannot be empty."
    exit 1
}

$tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("cf_vault_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null

try {
    if (Test-Path $sshDir) {
        $destSsh = Join-Path $tempFolder "ssh"
        Copy-Item -Path "$sshDir" -Destination $destSsh -Recurse -Force
        Write-Host "✔ Added ~/.ssh contents" -ForegroundColor Green
    }

    if (Test-Path $secretsDir) {
        $destSecrets = Join-Path $tempFolder "secrets"
        Copy-Item -Path "$secretsDir" -Destination $destSecrets -Recurse -Force
        Write-Host "✔ Added ~/.config/secrets contents" -ForegroundColor Green
    }

    $hasTar = Get-Command tar -ErrorAction SilentlyContinue
    $hasOpenssl = Get-Command openssl -ErrorAction SilentlyContinue

    if ($hasTar -and $hasOpenssl) {
        Write-Host "Archiving with Tar and OpenSSL AES-256-CBC..." -ForegroundColor Yellow
        $tempTar = [System.IO.Path]::GetTempFileName()
        $tempEnc = [System.IO.Path]::GetTempFileName()
        try {
            & tar -C $tempFolder -czf $tempTar .
            & openssl enc -aes-256-cbc -pbkdf2 -salt -pass "pass:$plainPass" -in $tempTar -out $tempEnc
            $encBytes = [System.IO.File]::ReadAllBytes($tempEnc)
            
            $headers = @{ "Content-Type" = "application/octet-stream" }
            ${clientToken ? `$headers["X-Sync-Token"] = "${clientToken}"` : ''}

            Invoke-RestMethod -Uri "${origin}/data${tokenQuery}" -Method Post -Body $encBytes -Headers $headers
            Write-Host "✅ Success! Encrypted vault uploaded." -ForegroundColor Green
        } finally {
            Remove-Item -Force $tempTar, $tempEnc -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "OpenSSL/Tar not found. Using PowerShell Zip & AES-256..." -ForegroundColor Yellow
        $tempZip = [System.IO.Path]::GetTempFileName() + ".zip"
        try {
            Compress-Archive -Path "$tempFolder\\*" -DestinationPath $tempZip -Force
            $zipBytes = [System.IO.File]::ReadAllBytes($tempZip)

            # AES-256 PBKDF2 via .NET
            $salt = New-Object byte[](16)
            [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
            $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($plainPass, $salt, 10000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
            $key = $derive.GetBytes(32)
            $iv = $derive.GetBytes(16)

            $aes = [System.Security.Cryptography.Aes]::Create()
            $aes.Key = $key
            $aes.IV = $iv
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $encryptor = $aes.CreateEncryptor()
            $encrypted = $encryptor.TransformFinalBlock($zipBytes, 0, $zipBytes.Length)

            # Format: [16 bytes salt][16 bytes IV][Ciphertext]
            $payload = [byte[]]::new(32 + $encrypted.Length)
            [Buffer]::BlockCopy($salt, 0, $payload, 0, 16)
            [Buffer]::BlockCopy($iv, 0, $payload, 16, 16)
            [Buffer]::BlockCopy($encrypted, 0, $payload, 32, $encrypted.Length)

            $headers = @{ "Content-Type" = "application/octet-stream" }
            ${clientToken ? `$headers["X-Sync-Token"] = "${clientToken}"` : ''}

            Invoke-RestMethod -Uri "${origin}/data${tokenQuery}" -Method Post -Body $payload -Headers $headers
            Write-Host "✅ Success! Encrypted vault uploaded." -ForegroundColor Green
        } finally {
            Remove-Item -Force $tempZip -ErrorAction SilentlyContinue
        }
    }
} finally {
    Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
}
`;
      return new Response(script, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    // 4. GET /get.ps1 (Windows PowerShell, Public zero-knowledge)
    if (pathname === '/get.ps1') {
      const script = `$ErrorActionPreference = 'Stop'
$sshDir = Join-Path $HOME ".ssh"
$secretsDir = Join-Path $HOME ".config\\secrets"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  🔑 Downloading & Restoring Vault (Windows)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$pass = Read-Host "Enter decryption passphrase" -AsSecureString
$passBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($passBSTR)

if ([string]::IsNullOrEmpty($plainPass)) {
    Write-Error "Passphrase cannot be empty."
    exit 1
}

Write-Host "Fetching encrypted payload..." -ForegroundColor Yellow
$resp = Invoke-WebRequest -Uri "${origin}/data" -UseBasicParsing
$payload = $resp.Content

if ($resp.RawContentStream) {
    $ms = New-Object System.IO.MemoryStream
    $resp.RawContentStream.CopyTo($ms)
    $payload = $ms.ToArray()
}

$hasTar = Get-Command tar -ErrorAction SilentlyContinue
$hasOpenssl = Get-Command openssl -ErrorAction SilentlyContinue

function Extract-ArchiveData {
    param([byte[]]$Data, [string]$DestDir)
    
    $isGzip = ($Data.Length -ge 2 -and $Data[0] -eq 0x1F -and $Data[1] -eq 0x8B)
    $isZip = ($Data.Length -ge 4 -and $Data[0] -eq 0x50 -and $Data[1] -eq 0x4B)

    if ($isZip) {
        $tempZip = [System.IO.Path]::GetTempFileName() + ".zip"
        [System.IO.File]::WriteAllBytes($tempZip, $Data)
        try {
            Expand-Archive -Path $tempZip -DestinationPath $DestDir -Force
        } finally {
            Remove-Item -Force $tempZip -ErrorAction SilentlyContinue
        }
        return
    }

    $uncompressed = $Data
    if ($isGzip) {
        $msIn = New-Object System.IO.MemoryStream(,$Data)
        $gz = New-Object System.IO.Compression.GZipStream($msIn, [System.IO.Compression.CompressionMode]::Decompress)
        $msOut = New-Object System.IO.MemoryStream
        $gz.CopyTo($msOut)
        $gz.Close()
        $msIn.Close()
        $uncompressed = $msOut.ToArray()
        $msOut.Close()
    }

    if (Get-Command tar -ErrorAction SilentlyContinue) {
        $tempTar = [System.IO.Path]::GetTempFileName()
        [System.IO.File]::WriteAllBytes($tempTar, $uncompressed)
        try {
            & tar -xf $tempTar -C $DestDir
        } finally {
            Remove-Item -Force $tempTar -ErrorAction SilentlyContinue
        }
    } else {
        # Pure PowerShell TAR extraction
        $pos = 0
        while ($pos + 512 -le $uncompressed.Length) {
            $header = $uncompressed[$pos..($pos + 511)]
            $allNull = $true
            for ($i = 0; $i -lt 512; $i++) {
                if ($header[$i] -ne 0) { $allNull = $false; break }
            }
            if ($allNull) { break }

            $nameBytes = $header[0..99]
            $nameLen = 0
            while ($nameLen -lt 100 -and $nameBytes[$nameLen] -ne 0) { $nameLen++ }
            if ($nameLen -eq 0) { $pos += 512; continue }
            $name = [System.Text.Encoding]::ASCII.GetString($nameBytes, 0, $nameLen).Trim()

            if ($header[257..262] -match "ustar") {
                $prefixBytes = $header[345..499]
                $prefixLen = 0
                while ($prefixLen -lt 155 -and $prefixBytes[$prefixLen] -ne 0) { $prefixLen++ }
                if ($prefixLen -gt 0) {
                    $prefix = [System.Text.Encoding]::ASCII.GetString($prefixBytes, 0, $prefixLen).Trim()
                    $name = "$prefix/$name"
                }
            }

            $sizeStr = [System.Text.Encoding]::ASCII.GetString($header[124..135]).Trim([char]0, ' ')
            $size = 0
            if ($sizeStr) {
                try { $size = [Convert]::ToInt64($sizeStr, 8) } catch { $size = 0 }
            }

            $typeFlag = [char]$header[156]
            $pos += 512

            $cleanName = $name -replace '^\\./', '' -replace '/', [System.IO.Path]::DirectorySeparatorChar
            $targetPath = Join-Path $DestDir $cleanName

            if ($typeFlag -eq '5' -or $name.EndsWith('/')) {
                if (-not (Test-Path $targetPath)) {
                    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                }
            } else {
                $parent = Split-Path -Parent $targetPath
                if ($parent -and -not (Test-Path $parent)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                if ($size -gt 0) {
                    $fileBytes = $uncompressed[$pos..($pos + $size - 1)]
                    [System.IO.File]::WriteAllBytes($targetPath, $fileBytes)
                } else {
                    [System.IO.File]::WriteAllBytes($targetPath, @())
                }
            }

            $blocks = [Math]::Ceiling($size / 512.0)
            $pos += ($blocks * 512)
        }
    }
}

$tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) ("cf_restore_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

try {
    $isOpensslFormat = ($payload.Length -ge 16 -and [System.Text.Encoding]::ASCII.GetString($payload[0..7]) -eq "Salted__")
    $decryptedBytes = $null

    if ($isOpensslFormat) {
        Write-Host "Detected OpenSSL AES-256-CBC payload format..." -ForegroundColor Cyan
        if ($hasOpenssl -and $hasTar) {
            $tempEnc = [System.IO.Path]::GetTempFileName()
            $tempTar = [System.IO.Path]::GetTempFileName()
            try {
                [System.IO.File]::WriteAllBytes($tempEnc, $payload)
                & openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass "pass:$plainPass" -in $tempEnc -out $tempTar
                if ($LASTEXITCODE -eq 0) {
                    & tar -xzf $tempTar -C $tempExtract
                    $decryptedBytes = "DONE"
                }
            } finally {
                Remove-Item -Force $tempEnc, $tempTar -ErrorAction SilentlyContinue
            }
        }

        if (-not $decryptedBytes) {
            Write-Host "Decrypting via native .NET AES (PBKDF2 SHA256)..." -ForegroundColor Cyan
            $salt = $payload[8..15]
            $ciphertext = $payload[16..($payload.Length - 1)]

            $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($plainPass, $salt, 10000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
            $key = $derive.GetBytes(32)
            $iv = $derive.GetBytes(16)

            $aes = [System.Security.Cryptography.Aes]::Create()
            $aes.Key = $key
            $aes.IV = $iv
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $decryptor = $aes.CreateDecryptor()
            $decryptedBytes = $decryptor.TransformFinalBlock($ciphertext, 0, $ciphertext.Length)
        }
    } else {
        Write-Host "Decrypting via native .NET AES..." -ForegroundColor Cyan
        $salt = $payload[0..15]
        $iv = $payload[16..31]
        $ciphertext = $payload[32..($payload.Length - 1)]

        $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($plainPass, $salt, 10000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        $key = $derive.GetBytes(32)

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $decryptor = $aes.CreateDecryptor()
        $decryptedBytes = $decryptor.TransformFinalBlock($ciphertext, 0, $ciphertext.Length)
    }

    if ($decryptedBytes -and $decryptedBytes -ne "DONE") {
        Extract-ArchiveData -Data $decryptedBytes -DestDir $tempExtract
    }

    # 1. Restore SSH
    if (Test-Path (Join-Path $tempExtract "ssh")) {
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
        Copy-Item -Path (Join-Path $tempExtract "ssh\\*") -Destination $sshDir -Recurse -Force
        Write-Host "✔ Restored ~/.ssh" -ForegroundColor Green
    } elseif (-not (Test-Path (Join-Path $tempExtract "secrets"))) {
        # Legacy format fallback
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
        Copy-Item -Path (Join-Path $tempExtract "*") -Destination $sshDir -Recurse -Force
        Write-Host "✔ Restored ~/.ssh (Legacy format)" -ForegroundColor Green
    }

    # 2. Restore Secrets
    if (Test-Path (Join-Path $tempExtract "secrets")) {
        if (-not (Test-Path $secretsDir)) { New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null }
        Copy-Item -Path (Join-Path $tempExtract "secrets\\*") -Destination $secretsDir -Recurse -Force
        Write-Host "✔ Restored ~/.config/secrets" -ForegroundColor Green
    }

    # 3. Unlock git-crypt if key and repo are present
    $cryptKey = Join-Path $secretsDir "chezmoi-git-crypt.key"
    $cmRepo = Join-Path $HOME ".local\\share\\chezmoi"
    if ((Test-Path $cryptKey) -and (Test-Path (Join-Path $cmRepo ".git"))) {
        $hasGitCrypt = Get-Command git-crypt -ErrorAction SilentlyContinue
        if ($hasGitCrypt) {
            Write-Host "🔓 Unlocking Chezmoi Git-Crypt repository..." -ForegroundColor Cyan
            Push-Location $cmRepo
            try {
                & git-crypt unlock $cryptKey
                Write-Host "✅ Chezmoi repository decrypted with git-crypt." -ForegroundColor Green
            } finally {
                Pop-Location
            }
        }
    }

    Write-Host "🎉 Done! Your SSH environment and secrets vault are ready." -ForegroundColor Green
} catch {
    Write-Error "Decryption or restoration failed! ($($_.Exception.Message)) Please verify your passphrase."
    exit 1
} finally {
    Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
}
`;
      return new Response(script, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    // 5. POST /data - Store encrypted bytes into KV (Requires token if SYNC_TOKEN is set)
    if (pathname === '/data' && request.method === 'POST') {
      if (!validateToken(request)) {
        return new Response('❌ Unauthorized: Missing or invalid token parameter (?token=YOUR_TOKEN)\n', {
          status: 401,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }

      if (!env.SSH_KV) {
        return new Response('KV Binding "SSH_KV" not configured.', { status: 500 });
      }
      const data = await request.arrayBuffer();
      if (data.byteLength === 0) {
        return new Response('Empty payload.', { status: 400 });
      }

      await env.SSH_KV.put('ssh_payload', data);
      return new Response('Encrypted vault payload stored successfully.', { status: 200 });
    }

    // 6. GET /data - Retrieve encrypted bytes from KV (Public zero-knowledge)
    if (pathname === '/data' && request.method === 'GET') {
      if (!env.SSH_KV) {
        return new Response('KV Binding "SSH_KV" not configured.', { status: 500 });
      }
      const data = await env.SSH_KV.get('ssh_payload', { type: 'arrayBuffer' });
      if (!data) {
        return new Response('No vault payload found in store.', { status: 404 });
      }
      return new Response(data, {
        headers: {
          'Content-Type': 'application/octet-stream',
          'Cache-Control': 'no-store, no-cache, must-revalidate',
        },
      });
    }

    // 7. Web UI / Default Info
    const acceptHeader = request.headers.get('Accept') || '';
    const userAgent = (request.headers.get('User-Agent') || '').toLowerCase();
    const isCli = userAgent.includes('curl') || userAgent.includes('wget') || userAgent.includes('httpie') || acceptHeader.startsWith('text/plain');

    if (isCli && pathname === '/') {
      return new Response(
        `🔒 Warden Cloudflare Vault & SSH Sync Worker

Usage:
------
1. Download & Restore vault (Public, Zero-Knowledge):
   - Linux/Mac/Termux : curl -fsSL ${origin}/get.sh | bash
   - Windows (PS)     : irm ${origin}/get.ps1 | iex

2. Encrypt & Upload vault (Requires token):
   - Linux/Mac/Termux : curl -fsSL "${origin}/send.sh?token=YOUR_TOKEN" | bash
   - Windows (PS)     : irm "${origin}/send.ps1?token=YOUR_TOKEN" | iex

Endpoints:
----------
- Linux Send Script : ${origin}/send.sh?token=YOUR_TOKEN
- Linux Get Script  : ${origin}/get.sh
- Win Send Script   : ${origin}/send.ps1?token=YOUR_TOKEN
- Win Get Script    : ${origin}/get.ps1
`,
        { headers: { 'Content-Type': 'text/plain; charset=utf-8' } }
      );
    }

    if (pathname === '/') {
      const html = `<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Warden Vault Sync | هماهنگ‌سازی امن کلیدها و سکرت‌ها</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Vazirmatn:wght@300;400;600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-primary: #0b0f19;
      --bg-card: rgba(22, 29, 47, 0.75);
      --bg-card-hover: rgba(30, 41, 67, 0.85);
      --border-color: rgba(255, 255, 255, 0.08);
      --accent-cyan: #06b6d4;
      --accent-cyan-glow: rgba(6, 182, 212, 0.25);
      --accent-blue: #3b82f6;
      --accent-emerald: #10b981;
      --accent-purple: #a855f7;
      --text-main: #f8fafc;
      --text-muted: #94a3b8;
      --code-bg: #050811;
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    body {
      background-color: var(--bg-primary);
      color: var(--text-main);
      font-family: 'Vazirmatn', sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 2rem 1rem;
      background-image: 
        radial-gradient(at 0% 0%, rgba(59, 130, 246, 0.12) 0px, transparent 50%),
        radial-gradient(at 100% 100%, rgba(6, 182, 212, 0.12) 0px, transparent 50%);
      background-attachment: fixed;
    }

    .container {
      width: 100%;
      max-width: 950px;
    }

    header {
      text-align: center;
      margin-bottom: 1.75rem;
    }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      background: rgba(6, 182, 212, 0.1);
      border: 1px solid rgba(6, 182, 212, 0.25);
      color: var(--accent-cyan);
      font-size: 0.8rem;
      font-weight: 600;
      padding: 0.25rem 0.8rem;
      border-radius: 9999px;
      margin-bottom: 0.75rem;
      box-shadow: 0 0 15px var(--accent-cyan-glow);
    }

    .status-dot {
      width: 8px;
      height: 8px;
      background-color: var(--accent-emerald);
      border-radius: 50%;
      box-shadow: 0 0 8px var(--accent-emerald);
    }

    h1 {
      font-size: 1.85rem;
      font-weight: 800;
      letter-spacing: -0.02em;
      margin-bottom: 0.4rem;
      background: linear-gradient(135deg, #ffffff 30%, var(--accent-cyan) 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }

    p.subtitle {
      color: var(--text-muted);
      font-size: 0.95rem;
      line-height: 1.5;
    }

    .card {
      background: var(--bg-card);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid var(--border-color);
      border-radius: 14px;
      padding: 1.25rem;
      margin-bottom: 1.25rem;
      box-shadow: 0 10px 25px rgba(0, 0, 0, 0.3);
      transition: border-color 0.2s ease;
    }

    .card:hover {
      border-color: rgba(6, 182, 212, 0.3);
    }

    .card-title {
      font-size: 1.1rem;
      font-weight: 700;
      margin-bottom: 0.85rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.6rem;
      color: #fff;
    }

    .card-title-left {
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }

    .card-title .icon {
      font-size: 1.25rem;
    }

    .step-tag {
      font-size: 0.72rem;
      font-weight: 700;
      padding: 0.15rem 0.55rem;
      border-radius: 6px;
      background: rgba(6, 182, 212, 0.15);
      color: var(--accent-cyan);
      border: 1px solid rgba(6, 182, 212, 0.3);
    }

    .step-tag.green {
      background: rgba(16, 185, 129, 0.15);
      color: var(--accent-emerald);
      border-color: rgba(16, 185, 129, 0.3);
    }

    .step-tag.purple {
      background: rgba(168, 85, 247, 0.15);
      color: var(--accent-purple);
      border-color: rgba(168, 85, 247, 0.3);
    }

    .ssh-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
      gap: 1rem;
      margin-bottom: 1.25rem;
    }

    .ssh-grid .card {
      margin-bottom: 0;
    }

    .tab-group {
      display: flex;
      gap: 0.35rem;
      margin-bottom: 0.75rem;
      background: rgba(0, 0, 0, 0.35);
      padding: 0.25rem;
      border-radius: 8px;
      border: 1px solid var(--border-color);
      overflow-x: auto;
    }

    .tab-btn {
      flex: 1;
      background: transparent;
      border: none;
      color: var(--text-muted);
      font-family: inherit;
      font-size: 0.82rem;
      font-weight: 600;
      padding: 0.45rem 0.6rem;
      border-radius: 6px;
      cursor: pointer;
      transition: all 0.2s ease;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 0.35rem;
      white-space: nowrap;
    }

    .tab-btn.active {
      background: rgba(255, 255, 255, 0.12);
      color: #fff;
      box-shadow: 0 2px 6px rgba(0,0,0,0.25);
    }

    .tab-content {
      display: none;
    }

    .tab-content.active {
      display: block;
    }

    .code-box {
      position: relative;
      background: var(--code-bg);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 10px;
      padding: 0.75rem 1rem;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85rem;
      direction: ltr;
      text-align: left;
      color: #38bdf8;
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 0.75rem;
    }

    .code-text {
      white-space: pre-wrap;
      word-break: break-word;
      overflow-wrap: anywhere;
      line-height: 1.55;
      padding-right: 0.5rem;
      flex: 1;
    }

    .copy-btn {
      background: rgba(255, 255, 255, 0.08);
      border: 1px solid rgba(255, 255, 255, 0.12);
      color: #e2e8f0;
      border-radius: 6px;
      padding: 0.35rem 0.75rem;
      font-size: 0.75rem;
      font-family: 'Vazirmatn', sans-serif;
      font-weight: 600;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 0.3rem;
      white-space: nowrap;
      transition: all 0.2s ease;
      flex-shrink: 0;
    }

    .copy-btn:hover {
      background: var(--accent-cyan);
      color: #04101e;
      border-color: var(--accent-cyan);
    }

    .copy-btn.copied {
      background: var(--accent-emerald);
      color: #022415;
      border-color: var(--accent-emerald);
    }

    .cmd-desc {
      color: var(--text-muted);
      font-size: 0.8rem;
      margin-bottom: 0.6rem;
      line-height: 1.4;
    }

    .links-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 0.75rem;
      margin-top: 0.5rem;
    }

    .link-item {
      background: rgba(0, 0, 0, 0.25);
      border: 1px solid var(--border-color);
      border-radius: 8px;
      padding: 0.75rem 0.85rem;
      text-decoration: none;
      color: var(--text-main);
      display: flex;
      flex-direction: column;
      gap: 0.25rem;
      transition: all 0.2s ease;
    }

    .link-item:hover {
      background: var(--bg-card-hover);
      border-color: var(--accent-cyan);
      transform: translateY(-2px);
    }

    .link-item .name {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85rem;
      font-weight: 700;
      color: var(--accent-cyan);
      direction: ltr;
      text-align: left;
    }

    .link-item .desc {
      font-size: 0.75rem;
      color: var(--text-muted);
    }

    .feature-list {
      list-style: none;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 0.75rem;
      margin-top: 0.25rem;
    }

    .feature-item {
      display: flex;
      align-items: flex-start;
      gap: 0.5rem;
      font-size: 0.82rem;
      color: var(--text-muted);
      line-height: 1.4;
    }

    .feature-item strong {
      color: var(--text-main);
    }

    .feature-item .check {
      color: var(--accent-emerald);
      font-size: 1rem;
      line-height: 1;
    }

    footer {
      text-align: center;
      margin-top: 1.5rem;
      color: var(--text-muted);
      font-size: 0.8rem;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="badge">
        <span class="status-dot"></span>
        <span>Cloudflare Worker &amp; KV Online</span>
      </div>
      <h1>همگام‌سازی امن سکرت‌ها، کلیدهای SSH و Chezmoi</h1>
      <p class="subtitle">انتقال رمزنگاری‌شده محلی دایرکتوری‌های ~/.ssh و ~/.config/secrets به همراه آنلاک خودکار Git-Crypt</p>
    </header>

    <!-- SSH & Vault Section -->
    <div class="ssh-grid">
      <!-- Send Vault -->
      <div class="card">
        <div class="card-title">
          <div class="card-title-left">
            <span class="icon">📤</span>
            <span>۱. ارسال و رمزنگاری (دستگاه مبدأ)</span>
          </div>
          <span class="step-tag">Upload</span>
        </div>
        <div class="cmd-desc">در سیستمی که سکرت‌ها و کلیدها روی آن است اجرا کنید (نیازمند توکن):</div>
        <div class="tab-group">
          <button class="tab-btn active" onclick="switchTab(this, 'send-linux')">🐧 Linux / macOS / Termux</button>
          <button class="tab-btn" onclick="switchTab(this, 'send-win')">🪟 Windows (PS)</button>
        </div>
        <div id="send-linux" class="tab-content active">
          <div class="code-box">
            <div class="code-text" id="cmd-send-linux">curl -fsSL "${origin}/send.sh?token=YOUR_TOKEN" | bash</div>
            <button class="copy-btn" onclick="copyCode('cmd-send-linux', this)">کپی</button>
          </div>
        </div>
        <div id="send-win" class="tab-content">
          <div class="code-box">
            <div class="code-text" id="cmd-send-win">irm "${origin}/send.ps1?token=YOUR_TOKEN" | iex</div>
            <button class="copy-btn" onclick="copyCode('cmd-send-win', this)">کپی</button>
          </div>
        </div>
      </div>

      <!-- Get Vault -->
      <div class="card">
        <div class="card-title">
          <div class="card-title-left">
            <span class="icon">📥</span>
            <span>۲. دریافت و رمزگشایی (دستگاه مقصد)</span>
          </div>
          <span class="step-tag green">Restore</span>
        </div>
        <div class="cmd-desc">در سیستم جدید اجرا کرده و پسورد رمزنگاری را وارد کنید (بدون نیاز به توکن):</div>
        <div class="tab-group">
          <button class="tab-btn active" onclick="switchTab(this, 'get-linux')">🐧 Linux / macOS / Termux</button>
          <button class="tab-btn" onclick="switchTab(this, 'get-win')">🪟 Windows (PS)</button>
        </div>
        <div id="get-linux" class="tab-content active">
          <div class="code-box">
            <div class="code-text" id="cmd-get-linux">curl -fsSL ${origin}/get.sh | bash</div>
            <button class="copy-btn" onclick="copyCode('cmd-get-linux', this)">کپی</button>
          </div>
        </div>
        <div id="get-win" class="tab-content">
          <div class="code-box">
            <div class="code-text" id="cmd-get-win">irm ${origin}/get.ps1 | iex</div>
            <button class="copy-btn" onclick="copyCode('cmd-get-win', this)">کپی</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Step 3: Chezmoi Dotfiles Bootstrap by OS -->
    <div class="card">
      <div class="card-title">
        <div class="card-title-left">
          <span class="icon">⚡</span>
          <span>۳. کلون و اعمال مخزن دات‌فایل‌ها (Chezmoi Bootstrap)</span>
        </div>
        <span class="step-tag purple">Dotfiles</span>
      </div>
      <div class="cmd-desc">
        پس از دریافت سکرت‌ها و کلیدها، دستور سیستم‌عامل خود را اجرا کنید تا دات‌فایل‌ها کلون و اعمال شوند:
      </div>

      <div class="tab-group">
        <button class="tab-btn active" onclick="switchTab(this, 'cm-arch')">🏹 Arch Linux</button>
        <button class="tab-btn" onclick="switchTab(this, 'cm-ubuntu')">🐧 Ubuntu / Debian</button>
        <button class="tab-btn" onclick="switchTab(this, 'cm-termux')">📱 Termux</button>
        <button class="tab-btn" onclick="switchTab(this, 'cm-win')">🪟 Windows</button>
      </div>

      <!-- Arch Linux -->
      <div id="cm-arch" class="tab-content active">
        <div class="code-box">
          <div class="code-text" id="cmd-cm-arch">sudo pacman -S --needed --noconfirm chezmoi git openssh &amp;&amp; chezmoi init --apply git@github.com:mehdichamani/dotfiles.git</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-arch', this)">کپی دستور</button>
        </div>
      </div>

      <!-- Ubuntu / Debian -->
      <div id="cm-ubuntu" class="tab-content">
        <div class="code-box">
          <div class="code-text" id="cmd-cm-ubuntu">sudo apt update &amp;&amp; sudo apt install -y git openssh-client &amp;&amp; sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin &amp;&amp; export PATH="$HOME/.local/bin:$PATH" &amp;&amp; chezmoi init --apply git@github.com:mehdichamani/dotfiles.git</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-ubuntu', this)">کپی دستور</button>
        </div>
      </div>

      <!-- Termux -->
      <div id="cm-termux" class="tab-content">
        <div class="code-box">
          <div class="code-text" id="cmd-cm-termux">pkg update -y &amp;&amp; pkg install -y chezmoi git openssh &amp;&amp; chezmoi init --apply git@github.com:mehdichamani/dotfiles.git</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-termux', this)">کپی دستور</button>
        </div>
      </div>

      <!-- Windows -->
      <div id="cm-win" class="tab-content">
        <div class="code-box">
          <div class="code-text" id="cmd-cm-win">winget install Git.Git twpayne.chezmoi -e --accept-source-agreements --accept-package-agreements ; chezmoi init --apply git@github.com:mehdichamani/dotfiles.git</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-win', this)">کپی دستور</button>
        </div>
      </div>
    </div>

    <!-- Direct Script Links -->
    <div class="card">
      <div class="card-title">
        <div class="card-title-left">
          <span class="icon">🔗</span>
          <span>لینک‌های مستقیم اسکریپت‌ها (Direct Endpoints)</span>
        </div>
      </div>
      <div class="links-grid">
        <a href="${origin}/send.sh?token=YOUR_TOKEN" target="_blank" class="link-item">
          <span class="name">/send.sh?token=...</span>
          <span class="desc">اسکریپت بش آپلود (نیازمند توکن)</span>
        </a>
        <a href="${origin}/get.sh" target="_blank" class="link-item">
          <span class="name">/get.sh</span>
          <span class="desc">اسکریپت بش دانلود و آنلاک</span>
        </a>
        <a href="${origin}/send.ps1?token=YOUR_TOKEN" target="_blank" class="link-item">
          <span class="name">/send.ps1?token=...</span>
          <span class="desc">اسکریپت پاورشل آپلود (نیازمند توکن)</span>
        </a>
        <a href="${origin}/get.ps1" target="_blank" class="link-item">
          <span class="name">/get.ps1</span>
          <span class="desc">اسکریپت پاورشل دانلود و آنلاک</span>
        </a>
      </div>
    </div>

    <!-- Security & Architecture -->
    <div class="card">
      <div class="card-title">
        <div class="card-title-left">
          <span class="icon">🛡️</span>
          <span>مکانیزم امنیتی و ویژگی‌ها</span>
        </div>
      </div>
      <ul class="feature-list">
        <li class="feature-item">
          <span class="check">✔</span>
          <div><strong>Zero-Knowledge:</strong> رمزنگاری کلاینت با AES-256 قبل از ارسال به سرور.</div>
        </li>
        <li class="feature-item">
          <span class="check">✔</span>
          <div><strong>پوشش سکرت‌ها و SSH:</strong> همگام‌سازی یکپارچه ~/.ssh و ~/.config/secrets.</div>
        </li>
        <li class="feature-item">
          <span class="check">✔</span>
          <div><strong>Git-Crypt Unlock:</strong> آنلاک خودکار مخزن با chezmoi-git-crypt.key.</div>
        </li>
        <li class="feature-item">
          <span class="check">✔</span>
          <div><strong>Anti-Tampering:</strong> حفاظت از عملیات آپلود با توکن امنیتی SYNC_TOKEN.</div>
        </li>
      </ul>
    </div>

    <footer>
      <span>🔒 Warden Worker &bull; Powered by Cloudflare Workers &amp; KV</span>
    </footer>
  </div>

  <script>
    function switchTab(btn, tabId) {
      const parentCard = btn.closest('.card');
      parentCard.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      parentCard.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById(tabId).classList.add('active');
    }

    function copyCode(elementId, btn) {
      const text = document.getElementById(elementId).innerText;
      navigator.clipboard.writeText(text).then(() => {
        const origText = btn.innerText;
        btn.innerText = 'کپی شد! ✓';
        btn.classList.add('copied');
        setTimeout(() => {
          btn.innerText = origText;
          btn.classList.remove('copied');
        }, 2000);
      });
    }
  </script>
</body>
</html>`;
      return new Response(html, {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }
  },
};
