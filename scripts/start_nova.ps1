# Nova Launcher — start_nova.ps1
# Starts the combined server in a new window, then opens the browser to http://127.0.0.1:1515.

$scriptDir = $PSScriptRoot
$repoRoot  = Resolve-Path (Join-Path $scriptDir "..")
$serverScript = Join-Path $scriptDir "server.ps1"

$Port = 1515

# Detect which PowerShell to use for the new window (pwsh for PS7, powershell for PS5.1)
$psExe = "pwsh"
if (-not (Get-Command "pwsh" -ErrorAction SilentlyContinue)) { 
    $psExe = "powershell" 
}

Write-Host ("[Nova Launcher] Starting server on port {0}..." -f $Port)
Start-Process $psExe -ArgumentList `
    "-NoExit", `
    "-File", "`"$serverScript`"", `
    "-DistDir", "`"$repoRoot`"", `
    "-DataDir", "`"$(Join-Path $scriptDir '..\nova-data')`"", `
    "-Port", "$Port"

# == Give the server a moment to bind, then open the browser ===================
Start-Sleep -Milliseconds 1200
Write-Host ("[Nova Launcher] Opening http://127.0.0.1:{0} ..." -f $Port)
Start-Process ("http://127.0.0.1:{0}" -f $Port)
