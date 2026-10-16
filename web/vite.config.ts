import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';

// Two pages out of one project.
//
//   ui.html     the resource's ui_page: the prompt over the game while placing or looking at tape,
//               the style picker and the Tape Studio.
//   atlas.html  never seen by anyone. A DUI loads it and the game draws every tape from its one
//               canvas (client/tape/atlas.lua).
//
// Unhashed file names so the fxmanifest's files{} globs stay stable; relative paths so both pages
// resolve under https://cfx-nui-sd-policetape/web/build/. target chrome103 is FiveM's Chromium.
export default defineConfig({
  plugins: [react()],
  base: './',
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  server: { fs: { allow: ['..'] } },
  build: {
    outDir: 'build',
    emptyOutDir: true,
    assetsDir: 'assets',
    target: 'chrome103',
    rollupOptions: {
      input: {
        ui: fileURLToPath(new URL('./ui.html', import.meta.url)),
        atlas: fileURLToPath(new URL('./atlas.html', import.meta.url)),
      },
      output: {
        // The painter is shared by both pages and must never pull React in behind it.
        manualChunks(id) {
          if (id.includes('@fontsource')) return 'fonts';
          if (id.includes('node_modules')) return 'vendor';
          if (id.includes('/src/paint/')) return 'paint';
        },
        entryFileNames: 'assets/[name].js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name].[ext]',
      },
    },
  },
});
