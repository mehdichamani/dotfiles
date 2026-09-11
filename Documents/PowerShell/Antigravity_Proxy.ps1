# 1. Kill any existing instances
Stop-Process -Name "Antigravity IDE" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "antigravity" -Force -ErrorAction SilentlyContinue

# 2. Dynamically fetch system proxy from Windows Registry
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$sysProxy = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue

if ($sysProxy -and $sysProxy.ProxyEnable -eq 1 -and $sysProxy.ProxyServer) {
    $proxyServer = $sysProxy.ProxyServer

    if ($proxyServer -match "http=([^;]+)") {
        $httpProxy = $Matches[1]
    } else {
        $httpProxy = $proxyServer
    }

    if ($proxyServer -match "https=([^;]+)") {
        $httpsProxy = $Matches[1]
    } else {
        $httpsProxy = $httpProxy
    }

    if ($httpProxy -notmatch "^https?://") { $httpProxy = "http://$httpProxy" }
    if ($httpsProxy -notmatch "^https?://") { $httpsProxy = "http://$httpsProxy" }

    $env:HTTP_PROXY  = $httpProxy
    $env:HTTPS_PROXY = $httpsProxy
    $env:http_proxy  = $httpProxy
    $env:https_proxy = $httpsProxy

    if ($sysProxy.ProxyOverride) {
        $bypass = $sysProxy.ProxyOverride -replace '<local>', 'localhost' -replace ';', ','
        $env:no_proxy = $bypass
        $env:NO_PROXY = $bypass
    }
} else {
    Remove-Item env:HTTP_PROXY -ErrorAction SilentlyContinue
    Remove-Item env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item env:http_proxy -ErrorAction SilentlyContinue
    Remove-Item env:https_proxy -ErrorAction SilentlyContinue
    Remove-Item env:no_proxy -ErrorAction SilentlyContinue
    Remove-Item env:NO_PROXY -ErrorAction SilentlyContinue
}

# 3. Launch the IDE in the background and let the script exit
Start-Process -FilePath "$env:LOCALAPPDATA\Programs\Antigravity IDE\bin\antigravity-ide.cmd" -WindowStyle Hidden
