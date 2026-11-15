import { createRequire } from 'node:module';
const { test, expect } = createRequire(new URL('../../build/Dependencies/package.json', import.meta.url))('@playwright/test') as typeof import('@playwright/test');
export { test, expect };
export type { Page } from '@playwright/test';
