# Nova Launcher — start_nova.ps1
# Starts the combined server in a new window, then opens the browser to http://127.0.0.1:1414.

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot   = Resolve-Path (Join-Path $scriptDir "..")
$serverScript = Join-Path $scriptDir "server.ps1"

$Port = 1515

# ── Start combined server in a new PowerShell window ─────────────────────────
Write-Host "[Nova Launcher] Starting server on port $Port..."
Start-Process powershell -ArgumentList `
    "-NoExit", `
    "-File", "`"$serverScript`"", `
    "-DistDir", "`"$repoRoot`"", `
    "-DataDir", "`"$(Join-Path $scriptDir 'data')`"", `
    "-Port", "$Port"

# ── Give the server a moment to bind, then open the browser ───────────────────
Start-Sleep -Milliseconds 1000
Write-Host "[Nova Launcher] Opening http://127.0.0.1:$Port ..."
Start-Process "http://127.0.0.1:$Port"
