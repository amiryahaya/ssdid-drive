import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: '/admin/',
  server: {
    port: 5174,
    proxy: {
      '/api': {
        target: 'http://localhost:5139',
        changeOrigin: true,
      },
    },
  },
})
