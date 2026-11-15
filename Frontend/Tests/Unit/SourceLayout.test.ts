import { readdirSync } from 'node:fs';
import path from 'node:path';
import { expect, it } from 'vitest';
const WorkspaceRoot = process.env.OCB_WORKSPACE_ROOT ?? path.resolve(process.cwd(), '..');
it('keeps dependencies, caches and build output outside both source trees', () => {
    const forbidden = new Set(['node_modules', 'target', 'dist', 'gen', '.vite', '.vite-temp', '.vitest-cache', 'test-results', 'playwright-report']);
    const found: string[] = [];
    function inspect(directory: string) {
        for (const entry of readdirSync(directory, { withFileTypes: true })) {
            if (!entry.isDirectory()) continue;
            const file = path.join(directory, entry.name);
            if (forbidden.has(entry.name)) found.push(path.relative(WorkspaceRoot, file));
            else inspect(file);
        }
    }
    inspect(path.join(WorkspaceRoot, 'Frontend'));
    inspect(path.join(WorkspaceRoot, 'Backend'));
    expect(found).toEqual([]);
});
