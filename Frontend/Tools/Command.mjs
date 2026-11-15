import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const FrontendRoot = fileURLToPath(new URL('../', import.meta.url));
const DependencyRoot = fileURLToPath(new URL('../../build/Dependencies/', import.meta.url));
const Modules = path.join(DependencyRoot, 'node_modules');
const [action, ...extra] = process.argv.slice(2);
function run(script, args = [], cwd = FrontendRoot) {
    const result = spawnSync(process.execPath, [path.join(Modules, script), ...args], {
        cwd, stdio: 'inherit', windowsHide: true,
        env: { ...process.env, NODE_PATH: Modules, OCB_WORKSPACE_ROOT: path.dirname(FrontendRoot) },
    });
    if (result.error) throw result.error;
    if (result.status !== 0) process.exit(result.status ?? 1);
}
if (action === 'init') {
    mkdirSync(DependencyRoot, { recursive: true });
    for (const name of ['package.json', 'package-lock.json']) copyFileSync(path.join(FrontendRoot, name), path.join(DependencyRoot, name));
    const npm = process.env.npm_execpath;
    if (!npm) throw Error('Use npm run init or make init to install frontend dependencies.');
    const result = spawnSync(process.execPath, [npm, 'ci', '--prefix', DependencyRoot], { cwd: DependencyRoot, stdio: 'inherit', windowsHide: true });
    if (result.error) throw result.error;
    process.exit(result.status ?? 1);
}
if (!existsSync(Modules)) throw Error('Frontend dependencies are missing. Run make init.');
switch (action) {
    case 'build':
        run('typescript/bin/tsc', ['--noEmit']);
        run('vite/bin/vite.js', ['build', '--config', 'Vite.config.ts', '--configLoader', 'runner', ...extra]);
        break;
    case 'dev': run('vite/bin/vite.js', ['--config', 'Vite.config.ts', '--configLoader', 'runner', '--host', '127.0.0.1', ...extra]); break;
    case 'preview': run('vite/bin/vite.js', ['preview', '--config', 'Vite.config.ts', '--configLoader', 'runner', '--host', '127.0.0.1', '--port', '1421', '--strictPort', ...extra]); break;
    case 'test': run('vitest/vitest.mjs', ['run', '--config', 'Vite.config.ts', '--configLoader', 'runner', ...extra]); break;
    case 'browser-install': run('@playwright/test/cli.js', ['install', '--with-deps', 'chromium', ...extra]); break;
    case 'browser': run('@playwright/test/cli.js', ['test', ...extra]); break;
    case 'desktop': run('@wdio/cli/bin/wdio.js', ['run', 'Tests/Wdio.conf.ts', ...extra]); break;
    case 'tauri': run('@tauri-apps/cli/tauri.js', extra, path.join(FrontendRoot, '../Backend/Desktop')); break;
    default: throw Error(`Unknown frontend command: ${action}`);
}
