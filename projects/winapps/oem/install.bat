@echo off
title WinApps OEM Setup

fltmc >nul 2>&1 || (
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

echo [INFO] Applying RDP Registry Tweaks...
if exist "%~dp0RDPApps.reg" (
    reg import "%~dp0RDPApps.reg" >nul 2>&1
    echo [SUCCESS] Imported RDPApps.reg
)

echo [INFO] Enabling Remote Desktop in Firewall...
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >nul 2>&1
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "if (Get-Command Enable-NetFirewallRule -ErrorAction SilentlyContinue) { Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' }" >nul 2>&1

echo [SUCCESS] OEM setup completed.
