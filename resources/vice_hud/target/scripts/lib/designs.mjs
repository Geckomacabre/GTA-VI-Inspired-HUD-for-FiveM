import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
export const UI_DIR = resolve(ROOT, 'ui')
export const SOURCE_DIR = resolve(UI_DIR, 'src/designs')
export const PACK_DIR = resolve(ROOT, 'designs')

/** List of default design packs included in public distribution. */
export const FREE_DESIGNS = ['rail']

/** Discover available design source directories containing component and descriptor files. */
export function sourceDesignIds() {
  if (!existsSync(SOURCE_DIR)) return []

  return readdirSync(SOURCE_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== 'shared')
    .filter((entry) => existsSync(resolve(SOURCE_DIR, entry.name, 'index.tsx')))
    .filter((entry) => existsSync(resolve(SOURCE_DIR, entry.name, 'design.lua')))
    .map((entry) => entry.name)
    .sort()
}

/** Discover installed and compiled design pack directories. */
export function builtDesignIds() {
  if (!existsSync(PACK_DIR)) return []

  return readdirSync(PACK_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .filter((entry) => existsSync(resolve(PACK_DIR, entry.name, 'design.js')))
    .filter((entry) => existsSync(resolve(PACK_DIR, entry.name, 'design.lua')))
    .map((entry) => entry.name)
    .sort()
}

/** Parse metadata fields from Lua design descriptor. */
export function readDescriptor(file) {
  const text = readFileSync(file, 'utf8')
  const field = (name) => text.match(new RegExp(`\\b${name}\\s*=\\s*'([^']*)'`))?.[1]

  return {
    id: field('id'),
    label: field('label'),
    version: field('version'),
    sdk: Number(text.match(/\bsdk\s*=\s*(\d+)/)?.[1]),
  }
}

/** Recursively gather all source files for a given design id. */
export function collectSourceFiles(id) {
  const dir = resolve(SOURCE_DIR, id)
  if (!existsSync(dir)) return []

  const results = []
  function scan(currentDir, relativePrefix = '') {
    const entries = readdirSync(currentDir, { withFileTypes: true })
    for (const entry of entries) {
      if (entry.name.startsWith('.') || entry.name.endsWith('.tsbuildinfo')) continue
      const fullPath = resolve(currentDir, entry.name)
      const relPath = relativePrefix ? `${relativePrefix}/${entry.name}` : entry.name
      if (entry.isDirectory()) {
        scan(fullPath, relPath)
      } else if (entry.isFile()) {
        results.push({ relPath, fullPath })
      }
    }
  }

  scan(dir)
  return results
}

/** Resolve location of public osm-target distribution directory. */
export function resolveBasePublicDir() {
  const candidates = [
    process.env.OSM_TARGET_PUBLIC_DIR,
    resolve(ROOT, '../osm-target-public'),
    resolve(ROOT, 'osm-target-public'),
    resolve(ROOT, 'dist/public/osm-target'),
  ].filter(Boolean)

  for (const candidate of candidates) {
    if (existsSync(candidate) && existsSync(resolve(candidate, 'fxmanifest.lua'))) {
      return candidate
    }
  }

  return null
}

/** Recursively gather base resource files for distribution packaging. */
export function collectBaseReleaseFiles(baseDir, { includeUi = false } = {}) {
  const skip = new Set(['.git', '.github', 'node_modules', 'dist'])
  const files = []

  function scan(dir, baseRel = '') {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (skip.has(entry.name) || entry.name.endsWith('.tsbuildinfo') || entry.name.startsWith('.')) continue
      if (!includeUi && (entry.name === 'ui' || entry.name === 'scripts')) continue

      const full = resolve(dir, entry.name)
      const rel = baseRel ? `${baseRel}/${entry.name}` : entry.name

      if (entry.isDirectory()) {
        scan(full, rel)
      } else if (entry.isFile()) {
        files.push({ relPath: rel, fullPath: full })
      }
    }
  }

  scan(baseDir)
  return files
}
