# =============================================================================
# Nova Local Implementation (PS 5.1 & PS 7+ Compatible)
# =============================================================================
param (
    [int]    $Port    = 1515,
    [string] $DataDir = "..\nova-data",
    [string] $DistDir = "..\"
)

# HELPER: Ensure paths are absolute and resolved for .NET methods
function Get-ResolvedPath($Path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($DistDir -eq "..\" ) {
    $resolvedRoot = Resolve-Path (Join-Path $scriptDir "..")
    $DistDir = Get-ResolvedPath $resolvedRoot.Path
} else {
    $DistDir = Get-ResolvedPath $DistDir
}

if ($DataDir -eq "..\nova-data" ) {
    $DataDir = Get-ResolvedPath (Join-Path $scriptDir "..\nova-data")
} else {
    $DataDir = Get-ResolvedPath $DataDir
}

# ── Token generation ──────────────────────────────────────────────────────────
$tokenBytes = New-Object byte[] 32
$rng        = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($tokenBytes)
$Token      = [Convert]::ToBase64String($tokenBytes)
Write-Host "[Nova] Session token generated (ephemeral — changes on each server start)"

# ── Data directory ────────────────────────────────────────────────────────────
if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir | Out-Null
    Write-Host ("[Nova] Created data directory: {0}" -f $DataDir)
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
    $filePath = Join-Path $DataDir ("{0}.json" -f $key)
    if (Test-Path $filePath) {
        try { 
            $absolutePath = Get-ResolvedPath $filePath
            $Data[$key] = [System.IO.File]::ReadAllText($absolutePath, [System.Text.Encoding]::UTF8)
        } catch { 
            $Data[$key] = $null
            Write-Warning ("[Nova] Could not read {0}: {1}" -f $filePath, $_)
        }
    } else {
        $Data[$key] = $null
    }
}
Write-Host ("[Nova] Loaded {0} key(s) from {1}" -f (@($Data.Values | Where-Object { $null -ne $_ }).Count), $DataDir)

$LocalhostCsp = "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data: blob:; connect-src 'self' https://*; base-uri 'none'; form-action 'none'; object-src 'none'"

Write-Host ("[Nova] Serving static files from: {0}" -f $DistDir)
Write-Host ("[Nova] CSP: {0}" -f $LocalhostCsp)

# ── Safe HTML Patching ───────────────────────────────────────────────────────
function Get-IndexHtml {
    $indexPath = Join-Path $DistDir "index.html"
    if (-not (Test-Path $indexPath)) {
        return $null
    }
    
    $absolutePath = Get-ResolvedPath $indexPath
    $raw = [System.IO.File]::ReadAllText($absolutePath, [System.Text.Encoding]::UTF8)
    
    # Split the file at the first <script tag to avoid corrupting minified bundles
    $parts = $raw -split "(<script)", 2
    
    # parts[0] is the pre-script (header stuff)
    # parts[1] is "<script"
    # parts[2] is the rest (the code)
    
    if ($parts.Count -lt 3) {
        # No script tags found, patch as usual
        $header = $raw
        $footer = ""
    } else {
        $header = $parts[0]
        $footer = $parts[1] + $parts[2]
    }

    $metaTag = ("`n  <meta name=""nova-token"" content=""{0}"" />" -f $Token)
    $header = $header -replace '(<head[^>]*>)', ("`$1{0}" -f $metaTag)

    $cspMeta = ("`n  <meta http-equiv=""Content-Security-Policy"" content=""{0}"">" -f $LocalhostCsp)
    $cspPattern = '<meta[^>]+http-equiv\s*=\s*[''"]Content-Security-Policy[''"][^>]*>'
    
    if ($header -match $cspPattern) {
        $header = $header -replace $cspPattern, $cspMeta
    } else {
        $header = $header -replace '(<head[^>]*>)', ("`$1{0}" -f $cspMeta)
    }

    return $header + $footer
}

$MimeTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.svg'  = 'image/svg+xml; charset=utf-8'
    '.png'  = 'image/png'
    '.ico'  = 'image/x-icon'
    '.woff2'= 'font/woff2'
    '.woff' = 'font/woff'
    '.ttf'  = 'font/ttf'
}

