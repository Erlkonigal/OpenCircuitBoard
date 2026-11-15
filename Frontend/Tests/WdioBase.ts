import type {} from 'webdriverio';
import { spawn, type ChildProcess } from 'node:child_process';
import path from 'node:path';
import { mkdir } from 'node:fs/promises';
import { WorkspaceRoot, buildPath } from './Paths';
let driver: ChildProcess;
export const config: WebdriverIO.Config = {
    runner: 'local', specs: [path.join(WorkspaceRoot, 'Frontend/Tests/Desktop/**/*.spec.ts')], maxInstances: 1, hostname: '127.0.0.1', port: 4444, logLevel: 'warn',
    capabilities: [{ 'tauri:options': { application: path.join(WorkspaceRoot, 'Backend/target/release/OpenCircuitBoard' + (process.platform === 'win32' ? '.exe' : '')) }, 'wdio:enforceWebDriverClassic': true } as WebdriverIO.Capabilities],
    framework: 'mocha', reporters: ['spec'], mochaOpts: { timeout: 60000 }, waitforTimeout: 10000,
    beforeSession: async () => {
        await mkdir(buildPath('.'), { recursive: true });
        let failure: Error | undefined;
        driver = spawn('tauri-driver', [], { stdio: 'inherit', windowsHide: true });
        driver.once('error', error => { failure = error; });
        const deadline = Date.now() + 10000;
        while (Date.now() < deadline) {
            if (failure)
                throw failure;
            if (driver.exitCode !== null)
                throw Error(`tauri-driver exited ${driver.exitCode}`);
            try {
                await fetch('http://127.0.0.1:4444/status');
                return;
            }
            catch {
                await new Promise(resolve => setTimeout(resolve, 100));
            }
        }
        throw Error('tauri-driver did not start');
    },
    afterSession: () => { driver?.kill(); }
};
