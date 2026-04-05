# =============================================================================
param (
    [int]    $Port    = 1515,
    [string] $DataDir = ".\data",
    [string] $DistDir = "..\"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($DistDir -eq "..\") {
    $DistDir = Resolve-Path (Join-Path $scriptDir "..")
}
if ($DataDir -eq ".\data") {
    $DataDir = Join-Path $scriptDir "data"
}

# ── Token generation ──────────────────────────────────────────────────────────
$tokenBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
$Token      = [Convert]::ToBase64String($tokenBytes)
Write-Host "[Nova] Session token generated (ephemeral — changes on each server start)"

# ── Data directory ────────────────────────────────────────────────────────────
if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir | Out-Null
    Write-Host "[Nova] Created data directory: $DataDir"
}

# ── Whitelisted key domains ───────────────────────────────────────────────────
$AllowedKeys = @(
  'tracker_issues_v3',
  'tracker_cats_v3',
  'tracker_statuses_v3',
  'tracker_sevs_v1',
  'tracker_effs_v1',
  'tracker_export_destination_v1'
)

# ── Load persisted data from disk into memory ─────────────────────────────────
$Data = @{}
foreach ($key in $AllowedKeys) {
    $filePath = Join-Path $DataDir "$key.json"
    if (Test-Path $filePath) {
        try   { $Data[$key] = Get-Content $filePath -Raw -Encoding UTF8 }
        catch { $Data[$key] = $null; Write-Warning "[Nova] Could not read $filePath" }
    } else {
        $Data[$key] = $null
    }
}
Write-Host "[Nova] Loaded $(($Data.Values | Where-Object { $null -ne $_ }).Count) key(s) from $DataDir"

$LocalhostCsp = "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data: blob:; connect-src 'self' https://*; base-uri 'none'; form-action 'none'; object-src 'none'"

Write-Host "[Nova] Serving static files from: $(Resolve-Path $DistDir)"
Write-Host "[Nova] CSP: $LocalhostCsp"

function Get-IndexHtml {
    $indexPath = Join-Path $DistDir "index.html"
    if (-not (Test-Path $indexPath)) {
        return $null
    }
    
    $raw = Get-Content $indexPath -Raw -Encoding UTF8
    $metaTag = '<meta name="nova-token" content="' + $Token + '" />'
    $raw = $raw -replace '(<head[^>]*>)', "`$1`n  $metaTag"

    $cspMeta = '<meta http-equiv="Content-Security-Policy" content="' + $LocalhostCsp + '">'
    $cspPattern = '<meta[^>]+http-equiv\s*=\s*[''"]Content-Security-Policy[''"][^>]*>'
    if ($raw -match $cspPattern) {
        $raw = $raw -replace $cspPattern, $cspMeta
    } else {
        $raw = $raw -replace '(<head[^>]*>)', "`$1`n  $cspMeta"
    }

    return $raw
}

$MimeTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript'
    '.css'  = 'text/css'
    '.svg'  = 'image/svg+xml'
    '.png'  = 'image/png'
    '.ico'  = 'image/x-icon'
    '.woff2'= 'font/woff2'
    '.woff' = 'font/woff'
    '.ttf'  = 'font/ttf'
}

function Send-Text {
    param($res, [int]$status = 200, [string]$contentType = 'text/plain', [string]$body = '')
    $res.StatusCode  = $status
    $res.ContentType = $contentType
    
    # ── CORS & Cache Headers ──
    $res.AddHeader("Access-Control-Allow-Origin", "*")
    $res.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $res.AddHeader("Access-Control-Allow-Headers", "Content-Type, X-Nova-Token")
    $res.AddHeader("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate")
    
    $bytes           = [System.Text.Encoding]::UTF8.GetBytes($body)
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
}

