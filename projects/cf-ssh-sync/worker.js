/**
 * Cloudflare Worker for Secure SSH Keys & Secrets Vault Sync
 * 
 * Routes:
 *  - GET  /         : Rich Web UI / CLI instructions
 *  - GET  /send.sh  : Bash script to encrypt and upload ~/.ssh and ~/.ssh/secrets (Requires token)
 *  - GET  /get.sh   : Bash script to download, decrypt and restore ~/.ssh and ~/.ssh/secrets
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

if [ ! -d "\$SSH_DIR" ]; then
  echo "Error: \$SSH_DIR does not exist!" >&2
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
mkdir -p "\$TEMP_DIR/ssh"
cp -a "\$SSH_DIR/." "\$TEMP_DIR/ssh/"
echo "✔ Added ~/.ssh (including keys, config and ~/.ssh/secrets)"

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

# Ensure openssl, tar, curl, and gzip/unzip are installed
ensure_deps() {
  local missing=()
  command -v openssl >/dev/null 2>&1 || missing+=("openssl")
  command -v tar >/dev/null 2>&1 || missing+=("tar")
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v gzip >/dev/null 2>&1 || missing+=("gzip")

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
      echo "❌ Please install \${missing[*]} manually and rerun." >&2
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
TEMP_DECRYPTED=$(mktemp)
TEMP_EXTRACT=$(mktemp -d)
trap 'rm -rf "$TEMP_FILE" "$TEMP_DECRYPTED" "$TEMP_EXTRACT"' EXIT

HTTP_CODE=$(curl -s -w "%{http_code}" -o "\$TEMP_FILE" "${origin}/data")

if [ "\$HTTP_CODE" -ne 200 ]; then
  echo "❌ Failed to download vault payload. HTTP status: \$HTTP_CODE (Payload may not have been uploaded yet)" >&2
  rm -rf "\$TEMP_FILE" "\$TEMP_DECRYPTED" "\$TEMP_EXTRACT"
  exit 1
fi

echo "Decrypting vault payload..."
if openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass pass:"\$PASSPHRASE" -in "\$TEMP_FILE" -out "\$TEMP_DECRYPTED" 2>/dev/null; then
  echo "✅ Decryption successful."
else
  echo "❌ Decryption failed! Check your passphrase." >&2
  rm -rf "\$TEMP_FILE" "\$TEMP_DECRYPTED" "\$TEMP_EXTRACT"
  exit 1
fi

echo "Extracting archive contents..."
# Detect format (Gzip Tar, Standard Tar, or Zip)
FIRST_BYTES=$(od -N 2 -t x1 "\$TEMP_DECRYPTED" 2>/dev/null | head -n 1 | awk '{print \$2 \$3}')
if [ "\$FIRST_BYTES" = "1f8b" ]; then
  # Gzip Tar
  tar -xzf "\$TEMP_DECRYPTED" -C "\$TEMP_EXTRACT"
elif [ "\$FIRST_BYTES" = "504b" ]; then
  # Zip archive
  if ! command -v unzip >/dev/null 2>&1; then
    if command -v pkg >/dev/null 2>&1; then pkg install -y unzip; elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm unzip; elif command -v apt-get >/dev/null 2>&1; then sudo apt-get install -y unzip; fi
  fi
  unzip -q "\$TEMP_DECRYPTED" -d "\$TEMP_EXTRACT"
else
  # Plain Tar or fallback
  tar -xf "\$TEMP_DECRYPTED" -C "\$TEMP_EXTRACT" 2>/dev/null || unzip -q "\$TEMP_DECRYPTED" -d "\$TEMP_EXTRACT"
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

# 2. Apply Strict Security Permissions
chmod 700 "\$SSH_DIR" 2>/dev/null || true
find "\$SSH_DIR" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} + 2>/dev/null || true
find "\$SSH_DIR" -type f -name "*.pub" -exec chmod 644 {} + 2>/dev/null || true
[ -f "\$SSH_DIR/config" ] && chmod 600 "\$SSH_DIR/config" 2>/dev/null || true
[ -f "\$SSH_DIR/authorized_keys" ] && chmod 600 "\$SSH_DIR/authorized_keys" 2>/dev/null || true

if [ -d "\$SSH_DIR/secrets" ]; then
  chmod 700 "\$SSH_DIR/secrets" 2>/dev/null || true
  find "\$SSH_DIR/secrets" -type f -exec chmod 600 {} + 2>/dev/null || true
fi
echo "✔ Strict security permissions (700/600) applied."

# 3. Optional fix_permisions.sh execution if present
FIX_PERMS="\$SSH_DIR/fix_permisions.sh"
if [ -f "\$FIX_PERMS" ]; then
  # Strip carriage returns if uploaded from Windows
  tr -d '\r' < "\$FIX_PERMS" > "\$FIX_PERMS.tmp" && mv -f "\$FIX_PERMS.tmp" "\$FIX_PERMS" 2>/dev/null || true
  chmod +x "\$FIX_PERMS"
  bash "\$FIX_PERMS"
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

if (-not (Test-Path $sshDir)) {
    Write-Error "$sshDir does not exist!"
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
    $destSsh = Join-Path $tempFolder "ssh"
    Copy-Item -Path "$sshDir" -Destination $destSsh -Recurse -Force
    Write-Host "✔ Added ~/.ssh contents (including keys, config, and secrets)" -ForegroundColor Green

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
        # Standard OpenSSL-compatible AES-256-CBC PBKDF2 via native PowerShell/.NET
        $tempArchive = $null
        $archiveBytes = $null

        if ($hasTar) {
            Write-Host "Archiving with Windows Tar and native .NET OpenSSL AES-256..." -ForegroundColor Yellow
            $tempArchive = [System.IO.Path]::GetTempFileName()
            & tar -C $tempFolder -czf $tempArchive .
            $archiveBytes = [System.IO.File]::ReadAllBytes($tempArchive)
        } else {
            Write-Host "Archiving with PowerShell Zip and native .NET OpenSSL AES-256..." -ForegroundColor Yellow
            $tempArchive = [System.IO.Path]::GetTempFileName() + ".zip"
            Compress-Archive -Path "$tempFolder\\*" -DestinationPath $tempArchive -Force
            $archiveBytes = [System.IO.File]::ReadAllBytes($tempArchive)
        }

        try {
            # Standard OpenSSL PBKDF2: 8-byte salt, SHA-256, 10000 iterations
            $salt = New-Object byte[](8)
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
            $encrypted = $encryptor.TransformFinalBlock($archiveBytes, 0, $archiveBytes.Length)

            # Standard OpenSSL File Format: [8 bytes 'Salted__'][8 bytes Salt][Ciphertext]
            $magic = [System.Text.Encoding]::ASCII.GetBytes("Salted__")
            $payload = [byte[]]::new(16 + $encrypted.Length)
            [Buffer]::BlockCopy($magic, 0, $payload, 0, 8)
            [Buffer]::BlockCopy($salt, 0, $payload, 8, 8)
            [Buffer]::BlockCopy($encrypted, 0, $payload, 16, $encrypted.Length)

            $headers = @{ "Content-Type" = "application/octet-stream" }
            ${clientToken ? `$headers["X-Sync-Token"] = "${clientToken}"` : ''}

            Invoke-RestMethod -Uri "${origin}/data${tokenQuery}" -Method Post -Body $payload -Headers $headers
            Write-Host "✅ Success! Encrypted vault uploaded." -ForegroundColor Green
        } finally {
            if ($tempArchive) { Remove-Item -Force $tempArchive -ErrorAction SilentlyContinue }
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
        Copy-Item -Path (Join-Path $tempExtract "ssh\*") -Destination $sshDir -Recurse -Force
        Write-Host "✔ Restored ~/.ssh (including keys, config, and secrets)" -ForegroundColor Green
    } else {
        # Legacy format fallback
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
        Copy-Item -Path (Join-Path $tempExtract "*") -Destination $sshDir -Recurse -Force
        Write-Host "✔ Restored ~/.ssh (Legacy format)" -ForegroundColor Green
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
        `[WARDEN VAULT & SYNC SERVICE]
-----------------------------------------------------------------
Zero-Knowledge Encrypted State Transfer Protocol (AES-256-CBC)

DEPLOYMENT INSTRUCTIONS:
------------------------
1. RESTORE VAULT (Target Node - Zero-Knowledge):
   Linux / macOS / Termux : curl -fsSL ${origin}/get.sh | bash
   Windows (PowerShell)   : irm ${origin}/get.ps1 | iex

2. COMMIT & UPLOAD VAULT (Source Node - Requires Token):
   Linux / macOS / Termux : curl -fsSL "${origin}/send.sh?token=YOUR_TOKEN" | bash
   Windows (PowerShell)   : irm "${origin}/send.ps1?token=YOUR_TOKEN" | iex
-----------------------------------------------------------------
`,
        { headers: { 'Content-Type': 'text/plain; charset=utf-8' } }
      );
    }

    if (pathname === '/') {
      const html = `<!DOCTYPE html>
<html lang="en" dir="ltr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>WARDEN // ZERO-KNOWLEDGE VAULT SYNC</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-primary: #05070a;
      --bg-card: rgba(10, 15, 23, 0.95);
      --border-color: #1e293b;
      --border-active: #00ff66;
      --accent-green: #00ff66;
      --accent-green-dim: rgba(0, 255, 102, 0.12);
      --accent-cyan: #00e5ff;
      --accent-amber: #ffb700;
      --text-main: #f1f5f9;
      --text-muted: #64748b;
      --text-secondary: #94a3b8;
      --code-bg: #020408;
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    body {
      background-color: var(--bg-primary);
      color: var(--text-main);
      font-family: 'JetBrains Mono', monospace;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 2.5rem 1rem;
      background-image: 
        linear-gradient(rgba(0, 255, 102, 0.03) 1px, transparent 1px),
        linear-gradient(90deg, rgba(0, 255, 102, 0.03) 1px, transparent 1px);
      background-size: 32px 32px;
      position: relative;
    }

    body::before {
      content: "";
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: radial-gradient(circle at 50% 20%, rgba(0, 229, 255, 0.04) 0%, transparent 60%);
      pointer-events: none;
      z-index: 0;
    }

    .container {
      width: 100%;
      max-width: 960px;
      position: relative;
      z-index: 1;
    }

    header {
      margin-bottom: 2rem;
      border-bottom: 1px solid var(--border-color);
      padding-bottom: 1.5rem;
    }

    .top-meta {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
      margin-bottom: 1rem;
      flex-wrap: wrap;
    }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 0.6rem;
      background: rgba(0, 255, 102, 0.05);
      border: 1px solid rgba(0, 255, 102, 0.3);
      color: var(--accent-green);
      font-size: 0.72rem;
      font-weight: 700;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      padding: 0.3rem 0.75rem;
      border-radius: 2px;
    }

    .status-dot {
      width: 6px;
      height: 6px;
      background-color: var(--accent-green);
      box-shadow: 0 0 8px var(--accent-green);
    }

    .meta-id {
      font-size: 0.72rem;
      color: var(--text-muted);
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }

    h1 {
      font-size: 1.65rem;
      font-weight: 800;
      letter-spacing: -0.01em;
      margin-bottom: 0.4rem;
      color: #ffffff;
      text-transform: uppercase;
    }

    h1 span {
      color: var(--accent-green);
    }

    p.subtitle {
      color: var(--text-secondary);
      font-size: 0.82rem;
      line-height: 1.6;
      letter-spacing: 0.02em;
    }

    .card {
      background: var(--bg-card);
      border: 1px solid var(--border-color);
      border-radius: 2px;
      padding: 1.25rem 1.4rem;
      margin-bottom: 1.25rem;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.6);
      position: relative;
    }

    .card::before {
      content: "";
      position: absolute;
      top: -1px;
      left: 0;
      width: 24px;
      height: 2px;
      background: var(--accent-cyan);
    }

    .card-title {
      font-size: 0.92rem;
      font-weight: 700;
      margin-bottom: 0.9rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.6rem;
      color: #ffffff;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }

    .card-title-left {
      display: flex;
      align-items: center;
      gap: 0.6rem;
    }

    .tag-prefix {
      color: var(--accent-green);
      font-weight: 800;
    }

    .step-tag {
      font-size: 0.68rem;
      font-weight: 700;
      letter-spacing: 0.1em;
      padding: 0.2rem 0.5rem;
      border-radius: 2px;
      background: rgba(0, 229, 255, 0.08);
      color: var(--accent-cyan);
      border: 1px solid rgba(0, 229, 255, 0.3);
      text-transform: uppercase;
    }

    .step-tag.green {
      background: rgba(0, 255, 102, 0.08);
      color: var(--accent-green);
      border-color: rgba(0, 255, 102, 0.3);
    }

    .step-tag.amber {
      background: rgba(255, 183, 0, 0.08);
      color: var(--accent-amber);
      border-color: rgba(255, 183, 0, 0.3);
    }

    .ssh-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
      gap: 1.25rem;
      margin-bottom: 1.25rem;
    }

    .ssh-grid .card {
      margin-bottom: 0;
    }

    .tab-group {
      display: flex;
      gap: 0.3rem;
      margin-bottom: 0.85rem;
      background: #000000;
      padding: 0.25rem;
      border: 1px solid var(--border-color);
      border-radius: 2px;
      overflow-x: auto;
    }

    .tab-btn {
      flex: 1;
      background: transparent;
      border: 1px solid transparent;
      color: var(--text-muted);
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.72rem;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      padding: 0.45rem 0.6rem;
      border-radius: 2px;
      cursor: pointer;
      transition: all 0.15s ease;
      white-space: nowrap;
      text-align: center;
    }

    .tab-btn:hover {
      color: var(--text-main);
    }

    .tab-btn.active {
      background: #111a28;
      color: var(--accent-cyan);
      border-color: #24354d;
    }

    .tab-content {
      display: none;
    }

    .tab-content.active {
      display: block;
    }

    .code-box {
      background: var(--code-bg);
      border: 1px solid #162030;
      border-left: 2px solid var(--accent-cyan);
      border-radius: 2px;
      padding: 0.8rem 1rem;
      font-size: 0.8rem;
      color: #7dd3fc;
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 0.75rem;
    }

    .code-text {
      white-space: pre-wrap;
      word-break: break-word;
      overflow-wrap: anywhere;
      line-height: 1.6;
      flex: 1;
      font-family: 'JetBrains Mono', monospace;
    }

    .copy-btn {
      background: #0b1320;
      border: 1px solid #23354e;
      color: var(--text-secondary);
      border-radius: 2px;
      padding: 0.35rem 0.75rem;
      font-size: 0.68rem;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      cursor: pointer;
      white-space: nowrap;
      transition: all 0.15s ease;
      flex-shrink: 0;
    }

    .copy-btn:hover {
      background: var(--accent-cyan);
      color: #000000;
      border-color: var(--accent-cyan);
    }

    .copy-btn.copied {
      background: var(--accent-green);
      color: #000000;
      border-color: var(--accent-green);
    }

    .cmd-desc {
      color: var(--text-secondary);
      font-size: 0.75rem;
      margin-bottom: 0.75rem;
      line-height: 1.5;
    }

    .terminal-step {
      font-size: 0.78rem;
      line-height: 1.6;
      color: var(--text-secondary);
      margin: 0.9rem 0 0.35rem 0;
    }

    .terminal-step strong {
      color: #ffffff;
      font-weight: 600;
    }

    .terminal-step:first-child {
      margin-top: 0;
    }

    .note-hint {
      font-size: 0.72rem;
      color: var(--text-muted);
      margin: 0.35rem 0 0.75rem 0;
    }

    .note-hint code {
      color: var(--accent-cyan);
      background: rgba(0, 229, 255, 0.06);
      padding: 0.1rem 0.35rem;
      border-radius: 2px;
    }

    .feature-list {
      list-style: none;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 0.85rem;
    }

    .feature-item {
      display: flex;
      align-items: flex-start;
      gap: 0.65rem;
      font-size: 0.76rem;
      color: var(--text-secondary);
      line-height: 1.5;
      background: #020408;
      border: 1px solid #131c2b;
      padding: 0.75rem 0.85rem;
      border-radius: 2px;
    }

    .feature-item strong {
      color: #ffffff;
      display: block;
      margin-bottom: 0.15rem;
      font-size: 0.78rem;
    }

    .bullet {
      color: var(--accent-green);
      font-size: 0.85rem;
      line-height: 1.2;
    }

    footer {
      text-align: center;
      margin-top: 2rem;
      padding-top: 1.25rem;
      border-top: 1px solid var(--border-color);
      color: var(--text-muted);
      font-size: 0.72rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="top-meta">
        <div class="badge">
          <span class="status-dot"></span>
          <span>SERVICE STATUS: OPERATIONAL</span>
        </div>
        <div class="meta-id">PROTOCOL // WARDEN-AES256-KV</div>
      </div>
      <h1>WARDEN // <span>SECURITY VAULT SYNC</span></h1>
      <p class="subtitle">Zero-knowledge local encryption pipeline for ~/.ssh keys and ~/.ssh/secrets vault distribution.</p>
    </header>

    <!-- Transfer Pipeline -->
    <div class="ssh-grid">
      <!-- 01. Commit & Upload -->
      <div class="card">
        <div class="card-title">
          <div class="card-title-left">
            <span class="tag-prefix">[01]</span>
            <span>SOURCE NODE // ENCRYPT &amp; PUSH</span>
          </div>
          <span class="step-tag">UPLOAD</span>
        </div>
        <div class="cmd-desc">Execute on authorized source host containing active keys (Requires SYNC_TOKEN):</div>
        <div class="tab-group">
          <button class="tab-btn active" onclick="switchTab(this, 'send-linux')">LINUX / MACOS / TERMUX</button>
          <button class="tab-btn" onclick="switchTab(this, 'send-win')">WINDOWS (PWSH)</button>
        </div>
        <div id="send-linux" class="tab-content active">
          <div class="code-box">
            <div class="code-text" id="cmd-send-linux">curl -fsSL "${origin}/send.sh?token=YOUR_TOKEN" | bash</div>
            <button class="copy-btn" onclick="copyCode('cmd-send-linux', this)">COPY</button>
          </div>
        </div>
        <div id="send-win" class="tab-content">
          <div class="code-box">
            <div class="code-text" id="cmd-send-win">irm "${origin}/send.ps1?token=YOUR_TOKEN" | iex</div>
            <button class="copy-btn" onclick="copyCode('cmd-send-win', this)">COPY</button>
          </div>
        </div>
      </div>

      <!-- 02. Download & Decrypt -->
      <div class="card">
        <div class="card-title">
          <div class="card-title-left">
            <span class="tag-prefix">[02]</span>
            <span>TARGET NODE // PULL &amp; DECRYPT</span>
          </div>
          <span class="step-tag green">RESTORE</span>
        </div>
        <div class="cmd-desc">Execute on new host and enter passphrase (Zero-Knowledge, No token required):</div>
        <div class="tab-group">
          <button class="tab-btn active" onclick="switchTab(this, 'get-linux')">LINUX / MACOS / TERMUX</button>
          <button class="tab-btn" onclick="switchTab(this, 'get-win')">WINDOWS (PWSH)</button>
        </div>
        <div id="get-linux" class="tab-content active">
          <div class="code-box">
            <div class="code-text" id="cmd-get-linux">curl -fsSL ${origin}/get.sh | bash</div>
            <button class="copy-btn" onclick="copyCode('cmd-get-linux', this)">COPY</button>
          </div>
        </div>
        <div id="get-win" class="tab-content">
          <div class="code-box">
            <div class="code-text" id="cmd-get-win">irm ${origin}/get.ps1 | iex</div>
            <button class="copy-btn" onclick="copyCode('cmd-get-win', this)">COPY</button>
          </div>
        </div>
      </div>
    </div>

    <!-- 03. Environment Provisioning -->
    <div class="card">
      <div class="card-title">
        <div class="card-title-left">
          <span class="tag-prefix">[03]</span>
          <span>HOST BOOTSTRAP // DOTFILES PROVISIONING</span>
        </div>
        <span class="step-tag amber">PROVISION</span>
      </div>
      <div class="cmd-desc">
        Run corresponding initialization steps for host platform after vault restoration:
      </div>

      <div class="tab-group">
        <button class="tab-btn active" onclick="switchTab(this, 'cm-arch')">OMARCHY LINUX</button>
        <button class="tab-btn" onclick="switchTab(this, 'cm-ubuntu')">UBUNTU / DEBIAN</button>
        <button class="tab-btn" onclick="switchTab(this, 'cm-termux')">ANDROID (TERMUX)</button>
        <button class="tab-btn" onclick="switchTab(this, 'cm-win')">WINDOWS</button>
      </div>

      <!-- Omarchy Linux -->
      <div id="cm-arch" class="tab-content active">
        <div class="terminal-step"><strong>1. Initialize Chezmoi and apply base configuration:</strong></div>
        <div class="code-box">
          <div class="code-text" id="cmd-cm-arch-1">sudo pacman -S --needed chezmoi fish && chezmoi init mehdichamani && chezmoi apply</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-arch-1', this)">COPY</button>
        </div>

        <div class="terminal-step"><strong>2. Install core package bundle &amp; Omarchy menu (in fish):</strong></div>
        <div class="code-box">
          <div class="code-text" id="cmd-cm-arch-2">dotsync install && omarchy plugin add https://github.com/filip-spaldon/omarchy-menu.git --enable</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-arch-2', this)">COPY</button>
        </div>

        <div class="terminal-step"><strong>3. Sync encrypted notes and archives from primary device:</strong></div>
        <div class="code-box">
          <div class="code-text" id="cmd-cm-arch-3">sftp s24-home</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-arch-3', this)">COPY</button>
        </div>
        <div class="note-hint">(In SFTP session run: <code>get -r /sdcard/Notes/</code> and <code>get -r /sdcard/insync/</code>)</div>

        <div class="terminal-step"><strong>4. Install network proxy runtime and toolchains:</strong></div>
        <div class="code-box">
          <div class="code-text" id="cmd-cm-arch-4">pinstall https://github.com/patterniha/PattN/ && proxy 10808 && mise install</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-arch-4', this)">COPY</button>
        </div>

        <div class="terminal-step"><strong>5. Install Antigravity IDE and Persian UI language pack:</strong></div>
        <div class="code-box">
          <div class="code-text" id="cmd-cm-arch-5">yay -S antigravity-ide && curl -fsSL https://raw.githubusercontent.com/mehdichamani/PersianAntigravityIDE/main/setup.sh | bash</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-arch-5', this)">COPY</button>
        </div>

        <div class="terminal-step"><strong>6. Enable system services &amp; harden SSH daemon (Port 22456 + UFW):</strong></div>
        <div class="code-box">
          <div class="code-text" id="cmd-cm-arch-6">systemctl --user enable --now syncthing.service && sudo systemctl enable --now docker.service && sudo usermod -aG docker $USER && echo "Port 22456" | sudo tee /etc/ssh/sshd_config.d/port.conf && sudo ufw allow 22456/tcp && sudo systemctl enable --now sshd && sudo systemctl restart sshd</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-arch-6', this)">COPY</button>
        </div>
      </div>

      <!-- Ubuntu / Debian -->
      <div id="cm-ubuntu" class="tab-content">
        <div class="terminal-step"><strong>Ubuntu / Debian Bootstrap Protocol:</strong></div>
        <div class="code-box">
          <div class="code-text" id="cmd-cm-ubuntu">sudo apt update && sudo apt install -y git openssh-client && sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin && export PATH="$HOME/.local/bin:$PATH" && chezmoi init --apply mehdichamani</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-ubuntu', this)">COPY</button>
        </div>
      </div>

      <!-- Termux -->
      <div id="cm-termux" class="tab-content">
        <div class="terminal-step"><strong>Android Termux Bootstrap Protocol:</strong></div>
        <div class="code-box">
          <div class="code-text" id="cmd-cm-termux">pkg update -y && pkg install -y chezmoi git openssh && chezmoi init --apply mehdichamani</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-termux', this)">COPY</button>
        </div>
      </div>

      <!-- Windows -->
      <div id="cm-win" class="tab-content">
        <div class="terminal-step"><strong>Windows PowerShell Bootstrap Protocol:</strong></div>
        <div class="code-box">
          <div class="code-text" id="cmd-cm-win">winget install Git.Git twpayne.chezmoi -e --accept-source-agreements --accept-package-agreements ; chezmoi init --apply mehdichamani</div>
          <button class="copy-btn" onclick="copyCode('cmd-cm-win', this)">COPY</button>
        </div>
      </div>
    </div>

    <!-- Security & Architecture -->
    <div class="card">
      <div class="card-title">
        <div class="card-title-left">
          <span class="tag-prefix">[04]</span>
          <span>SECURITY SPECIFICATIONS &amp; ARCHITECTURE</span>
        </div>
      </div>
      <div class="feature-list">
        <div class="feature-item">
          <span class="bullet">&gt;</span>
          <div>
            <strong>ZERO-KNOWLEDGE ENCRYPTION</strong>
            Client-side AES-256-CBC encryption via OpenSSL/PowerShell prior to cloud transit. Server maintains zero plaintext visibility.
          </div>
        </div>
        <div class="feature-item">
          <span class="bullet">&gt;</span>
          <div>
            <strong>SECRETS VAULT COVERAGE</strong>
            Full synchronization coverage across ~/.ssh private keys and isolated environment vault (~/.ssh/secrets).
          </div>
        </div>
        <div class="feature-item">
          <span class="bullet">&gt;</span>
          <div>
            <strong>ANTI-TAMPERING AUTHORIZATION</strong>
            Mutation and upload vectors strictly gated by Cloudflare Worker secret SYNC_TOKEN token validation.
          </div>
        </div>
      </div>
    </div>

    <footer>
      <span>WARDEN SYNC SYSTEM // POWERED BY CLOUDFLARE WORKERS &amp; KV</span>
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
        btn.innerText = 'COPIED';
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
