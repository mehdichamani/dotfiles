@echo off
:: Run the PowerShell script in the background with a hidden window style
powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%~dp0Antigravity_Proxy.ps1"
exit