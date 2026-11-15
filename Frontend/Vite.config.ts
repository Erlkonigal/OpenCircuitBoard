import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import manifest from './package.json';
const dependencyRequire = createRequire(new URL('../build/Dependencies/package.json', import.meta.url));
const { default: react } = dependencyRequire('@vitejs/plugin-react');

export default {
    cacheDir: '../build/Cache/Vite',
    plugins: [{
        name: 'project-dependencies',
        enforce: 'pre',
        async resolveId(this: { resolve: (id: string, importer: string, options: object) => Promise<unknown> }, id: string, importer: string | undefined, options: object) {
            const names = [...Object.keys(manifest.dependencies), 'vitest', '@testing-library/react'];
            if (!importer || importer.includes('/node_modules/') || importer.includes('\\node_modules\\') || !names.some(name => id === name || id.startsWith(`${name}/`))) return;
            return this.resolve(id, fileURLToPath(new URL('../build/Dependencies/package.json', import.meta.url)), { ...options, skipSelf: true });
        }
    }, react({ exclude: [/node_modules/, /[/\\]build[/\\](Dependencies|Cache)[/\\]/] })],
    resolve: { alias: ['react', 'react-dom'].map(name => ({
        find: new RegExp(`^${name}(?=/|$)`), replacement: name,
        customResolver: (id: string) => dependencyRequire.resolve(id)
    })) },
    server: { port: 1420, strictPort: true },
    clearScreen: false,
    test: {
        include: ['Tests/Unit/**/*.test.ts', 'Tests/Unit/**/*.test.tsx'],
        environment: 'jsdom',
        pool: 'forks',
        fsModuleCachePath: fileURLToPath(new URL('../build/Cache/Vitest', import.meta.url)),
        coverage: { reportsDirectory: '../build/Coverage' }
    },
    build: { outDir: '../build/Frontend', emptyOutDir: true, chunkSizeWarningLimit: 1000 }
};
