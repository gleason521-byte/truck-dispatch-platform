<#
Start-and-test.ps1

Starts API and Client servers with repository .ENV variables injected (so GOOGLE_APPLICATION_CREDENTIALS is available),
teeing output to logs, then runs basic smoke tests against /health and /firebase (API) and client root.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\start-and-test.ps1
#>

param(
    [int]$WaitSeconds = 3
)

$root = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$envFile = Join-Path $root ".ENV"

function Read-EnvFile($path) {
    $dict = @{}
    if (-not (Test-Path $path)) { return $dict }
    Get-Content $path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        if ($line -match '^[#`]{1,3}') { return }
        $i = $line.IndexOf('=')
        if ($i -gt 0) {
            $k = $line.Substring(0,$i).Trim()
            $v = $line.Substring($i+1).Trim()
            $dict[$k] = $v
        }
    }
    return $dict
}

$envVars = Read-EnvFile $envFile
if ($envVars.Count -gt 0) {
    Write-Host ("Loaded env vars from $($envFile)`n") -ForegroundColor Cyan
    $envVars.GetEnumerator() | ForEach-Object { Write-Host " $($_.Key) = $($_.Value)" }
} else {
    Write-Host "No .ENV file found at $envFile" -ForegroundColor Yellow
}

# Kill processes listening on ports if present
function Kill-ByPorts([int[]]$ports) {
    foreach ($p in $ports) {
        try {
            $conns = Get-NetTCPConnection -LocalPort $p -ErrorAction Stop
            foreach ($c in $conns) {
                if ($c.OwningProcess) {
                    Write-Host "Killing PID $($c.OwningProcess) (port $p)"
                    Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            # no listeners or Get-NetTCPConnection unavailable
        }
    }
}

Kill-ByPorts -ports 3000,5173

$apiCwd = Join-Path $root 'api'
$clientCwd = Join-Path $root 'client'
$logsDir = Join-Path $root 'logs'
if (-not (Test-Path $logsDir)) { New-Item -Path $logsDir -ItemType Directory -Force | Out-Null }
$apiLog = Join-Path $logsDir 'API_Server.log'
$clientLog = Join-Path $logsDir 'Client_Server.log'

# Build environment injection string for PowerShell child process
$envSetup = ""
foreach ($k in $envVars.Keys) {
    $v = $envVars[$k] -replace "'","''"
    $envSetup += "`$env:$k = '$v'; "
}

# Commands to run in new windows
$apiCmd = "$envSetup Set-Location '$apiCwd'; node index.js 2>&1 | Tee-Object -FilePath '$apiLog'"
$clientCmd = "Set-Location '$clientCwd'; node index.js 2>&1 | Tee-Object -FilePath '$clientLog'"

Write-Host "Starting API in new PowerShell window (logs -> $apiLog)" -ForegroundColor Green
Start-Process powershell -ArgumentList '-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-Command',$apiCmd -WorkingDirectory $apiCwd

Start-Sleep -Milliseconds 300
Write-Host "Starting Client in new PowerShell window (logs -> $clientLog)" -ForegroundColor Green
Start-Process powershell -ArgumentList '-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-Command',$clientCmd -WorkingDirectory $clientCwd

Write-Host "Waiting $WaitSeconds seconds for servers to start..." -ForegroundColor Cyan
Start-Sleep -Seconds $WaitSeconds

function Try-Get($url) {
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
        return @{ ok = $true; status = $r.StatusCode; body = $r.Content }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

$results = @{}
$results['api_health'] = Try-Get 'http://localhost:3000/health'
$results['api_firebase'] = Try-Get 'http://localhost:3000/firebase'
$results['client_root'] = Try-Get 'http://localhost:5173/'

Write-Host "\nSmoke test results:" -ForegroundColor Magenta
foreach ($k in $results.Keys) {
    $v = $results[$k]
    if ($v.ok) {
        Write-Host " $k -> HTTP $($v.status)" -ForegroundColor Green
        $body = $v.body
        if ($body.Length -gt 400) { $body = $body.Substring(0,400) + '...(truncated)' }
        Write-Host "   $body`n"
    } else {
        Write-Host " $k -> FAILED: $($v.error)" -ForegroundColor Red
    }
}

Write-Host "Logs written to: $apiLog and $clientLog" -ForegroundColor Cyan
Write-Host "If something failed, open the log files to inspect startup output." -ForegroundColor Yellow
