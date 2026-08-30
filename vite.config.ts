import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// GitHub Pages project site: https://william101102.github.io/zenly-app/
const base = process.env.GITHUB_ACTIONS ? '/zenly-app/' : '/';

export default defineConfig({
  plugins: [react()],
  base,
});