function Send-Bytes {
    param($res, [int]$status = 200, [string]$contentType = 'application/octet-stream', [byte[]]$bytes)
    $res.StatusCode  = $status
    $res.ContentType = $contentType
    
    # ── CORS & Cache Headers (Static Assets) ──
    $res.AddHeader("Access-Control-Allow-Origin", "*")
    $res.AddHeader("Cache-Control", "public, max-age=3600")

    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")

try {
    $listener.Start()
} catch {
    Write-Error "[Nova] Could not bind to http://127.0.0.1:$Port/ — is another process using this port?"
    exit 1
}

Write-Host "[Nova] Listening at http://127.0.0.1:$Port/"
Write-Host "[Nova] Press Ctrl+C to stop."

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
    } catch {
        if ($listener.IsListening) { Write-Warning "[Nova] Listener error: $_" }
        continue
    }

    $req  = $ctx.Request
    $res  = $ctx.Response
    $path = $req.Url.AbsolutePath

    try {
        if ($req.HttpMethod -eq 'OPTIONS') {
            $res.StatusCode = 204
            $res.AddHeader("Access-Control-Allow-Origin", "*")
            $res.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            $res.AddHeader("Access-Control-Allow-Headers", "Content-Type, X-Nova-Token")
            $res.AddHeader("Access-Control-Max-Age", "86400")
            $res.OutputStream.Close()
            continue
        }

        if ($path -eq '/' -or $path -eq '/index.html') {
            $htmlContent = Get-IndexHtml
            if ($null -ne $htmlContent) {
                Send-Text $res 200 'text/html; charset=utf-8' $htmlContent
            } else {
                Send-Text $res 503 'text/plain' 'index.html not found'
            }
            continue
        }

        if ($path.StartsWith('/assets/')) {
            $relative  = $path.TrimStart('/')
            $full      = Join-Path $DistDir $relative
            if (Test-Path $full -PathType Leaf) {
                $ext   = [System.IO.Path]::GetExtension($full).ToLower()
                $mime  = if ($MimeTypes.ContainsKey($ext)) { $MimeTypes[$ext] } else { 'application/octet-stream' }
                $bytes = [System.IO.File]::ReadAllBytes($full)
                Send-Bytes $res 200 $mime $bytes
            } else {
                Send-Text $res 404 'text/plain' 'Asset not found'
            }
            continue
        }

        if ($path.StartsWith('/api/')) {
            $reqToken = $req.Headers['X-Nova-Token']
            if ($reqToken -ne $Token) {
                Write-Warning "[Nova] Unauthorized API request to '$path' (token mismatch)"
                Send-Text $res 401 'application/json' '{"error":"Unauthorized"}'
                continue
            }

            $apiKey = $path.Substring(5).Trim('/')

            if ($apiKey -eq 'status') {
                Send-Text $res 200 'application/json' '{"ok":true}'
                continue
            }

            if ($AllowedKeys -notcontains $apiKey) {
                Send-Text $res 404 'application/json' '{"error":"Unknown key"}'
                continue
            }

            if ($req.HttpMethod -eq 'GET') {
                $val = $Data[$apiKey]
                if ($null -eq $val) {
                    Write-Host "[Nova] GET '$apiKey' — No data on disk (204)"
                    $res.StatusCode = 204
                    $res.AddHeader("Access-Control-Allow-Origin", "*")
                    $res.OutputStream.Close()
                } else {
                    Write-Host "[Nova] GET '$apiKey' — Serving $($val.Length) bytes"
                    Send-Text $res 200 'application/json' $val
                }

            } elseif ($req.HttpMethod -eq 'POST') {
                try {
                    $MaxBodyBytes = 50 * 1024 * 1024
                    if ($req.ContentLength64 -gt $MaxBodyBytes) {
                        Send-Text $res 413 'application/json' '{"error":"Payload too large (50 MB limit)"}'
                        continue
                    }

                    $reader   = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                    $body     = $reader.ReadToEnd()
                    $reader.Dispose()

                    if (-not $body -or $body.Trim() -eq '') {
                        Send-Text $res 400 'application/json' '{"error":"Empty body"}'
                        continue
                    }
                    try { $null = $body | ConvertFrom-Json -ErrorAction Stop } catch {
                        Send-Text $res 400 'application/json' '{"error":"Invalid JSON"}'
                        continue
                    }

                    $Data[$apiKey] = $body
                    $filePath      = Join-Path $DataDir "$apiKey.json"
                    Set-Content -Path $filePath -Value $body -Encoding UTF8 -NoNewline
                    Write-Host "[Nova] POST '$apiKey' — Saved $($body.Length) bytes"
                    Send-Text $res 200 'application/json' '{"ok":true}'
                } catch {
                    Write-Warning "[Nova] POST write error for key '$apiKey': $_"
                    Send-Text $res 500 'application/json' '{"error":"Write failed"}'
                }
            } else {
                Send-Text $res 405 'application/json' '{"error":"Method not allowed"}'
            }

            continue
        }

        Send-Text $res 404 'text/plain' 'Not found'

    } catch {
        Write-Warning "[Nova] Request handling error: $_"
        try { $res.StatusCode = 500; $res.OutputStream.Close() } catch {}
    }
}
