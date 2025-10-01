<#
.SYNOPSIS
  Restart servers defined in a JSON config by killing processes (by port or process name) and starting them with the provided start command.

.DESCRIPTION
  Reads a JSON file (default: ./servers.json) containing an array of server objects:
    - name: friendly name
    - port: local port (optional) used to find and kill existing process
    - processName: process name to kill (optional)
    - startCommand: command to start the server (required)
    - cwd: working directory for the start command (optional, default = script directory)

  The script kills existing processes (prefer Get-NetTCPConnection, fallback to netstat/taskkill) and launches each server in a new PowerShell window.
#>

param(
    [string]$ConfigPath = "./servers.json"
)

function Kill-ProcessByPort {
    param([int]$Port)
    Write-Host "-> Trying to find processes listening on port $Port..."
    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -ErrorAction Stop
        foreach ($c in $conns) {
            if ($c.OwningProcess) {
                Write-Host "   Stopping PID $($c.OwningProcess) (from Get-NetTCPConnection)"
                Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Host "   Get-NetTCPConnection unavailable; falling back to netstat parsing"
        $lines = netstat -ano | Select-String -Pattern ":$Port\s"
        foreach ($line in $lines) {
            $parts = -split $line -ne ''
            $pid = $parts[-1]
            if ($pid -match '^\d+$') {
                Write-Host "   taskkill /PID $pid /F"
                taskkill /PID $pid /F | Out-Null
            }
        }
    }
}

function Kill-ProcessByName {
    param([string]$Name)
    Write-Host "-> Trying to stop processes named '$Name'..."
    try {
        Get-Process -Name $Name -ErrorAction Stop | ForEach-Object {
            Write-Host "   Stopping PID $($_.Id) (Name: $($_.ProcessName))"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "   No running processes found with name '$Name'."
    }
}

function Start-Server {
    param(
        [object]$Server,
        [switch]$DryRun,
        [string]$LogDir = "./logs"
    )

    # If ConvertFrom-Json produced a PSCustomObject, convert to hashtable-like access
    if ($Server -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        $Server | Get-Member -MemberType NoteProperty | ForEach-Object { $h[$_.Name] = $Server.$($_.Name) }
        $Server = $h
    }

    $cwd = if ($Server.cwd) { Resolve-Path $Server.cwd } else { Resolve-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    $cmd = $Server.startCommand
    $name = ($Server.name -replace '[^a-zA-Z0-9\-_.]', '_')

    Write-Host "-> Starting '$($Server.name)' in $cwd with command: $cmd"

    if ($DryRun) {
        Write-Host "   [DryRun] Would run in: $cwd"
        Write-Host "   [DryRun] Command: $cmd"
        return
    }

    # Ensure log directory
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $logFile = Join-Path $LogDir "$name.log"

    # Start a new PowerShell window that runs the command, tees output to a log file, and keeps the window open
    $escapedCmd = $cmd -replace '"','\\"'
    # Build environment variable setup from repo .ENV so child windows inherit important vars (like credentials)
    $envSetup = ""
    try {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $repoRoot = Resolve-Path (Join-Path $scriptDir "..")
        $repoEnv = Join-Path $repoRoot ".ENV"
        if (Test-Path $repoEnv) {
            $lines = Get-Content $repoEnv | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not ($_ -match '^[#`]{1,3}') }
            foreach ($l in $lines) {
                $i = $l.IndexOf('=')
                if ($i -gt 0) {
                    $k = $l.Substring(0, $i).Trim()
                    $v = $l.Substring($i + 1).Trim()
                    # escape single quotes in value for safe single-quoted PowerShell literal
                    $vEsc = $v -replace "'","''"
                    $envSetup += "`$env:$k = '$vEsc'; "
                }
            }
        }
    } catch {
        # ignore env parse errors
    }

    # Use Out-File with -Append to keep logs and print to console via -NoExit
    $psCommand = "cd '$cwd'; $envSetup & { $escapedCmd } 2>&1 | Tee-Object -FilePath '$logFile'"
    $arguments = "-NoExit -Command $psCommand"

    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WorkingDirectory $cwd
    Write-Host "   Logs: $logFile"
}

function Restart-Servers {
    param(
        [string]$Config = $ConfigPath,
        [switch]$DryRun,
        [string]$LogDir = "./logs"
    )

    if (-Not (Test-Path $Config)) {
        Throw "Config file not found: $Config"
    }

    $json = Get-Content $Config -Raw | ConvertFrom-Json
    if (-Not $json) { Throw "Unable to parse JSON from $Config" }

    # Ensure logs directory when not dry-run
    if (-not $DryRun -and -not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

    foreach ($s in $json) {
        Write-Host "\n=== Restarting: $($s.name) ==="
        if ($s.port) { Kill-ProcessByPort -Port $s.port }
        if ($s.processName) { Kill-ProcessByName -Name $s.processName }
        Start-Server -Server $s -DryRun:$DryRun -LogDir $LogDir
    }
}

# If the script is executed directly, do not auto-run; user should call Restart-Servers with their config.

function Enable-GPT5Mini {
    param(
        [Parameter(Mandatory=$false)][object]$Enable = $true,
        [string]$EnvFile = "./.ENV",
        [string[]]$ServerDirs = @("./api", "./client"),
        [switch]$NoRestart,
        [switch]$DryRun
    )

    # Convert common string values to boolean safely
    try {
        $enableBool = [System.Management.Automation.LanguagePrimitives]::ConvertTo($Enable, [bool])
    } catch {
        $s = [string]$Enable
        if ($s -match '^(1|true|yes|y)$') { $enableBool = $true } else { $enableBool = $false }
    }

    $value = if ($enableBool) { 'true' } else { 'false' }

    Write-Host "-> Setting ENABLE_GPT5_MINI=$value in $EnvFile"

    # Ensure repo-level env file exists and update/append the key
    if (Test-Path $EnvFile) {
        $lines = Get-Content $EnvFile
        $found = $false
        $newLines = $lines | ForEach-Object {
            if ($_ -match '^[\s]*ENABLE_GPT5_MINI\s*=') { $found = $true; "ENABLE_GPT5_MINI=$value" } else { $_ }
        }
        if (-not $found) { $newLines += "ENABLE_GPT5_MINI=$value" }
        $newLines | Set-Content $EnvFile
    } else {
        Write-Host "   $EnvFile not found; creating and writing ENABLE_GPT5_MINI=$value"
        "ENABLE_GPT5_MINI=$value" | Set-Content $EnvFile
    }

    # Update per-server env files when present
    foreach ($d in $ServerDirs) {
        $serverEnv = Join-Path $d ".env"
        if (Test-Path $serverEnv) {
            Write-Host "-> Updating $serverEnv"
            $lines = Get-Content $serverEnv
            $found = $false
            $newLines = $lines | ForEach-Object {
                if ($_ -match '^[\s]*ENABLE_GPT5_MINI\s*=') { $found = $true; "ENABLE_GPT5_MINI=$value" } else { $_ }
            }
            if (-not $found) { $newLines += "ENABLE_GPT5_MINI=$value" }
            $newLines | Set-Content $serverEnv
        } else {
            Write-Host "-> $serverEnv not found; creating with ENABLE_GPT5_MINI=$value"
            # Create parent dir if necessary
            $parent = Split-Path -Parent $serverEnv
            if (-not (Test-Path $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
            "ENABLE_GPT5_MINI=$value" | Set-Content $serverEnv
        }
    }

    if ($NoRestart) {
        Write-Host "-> NoRestart specified; skipping server restart."
    } else {
        Write-Host "-> Restarting servers to pick up changes..."
        Restart-Servers -Config $ConfigPath -DryRun:$DryRun
    }
}
