$ErrorActionPreference="SilentlyContinue"
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Elite AI Bridge"
$DesktopLink = Join-Path ([Environment]::GetFolderPath("Desktop")) "Elite AI Bridge.lnk"

Write-Host "Elite AI Bridge Uninstaller"
Write-Host "Program files will be removed. Your settings and mappings in %LOCALAPPDATA%\EliteAIBridge will be preserved."
$answer = Read-Host "Continue? [Y/N]"
if ($answer -notmatch '^[Yy]') { exit 0 }

Remove-Item $DesktopLink -Force
Remove-Item $StartMenu -Recurse -Force

# Run deletion from a detached PowerShell after this script exits.
$escaped = $InstallRoot.Replace("'","''")
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -Command `"Start-Sleep 2; Remove-Item -LiteralPath '$escaped' -Recurse -Force`""
Write-Host "Elite AI Bridge has been uninstalled. User data was preserved."
Start-Sleep 2
