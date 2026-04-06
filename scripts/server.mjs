import http   from 'http'
import fs     from 'fs'
import path   from 'path'
import crypto from 'crypto'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const PORT     = parseInt(process.env.TRACKER_PORT || '1414', 10)
const DATA_DIR = process.env.TRACKER_DATA_DIR || path.join(__dirname, '..', 'nova-data')
const DIST_DIR = process.env.TRACKER_DIST_DIR || path.join(__dirname, '..')

// ── Token generation ──────────────────────────────────────────────────────────
const TOKEN = crypto.randomBytes(32).toString('base64')
console.log('[Nova] Session token generated (ephemeral — changes on each server start)')

// ── Data directory ────────────────────────────────────────────────────────────
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true })
  console.log(`[Nova] Created data directory: ${DATA_DIR}`)
}

// ── Whitelisted key domains (matches Issue Tracker keys) ──────────────────────
const ALLOWED_KEYS = [
  'tracker_issues_v3',
  'tracker_cats_v3',
  'tracker_statuses_v3',
  'tracker_sevs_v1',
  'tracker_effs_v1',
  'tracker_export_destination_v1',
]

// ── Load persisted data from disk into memory ─────────────────────────────────
const data = {}
let loadedCount = 0
for (const key of ALLOWED_KEYS) {
  const filePath = path.join(DATA_DIR, `${key}.json`)
  if (fs.existsSync(filePath)) {
    try   { data[key] = fs.readFileSync(filePath, 'utf8'); loadedCount++ }
    catch { data[key] = null; console.warn(`[Nova] Could not read ${filePath}`) }
  } else {
    data[key] = null
  }
}
console.log(`[Nova] Loaded ${loadedCount} key(s) from ${DATA_DIR}`)

// ── Read and patch index.html dynamically ─────────────────────────────────────
const LOCALHOST_CSP = [
  `default-src 'self'`,
  `script-src 'self' 'unsafe-inline' 'unsafe-eval'`,
  `style-src 'self' 'unsafe-inline'`,
  `font-src 'self' data:`,
  `img-src 'self' data: blob:`,
  `connect-src 'self' https://*`,
  `base-uri 'none'`,
  `form-action 'none'`,
  `object-src 'none'`,
].join('; ')

