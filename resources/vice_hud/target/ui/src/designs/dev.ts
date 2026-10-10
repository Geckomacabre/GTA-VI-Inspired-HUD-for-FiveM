/**
 * Development design loader: dynamically imports design sources during local Vite development.
 */

const SOURCES = import.meta.glob('./*/index.tsx')

/** Load design source: evaluates local index.tsx module to register design. */
export async function loadFromSource(id: string): Promise<void> {
  const loader = SOURCES[`./${id}/index.tsx`]
  if (!loader) throw new Error(`no source for design "${id}" in ui/src/designs/`)
  await loader()
}
