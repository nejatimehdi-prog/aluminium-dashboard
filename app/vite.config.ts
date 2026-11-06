import fs from 'node:fs';
import path from 'node:path';
import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { VitePWA } from 'vite-plugin-pwa';

const DATA_DIR = path.resolve(__dirname, '../data');

/** Serves ../data at /data in dev and copies it into dist/data on build. */
function dataDir(): Plugin {
  return {
    name: 'data-dir',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = decodeURIComponent((req.url ?? '').split('?')[0]);
        const m = url.match(/\/data\/(.+)$/);
        if (!m) return next();
        const file = path.join(DATA_DIR, m[1]);
        if (!file.startsWith(DATA_DIR) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return next();
        res.setHeader('Content-Type', file.endsWith('.json') ? 'application/json' : 'text/plain; charset=utf-8');
        res.setHeader('Cache-Control', 'no-cache');
        fs.createReadStream(file).pipe(res);
      });
    },
    writeBundle(opts) {
      fs.cpSync(DATA_DIR, path.join(opts.dir!, 'data'), {
        recursive: true,
        filter: (f) => !f.endsWith('.tmp'),
      });
    },
  };
}

export default defineConfig({
  // relative base: works on GitHub Pages (/<repo>/) and Cloudflare Pages (/) alike
  base: './',
  plugins: [
    react(),
    tailwindcss(),
    dataDir(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.ico', 'apple-touch-icon-180x180.png', 'icon.svg'],
      manifest: {
        id: './',
        name: 'داشبورد شمش آلومینیوم',
        short_name: 'شمش آلومینیوم',
        description: 'قیمت جهانی و داخلی شمش آلومینیوم، نمودار و آمار',
        lang: 'fa',
        dir: 'rtl',
        display: 'standalone',
        orientation: 'portrait',
        start_url: './',
        scope: './',
        theme_color: '#1c5cab',
        background_color: '#f9f9f7',
        icons: [
          { src: 'pwa-64x64.png', sizes: '64x64', type: 'image/png' },
          { src: 'pwa-192x192.png', sizes: '192x192', type: 'image/png' },
          { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png' },
          { src: 'maskable-icon-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,ico,woff2}'],
        globIgnores: ['data/**'],
        navigateFallbackDenylist: [/\/data\//],
        runtimeCaching: [
          {
            // the newest data when online, the last saved data when offline
            urlPattern: ({ url }) => url.pathname.includes('/data/') && url.pathname.endsWith('.json'),
            handler: 'NetworkFirst',
            options: {
              cacheName: 'data',
              networkTimeoutSeconds: 6,
              expiration: { maxEntries: 60, maxAgeSeconds: 60 * 60 * 24 * 60 },
            },
          },
        ],
      },
    }),
  ],
  server: { fs: { allow: ['..'] } },
});
