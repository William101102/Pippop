import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The native app loads from capacitor://localhost, so its assets must resolve
// against the bundle root. A custom domain also serves from the root, while the
// github.io project site serves from /zenly-app/.
const native = Boolean(process.env.CAP_BUILD);
const base =
  native || !process.env.GITHUB_ACTIONS || process.env.PAGES_CUSTOM_DOMAIN ? '/' : '/zenly-app/';

export default defineConfig({
  plugins: [react()],
  base,
});
