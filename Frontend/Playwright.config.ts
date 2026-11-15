import { defineConfig } from '@playwright/test';
import { buildPath } from './Tests/Paths';

export default defineConfig({
    testDir: 'Tests/Browser',
    timeout: 90000,
    use: {
        channel: process.platform === 'win32' ? 'msedge' : undefined,
        baseURL: 'http://127.0.0.1:1421',
        viewport: { width: 1280, height: 720 },
        screenshot: 'only-on-failure'
    },
    webServer: {
        command: 'npm run preview',
        url: 'http://127.0.0.1:1421',
        reuseExistingServer: !process.env.CI
    },
    outputDir: buildPath('BrowserTests'),
    reporter: 'list'
});