function getIndexHtml() {
  const indexPath = path.join(DIST_DIR, 'index.html')
  if (!fs.existsSync(indexPath)) return null
  
  let raw = fs.readFileSync(indexPath, 'utf8')
  
  // 1. Inject session token
  const tokenMeta = `<meta name="nova-token" content="${TOKEN}" />`
  raw = raw.replace(/(<head[^>]*>)/, `$1\n  ${tokenMeta}`)
  
  // 2. Patch CSP
  const cspMetaRe = /<meta[^>]+http-equiv\s*=\s*["']Content-Security-Policy["'][^>]*>/i
  const cspMeta   = `<meta http-equiv="Content-Security-Policy" content="${LOCALHOST_CSP}">`
  if (cspMetaRe.test(raw)) {
    raw = raw.replace(cspMetaRe, cspMeta)
  } else {
    raw = raw.replace(/(<head[^>]*>)/i, `$1\n  ${cspMeta}`)
  }
  
  return raw
}
console.log(`[Nova] Serving static files from: ${path.resolve(DIST_DIR)}`)
console.log(`[Nova] CSP: ${LOCALHOST_CSP}`)


// ── MIME type map ─────────────────────────────────────────────────────────────
const MIME = {
  '.html':  'text/html; charset=utf-8',
  '.js':    'application/javascript',
  '.css':   'text/css',
  '.svg':   'image/svg+xml',
  '.png':   'image/png',
  '.ico':   'image/x-icon',
  '.woff2': 'font/woff2',
  '.woff':  'font/woff',
  '.ttf':   'font/ttf',
}

// ── Response helpers ──────────────────────────────────────────────────────────
function sendText(res, status, contentType, body) {
  const buf = Buffer.from(body, 'utf8')
  res.writeHead(status, {
    'Content-Type':                contentType,
    'Content-Length':              buf.length,
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Nova-Token',
    'Cache-Control':               'no-store, no-cache, must-revalidate, proxy-revalidate',
  })
  res.end(buf)
}

function sendJson(res, status, obj) {
  sendText(res, status, 'application/json', JSON.stringify(obj))
}

function sendBytes(res, status, contentType, buf) {
  res.writeHead(status, {
    'Content-Type':                contentType,
    'Content-Length':              buf.length,
    'Access-Control-Allow-Origin': '*',
    'Cache-Control':               'public, max-age=3600',
  })
  res.end(buf)
}

// ── Request handler ───────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  let pathname
  try {
    pathname = new URL(req.url, `http://127.0.0.1`).pathname
  } catch {
    sendText(res, 400, 'text/plain', 'Bad request')
    return
  }

  // ── OPTIONS preflight ──────────────────────────────────────────────────────
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin':  '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-Nova-Token',
      'Access-Control-Max-Age':       '86400',
    })
    res.end()
    return
  }

  // ── Static: root ───────────────────────────────────────────────────────────
  if (pathname === '/' || pathname === '/index.html') {
    const htmlContent = getIndexHtml()
    if (htmlContent) {
      sendText(res, 200, 'text/html; charset=utf-8', htmlContent)
    } else {
      sendText(res, 503, 'text/plain', "index.html not found.")
    }
    return
  }

  // ── Static: assets ─────────────────────────────────────────────────────────
  if (pathname.startsWith('/assets/')) {
    const relative = pathname.slice(1)   // strip leading /
    const full     = path.resolve(DIST_DIR, relative)
    const distRoot = path.resolve(DIST_DIR)

    if (!full.startsWith(distRoot + path.sep) && full !== distRoot) {
      sendText(res, 403, 'text/plain', 'Forbidden')
      return
    }

    if (fs.existsSync(full)) {
      const ext  = path.extname(full).toLowerCase()
      const mime = MIME[ext] || 'application/octet-stream'
      const buf  = fs.readFileSync(full)
      sendBytes(res, 200, mime, buf)
    } else {
      sendText(res, 404, 'text/plain', 'Asset not found')
    }
    return
  }

  // ── API routes ─────────────────────────────────────────────────────────────
  if (pathname.startsWith('/api/')) {
    const reqToken = req.headers['x-nova-token']
    if (reqToken !== TOKEN) {
      console.warn(`[Nova] Unauthorized API request to "${pathname}" (token mismatch)`)
      sendJson(res, 401, { error: 'Unauthorized' })
      return
    }

    const apiKey = pathname.slice(5).replace(/^\/+|\/+$/, '')

    if (apiKey === 'status') {
      sendJson(res, 200, { ok: true })
      return
    }

    if (!ALLOWED_KEYS.includes(apiKey)) {
      sendJson(res, 404, { error: 'Unknown key' })
      return
    }

    if (req.method === 'GET') {
      const val = data[apiKey]
      if (val == null) {
        console.log(`[Nova] GET "${apiKey}" — No data on disk (204)`)
        res.writeHead(204, { 'Access-Control-Allow-Origin': '*' })
        res.end()
      } else {
        console.log(`[Nova] GET "${apiKey}" — Serving ${val.length} bytes`)
        sendText(res, 200, 'application/json', val)
      }
      return
    }

    if (req.method === 'POST') {
      const MAX_BODY_BYTES = 50 * 1024 * 1024
      let body = ''
      let bodyBytes = 0
      let tooLarge = false

      req.on('data', chunk => {
        bodyBytes += chunk.length
        if (bodyBytes > MAX_BODY_BYTES) {
          tooLarge = true
          req.destroy()
          sendJson(res, 413, { error: 'Payload too large (50 MB limit)' })
          return
        }
        body += chunk
      })
      req.on('error', err => {
        if (!tooLarge) {
          console.error(`[Nova] Request read error for "${apiKey}":`, err.message)
          sendJson(res, 500, { error: 'Read error' })
        }
      })
      req.on('end', () => {
        if (tooLarge) return
        if (!body || !body.trim()) {
          sendJson(res, 400, { error: 'Empty body' })
          return
        }
        // Validate JSON before storing
        try   { JSON.parse(body) }
        catch { sendJson(res, 400, { error: 'Invalid JSON' }); return }

        // Store encrypted payload identically
        data[apiKey] = body
        const filePath = path.join(DATA_DIR, `${apiKey}.json`)
        try {
          fs.writeFileSync(filePath, body, 'utf8')
          sendJson(res, 200, { ok: true })
        } catch (err) {
          console.error(`[Nova] Write error for key "${apiKey}":`, err.message)
          sendJson(res, 500, { error: 'Write failed' })
        }
      })
      return
    }

    sendJson(res, 405, { error: 'Method not allowed' })
    return
  }

  sendText(res, 404, 'text/plain', 'Not found')
})

server.on('error', err => {
  if (err.code === 'EADDRINUSE') {
    console.error(`[Nova] Port ${PORT} is already in use. Is another instance running?`)
  } else {
    console.error('[Nova] Server error:', err.message)
  }
  process.exit(1)
})

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[Nova] Listening at http://127.0.0.1:${PORT}/`)
  console.log(`[Nova] Data directory: ${DATA_DIR}`)
  console.log('[Nova] Press Ctrl+C to stop.')
})
