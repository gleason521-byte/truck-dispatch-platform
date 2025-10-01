# Simulate API (3000) and Client (5173) servers as background jobs
# Run this script from the repository root: powershell -ExecutionPolicy Bypass -File .\scripts\simulate-servers.ps1

# API simulator
Start-Job -Name "SimAPI" -ScriptBlock {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add('http://localhost:3000/')
    $listener.Start()
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $response = $context.Response
            $body = [System.Text.Encoding]::UTF8.GetBytes('API OK')
            $response.ContentLength64 = $body.Length
            $response.OutputStream.Write($body, 0, $body.Length)
            $response.OutputStream.Close()
        } catch {
            break
        }
    }
}

# Client simulator
Start-Job -Name "SimClient" -ScriptBlock {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add('http://localhost:5173/')
    $listener.Start()
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $response = $context.Response
            $body = [System.Text.Encoding]::UTF8.GetBytes('CLIENT OK')
            $response.ContentLength64 = $body.Length
            $response.OutputStream.Write($body, 0, $body.Length)
            $response.OutputStream.Close()
        } catch {
            break
        }
    }
}

Write-Host "Simulators started as jobs: SimAPI and SimClient"
Write-Host "Use Get-Job to view them and Remove-Job to stop them"