function Write-RequestLog($res, [int]$status = 200, [string]$contentType = 'text/plain; charset=utf-8', [string]$body = '') {
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

function Write-ByteResponse($res, [int]$status = 200, [string]$contentType = 'application/octet-stream', [byte[]]$bytes) {
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
$listener.Prefixes.Add(("http://127.0.0.1:{0}/" -f $Port))

try {
    $listener.Start()
} catch {
    Write-Error ("[Nova] Could not bind to http://127.0.0.1:{0}/ — is another process using this port?" -f $Port)
    exit 1
}

Write-Host ("[Nova] Listening at http://127.0.0.1:{0}/" -f $Port)
Write-Host "[Nova] Press Ctrl+C to stop."

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
    } catch {
        if ($listener.IsListening) { Write-Warning ("[Nova] Listener error: {0}" -f $_) }
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
                Write-RequestLog $res 200 'text/html; charset=utf-8' $htmlContent
            } else {
                Write-RequestLog $res 503 'text/plain; charset=utf-8' 'index.html not found'
            }
            continue
        }

        if ($path.StartsWith('/assets/')) {
            $relative  = $path.TrimStart('/')
            $full      = Join-Path $DistDir $relative
            if (Test-Path $full -PathType Leaf) {
                $ext   = [System.IO.Path]::GetExtension($full).ToLower()
                $mime  = if ($MimeTypes.ContainsKey($ext)) { $MimeTypes[$ext] } else { 'application/octet-stream' }
                $bytes = [System.IO.File]::ReadAllBytes((Get-ResolvedPath $full))
                Write-ByteResponse $res 200 $mime $bytes
            } else {
                Write-RequestLog $res 404 'text/plain; charset=utf-8' 'Asset not found'
            }
            continue
        }

        if ($path.StartsWith('/api/')) {
            $reqToken = $req.Headers['X-Nova-Token']
            if ($reqToken -ne $Token) {
                Write-Warning ("[Nova] Unauthorized API request to '{0}' (token mismatch)" -f $path)
                Write-RequestLog $res 401 'application/json; charset=utf-8' '{"error":"Unauthorized"}'
                continue
            }

            $apiKey = $path.Substring(5).Trim('/')

            if ($apiKey -eq 'status') {
                Write-RequestLog $res 200 'application/json; charset=utf-8' '{"ok":true}'
                continue
            }

            if ($AllowedKeys -notcontains $apiKey) {
                Write-RequestLog $res 404 'application/json; charset=utf-8' '{"error":"Unknown key"}'
                continue
            }

            if ($req.HttpMethod -eq 'GET') {
                $val = $Data[$apiKey]
                if ($null -eq $val) {
                    Write-Host ("[Nova] GET '{0}' — No data on disk (204)" -f $apiKey)
                    $res.StatusCode = 204
                    $res.AddHeader("Access-Control-Allow-Origin", "*")
                    $res.OutputStream.Close()
                } else {
                    Write-Host ("[Nova] GET '{0}' — Serving {1} bytes" -f $apiKey, $val.Length)
                    Write-RequestLog $res 200 'application/json; charset=utf-8' $val
                }

            } elseif ($req.HttpMethod -eq 'POST') {
                try {
                    # No BOM check (PS 5.1 friendly)
                    $reader   = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                    $body     = $reader.ReadToEnd()
                    $reader.Dispose()

                    if (-not $body -or $body.Trim() -eq '') {
                        Write-RequestLog $res 400 'application/json; charset=utf-8' '{"error":"Empty body"}'
                        continue
                    }
                    try { $null = $body | ConvertFrom-Json -ErrorAction Stop } catch {
                        Write-RequestLog $res 400 'application/json; charset=utf-8' '{"error":"Invalid JSON"}'
                        continue
                    }

                    $Data[$apiKey] = $body
                    $filePath      = Join-Path $DataDir ("{0}.json" -f $apiKey)
                    
                    # Store as UTF-8 without BOM (.NET method is cross-platform safe)
                    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                    [System.IO.File]::WriteAllText((Get-ResolvedPath $filePath), $body, $utf8NoBom)
                    
                    Write-Host ("[Nova] POST '{0}' - Saved {1} bytes" -f $apiKey, $body.Length)
                    Write-RequestLog $res 200 'application/json; charset=utf-8' '{"ok":true}'
                } catch {
                    Write-Warning ("[Nova] POST write error for key '{0}': {1}" -f $apiKey, $_)
                    Write-RequestLog $res 500 'application/json; charset=utf-8' '{"error":"Write failed"}'
                }
            } else {
                Write-RequestLog $res 405 'application/json; charset=utf-8' '{"error":"Method not allowed"}'
            }
            continue
        }

        Write-RequestLog $res 404 'text/plain; charset=utf-8' 'Not found'

    } catch {
        Write-Warning ("[Nova] Request handling error: {0}" -f $_)
        try { $res.StatusCode = 500; $res.OutputStream.Close() } catch {}
    }
}
