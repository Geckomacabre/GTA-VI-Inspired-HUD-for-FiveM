import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Host NUI build config: compiles the root UI bundle into html/ for resource distribution
export default defineConfig({
  plugins: [react()],
  base: './', // Use relative paths: ensures FiveM CEF and DUI surfaces load bundled assets correctly
  resolve: {
    alias: {
      // Design SDK alias: resolve host SDK modules locally during host compilation
      '@host': fileURLToPath(new URL('./src/host/index.ts', import.meta.url)),
    },
  },
  build: {
    outDir: '../html',
    emptyOutDir: true,
    assetsDir: 'assets',
    // Target Chromium 91: maintains compatibility with FiveM CEF browser runtime
    target: 'chrome91',
    cssTarget: 'chrome91',
    rollupOptions: {
      output: {
        // Hash output assets: prevents stale browser caching across client restarts
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash].[ext]',
      },
    },
  },
})
