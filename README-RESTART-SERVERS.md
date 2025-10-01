# Restart servers utility

This repository includes a small PowerShell utility to restart multiple local servers defined in a JSON config.

Files added:
- `scripts/restart-servers.ps1` - PowerShell script with function `Restart-Servers`.
- `servers.json` - Example configuration listing two servers (edit to match your project).

Usage:

1. Edit `servers.json` and set `startCommand` and `cwd` for each server. You can also set `port` and/or `processName` to help the script find and kill existing processes.

2. From PowerShell, run (example):

```powershell
cd C:\Users\Whimsy\Downloads\TRUCK-DISPATCH-PLATFORM\scripts
.\restart-servers.ps1 -ConfigPath "..\servers.json"
# call the exported function
Restart-Servers -Config "..\servers.json"
```

Notes:
- The script uses `Get-NetTCPConnection` on modern Windows to find processes by port; if unavailable it falls back to parsing `netstat -ano`.
- `Start-Process` opens each server in a new PowerShell window so you can see output. Adjust to your preferences if you want background jobs instead.
