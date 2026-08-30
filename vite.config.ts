import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// A custom domain serves the site from the root, while the github.io project
// site serves it from /zenly-app/. Setting the PAGES_CUSTOM_DOMAIN repo
// variable switches both this base and the CNAME file in the Pages workflow.
const base = !process.env.GITHUB_ACTIONS || process.env.PAGES_CUSTOM_DOMAIN ? '/' : '/zenly-app/';

export default defineConfig({
  plugins: [react()],
  base,
});
