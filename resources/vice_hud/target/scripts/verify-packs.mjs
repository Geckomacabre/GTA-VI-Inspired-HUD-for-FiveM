#!/usr/bin/env node
import { createServer } from 'node:http'
import { createReadStream, existsSync, readFileSync, statSync } from 'node:fs'
import { extname, resolve } from 'node:path'
import { createContext, runInContext } from 'node:vm'
import { PACK_DIR, ROOT, builtDesignIds, readDescriptor } from './lib/designs.mjs'

/**
 * Design pack verification test: validates SDK contract compliance and runtime bundle execution.
 *
 * Usage:
 *   node scripts/verify-packs.mjs
 */

let failures = 0

function check(label, ok, detail = '') {
  console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}`)
  if (!ok) failures += 1
}

/* ── 1. Validate Bundle Contract ────────────────────────────────────────── */

console.log('\ndesign bundles register against the host SDK:')

const ids = builtDesignIds()
if (ids.length === 0) {
  console.error('  no built packs in designs/. Run `npm run build:designs` in ui/.')
  process.exit(1)
}

for (const id of ids) {
  const descriptor = readDescriptor(resolve(PACK_DIR, id, 'design.lua'))
  const registered = []

  // Initialize mock host environment for sandboxed bundle evaluation
  const host = {
    registerDesign: (module) => registered.push(module),
    jsxRuntime: { jsx: () => null, jsxs: () => null, Fragment: Symbol('Fragment') },
  }

  for (const name of [
    'React', 'ReactDOM', 'useState', 'useEffect', 'useRef', 'useMemo', 'useCallback',
    'useLayoutEffect', 'Fragment', 'OptionIcon', 'resolveIcon', 'rgba', 'hexToRgb',
    'IndicatorShape', 'CursorShape', 'LockGlyph', 'ChevronGlyph', 'EASE', 'amp',
    'clampLines', 'disabledStyle', 'duration', 'gate', 'gatedLabel', 'intensity',
    'labelLines', 'labelType', 'readBool', 'readNumber', 'readString', 'showsLock',
  ]) {
    if (!(name in host)) host[name] = () => null
  }

  const sandbox = createContext({ OsmTargetHost: host, window: {}, document: {}, console })

  try {
    runInContext(readFileSync(resolve(PACK_DIR, id, 'design.js'), 'utf8'), sandbox, {
      filename: `designs/${id}/design.js`,
    })
  } catch (error) {
    check(`${id}: bundle evaluates`, false, String(error))
    continue
  }

  const [module] = registered
  check(`${id}: calls registerDesign`, registered.length === 1)
  if (!module) continue

  check(`${id}: id matches its descriptor`, module.id === id && descriptor.id === id,
    `bundle "${module.id}", descriptor "${descriptor.id}"`)
  check(`${id}: SDK matches its descriptor`, module.sdk === descriptor.sdk,
    `bundle ${module.sdk}, descriptor ${descriptor.sdk}`)
  check(`${id}: exports Menu, Indicator and Cursor`,
    ['Menu', 'Indicator', 'Cursor'].every((part) => typeof module[part] === 'function'))
  check(`${id}: descriptor declares a version`, Boolean(descriptor.version), descriptor.version)

  // Validate host global export bindings
  const unknown = [...readFileSync(resolve(PACK_DIR, id, 'design.js'), 'utf8')
    .matchAll(/OsmTargetHost\.([A-Za-z_$][\w$]*)/g)]
    .map((match) => match[1])
    .filter((name) => !(name in host))
  check(`${id}: uses only SDK exports`, unknown.length === 0, [...new Set(unknown)].join(', '))
}

/* ── 2. Validate Relative Asset Paths ───────────────────────────────────── */

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' }

// Static test server for relative URL resolution
const server = createServer((request, response) => {
  const path = decodeURIComponent(new URL(request.url, 'http://x').pathname)
  const file = resolve(ROOT, `.${path}`)

  if (!file.startsWith(ROOT) || !existsSync(file) || !statSync(file).isFile()) {
    response.writeHead(404).end()
    return
  }

  response.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' })
  createReadStream(file).pipe(response)
})

await new Promise((ready) => server.listen(0, '127.0.0.1', ready))
const origin = `http://127.0.0.1:${server.address().port}`

console.log('\nthe page can reach the packs from its own location:')

const page = `${origin}/html/index.html`
check('html/index.html is served', (await fetch(page)).ok)

for (const id of ids) {
  const { version } = readDescriptor(resolve(PACK_DIR, id, 'design.lua'))
  const url = new URL(`../designs/${id}/design.js?v=${version}`, page).href
  const response = await fetch(url)
  check(`${id}: ${url.slice(origin.length)}`, response.ok, response.ok ? '' : `HTTP ${response.status}`)
}

server.close()

console.log(failures === 0 ? '\nall pack checks passed\n' : `\n${failures} check(s) failed\n`)
process.exit(failures === 0 ? 0 : 1)
