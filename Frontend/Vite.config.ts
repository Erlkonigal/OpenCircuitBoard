import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
    plugins: [react()],
    server: { port: 1420, strictPort: true },
    clearScreen: false,
    test: {
        include: ['Tests/Unit/**/*.test.ts', 'Tests/Unit/**/*.test.tsx'],
        environment: 'jsdom',
        pool: 'forks'
    },
    build: { chunkSizeWarningLimit: 1000 }
});
