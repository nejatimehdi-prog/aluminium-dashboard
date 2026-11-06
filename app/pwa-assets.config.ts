import { defineConfig, minimal2023Preset } from '@vite-pwa/assets-generator/config';

export default defineConfig({
  preset: {
    ...minimal2023Preset,
    maskable: { ...minimal2023Preset.maskable, resizeOptions: { background: '#1c5cab' } },
    apple: { ...minimal2023Preset.apple, resizeOptions: { background: '#1c5cab' } },
  },
  images: ['public/icon.svg'],
});
